import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'lcm/codec.dart';
import 'lcm/lcm_preview_client.dart';
import 'lcm/multicast_lock.dart';
import 'models.dart';

/// 实时预览：LCM 组播收帧（接收 isolate 里完成重组），UI 侧只解码最新画面。
///
/// 每路相机保留“最新一张待解码”，解码串行执行，网络抖动不会堆帧。
class LivePreview extends ChangeNotifier {
  LivePreview({Iterable<String>? channels})
    : _channels =
          (channels ??
                  CameraId.values.map((c) => '/preview/cameras/${c.channel}'))
              .toList();

  final List<String> _channels;
  LcmPreviewClient? _client;

  /// 相机键（cam_head 等）→ 已解码画面。
  final Map<String, ui.Image> images = {};

  /// 相机键 → 最近一次收到帧的时间。
  final Map<String, DateTime> lastFrame = {};
  final Map<String, List<DateTime>> _arrivals = {};
  final Map<String, Uint8List> _pending = {};
  final Set<String> _decoding = {};

  StreamSubscription<PreviewImage>? _frameSub;
  StreamSubscription<List<JointFrame>>? _jointSub;

  JointFrame? joints;
  DateTime? jointsAt;
  bool running = false;
  String? error;
  bool _disposed = false;

  double fps(String camera) {
    final list = _arrivals[camera];
    if (list == null || list.length < 2) return 0;
    final span = list.last.difference(list.first).inMicroseconds;
    return span <= 0 ? 0 : (list.length - 1) * 1e6 / span;
  }

  bool isOnline(String camera) {
    final at = lastFrame[camera];
    return at != null && DateTime.now().difference(at).inSeconds < 2;
  }

  bool get allCamerasOnline =>
      CameraId.values.every((c) => isOnline(c.channel));

  bool get jointsOnline {
    final at = jointsAt;
    return at != null && DateTime.now().difference(at).inSeconds < 2;
  }

  Future<void> start() async {
    if (_disposed || running) return;
    running = true;
    error = null;
    final client = _client ??= LcmPreviewClient();
    _frameSub = client.frames.listen(_onFrame, onError: _onError);
    _jointSub = client.joints.listen(_onJoints, onError: _onError);
    await MulticastLock.acquire();
    try {
      await client.start(_channels);
    } catch (e) {
      error = '$e';
      running = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    if (!running) return;
    running = false;
    await _frameSub?.cancel();
    await _jointSub?.cancel();
    _frameSub = null;
    _jointSub = null;
    await _client?.dispose();
    _client = null;
    await MulticastLock.release();
    final old = images.values.toList();
    images.clear();
    lastFrame.clear();
    for (final image in old) {
      image.dispose();
    }
    if (!_disposed) notifyListeners();
  }

  void _onFrame(PreviewImage frame) {
    if (_disposed) return;
    final now = DateTime.now();
    lastFrame[frame.camera] = now;
    (_arrivals[frame.camera] ??= []).add(now);
    if (_arrivals[frame.camera]!.length > 30) {
      _arrivals[frame.camera]!.removeAt(0);
    }
    _pending[frame.camera] = frame.bytes;
    if (!_decoding.contains(frame.camera)) {
      _decoding.add(frame.camera);
      unawaited(_decodeLoop(frame.camera));
    }
    notifyListeners();
  }

  void _onJoints(List<JointFrame> batch) {
    if (_disposed || batch.isEmpty) return;
    joints = batch.last;
    jointsAt = DateTime.now();
    notifyListeners();
  }

  Future<void> _decodeLoop(String camera) async {
    while (!_disposed && _pending.containsKey(camera)) {
      final bytes = _pending.remove(camera)!;
      ui.Codec? codec;
      try {
        codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        if (_disposed) {
          frame.image.dispose();
          return;
        }
        _replace(camera, frame.image);
      } catch (_) {
        // 坏帧直接丢弃，保留上一张。
      } finally {
        codec?.dispose();
      }
    }
    _decoding.remove(camera);
  }

  void _replace(String camera, ui.Image image) {
    final old = images[camera];
    images[camera] = image;
    if (old != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    notifyListeners();
  }

  void _onError(Object e) {
    if (_disposed) return;
    error = '$e';
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _frameSub?.cancel();
    _jointSub?.cancel();
    unawaited(_client?.dispose());
    _client = null;
    unawaited(MulticastLock.release());
    for (final image in images.values) {
      image.dispose();
    }
    images.clear();
    super.dispose();
  }
}
