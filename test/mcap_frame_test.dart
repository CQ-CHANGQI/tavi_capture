import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:tavi_capture/core/mcap/mcap_frame_loader.dart';
import 'package:tavi_capture/core/mcap/mcap_review_index.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads a bgr8 Image message into a ui.Image', () async {
    final payload = _bgrImagePayload();
    final dir = Directory.systemTemp.createTempSync('mcap_frame_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/frame.bin')..writeAsBytesSync(payload);

    final loader = McapFrameLoader(file.path);
    addTearDown(loader.close);
    final image = await loader.load(
      McapFrameRef(time: 0, offset: 0, length: payload.length),
    );
    addTearDown(image.dispose);

    expect(image.width, 2);
    expect(image.height, 1);
  });
}

/// 两像素 bgr8 图像：红、绿。
Uint8List _bgrImagePayload() {
  final out = <int>[
    0x00, 0x01, 0x00, 0x00, // CDR LE
    ..._i32(1),
    ..._u32(2),
    ..._string('cam'),
    ..._u32(1), // height
    ..._u32(2), // width
    ..._string('bgr8'),
    0x00, // is_bigendian
    0x00, 0x00, // align step to 4 (origin = 4)
    ..._u32(6), // step
    ..._u32(6), // data length
    0x00, 0x00, 0xff, // red
    0x00, 0xff, 0x00, // green
  ];
  return Uint8List.fromList(out);
}

List<int> _string(String value) {
  final bytes = value.codeUnits;
  return [..._u32(bytes.length + 1), ...bytes, 0];
}

List<int> _u32(int value) {
  return [
    value & 0xff,
    (value >> 8) & 0xff,
    (value >> 16) & 0xff,
    (value >> 24) & 0xff,
  ];
}

List<int> _i32(int value) => _u32(value);
