import 'dart:convert';
import 'dart:typed_data';

import 'mcap_reader.dart';

/// Decoded `sensor_msgs/msg/Image` in RGBA8888.
class McapRawImage {
  McapRawImage({
    required this.width,
    required this.height,
    required this.encoding,
    required this.rgba,
  });

  final int width;
  final int height;
  final String encoding;
  final Uint8List rgba;
}

/// Decoded `sensor_msgs/msg/CompressedImage`.
class McapCompressedImage {
  McapCompressedImage({required this.format, required this.data});

  final String format;
  final Uint8List data;
}

/// One entry from `pal_statistics_msgs/msg/Statistics`.
class McapStatistic {
  McapStatistic({required this.name, required this.value});

  final String name;
  final double value;
}

/// Decoded `pal_statistics_msgs/msg/Statistics`.
class McapStatistics {
  McapStatistics({required this.statistics});

  final List<McapStatistic> statistics;
}

/// Decoded `sensor_msgs/msg/JointState`.
class McapJointState {
  McapJointState({
    required this.names,
    required this.positions,
    required this.velocities,
    required this.efforts,
  });

  final List<String> names;
  final List<double> positions;
  final List<double> velocities;
  final List<double> efforts;
}

McapRawImage decodeRosImage(Uint8List cdr) {
  final reader = _CdrReader(cdr);
  reader.int32(); // stamp.sec
  reader.uint32(); // stamp.nanosec
  reader.string(); // header.frame_id
  final height = reader.uint32();
  final width = reader.uint32();
  final encoding = reader.string();
  reader.uint8(); // is_bigendian (8-bit encodings are unaffected)
  final step = reader.uint32();
  final data = reader.uint8Array();

  if (width <= 0 || height <= 0 || step <= 0) {
    throw McapException('Image 尺寸无效: ${width}x$height step=$step');
  }
  if (data.length < step * height) {
    throw McapException('Image 数据不足: ${data.length} < ${step * height}');
  }

  final rgba = Uint8List(width * height * 4);
  final channels = switch (encoding) {
    'bgr8' || 'rgb8' => 3,
    'bgra8' || 'rgba8' => 4,
    'mono8' => 1,
    _ => throw McapException('暂不支持 Image 编码: $encoding'),
  };
  if (step < width * channels) {
    throw McapException('Image step 太小: $step');
  }

  for (var y = 0; y < height; y++) {
    final row = y * step;
    for (var x = 0; x < width; x++) {
      final source = row + x * channels;
      final target = (y * width + x) * 4;
      switch (encoding) {
        case 'bgr8':
          rgba[target] = data[source + 2];
          rgba[target + 1] = data[source + 1];
          rgba[target + 2] = data[source];
          break;
        case 'rgb8':
          rgba[target] = data[source];
          rgba[target + 1] = data[source + 1];
          rgba[target + 2] = data[source + 2];
          break;
        case 'bgra8':
          rgba[target] = data[source + 2];
          rgba[target + 1] = data[source + 1];
          rgba[target + 2] = data[source];
          rgba[target + 3] = data[source + 3];
          continue;
        case 'rgba8':
          rgba[target] = data[source];
          rgba[target + 1] = data[source + 1];
          rgba[target + 2] = data[source + 2];
          rgba[target + 3] = data[source + 3];
          continue;
        case 'mono8':
          final value = data[source];
          rgba[target] = value;
          rgba[target + 1] = value;
          rgba[target + 2] = value;
          break;
      }
      rgba[target + 3] = 255;
    }
  }
  return McapRawImage(
    width: width,
    height: height,
    encoding: encoding,
    rgba: rgba,
  );
}

McapCompressedImage decodeRosCompressedImage(Uint8List cdr) {
  final reader = _CdrReader(cdr);
  reader.int32(); // stamp.sec
  reader.uint32(); // stamp.nanosec
  reader.string(); // header.frame_id
  final format = reader.string();
  final data = reader.uint8Array();
  return McapCompressedImage(format: format, data: data);
}

McapStatistics decodeRosStatistics(Uint8List cdr) {
  final reader = _CdrReader(cdr);
  reader.int32(); // stamp.sec
  reader.uint32(); // stamp.nanosec
  reader.string(); // header.frame_id
  final count = reader.uint32();
  final statistics = <McapStatistic>[
    for (var i = 0; i < count; i++)
      McapStatistic(name: reader.string(), value: reader.float64()),
  ];
  return McapStatistics(statistics: statistics);
}

McapJointState decodeRosJointState(Uint8List cdr) {
  final reader = _CdrReader(cdr);
  reader.int32(); // stamp.sec
  reader.uint32(); // stamp.nanosec
  reader.string(); // header.frame_id
  final names = reader.stringArray();
  final positions = reader.float64Array();
  final velocities = reader.float64Array();
  final efforts = reader.float64Array();
  return McapJointState(
    names: names,
    positions: positions,
    velocities: velocities,
    efforts: efforts,
  );
}

class _CdrReader {
  _CdrReader(this.data)
    : _view = ByteData.sublistView(data),
      _endian = data.length > 1 && data[1] == 1 ? Endian.little : Endian.big,
      _offset = 4,
      _base = 4 {
    if (data.length < 4 || data[0] != 0) {
      throw McapException('不是有效的 CDR 数据');
    }
  }

  final Uint8List data;
  final ByteData _view;
  final Endian _endian;
  final int _base;
  int _offset;

  void _align(int alignment) {
    final relative = _offset - _base;
    final aligned = (relative + alignment - 1) & ~(alignment - 1);
    _offset = _base + aligned;
  }

  void _need(int count) {
    if (count < 0 || _offset + count > data.length) {
      throw McapException('CDR 数据越界: offset $_offset, need $count');
    }
  }

  int uint8() {
    _need(1);
    return data[_offset++];
  }

  int int32() {
    _align(4);
    _need(4);
    final value = _view.getInt32(_offset, _endian);
    _offset += 4;
    return value;
  }

  int uint32() {
    _align(4);
    _need(4);
    final value = _view.getUint32(_offset, _endian);
    _offset += 4;
    return value;
  }

  double float64() {
    _align(8);
    _need(8);
    final value = _view.getFloat64(_offset, _endian);
    _offset += 8;
    return value;
  }

  String string() {
    final length = uint32();
    final bytes = _bytes(length);
    if (bytes.isEmpty) return '';
    final end = bytes.last == 0 ? bytes.length - 1 : bytes.length;
    return utf8.decode(bytes.sublist(0, end), allowMalformed: true);
  }

  List<String> stringArray() {
    final length = uint32();
    return [for (var i = 0; i < length; i++) string()];
  }

  List<double> float64Array() {
    final length = uint32();
    _align(8);
    return [for (var i = 0; i < length; i++) float64()];
  }

  Uint8List uint8Array() {
    final length = uint32();
    return _bytes(length);
  }

  Uint8List _bytes(int length) {
    _need(length);
    final bytes = Uint8List.sublistView(data, _offset, _offset + length);
    _offset += length;
    return bytes;
  }
}
