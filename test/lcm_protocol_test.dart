import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tavi_capture/core/lcm/lcm_message.dart';
import 'package:tavi_capture/core/lcm/preview_protocol.dart';

// ---------------------------------------------------------------------------
// 组包工具：按真实线上格式拼字节
// ---------------------------------------------------------------------------

Uint8List _int32(int value) =>
    (ByteData(4)..setInt32(0, value)).buffer.asUint8List();

Uint8List _int64(int value) =>
    (ByteData(8)..setInt64(0, value)).buffer.asUint8List();

Uint8List _uint16(int value) =>
    (ByteData(2)..setUint16(0, value)).buffer.asUint8List();

Uint8List _double(double value) =>
    (ByteData(8)..setFloat64(0, value)).buffer.asUint8List();

Uint8List _lcmString(String value) {
  final bytes = utf8.encode(value);
  return Uint8List.fromList([..._int32(bytes.length + 1), ...bytes, 0]);
}

Uint8List _shortMessage(String channel, List<int> payload, {int seq = 1}) {
  final builder = BytesBuilder()
    ..add(_int32(0x4c433032))
    ..add(_int32(seq))
    ..add(utf8.encode(channel))
    ..add([0])
    ..add(payload);
  return builder.takeBytes();
}

/// 把 payload 切成长包分片；channel 只写在第 0 片。
List<Uint8List> _longFragments(
  String channel,
  List<int> payload, {
  int seq = 7,
  int parts = 3,
}) {
  final total = payload.length;
  final size = (total / parts).ceil();
  final result = <Uint8List>[];
  var offset = 0;
  for (var index = 0; index < parts; index++) {
    final end = math.min(offset + size, total);
    final chunk = payload.sublist(offset, end);
    final builder = BytesBuilder()
      ..add(_int32(0x4c433033))
      ..add(_int32(seq))
      ..add(_int32(total))
      ..add(_int32(offset))
      ..add(_uint16(index))
      ..add(_uint16(parts));
    if (index == 0) {
      builder
        ..add(utf8.encode(channel))
        ..add([0]);
    }
    builder.add(chunk);
    result.add(builder.takeBytes());
    offset = end;
  }
  return result;
}

Uint8List _previewChunk({
  required int messageId,
  required int index,
  required int count,
  required int total,
  required List<int> payload,
  int streamId = 1,
}) {
  final header = ByteData(previewChunkHeaderBytes + payload.length);
  header.setInt64(8, messageId);
  header.setInt32(16, streamId);
  header.setInt32(20, index);
  header.setInt32(24, count);
  header.setInt32(28, total);
  header.setInt32(32, payload.length);
  final bytes = header.buffer.asUint8List();
  bytes.setRange(previewChunkHeaderBytes, bytes.length, payload);
  return bytes;
}

List<Uint8List> _previewFrames(
  List<int> image, {
  required int messageId,
  int streamId = 1,
}) {
  final count =
      (image.length + previewChunkPayloadBytes - 1) ~/ previewChunkPayloadBytes;
  return [
    for (var index = 0; index < count; index++)
      _previewChunk(
        messageId: messageId,
        streamId: streamId,
        index: index,
        count: count,
        total: image.length,
        payload: image.sublist(
          index * previewChunkPayloadBytes,
          math.min((index + 1) * previewChunkPayloadBytes, image.length),
        ),
      ),
  ];
}

/// 一帧 joint_batch_t：10 个固定槽位，只有第 0 个有真实数据。
Uint8List _jointBatch({
  required int timestamp,
  required List<String> stateNames,
  required List<double> stateValues,
  required List<String> commandNames,
  required List<double> commandValues,
}) {
  final builder = BytesBuilder()..add(Uint8List(8));
  builder.add(_int32(1));
  for (var i = 0; i < 10; i++) {
    builder.add(_int64(i == 0 ? timestamp : 0));
  }
  for (var i = 0; i < 10; i++) {
    builder.add(_lcmString(i == 0 ? stateNames.join('\n') : ''));
  }
  for (var i = 0; i < 10; i++) {
    builder.add(_lcmString(i == 0 ? commandNames.join('\n') : ''));
  }
  for (var i = 0; i < 10; i++) {
    builder.add(_int32(i == 0 ? stateNames.length : 0));
  }
  for (var i = 0; i < 10; i++) {
    builder.add(_int32(i == 0 ? commandNames.length : 0));
  }
  // 先占位 10×128 个 double，再按结构回填第 0 行。
  for (var i = 0; i < 128 * 10 * 2; i++) {
    builder.add(_double(0));
  }
  final bytes = builder.takeBytes();
  final data = ByteData.sublistView(bytes);
  final reader = BigEndianReader(bytes)..skip(8);
  reader.int32;
  for (var i = 0; i < 10; i++) {
    reader.int64;
  }
  for (var i = 0; i < 10; i++) {
    reader.lcmString();
  }
  for (var i = 0; i < 10; i++) {
    reader.lcmString();
  }
  for (var i = 0; i < 10; i++) {
    reader.int32;
  }
  for (var i = 0; i < 10; i++) {
    reader.int32;
  }
  var position = reader.offset;
  for (var i = 0; i < 128; i++) {
    data.setFloat64(position, i < stateValues.length ? stateValues[i] : 0);
    position += 8;
  }
  // 状态行其余 9 行保持 0，然后是指令第 0 行。
  position += 128 * 8 * 9;
  for (var i = 0; i < 128; i++) {
    data.setFloat64(position, i < commandValues.length ? commandValues[i] : 0);
    position += 8;
  }
  return bytes;
}

void main() {
  test('短包：解出通道和载荷', () {
    final reader = LcmMessageReader();
    final message = reader.read(
      _shortMessage('/preview/cameras/cam_head', [1, 2, 3]),
      sender: '1.2.3.4:7667',
    );
    expect(message, isNotNull);
    expect(message!.channel, '/preview/cameras/cam_head');
    expect(message.payload, [1, 2, 3]);
  });

  test('长包：通道只在第 0 片，乱序也能拼回', () {
    final payload = [for (var i = 0; i < 100; i++) i];
    final fragments = _longFragments('/preview/joint_batch', payload);
    final reader = LcmMessageReader();

    LcmMessage? message;
    // 先收 1、2，再收带通道名的 0。
    for (final index in [1, 2, 0]) {
      message = reader.read(fragments[index], sender: '10.0.0.2:7668');
    }
    expect(message, isNotNull);
    expect(message!.channel, '/preview/joint_batch');
    expect(message.payload, payload);
    expect(reader.pending, 0);
  });

  test('长包：缺片超时后被丢弃', () async {
    final reader = LcmMessageReader(timeout: const Duration(milliseconds: 1));
    final fragments = _longFragments(
      '/preview/joint_batch',
      List.filled(60, 1),
    );
    expect(reader.read(fragments[0], sender: 'a:1'), isNull);
    expect(reader.pending, 1);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    reader.expire();
    expect(reader.pending, 0);
    expect(reader.counters.dropped, 1);
  });

  test('preview 分片：1200 字节切片按 message_id 重组', () {
    final image = [0xFF, 0xD8, ...List.filled(3000, 0xAB)];
    final frames = _previewFrames(image, messageId: 42);
    final assembler = PreviewAssembler();

    Uint8List? result;
    for (final chunk in frames.reversed) {
      final parsed = readPreviewChunk(chunk)!;
      result = assembler.add('cam_head/1', parsed);
    }
    expect(result, image);
  });

  test('同尺寸的两帧不会串', () {
    final first = [0xFF, 0xD8, ...List.filled(3000, 0x01)];
    final second = [0xFF, 0xD8, ...List.filled(3000, 0x02)];
    final a = _previewFrames(first, messageId: 1);
    final b = _previewFrames(second, messageId: 2);
    final assembler = PreviewAssembler();

    Uint8List? result;
    for (var i = 0; i < 3; i++) {
      result = assembler.add('cam_head/1', readPreviewChunk(a[i])!);
      result = assembler.add('cam_head/1', readPreviewChunk(b[i])!) ?? result;
    }
    expect(result, second);
  });

  test('完成过新帧后，旧帧分片被忽略', () {
    final image = [0xFF, 0xD8, ...List.filled(1500, 0x01)];
    final frames = _previewFrames(image, messageId: 5);
    final assembler = PreviewAssembler();
    for (final chunk in frames) {
      assembler.add('cam_head/1', readPreviewChunk(chunk)!);
    }
    final late = readPreviewChunk(frames.first)!;
    expect(assembler.add('cam_head/1', late), isNull);
    expect(assembler.counters.dropped, greaterThan(0));
  });

  test('每路最多 3 个半成品，丢了片的帧不阻塞后面的帧', () {
    final assembler = PreviewAssembler();
    for (var id = 10; id < 14; id++) {
      final chunk = _previewFrames([
        0xFF,
        0xD8,
        ...List.filled(1500, id),
      ], messageId: id).first;
      assembler.add('cam_head/1', readPreviewChunk(chunk)!);
    }
    expect(assembler.pendingFrames, 3);
    expect(assembler.counters.incomplete, 1);
  });

  test('坏分片：片数/长度对不上直接拒绝', () {
    final chunk = _previewChunk(
      messageId: 1,
      index: 0,
      count: 3,
      total: 3000,
      payload: List.filled(1200, 0),
    );
    expect(readPreviewChunk(chunk), isNotNull);
    // 改掉 count，变成不合法分片。
    chunk[27] = 2;
    expect(readPreviewChunk(chunk), isNull);
  });

  test('joint_batch：状态/指令按名字对齐，非 position 丢弃', () {
    final payload = _jointBatch(
      timestamp: 1768893097,
      stateNames: [
        'left_joint1/position',
        'left_joint2/position',
        'left_joint1/velocity',
      ],
      stateValues: [1.0, -2.0, 9.9],
      commandNames: ['left_joint1/position', 'left_joint2/position'],
      commandValues: [1.5, -2.5],
    );
    final batches = decodeJointBatches(payload);
    expect(batches, hasLength(1));
    expect(batches.first.timestampNs, 1768893097);
    expect(batches.first.state, {'left_joint1': 1.0, 'left_joint2': -2.0});
    expect(batches.first.command, {'left_joint1': 1.5, 'left_joint2': -2.5});
  });

  test('路由：相机通道出画面，关节通道出批次', () {
    final frames = <CameraFrame>[];
    final joints = <JointBatch>[];
    final router = PreviewRouter(
      onCameraFrame: frames.add,
      onJointBatches: joints.addAll,
    );

    final image = [0xFF, 0xD8, 0x01, 0x02];
    for (final chunk in _previewFrames(image, messageId: 1)) {
      router.handle(LcmMessage('${cameraChannelPrefix}cam_left', chunk));
    }

    final joint = _jointBatch(
      timestamp: 7,
      stateNames: ['body_joint1/position'],
      stateValues: [0.25],
      commandNames: const [],
      commandValues: const [],
    );
    router.handle(LcmMessage(jointBatchChannel, joint));

    expect(frames, hasLength(1));
    expect(frames.first.camera, 'cam_left');
    expect(frames.first.image, image);
    expect(joints, hasLength(1));
    expect(joints.first.state['body_joint1'], 0.25);
  });

  test('路由：不是 JPEG/PNG 的完整帧计为 corrupt，不交给 UI', () {
    final frames = <CameraFrame>[];
    final router = PreviewRouter(
      onCameraFrame: frames.add,
      onJointBatches: (_) {},
    );
    for (final chunk in _previewFrames([1, 2, 3, 4], messageId: 1)) {
      router.handle(LcmMessage('${cameraChannelPrefix}cam_head', chunk));
    }
    expect(frames, isEmpty);
    expect(router.counters.corrupt, 1);
  });
}
