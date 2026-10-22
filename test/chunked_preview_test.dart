import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tavi_capture/core/lcm/chunked_preview.dart';
import 'package:tavi_capture/core/lcm/codec.dart';
import 'package:tavi_capture/core/lcm/types.dart';

const _channel = '/preview/cameras/cam_left';

void main() {
  test('reassembles chunked JPEG, including a short last chunk', () {
    final jpeg = _fakeJpeg(3000);
    final assembler = ChunkedPreviewAssembler();

    expect(
      assembler.add(_channel, _packet(2, 3, 3000, jpeg.sublist(2400))),
      isNull,
    );
    expect(
      assembler.add(_channel, _packet(0, 3, 3000, jpeg.sublist(0, 1200))),
      isNull,
    );

    final image = assembler.add(
      _channel,
      _packet(1, 3, 3000, jpeg.sublist(1200, 2400)),
    );

    expect(image, isNotNull);
    expect(image!.camera, 'cam_left');
    expect(image.width, 640);
    expect(image.height, 360);
    expect(image.bytes.length, 3000);
    expect(image.bytes.sublist(0, 2), <int>[0xFF, 0xD8]);
  });

  test('incomplete frame is not emitted', () {
    final jpeg = _fakeJpeg(3000);
    final assembler = ChunkedPreviewAssembler();

    expect(
      assembler.add(_channel, _packet(0, 3, 3000, jpeg.sublist(0, 1200))),
      isNull,
    );
    expect(
      assembler.add(_channel, _packet(2, 3, 3000, jpeg.sublist(2400))),
      isNull,
    );
  });

  test('two frames with the same size never mix', () {
    final a = _fakeJpeg(3000, fill: 0x11);
    final b = _fakeJpeg(3000, fill: 0x22);
    final assembler = ChunkedPreviewAssembler();

    // Frame A loses chunk 1, so its entry stays pending.
    expect(
      assembler.add(
        _channel,
        _packet(0, 3, 3000, a.sublist(0, 1200), timestamp: 1),
      ),
      isNull,
    );
    expect(
      assembler.add(
        _channel,
        _packet(2, 3, 3000, a.sublist(2400), timestamp: 1),
      ),
      isNull,
    );

    // Frame B has the same JPEG size; it must not complete A's entry.
    expect(
      assembler.add(
        _channel,
        _packet(0, 3, 3000, b.sublist(0, 1200), timestamp: 2),
      ),
      isNull,
    );
    expect(
      assembler.add(
        _channel,
        _packet(1, 3, 3000, b.sublist(1200, 2400), timestamp: 2),
      ),
      isNull,
    );
    final image = assembler.add(
      _channel,
      _packet(2, 3, 3000, b.sublist(2400), timestamp: 2),
    );

    expect(image, isNotNull);
    expect(image!.bytes.length, 3000);
    // Chunk 1 of B; a mixed frame would still carry A's fill byte here.
    expect(image.bytes[1200], 0x22);
    expect(assembler.pendingFrames, 1); // A is still waiting for its chunk
  });

  test('duplicate chunk is ignored', () {
    final jpeg = _fakeJpeg(3000);
    final assembler = ChunkedPreviewAssembler();

    expect(
      assembler.add(_channel, _packet(0, 3, 3000, jpeg.sublist(0, 1200))),
      isNull,
    );
    expect(
      assembler.add(_channel, _packet(0, 3, 3000, jpeg.sublist(0, 1200))),
      isNull,
    );
    expect(
      assembler.add(_channel, _packet(1, 3, 3000, jpeg.sublist(1200, 2400))),
      isNull,
    );

    final image = assembler.add(
      _channel,
      _packet(2, 3, 3000, jpeg.sublist(2400)),
    );
    expect(image, isNotNull);
    expect(image!.bytes.length, 3000);
  });

  test('bounded in-flight frames: the oldest is evicted', () {
    final stats = LcmStats();
    final assembler = ChunkedPreviewAssembler(stats: stats);
    final jpeg = _fakeJpeg(3000);

    for (var id = 1; id <= 3; id++) {
      expect(
        assembler.add(
          _channel,
          _packet(0, 3, 3000, jpeg.sublist(0, 1200), timestamp: id),
        ),
        isNull,
      );
    }
    expect(assembler.pendingFrames, 3);

    expect(
      assembler.add(
        _channel,
        _packet(0, 3, 3000, jpeg.sublist(0, 1200), timestamp: 4),
      ),
      isNull,
    );

    expect(assembler.pendingFrames, 3);
    expect(stats.incompleteFrames, 1);
  });

  test('payload that is not an image is counted as corrupt', () {
    final stats = LcmStats();
    final assembler = ChunkedPreviewAssembler(stats: stats);
    final blank = Uint8List(3000); // no SOI / PNG signature

    assembler.add(_channel, _packet(0, 3, 3000, blank.sublist(0, 1200)));
    assembler.add(_channel, _packet(1, 3, 3000, blank.sublist(1200, 2400)));
    final image = assembler.add(
      _channel,
      _packet(2, 3, 3000, blank.sublist(2400)),
    );

    expect(image, isNull);
    expect(stats.corruptFrames, 1);
  });

  test('accepts a package regardless of its type fingerprint', () {
    // The Compose client skips the fingerprint; a changed .lcm hash must not
    // blank the preview.
    final jpeg = _fakeJpeg(1300);
    final assembler = ChunkedPreviewAssembler();
    final first = _packet(0, 2, 1300, jpeg.sublist(0, 1200))
      ..fillRange(0, 8, 0);
    final second = _packet(1, 2, 1300, jpeg.sublist(1200))..fillRange(0, 8, 0);

    expect(assembler.add(_channel, first), isNull);
    final image = assembler.add(_channel, second);
    expect(image, isNotNull);
    expect(image!.bytes.length, 1300);
  });

  test('chunked PNG dimensions come from the IHDR header', () {
    final png = _fakePng(320, 180);
    final assembler = ChunkedPreviewAssembler();
    final image = assembler.add(_channel, _packet(0, 1, png.length, png));

    expect(image, isNotNull);
    expect(image!.width, 320);
    expect(image.height, 180);
  });

  test('joint batches are reassembled from preview_package_t fragments', () {
    final raw = _jointBatch();
    expect(decodePreviewPackage(raw), isNull); // a raw joint_batch_t is not one

    final emitted = <List<JointFrame>>[];
    final assembler = JointBatchAssembler(emitted.add);
    final messages = _fragments(raw, messageId: 42);

    // Out of order, then duplicate the first and last fragment.
    for (final message in messages.reversed) {
      assembler.add(decodePreviewPackage(message)!);
    }
    assembler.add(decodePreviewPackage(messages.first)!);
    assembler.add(decodePreviewPackage(messages.last)!);

    expect(emitted, hasLength(1));
    final frame = emitted.single.single;
    expect(frame.timestampNs, 777);
    expect(frame.stateNames, <String>['j1/position']);
    expect(frame.stateValues, <double>[1.5]);
  });
}

Uint8List _packet(
  int index,
  int count,
  int total,
  Uint8List data, {
  int timestamp = 123456789,
}) {
  final bytes = ByteData(36 + data.length);
  const fingerprint = <int>[0x6a, 0x92, 0xf4, 0x94, 0x7c, 0xbc, 0x31, 0x90];
  for (var i = 0; i < fingerprint.length; i++) {
    bytes.setUint8(i, fingerprint[i]);
  }
  bytes.setInt64(8, timestamp, Endian.big);
  bytes.setUint32(16, 42, Endian.big);
  bytes.setUint32(20, index, Endian.big);
  bytes.setUint32(24, count, Endian.big);
  bytes.setUint32(28, total, Endian.big);
  bytes.setUint32(32, data.length, Endian.big);

  final out = bytes.buffer.asUint8List();
  out.setRange(36, 36 + data.length, data);
  return out;
}

Uint8List _fakeJpeg(int length, {int fill = 0}) {
  final jpeg = Uint8List(length);
  if (fill != 0) jpeg.fillRange(0, length, fill);
  jpeg[0] = 0xFF;
  jpeg[1] = 0xD8;
  jpeg[2] = 0xFF;
  jpeg[3] = 0xC0;
  jpeg[4] = 0;
  jpeg[5] = 17; // SOF segment length
  jpeg[6] = 8; // precision
  jpeg[7] = 0x01; // height 360
  jpeg[8] = 0x68;
  jpeg[9] = 0x02; // width 640
  jpeg[10] = 0x80;
  jpeg[length - 2] = 0xFF;
  jpeg[length - 1] = 0xD9;
  return jpeg;
}

Uint8List _fakePng(int width, int height) {
  final bytes = Uint8List(24);
  bytes.setRange(0, 8, <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  final data = ByteData.sublistView(bytes);
  data.setUint32(8, 13, Endian.big); // IHDR length
  bytes.setRange(12, 16, <int>[0x49, 0x48, 0x44, 0x52]); // "IHDR"
  data.setUint32(16, width, Endian.big);
  data.setUint32(20, height, Endian.big);
  return bytes;
}

List<Uint8List> _fragments(Uint8List payload, {required int messageId}) {
  final total = payload.length;
  final count = (total + previewFragmentPayload - 1) ~/ previewFragmentPayload;
  return <Uint8List>[
    for (var i = 0; i < count; i++)
      _packet(
        i,
        count,
        total,
        payload.sublist(
          i * previewFragmentPayload,
          math.min((i + 1) * previewFragmentPayload, total),
        ),
        timestamp: messageId,
      ),
  ];
}

/// One `joint_batch_t` with a single frame: timestamp 777, state
/// `j1/position` = 1.5, no command values.
Uint8List _jointBatch() {
  final out = BytesBuilder();
  void be32(int value) => out.add(
    (ByteData(4)..setInt32(0, value, Endian.big)).buffer.asUint8List(),
  );
  void be64(int value) => out.add(
    (ByteData(8)..setInt64(0, value, Endian.big)).buffer.asUint8List(),
  );
  void beF64(double value) => out.add(
    (ByteData(8)..setFloat64(0, value, Endian.big)).buffer.asUint8List(),
  );
  void lcmString(String value) {
    final bytes = utf8.encode(value);
    be32(bytes.length + 1); // LCM strings include the trailing NUL
    out.add(bytes);
    out.addByte(0);
  }

  out.add(Uint8List(8)); // fingerprint (skipped by the decoder)
  be32(1); // num_frames
  for (var i = 0; i < 10; i++) {
    be64(i == 0 ? 777 : 0);
  }
  for (var i = 0; i < 10; i++) {
    lcmString(i == 0 ? 'j1/position' : '');
  }
  for (var i = 0; i < 10; i++) {
    lcmString('');
  }
  for (var i = 0; i < 10; i++) {
    be32(i == 0 ? 1 : 0); // state_value_count
  }
  for (var i = 0; i < 10; i++) {
    be32(0); // command_value_count
  }
  for (var i = 0; i < 10; i++) {
    for (var j = 0; j < 128; j++) {
      beF64(i == 0 && j == 0 ? 1.5 : 0);
    }
  }
  for (var i = 0; i < 10; i++) {
    for (var j = 0; j < 128; j++) {
      beF64(0);
    }
  }
  return out.takeBytes();
}
