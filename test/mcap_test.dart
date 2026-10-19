import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tavi_capture/core/mcap/mcap_reader.dart';
import 'package:tavi_capture/core/mcap/ros2_messages.dart';

void main() {
  test('decodes JointState CDR from a real ROS2 MCap', () {
    final message = decodeRos2Message(
      'sensor_msgs/msg/JointState',
      _hex(
        '00010000a92a6f6915262418130000006c6566745f61726d5f626173655f6c696e6b000006000000070000006a6f696e74310000070000006a6f696e74320000070000006a6f696e74330000070000006a6f696e74340000070000006a6f696e74350000070000006a6f696e74360000060000004f660aea3eb3fb3f4013101bdca1d43f45ebd1309390fabf1937d9f2d5ca0740892747390d24f7bf2bc1b5aff40f00c006000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
      ),
    ) as RosJointState;

    expect(message.header.sec, 1768893097);
    expect(message.header.nanosec, 405022229);
    expect(message.header.frameId, 'left_arm_base_link');
    expect(message.name, [
      'joint1',
      'joint2',
      'joint3',
      'joint4',
      'joint5',
      'joint6',
    ]);
    expect(message.position.first, closeTo(1.7312611715518818, 1e-12));
    expect(message.position.last, closeTo(-2.0077909209577647, 1e-12));
    expect(message.velocity, everyElement(0.0));
    expect(message.effort, everyElement(0.0));
  });

  test('streams records from byte chunks of any size', () async {
    final bytes = _sampleMcap();
    // 每次只喂 3 字节，专门打乱 header/body 的边界。
    final chunks = <List<int>>[];
    for (var i = 0; i < bytes.length; i += 3) {
      chunks.add(bytes.sublist(i, i + 3 > bytes.length ? bytes.length : i + 3));
    }

    final records = await McapStreamReader(
      Stream.fromIterable(chunks),
      trackOffsets: true,
    ).records().toList();

    expect(records, hasLength(4));
    expect(records[0], isA<McapHeader>());
    expect((records[1] as McapSchema).name, 'test/msg/Sample');
    expect((records[1] as McapSchema).data, [1, 2, 3, 4]);
    expect((records[2] as McapChannel).topic, '/sample');
    expect((records[2] as McapChannel).metadata, isEmpty);
    final message = records[3] as McapMessage;
    expect(message.channelId, 1);
    expect(message.sequence, 7);
    expect(message.logTime, 123456789);
    expect(message.data, [0xde, 0xad, 0xbe, 0xef]);
    expect(message.dataOffset, _indexOf(bytes, const [0xde, 0xad, 0xbe, 0xef]));
  });
}

Uint8List _hex(String value) {
  final bytes = Uint8List(value.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(value.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

Uint8List _sampleMcap() {
  final out = <int>[0x89, 0x4d, 0x43, 0x41, 0x50, 0x30, 0x0d, 0x0a];

  final header = <int>[];
  _string(header, 'ros2');
  _string(header, 'test');
  _record(out, 0x01, header);

  final schema = <int>[];
  _u16(schema, 1);
  _string(schema, 'test/msg/Sample');
  _string(schema, 'ros2msg');
  final schemaData = [1, 2, 3, 4];
  _u32(schema, schemaData.length);
  schema.addAll(schemaData);
  _record(out, 0x03, schema);

  final channel = <int>[];
  _u16(channel, 1);
  _u16(channel, 1);
  _string(channel, '/sample');
  _string(channel, 'cdr');
  _u32(channel, 0); // metadata byte length
  _record(out, 0x04, channel);

  final message = <int>[];
  _u16(message, 1);
  _u32(message, 7);
  _u64(message, 123456789);
  _u64(message, 123456789);
  message.addAll([0xde, 0xad, 0xbe, 0xef]);
  final messageRecord = _recordBytes(0x05, message);

  final chunk = <int>[];
  _u64(chunk, 123456789);
  _u64(chunk, 123456789);
  _u64(chunk, messageRecord.length);
  _u32(chunk, 0);
  _u32(chunk, 0); // compression string
  _u64(chunk, messageRecord.length);
  chunk.addAll(messageRecord);
  _record(out, 0x06, chunk);

  final footer = <int>[];
  _u64(footer, 0);
  _u64(footer, 0);
  _u32(footer, 0);
  _record(out, 0x02, footer);

  return Uint8List.fromList(out);
}

List<int> _recordBytes(int opcode, List<int> body) {
  final out = <int>[opcode];
  _u64(out, body.length);
  out.addAll(body);
  return out;
}

void _record(List<int> out, int opcode, List<int> body) {
  out.addAll(_recordBytes(opcode, body));
}

void _u16(List<int> out, int value) {
  out.addAll([value & 0xff, (value >> 8) & 0xff]);
}

void _u32(List<int> out, int value) {
  out.addAll([
    value & 0xff,
    (value >> 8) & 0xff,
    (value >> 16) & 0xff,
    (value >> 24) & 0xff,
  ]);
}

void _u64(List<int> out, int value) {
  _u32(out, value & 0xffffffff);
  _u32(out, (value >> 32) & 0xffffffff);
}

void _string(List<int> out, String value) {
  final bytes = utf8.encode(value);
  _u32(out, bytes.length);
  out.addAll(bytes);
}

int _indexOf(List<int> bytes, List<int> pattern) {
  for (var i = 0; i <= bytes.length - pattern.length; i++) {
    var match = true;
    for (var j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) {
        match = false;
        break;
      }
    }
    if (match) return i;
  }
  return -1;
}
