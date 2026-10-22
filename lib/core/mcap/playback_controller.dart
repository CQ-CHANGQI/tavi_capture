import 'dart:async';

import 'package:flutter/foundation.dart';

import '../telemetry/sample.dart';
import 'recording_decoder.dart';
import 'remote_mcap.dart';

/// Playback clock, buffered messages and seek cancellation belong here, not UI.
class PlaybackController extends ChangeNotifier {
  PlaybackController({String url = recordingUrl})
    : file = RemoteMcap(Uri.parse(url));
  final RemoteMcap file;
  final cameras = <String, CameraFrame>{};
  final history = <JointSample>[];
  String? error;
  bool loading = true, buffering = false, playing = false, loop = false;
  double speed = 1;
  int position = 0;
  int _generation = 0;
  bool _disposed = false;
  List<McapMessage> _messages = [];
  int _next = 0, _bufferEnd = 0;
  Timer? _timer;
  final _clock = Stopwatch();
  int _anchor = 0;
  Future<void> _reads = Future.value();

  Duration get elapsed =>
      Duration(microseconds: (position - file.start).clamp(0, 1 << 62) ~/ 1000);
  Duration get duration => file.duration;
  double get progress => file.end <= file.start
      ? 0
      : ((position - file.start) / (file.end - file.start)).clamp(0, 1);

  Future<void> open() async {
    try {
      await file.open();
      if (_disposed) return;
      position = file.start;
      loading = false;
      await seek(file.start);
    } catch (e) {
      if (!_disposed) {
        error = '$e';
        loading = false;
        notifyListeners();
      }
    }
  }

  void play() {
    if (_disposed || loading || buffering || error != null) return;
    if (position >= file.end) {
      unawaited(seek(file.start, resume: true));
      return;
    }
    playing = true;
    _anchor = position;
    _clock
      ..reset()
      ..start();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 33), (_) => _tick());
    notifyListeners();
  }

  void pause() {
    playing = false;
    _timer?.cancel();
    _timer = null;
    _clock.stop();
    if (!_disposed) notifyListeners();
  }

  void setSpeed(double value) {
    final resume = playing;
    pause();
    speed = value;
    if (resume) play();
  }

  void toggleLoop() {
    loop = !loop;
    notifyListeners();
  }

  void seekProgress(double progress) => unawaited(
    seek(
      file.start + ((file.end - file.start) * progress.clamp(0, 1)).round(),
      resume: playing,
    ),
  );
  void skip(Duration delta) =>
      unawaited(seek(position + delta.inMicroseconds * 1000));

  /// Frame stepping uses actual camera timestamps rather than guessing 30 fps.
  Future<void> step(int direction) async {
    pause();
    final token = ++_generation;
    buffering = true;
    notifyListeners();
    try {
      final from = (position - 1000000000).clamp(file.start, file.end);
      final until = (position + 1000000000).clamp(file.start, file.end);
      final messages = await _read(from, until);
      if (_disposed || token != _generation) return;
      final head = file.channels.values
          .where((c) => cameraOf(c.topic) == 'cam_head')
          .firstOrNull;
      final times = messages
          .where((m) => m.channelId == head?.id)
          .map((m) => m.logTime)
          .toList();
      final candidates = times
          .where((t) => direction < 0 ? t < position : t > position)
          .toList();
      await seek(
        candidates.isEmpty
            ? (direction < 0 ? file.start : file.end)
            : (direction < 0 ? candidates.last : candidates.first),
      );
    } catch (e) {
      _fail(e, token);
    }
  }

  /// Serialize range windows: rapidly dragging cannot create unlimited requests.
  Future<List<McapMessage>> _read(int from, int until) {
    final read = _reads.then((_) => file.window(from, until));
    _reads = read.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return read;
  }

  Future<void> seek(int target, {bool resume = false}) async {
    if (_disposed || loading) return;
    pause();
    final token = ++_generation;
    target = target.clamp(file.start, file.end);
    position = target;
    buffering = true;
    error = null;
    cameras.clear();
    history.clear();
    notifyListeners();
    try {
      final from = (target - 200000000).clamp(file.start, file.end);
      final until = (target + 700000000).clamp(file.start, file.end);
      final messages = await _read(from, until);
      if (_disposed || token != _generation) return;
      _messages = messages;
      _bufferEnd = until;
      _next = 0;
      _consume(target);
      // At the very beginning, some cameras' first message is slightly later.
      for (final message in messages.skip(_next)) {
        final channel = file.channels[message.channelId];
        final camera = channel == null ? null : cameraOf(channel.topic);
        if (camera != null && !cameras.containsKey(camera)) _apply(message);
      }
      buffering = false;
      notifyListeners();
      if (resume) play();
    } catch (e) {
      _fail(e, token);
    }
  }

  void _tick() {
    if (_disposed || !playing || buffering) return;
    final target =
        (_anchor + (_clock.elapsedMicroseconds * 1000 * speed).round()).clamp(
          file.start,
          file.end,
        );
    if (target > _bufferEnd) {
      unawaited(_refill());
      return;
    }
    position = target;
    _consume(target);
    if (position >= file.end) {
      pause();
      if (loop) unawaited(seek(file.start, resume: true));
    }
    notifyListeners();
  }

  Future<void> _refill() async {
    final token = _generation;
    buffering = true;
    _clock.stop();
    notifyListeners();
    try {
      final until = (_bufferEnd + 700000000).clamp(file.start, file.end);
      final messages = await _read(_bufferEnd + 1, until);
      if (_disposed || token != _generation) return;
      // Consume any remainder before replacing the window.
      _consume(_bufferEnd);
      position = _bufferEnd;
      _messages = messages;
      _next = 0;
      _bufferEnd = until;
      buffering = false;
      _anchor = position;
      _clock.reset();
      if (playing) _clock.start();
      notifyListeners();
    } catch (e) {
      _fail(e, token);
    }
  }

  void _consume(int target) {
    while (_next < _messages.length && _messages[_next].logTime <= target) {
      _apply(_messages[_next++]);
    }
  }

  void _apply(McapMessage message) {
    final channel = file.channels[message.channelId];
    final type = file.schemas[channel?.schemaId]?.name;
    if (channel == null) return;
    if (type == 'sensor_msgs/msg/CompressedImage') {
      final camera = cameraOf(channel.topic);
      if (camera != null) cameras[camera] = decodeCompressedFrame(message);
    } else if (type == 'pal_statistics_msgs/msg/Statistics') {
      // 20 Hz is enough for visible curves, while preserving message timestamps.
      if (history.isNotEmpty &&
          message.logTime - history.last.timeNs < 50000000) {
        return;
      }
      history.add(decodeStatistics(message));
      if (history.length > 240) history.removeAt(0);
    }
  }

  void _fail(Object e, int token) {
    if (_disposed || token != _generation) return;
    pause();
    buffering = false;
    error = '$e';
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    file.close();
    super.dispose();
  }
}
