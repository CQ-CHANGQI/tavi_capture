import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'lcm/lcm_receiver.dart';
import 'lcm/multicast_lock.dart';
import 'lcm/preview_protocol.dart';
import 'models.dart';

/// 实时预览：接收 isolate 负责收包和重组，这里每路只保留最新一帧。
///
/// 解码来不及就覆盖旧帧，不排队、不累积延迟；保证画面始终是最新数据。
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

  /// 相机键（cam_head 等）→ 当前显示的已解码画面。
  final Map<String, ui.Image> images = {};

  /// 相机键 → 最近一次收到帧的时间。
  final Map<String, DateTime> lastFrame = {};
  final Map<String, List<DateTime>> _arrivals = {};

  /// 相机键 → 最新一帧待解码数据（解码慢时被新帧覆盖）。
  final Map<String, Uint8List> _latest = {};
  final Set<String> _decoding = {};

  List<JointBatch>? joints;
  bool running = false;
  String? error;
  bool _disposed = false;

  /// 已解码并参与显示的帧率。
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

  /// 是否至少收到过一帧。用来区分“还没开始”和“曾经有画面后掉线”。
  bool hasFrame(String camera) => lastFrame.containsKey(camera);

  bool get allCamerasOnline =>
      CameraId.values.every((c) => isOnline(c.channel));

  Future<void> start() async {
    if (_disposed || running) return;
    running = true;
    error = null;
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
    joints = null;
    if (!_disposed) notifyListeners();
  }

  void _onFrame(CameraFrame frame) {
    if (_disposed) return;
    final camera = frame.camera;
    lastFrame[camera] = DateTime.now();
    _latest[camera] = frame.image;
    if (_decoding.add(camera)) unawaited(_decode(camera));
  }

  void _onJoints(List<JointBatch> batches) {
    if (_disposed || batches.isEmpty) return;
    // 实时关节当前没有 UI 消费，只更新数据不通知，避免相机面板跟着重建。
    joints = batches;
  }

  Future<void> _decode(String camera) async {
    while (!_disposed) {
      final bytes = _latest.remove(camera);
      if (bytes == null) break;
      ui.Codec? codec;
      try {
        // 源比屏幕大很多时按 1280 宽解码；正常 640×360 不缩放。
        final size = imageSizeOf(bytes);
        final targetWidth = size != null && size.$1 > 1280 ? 1280 : null;
        codec = await ui.instantiateImageCodec(bytes, targetWidth: targetWidth);
        final frame = await codec.getNextFrame();
        if (_disposed) {
          frame.image.dispose();
          break;
        }
        final old = images[camera];
        images[camera] = frame.image;
        _recordRendered(camera);
        // 每解出一帧就通知；同一 vsync 内的多次通知由 Flutter 合并。
        notifyListeners();
        if (old != null) {
          SchedulerBinding.instance.addPostFrameCallback((_) => old.dispose());
        }
      } catch (_) {
        // 坏帧丢弃，继续下一帧。
      } finally {
        codec?.dispose();
      }
    }
    _decoding.remove(camera);
  }

  void _recordRendered(String camera) {
    final now = DateTime.now();
    final arrivals = _arrivals[camera] ??= [];
    arrivals.add(now);
    if (arrivals.length > 121) arrivals.removeAt(0);
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
    _latest.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    _frameSub?.cancel();
    _jointSub?.cancel();
    unawaited(_receiver?.dispose());
    _receiver = null;
    unawaited(AndroidMulticastLock.release());
    _clearImages();
    super.dispose();
  }
}
