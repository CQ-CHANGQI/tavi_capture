import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tavi_capture/core/mcap/mcap_codecs.dart';

/// 最小 CDR 写入器：够用来构造 JointState / Statistics 测试数据。
class _CdrWriter {
  final _bytes = BytesBuilder();
  int _offset = 0;

  _CdrWriter() {
    _bytes.add([0, 1, 0, 0]); // encapsulation header, little-endian
    _offset = 4;
  }

  void _align(int alignment) {
    // CDR 对齐是相对于 4 字节封装头之后的位置。
    final relative = _offset - 4;
    final pad = (alignment - relative % alignment) % alignment;
    if (pad > 0) {
      _bytes.add(List.filled(pad, 0));
      _offset += pad;
    }
  }

  void int32(int value) {
    _align(4);
    final data = ByteData(4)..setInt32(0, value, Endian.little);
    _bytes.add(data.buffer.asUint8List());
    _offset += 4;
  }

  void uint8(int value) {
    _bytes.add([value & 0xff]);
    _offset += 1;
  }

  void uint32(int value) {
    _align(4);
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    _bytes.add(data.buffer.asUint8List());
    _offset += 4;
  }

  void float64(double value) {
    _align(8);
    final data = ByteData(8)..setFloat64(0, value, Endian.little);
    _bytes.add(data.buffer.asUint8List());
    _offset += 8;
  }

  void string(String value) {
    final encoded = [for (final code in value.codeUnits) code, 0];
    uint32(encoded.length);
    _bytes.add(encoded);
    _offset += encoded.length;
  }

  void stringArray(List<String> values) {
    uint32(values.length);
    for (final value in values) {
      string(value);
    }
  }

  void doubleArray(List<double> values) {
    uint32(values.length);
    for (final value in values) {
      float64(value);
    }
  }

  Uint8List take() => _bytes.takeBytes();
}

void main() {
  test('解码 pal_statistics_msgs/Statistics：指令和状态都保留', () {
    final writer = _CdrWriter()
      ..int32(1768893097)
      ..uint32(405022229)
      ..string('left_arm_base_link')
      ..uint32(4)
      ..string('state_interface.left_joint1/position')
      ..float64(1.25)
      ..string('command_interface.left_joint1/position')
      ..float64(-0.5)
      ..string('state_interface.left_joint1/velocity')
      ..float64(9.9)
      ..string('diagnostic_counter')
      ..float64(42);

    final statistics = decodeRosStatistics(writer.take());
    expect(statistics.statistics.length, 4);
    expect(
      statistics.statistics[0].name,
      'state_interface.left_joint1/position',
    );
    expect(statistics.statistics[0].value, 1.25);
    expect(
      statistics.statistics[1].name,
      'command_interface.left_joint1/position',
    );
    expect(statistics.statistics[1].value, -0.5);
  });

  test('解码 sensor_msgs/msg/JointState：名字和位置一一对应', () {
    final writer = _CdrWriter()
      ..int32(1768893097)
      ..uint32(0)
      ..string('left_arm')
      ..stringArray(['joint1', 'joint2', 'joint3'])
      ..doubleArray([0.1, -0.2, 0.3])
      ..doubleArray([1, 2, 3])
      ..doubleArray([4, 5, 6]);

    final state = decodeRosJointState(writer.take());
    expect(state.names, ['joint1', 'joint2', 'joint3']);
    expect(state.positions, [0.1, -0.2, 0.3]);
    expect(state.velocities, [1, 2, 3]);
    expect(state.efforts, [4, 5, 6]);
  });

  test('bgr8 Image：通道顺序转换成 RGBA', () {
    // 2x1，BGR 蓝/红。
    final writer = _CdrWriter()
      ..int32(0)
      ..uint32(0)
      ..string('cam')
      ..uint32(1)
      ..uint32(2)
      ..string('bgr8')
      ..uint8(0)
      ..uint32(6)
      ..uint32(6);
    final payload = writer.take();
    final image = decodeRosImage(
      Uint8List.fromList([...payload, 255, 0, 0, 0, 0, 255]),
    );
    expect(image.width, 2);
    expect(image.height, 1);
    expect(image.rgba.sublist(0, 8), [0, 0, 255, 255, 255, 0, 0, 255]);
  });
}
