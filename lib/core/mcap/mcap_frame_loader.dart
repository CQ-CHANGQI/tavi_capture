import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'mcap_review_index.dart';
import 'ros2_messages.dart';

/// 按索引里的 offset 随机读取一帧并解码成 [ui.Image]。
class McapFrameLoader {
  McapFrameLoader(String path) : _file = File(path).openSync();

  final RandomAccessFile _file;
  bool _closed = false;

  Future<ui.Image> load(McapFrameRef ref) {
    if (_closed) throw StateError('McapFrameLoader is closed');
    _file.setPositionSync(ref.offset);
    final bytes = _file.readSync(ref.length);
    final image = decodeRos2Message('sensor_msgs/msg/Image', bytes) as RosImage;
    final rgba = image.toRgba();
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      image.width,
      image.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _file.closeSync();
  }
}
