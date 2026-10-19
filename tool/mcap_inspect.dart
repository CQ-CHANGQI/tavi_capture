import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:tavi_capture/core/mcap/mcap_reader.dart';
import 'package:tavi_capture/core/mcap/ros2_messages.dart';

/// 用法：
///   dart run tool/mcap_inspect.dart /path/to/data.mcap
///
/// 只依赖 dart:io，不启动 Flutter，方便在 Mac 上直接验证真实包。
void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/mcap_inspect.dart <file.mcap>');
    exitCode = 64;
    return;
  }

  final path = args.first;
  final outputDir = Directory('build/mcap_frames');
  if (!outputDir.existsSync()) outputDir.createSync(recursive: true);

  final file = McapFile.open(path);
  final schemas = <int, McapSchema>{};
  final channels = <int, McapChannel>{};
  final counts = <int, int>{};
  final firstSamples = <String, Object>{};
  final nextFrameAt = <int, int>{};
  final savedFrames = <String, int>{};
  var messageCount = 0;
  int? startTime;
  int? endTime;
  McapHeader? header;

  try {
    for (final record in file.records()) {
      switch (record) {
        case McapHeader():
          header = record;
        case McapSchema():
          schemas[record.id] = record;
        case McapChannel():
          channels[record.id] = record;
        case McapMessage():
          final channel = channels[record.channelId];
          final schema = channel == null ? null : schemas[channel.schemaId];
          if (channel == null || schema == null) continue;
          messageCount++;
          counts[record.channelId] = (counts[record.channelId] ?? 0) + 1;
          startTime = startTime == null || record.logTime < startTime
              ? record.logTime
              : startTime;
          endTime = endTime == null || record.logTime > endTime
              ? record.logTime
              : endTime;

          if (!firstSamples.containsKey(schema.name)) {
            try {
              firstSamples[schema.name] = decodeRos2Message(
                schema.name,
                record.data,
              );
            } on UnsupportedError {
              firstSamples[schema.name] = 'not decoded';
            }
          }

          if (schema.name == 'sensor_msgs/msg/Image') {
            final image = _tryImage(schema.name, record.data);
            if (image == null) continue;
            final next = nextFrameAt[record.channelId] ?? record.logTime;
            if (record.logTime >= next) {
              _saveFrame(outputDir, channel, image);
              savedFrames[channel.topic] =
                  (savedFrames[channel.topic] ?? 0) + 1;
              nextFrameAt[record.channelId] = record.logTime + 10000000000;
            }
          }
      }
    }
  } finally {
    file.close();
  }

  final duration = startTime == null || endTime == null
      ? Duration.zero
      : Duration(microseconds: (endTime - startTime) ~/ 1000);

  stdout.writeln('file      : $path (${_bytes(File(path).lengthSync())})');
  stdout.writeln('profile   : ${header?.profile}');
  stdout.writeln('library   : ${header?.library}');
  stdout.writeln('messages  : $messageCount');
  stdout.writeln('duration  : ${duration.inMilliseconds / 1000}s');
  stdout.writeln('channels  : ${channels.length}');
  stdout.writeln('');
  stdout.writeln('${'topic'.padRight(44)}${'schema'.padRight(36)}count');
  for (final channel in channels.values) {
    final schema = schemas[channel.schemaId];
    stdout.writeln(
      '${channel.topic.padRight(44)}${(schema?.name ?? '?').padRight(36)}${counts[channel.id] ?? 0}',
    );
  }

  stdout.writeln('');
  for (final entry in firstSamples.entries) {
    stdout.writeln('[${entry.key}] ${_describe(entry.value)}');
  }

  stdout.writeln('');
  for (final entry in savedFrames.entries) {
    stdout.writeln('frames    : ${entry.key} -> ${entry.value}');
  }
  stdout.writeln('output    : ${outputDir.path}');
}

RosImage? _tryImage(String schemaName, Uint8List data) {
  try {
    final decoded = decodeRos2Message(schemaName, data);
    return decoded is RosImage ? decoded : null;
  } catch (error) {
    stderr.writeln('image decode failed: $error');
    return null;
  }
}

void _saveFrame(Directory dir, McapChannel channel, RosImage image) {
  final rgba = image.toRgba();
  final stamp = image.header.sec * 1000 + image.header.nanosec ~/ 1000000;
  final name = channel.topic.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
  final file = File('${dir.path}/${name}_$stamp.png');
  file.writeAsBytesSync(encodePng(image.width, image.height, rgba));
}

String _describe(Object message) {
  return switch (message) {
    RosJointState() =>
      'frame=${message.header.frameId} names=${message.name} '
          'position=${message.position.map((e) => e.toStringAsFixed(3)).toList()}',
    RosPoseStamped() =>
      'frame=${message.header.frameId} '
          'p=(${message.position.x.toStringAsFixed(3)}, '
          '${message.position.y.toStringAsFixed(3)}, '
          '${message.position.z.toStringAsFixed(3)})',
    RosImage() =>
      'frame=${message.header.frameId} ${message.width}x${message.height} '
          '${message.encoding} step=${message.step}',
    RosGripper() =>
      'angle=${message.angle.toStringAsFixed(3)} '
          'distance=${message.distance.toStringAsFixed(4)} '
          'effort=${message.effort.toStringAsFixed(1)} '
          'voltage=${message.voltage.toStringAsFixed(2)} '
          'status=${message.status}',
    RosTeleopStatus() =>
      'topics=${message.topics} fail=${message.fail} quit=${message.quit}',
    RosString() => 'string length=${message.data.length}',
    _ => message.toString(),
  };
}

String _bytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

Uint8List encodePng(int width, int height, Uint8List rgba) {
  final stride = width * 4;
  final raw = Uint8List((stride + 1) * height);
  for (var y = 0; y < height; y++) {
    final row = y * (stride + 1);
    raw[row] = 0; // filter: none
    raw.setRange(row + 1, row + 1 + stride, rgba, y * stride);
  }
  final compressed = Uint8List.fromList(ZLibCodec(level: 6).encode(raw));
  final ihdr = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, 6)
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);

  final output = BytesBuilder(copy: false)
    ..add(const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
    ..add(_pngChunk('IHDR', ihdr.buffer.asUint8List()))
    ..add(_pngChunk('IDAT', compressed))
    ..add(_pngChunk('IEND', Uint8List(0)));
  return output.toBytes();
}

Uint8List _pngChunk(String type, Uint8List data) {
  final typeBytes = ascii.encode(type);
  final body = BytesBuilder(copy: false)
    ..add(typeBytes)
    ..add(data);
  final bodyBytes = body.toBytes();
  final output = BytesBuilder(copy: false)
    ..add(_u32(data.length))
    ..add(bodyBytes)
    ..add(_u32(_crc32(bodyBytes)));
  return output.toBytes();
}

Uint8List _u32(int value) {
  final data = ByteData(4)..setUint32(0, value);
  return data.buffer.asUint8List();
}

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc = _crcTable[(crc ^ byte) & 0xff] ^ (crc >> 8);
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
