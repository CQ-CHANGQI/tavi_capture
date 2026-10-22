import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'lcm/lcm_receiver.dart';
import 'lcm/multicast_lock.dart';
import 'lcm/preview_protocol.dart';
import 'models.dart';

/// 实时预览：LCM 组播进接收 isolate，UI 侧只解码每路最新一帧。
class LivePreview extends ChangeNotifier {
  LivePreview({Iterable<String>? channels})
    : _channels =
          (channels ??
                  CameraId.values.map(
                    (c) => '$cameraChannelPrefix${c.channel}',
                  ))
              .toList();

  final List<String> _channels;
  LcmReceiver? _receiver;
  StreamSubscription<CameraFrame>? _frameSub;
  StreamSubscription<List<JointBatch>>? _jointSub;

  /// 相机键（cam_head 等）→ 已解码画面。
  final Map<String, ui.Image> images = {};

  /// 相机键 → 最近一次收到帧的时间。
  final Map<String, DateTime> lastFrame = {};
  final Map<String, List<DateTime>> _arrivals = {};
  final Map<String, Uint8List> _pendingBytes = {};
  final Set<String> _decoding = {};

  List<JointBatch>? joints;
  DateTime? jointsAt;
  bool running = false;
  String? error;
  bool _disposed = false;
  bool _dirty = false;
  Timer? _ticker;

  LcmStats get stats => _receiver?.stats ?? LcmStats();

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
    _ticker ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (_disposed || !_dirty) return;
      _dirty = false;
      notifyListeners();
    });
    final receiver = _receiver ??= LcmReceiver();
    _frameSub = receiver.frames.listen(_onFrame, onError: _onError);
    _jointSub = receiver.joints.listen(_onJoints, onError: _onError);
    await AndroidMulticastLock.acquire();
    try {
      await receiver.start(_channels);
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
    await _receiver?.stop();
    await AndroidMulticastLock.release();
    _clearImages();
    lastFrame.clear();
    _arrivals.clear();
    if (!_disposed) notifyListeners();
  }

  void _onFrame(CameraFrame frame) {
    if (_disposed) return;
    final camera = frame.camera;
    lastFrame[camera] = DateTime.now();
    _pendingBytes[camera] = frame.image;
    if (_decoding.add(camera)) unawaited(_decode(camera));
  }

  void _onJoints(List<JointBatch> batches) {
    if (_disposed || batches.isEmpty) return;
    joints = batches;
    jointsAt = DateTime.now();
    _dirty = true;
  }

  Future<void> _decode(String camera) async {
    while (!_disposed && _pendingBytes.containsKey(camera)) {
      final bytes = _pendingBytes.remove(camera)!;
      ui.Codec? codec;
      try {
        codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        if (_disposed) {
          frame.image.dispose();
          break;
        }
        final old = images[camera];
        images[camera] = frame.image;
        _recordRendered(camera);
        _dirty = true;
        if (old != null) {
          SchedulerBinding.instance.addPostFrameCallback((_) => old.dispose());
        }
      } catch (_) {
        // 坏帧丢弃，保留上一张。
      } finally {
        codec?.dispose();
      }
    }
    _decoding.remove(camera);
  }

  /// fps 统计按“真正解出来并显示”的帧算，而不是收到的帧。
  void _recordRendered(String camera) {
    final now = DateTime.now();
    final arrivals = _arrivals[camera] ??= [];
    arrivals.add(now);
    if (arrivals.length > 61) arrivals.removeAt(0);
  }

  void _onError(Object e) {
    if (_disposed) return;
    error = '$e';
    notifyListeners();
  }

  void _clearImages() {
    for (final image in images.values) {
      image.dispose();
    }
    images.clear();
    _pendingBytes.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    _frameSub?.cancel();
    _jointSub?.cancel();
    _ticker?.cancel();
    _ticker = null;
    unawaited(_receiver?.dispose());
    _receiver = null;
    unawaited(AndroidMulticastLock.release());
    _clearImages();
    super.dispose();
  }
}
