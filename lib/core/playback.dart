import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'mcap/mcap_codecs.dart';
import 'mcap/mcap_reader.dart';
import 'models.dart';

/// MCAP 回放地址：默认机器人 8090 上的 rosbag_0，可用 --dart-define=MCAP_URL 覆盖。
const mcapUrlOverride = String.fromEnvironment('MCAP_URL');

String defaultMcapUrl(String robotIp) => mcapUrlOverride.isNotEmpty
    ? mcapUrlOverride
    : 'http://$robotIp:8090/rosbag_0.mcap';

const _jointColors = [
  0xff3b82c4,
  0xff2f9e62,
  0xffd39a3a,
  0xff7c6adf,
  0xffd4544a,
  0xff4db6c4,
  0xffc47a3b,
];

const _armLabels = ['肩俯仰', '肩滚转', '肩偏航', '肘俯仰', '腕俯仰', '腕滚转', '腕偏航'];
const _bodyLabels = ['腰俯仰', '腰滚转', '腰偏航', '升降'];

/// 一条画在图上的关节曲线。
class JointCurve {
  const JointCurve(this.name, this.values, this.color);

  final String name;
  final List<double> values;
  final int color;
}

/// 一个机械臂分组（左/右/身体）的指令与状态历史。
class JointTrack {
  JointTrack(this.group);

  final JointGroup group;
  final Map<String, List<double>> command = {};
  final Map<String, List<double>> state = {};
  final List<String> _order = [];

  static const maxPoints = 600;

  void add(String name, double value, {required bool isCommand}) {
    final short = _shortName(name);
    if (!_order.contains(short)) _order.add(short);
    final values = (isCommand ? command : state).putIfAbsent(short, () => []);
    values.add(value);
    if (values.length > maxPoints) {
      values.removeRange(0, values.length - maxPoints);
    }
  }

  void clear() {
    command.clear();
    state.clear();
    _order.clear();
  }

  static String _shortName(String raw) {
    var name = raw;
    if (name.endsWith('/position')) name = name.substring(0, name.length - 9);
    if (name.startsWith('state_interface.')) name = name.substring(16);
    if (name.startsWith('command_interface.')) name = name.substring(18);
    return name;
  }

  List<JointCurve> curves(JointMode mode) {
    var source = switch (mode) {
      JointMode.command => command,
      JointMode.state => state,
      JointMode.all => command.isEmpty ? state : command,
    };
    if (source.isEmpty) source = state;
    final names = _order.where(source.containsKey).toList();
    return [
      for (var i = 0; i < names.length; i++)
        JointCurve(
          _labelFor(names[i], i),
          source[names[i]]!,
          _jointColors[i % _jointColors.length],
        ),
    ];
  }

  static String _labelFor(String name, int index) {
    final labels =
        name.toLowerCase().contains('body') ||
            name.toLowerCase().contains('waist')
        ? _bodyLabels
        : _armLabels;
    return index < labels.length ? labels[index] : name;
  }
}

/// 回放器：按时间轴拉 MCAP chunk，解出四路画面 + 三组关节曲线。
class PlaybackController extends ChangeNotifier {
  PlaybackController({required this.url});

  final String url;

  McapRemoteFile? _file;
  McapSummary? _summary;
  McapChunkCursor? _cursor;
  final Map<int, String> _schemaName = {};
  final Map<int, String> _topicById = {};
  final Map<int, String> _cameraByChannel = {};
  final Set<int> _channelIds = {};

  final Map<String, ui.Image> cameras = {};
  final Map<String, Uint8List> _pendingImage = {};
  final Map<String, bool> _pendingCompressed = {};
  final Set<String> _decoding = {};
  final Map<JointGroup, JointTrack> tracks = {
    for (final group in JointGroup.values) group: JointTrack(group),
  };

  bool loading = true;
  bool playing = false;
  bool loop = false;
  double speed = 1;
  String? error;
  int positionNs = 0;
  int startNs = 0;
  int endNs = 0;

  int _generation = 0;
  bool _disposed = false;
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

  Duration get duration =>
      Duration(microseconds: (endNs - startNs).clamp(0, 1 << 62) ~/ 1000);
  Duration get position =>
      Duration(microseconds: (positionNs - startNs).clamp(0, 1 << 62) ~/ 1000);
  double get progress => endNs <= startNs
      ? 0
      : ((positionNs - startNs) / (endNs - startNs)).clamp(0, 1);
  bool get hasMedia => _cameraByChannel.isNotEmpty || _channelIds.isNotEmpty;

  Future<void> open() async {
    try {
      final file = _file = McapRemoteFile(Uri.parse(url));
      await file.open();
      final summary = _summary = await McapSummary.load(file);
      if (_disposed) return;
      startNs = summary.startTimeNs;
      endNs = summary.endTimeNs > startNs ? summary.endTimeNs : startNs + 1;
      positionNs = startNs;

      for (final channel in summary.channels) {
        _schemaName[channel.id] = summary.schemaOf(channel)?.name ?? '';
        _topicById[channel.id] = channel.topic.toLowerCase();
      }
      _mapChannels(summary);
      if (!hasMedia) {
        throw McapException('这个 MCAP 里没有图像或关节话题');
      }
      _cursor = _newCursor(positionNs);
      loading = false;
      notifyListeners();
      await _prime();
    } catch (e) {
      if (_disposed) return;
      loading = false;
      error = '$e';
      notifyListeners();
    }
  }

  void _mapChannels(McapSummary summary) {
    final images = <McapChannel>[];
    for (final channel in summary.channels) {
      final name = _schemaName[channel.id];
      if (name == 'sensor_msgs/msg/Image' ||
          name == 'sensor_msgs/msg/CompressedImage') {
        images.add(channel);
      } else if (name == 'sensor_msgs/msg/JointState' ||
          name == 'pal_statistics_msgs/msg/Statistics') {
        _channelIds.add(channel.id);
      }
    }
    images.sort((a, b) => a.topic.compareTo(b.topic));
    final taken = <String>{};
    for (final channel in images) {
      var camera = _cameraOfTopic(channel.topic);
      if (camera != null && taken.contains(camera)) camera = null;
      if (camera == null) {
        for (final candidate in CameraId.values) {
          if (!taken.contains(candidate.channel)) {
            camera = candidate.channel;
            break;
          }
        }
      }
      if (camera == null) continue;
      taken.add(camera);
      _cameraByChannel[channel.id] = camera;
      _channelIds.add(channel.id);
    }
  }

  static String? _cameraOfTopic(String topic) {
    final t = topic.toLowerCase();
    if (t.contains('head') || t.contains('cam1') || t.contains('main')) {
      return CameraId.head.channel;
    }
    if (t.contains('chest') ||
        t.contains('pan') ||
        t.contains('overview') ||
        t.contains('cam4')) {
      return CameraId.chest.channel;
    }
    // fisheye_l / fisheye_r 是腕部相机；也有 /cam3、/left 这类命名。
    if (t.contains('fisheye_l') ||
        t.contains('left') ||
        t.contains('cam3') ||
        t.endsWith('_l') ||
        t.contains('/l/')) {
      return CameraId.left.channel;
    }
    if (t.contains('fisheye_r') ||
        t.contains('right') ||
        t.contains('cam2') ||
        t.endsWith('_r') ||
        t.contains('/r/')) {
      return CameraId.right.channel;
    }
    return null;
  }

  static JointGroup? _groupOfTopic(String topic) {
    if (topic.contains('arm_l') ||
        topic.contains('left') ||
        topic.contains('_l/')) {
      return JointGroup.left;
    }
    if (topic.contains('arm_r') ||
        topic.contains('right') ||
        topic.contains('_r/')) {
      return JointGroup.right;
    }
    if (topic.contains('body') ||
        topic.contains('waist') ||
        topic.contains('torso') ||
        topic.contains('base')) {
      return JointGroup.body;
    }
    return null;
  }

  McapChunkCursor _newCursor(int timeNs) => McapChunkCursor(
    _file!,
    _summary!,
    startTimeNs: timeNs,
    channelIds: _channelIds,
  );

  void play() {
    if (_disposed || loading || error != null || playing) return;
    if (positionNs >= endNs) {
      unawaited(seekTo(startNs, resume: true));
      return;
    }
    playing = true;
    notifyListeners();
    unawaited(_run(++_generation));
  }

  void pause() {
    playing = false;
    _generation++;
    notifyListeners();
  }

  void toggle() => playing ? pause() : play();

  void setSpeed(double value) {
    if (value == speed) return;
    final wasPlaying = playing;
    pause();
    speed = value;
    if (wasPlaying) play();
  }

  void toggleLoop() {
    loop = !loop;
    notifyListeners();
  }

  Future<void> seekTo(int target, {bool resume = false}) async {
    if (_disposed || loading || error != null) return;
    final wasPlaying = resume || playing;
    pause();
    final token = ++_generation;
    positionNs = target.clamp(startNs, endNs);
    _clearMedia();
    _cursor = _newCursor(positionNs);
    notifyListeners();
    await _prime();
    if (_disposed || token != _generation) return;
    if (wasPlaying && positionNs < endNs) play();
  }

  Future<void> seekProgress(double value) => seekTo(
    startNs + ((endNs - startNs) * value.clamp(0, 1)).round(),
    resume: playing,
  );

  Future<void> skip(Duration delta) =>
      seekTo(positionNs + delta.inMicroseconds * 1000, resume: playing);

  Future<void> stepFrame(int direction) =>
      seekTo(positionNs + (direction < 0 ? -1 : 1) * 33333333);

  Future<void> _prime() async {
    final cursor = _cursor;
    if (cursor == null) return;
    final until = positionNs + 400000000;
    try {
      for (var i = 0; i < 240; i++) {
        final message = await cursor.next();
        if (message == null) break;
        if (message.logTimeNs > until) break;
        _apply(message);
      }
    } catch (e) {
      _fail(e);
      return;
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> _run(int generation) async {
    final cursor = _cursor;
    if (cursor == null) return;
    final mediaStart = positionNs;
    final wallStart = DateTime.now();
    while (!_disposed && playing && generation == _generation) {
      McapMessage? message;
      try {
        message = await cursor.next();
      } catch (e) {
        _fail(e);
        return;
      }
      if (message == null) {
        if (_disposed || generation != _generation) return;
        if (loop) {
          unawaited(seekTo(startNs, resume: true));
          return;
        }
        positionNs = endNs;
        playing = false;
        notifyListeners();
        return;
      }
      // 纳秒 → 毫秒，再按倍速缩放。
      final dueMs = (message.logTimeNs - mediaStart) / 1e6 / speed;
      var waitMs =
          dueMs - DateTime.now().difference(wallStart).inMicroseconds / 1000;
      while (waitMs > 0 && !_disposed && playing && generation == _generation) {
        final step = waitMs > 80 ? 80.0 : waitMs;
        await Future<void>.delayed(
          Duration(microseconds: (step * 1000).ceil()),
        );
        waitMs =
            dueMs - DateTime.now().difference(wallStart).inMicroseconds / 1000;
      }
      if (_disposed || !playing || generation != _generation) return;
      positionNs = message.logTimeNs;
      _apply(message);
      _notifyThrottled();
    }
  }

  void _apply(McapMessage message) {
    final schema = _schemaName[message.channelId] ?? '';
    final camera = _cameraByChannel[message.channelId];
    if (camera != null) {
      if (schema == 'sensor_msgs/msg/CompressedImage') {
        _queueImage(camera, message.data, compressed: true);
      } else if (schema == 'sensor_msgs/msg/Image') {
        _queueImage(camera, message.data, compressed: false);
      }
      return;
    }
    try {
      if (schema == 'sensor_msgs/msg/JointState') {
        final state = decodeRosJointState(message.data);
        final hint = _groupOfTopic(_topicById[message.channelId] ?? '');
        for (
          var i = 0;
          i < state.names.length && i < state.positions.length;
          i++
        ) {
          _addJoint(
            state.names[i],
            state.positions[i],
            isCommand: false,
            hint: hint,
          );
        }
      } else if (schema == 'pal_statistics_msgs/msg/Statistics') {
        final statistics = decodeRosStatistics(message.data);
        for (final item in statistics.statistics) {
          final isCommand = item.name.startsWith('command_interface.');
          _addJoint(item.name, item.value, isCommand: isCommand);
        }
      }
    } catch (_) {
      // 单条坏消息不影响时间轴。
    }
  }

  void _addJoint(
    String rawName,
    double value, {
    required bool isCommand,
    JointGroup? hint,
  }) {
    if (!value.isFinite) return;
    final lower = rawName.toLowerCase();
    final group =
        hint ??
        (lower.contains('left')
            ? JointGroup.left
            : lower.contains('right')
            ? JointGroup.right
            : (lower.contains('body') ||
                  lower.contains('waist') ||
                  lower.contains('torso') ||
                  lower.contains('base'))
            ? JointGroup.body
            : null);
    if (group == null) return;
    tracks[group]!.add(rawName, value, isCommand: isCommand);
  }

  /// 每路相机只保留最新待解码帧：网络/解码慢的时候丢旧帧，不排队。
  void _queueImage(String camera, Uint8List bytes, {required bool compressed}) {
    _pendingImage[camera] = bytes;
    _pendingCompressed[camera] = compressed;
    if (_decoding.add(camera)) unawaited(_decodeLoop(camera));
  }

  Future<void> _decodeLoop(String camera) async {
    while (!_disposed && _pendingImage.containsKey(camera)) {
      final bytes = _pendingImage.remove(camera)!;
      final compressed = _pendingCompressed[camera] ?? false;
      ui.Codec? codec;
      try {
        if (compressed) {
          final image = decodeRosCompressedImage(bytes);
          codec = await ui.instantiateImageCodec(image.data);
        } else {
          final image = decodeRosImage(bytes);
          final completer = Completer<ui.Image>();
          ui.decodeImageFromPixels(
            image.rgba,
            image.width,
            image.height,
            ui.PixelFormat.rgba8888,
            completer.complete,
          );
          _setImage(camera, await completer.future);
          continue;
        }
        final frame = await codec.getNextFrame();
        _setImage(camera, frame.image);
      } catch (_) {
        // 坏帧丢弃，继续下一张。
      } finally {
        codec?.dispose();
      }
    }
    _decoding.remove(camera);
  }

  void _setImage(String camera, ui.Image image) {
    if (_disposed) {
      image.dispose();
      return;
    }
    final old = cameras[camera];
    cameras[camera] = image;
    if (old != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    _notifyThrottled();
  }

  void _notifyThrottled() {
    final now = DateTime.now();
    if (now.difference(_lastNotify).inMilliseconds < 33) return;
    _lastNotify = now;
    notifyListeners();
  }

  void _clearMedia() {
    final old = cameras.values.toList();
    cameras.clear();
    if (old.isEmpty) return;
    if (_disposed) {
      for (final image in old) {
        image.dispose();
      }
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        for (final image in old) {
          image.dispose();
        }
      });
    }
    for (final track in tracks.values) {
      track.clear();
    }
  }

  void _fail(Object e) {
    if (_disposed) return;
    playing = false;
    error = '$e';
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    playing = false;
    _generation++;
    _clearMedia();
    _file?.close();
    super.dispose();
  }
}
