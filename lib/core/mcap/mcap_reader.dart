import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// MCAP 文件里的记录。只保留解析 ROS2 包需要的几类。
sealed class McapRecord {
  const McapRecord();
}

class McapHeader extends McapRecord {
  const McapHeader({required this.profile, required this.library});

  final String profile;
  final String library;
}

class McapSchema extends McapRecord {
  const McapSchema({
    required this.id,
    required this.name,
    required this.encoding,
    required this.data,
  });

  final int id;
  final String name;
  final String encoding;
  final Uint8List data;

  String get text => utf8.decode(data, allowMalformed: true);
}

class McapChannel extends McapRecord {
  const McapChannel({
    required this.id,
    required this.schemaId,
    required this.topic,
    required this.messageEncoding,
    required this.metadata,
  });

  final int id;
  final int schemaId;
  final String topic;
  final String messageEncoding;
  final Map<String, String> metadata;
}

class McapMessage extends McapRecord {
  const McapMessage({
    required this.channelId,
    required this.sequence,
    required this.logTime,
    required this.publishTime,
    required this.data,
    this.dataOffset,
  });

  final int channelId;
  final int sequence;
  final int logTime;
  final int publishTime;
  final Uint8List data;

  /// CDR payload 在文件里的绝对偏移；流式解析时为 null。
  final int? dataOffset;
}

/// 顺序读取 MCAP 容器。
///
/// 目前只支持未压缩的 chunk（本仓库的 ROS2 包就是这种）；遇到 zstd/lz4
/// 会抛 [UnsupportedError]，到时候再加解压。
class McapFile {
  McapFile._(this._file, this.length);

  factory McapFile.open(String path) {
    final file = File(path).openSync();
    final result = McapFile._(file, file.lengthSync());
    try {
      final magic = result._read(8);
      if (!_isMagic(magic)) {
        throw const FormatException('Not an MCAP file');
      }
    } catch (_) {
      file.closeSync();
      rethrow;
    }
    return result;
  }

  static const _magic = <int>[0x89, 0x4d, 0x43, 0x41, 0x50, 0x30, 0x0d, 0x0a];

  final RandomAccessFile _file;
  final int length;

  void close() => _file.closeSync();

  /// 从头扫一遍。Schema/Channel/Message 会被解析，其余记录跳过。
  Iterable<McapRecord> records() sync* {
    _file.setPositionSync(8);
    while (_file.positionSync() < length) {
      final header = _read(9);
      final opcode = header[0];
      final size = ByteData.sublistView(header, 1).getUint64(0, Endian.little);
      if (opcode == 0x02) return; // Footer，消息已读完
      final bodyOffset = _file.positionSync();
      yield* _parse(opcode, _read(size), bodyOffset: bodyOffset);
    }
  }

  static Iterable<McapRecord> _parse(
    int opcode,
    Uint8List body, {
    int? bodyOffset,
  }) sync* {
    final reader = _RecordReader(body);
    switch (opcode) {
      case 0x01:
        yield McapHeader(profile: reader.string(), library: reader.string());
        break;
      case 0x03:
        final id = reader.u16();
        final name = reader.string();
        final encoding = reader.string();
        yield McapSchema(
          id: id,
          name: name,
          encoding: encoding,
          data: reader.bytes(reader.u32()),
        );
        break;
      case 0x04:
        final id = reader.u16();
        final schemaId = reader.u16();
        final topic = reader.string();
        final messageEncoding = reader.string();
        final metadata = <String, String>{};
        final metadataEnd = reader.offset + reader.u32();
        while (reader.offset < metadataEnd) {
          final key = reader.string();
          metadata[key] = reader.string();
        }
        yield McapChannel(
          id: id,
          schemaId: schemaId,
          topic: topic,
          messageEncoding: messageEncoding,
          metadata: metadata,
        );
        break;
      case 0x05:
        final channelId = reader.u16();
        final sequence = reader.u32();
        final logTime = reader.u64();
        final publishTime = reader.u64();
        final dataOffset = bodyOffset == null
            ? null
            : bodyOffset + reader.offset;
        yield McapMessage(
          channelId: channelId,
          sequence: sequence,
          logTime: logTime,
          publishTime: publishTime,
          data: reader.rest(),
          dataOffset: dataOffset,
        );
        break;
      case 0x06:
        reader.u64(); // message_start_time
        reader.u64(); // message_end_time
        reader.u64(); // uncompressed_size
        reader.u32(); // uncompressed_crc
        final compression = reader.string();
        if (compression.isNotEmpty) {
          throw UnsupportedError('Compressed MCAP chunks: $compression');
        }
        final recordsLength = reader.u64();
        final recordsOffset = bodyOffset == null
            ? null
            : bodyOffset + reader.offset;
        final inner = _RecordReader(reader.bytes(recordsLength));
        while (inner.remaining >= 9) {
          final innerOpcode = inner.u8();
          final innerSize = inner.u64();
          final innerBodyOffset = recordsOffset == null
              ? null
              : recordsOffset + inner.offset;
          yield* _parse(
            innerOpcode,
            inner.bytes(innerSize),
            bodyOffset: innerBodyOffset,
          );
        }
        break;
      default:
        // MessageIndex / ChunkIndex / Statistics / Attachment 等不参与解析。
        break;
    }
  }

  Uint8List _read(int size) {
    final bytes = _file.readSync(size);
    if (bytes.length != size) {
      throw const FormatException('Unexpected end of MCAP file');
    }
    return bytes;
  }

  static bool _isMagic(Uint8List bytes) {
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) return false;
    }
    return true;
  }
}

/// 从任意字节流解析 MCAP，适合 HTTP/上传流或 [File.openRead]。
///
/// 与 [McapFile] 的区别：不需要可 seek 的文件，边收边解析；chunk 仍然会
/// 整个读进内存后再逐条发消息。
class McapStreamReader {
  McapStreamReader(this._input, {this.trackOffsets = false});

  final Stream<List<int>> _input;

  /// 为 true 时按流内字节位置填 [McapMessage.dataOffset]，用于边下边建帧索引。
  final bool trackOffsets;

  Stream<McapRecord> records() async* {
    final bytes = _StreamBytes(StreamIterator(_input));
    var position = 0;
    try {
      final magic = await bytes.read(8);
      position += 8;
      if (!McapFile._isMagic(magic)) {
        throw const FormatException('Not an MCAP file');
      }
      while (true) {
        final header = await bytes.read(9);
        position += 9;
        final opcode = header[0];
        final size = ByteData.sublistView(
          header,
          1,
        ).getUint64(0, Endian.little);
        if (opcode == 0x02) return; // Footer
        final bodyOffset = trackOffsets ? position : null;
        final body = await bytes.read(size);
        position += size;
        for (final record in McapFile._parse(
          opcode,
          body,
          bodyOffset: bodyOffset,
        )) {
          yield record;
        }
      }
    } finally {
      await bytes.cancel();
    }
  }
}

class _StreamBytes {
  _StreamBytes(this._iterator);

  final StreamIterator<List<int>> _iterator;
  Uint8List? _current;
  int _offset = 0;

  Future<Uint8List> read(int count) async {
    final output = Uint8List(count);
    var written = 0;
    while (written < count) {
      final current = _current;
      if (current == null || _offset >= current.length) {
        if (!await _iterator.moveNext()) {
          throw const FormatException('Unexpected end of MCAP stream');
        }
        final chunk = _iterator.current;
        _current = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
        _offset = 0;
        continue;
      }
      final available = current.length - _offset;
      final remaining = count - written;
      final take = available < remaining ? available : remaining;
      output.setRange(written, written + take, current, _offset);
      _offset += take;
      written += take;
    }
    return output;
  }

  Future<void> cancel() => _iterator.cancel();
}

class _RecordReader {
  _RecordReader(this._bytes) : _data = ByteData.sublistView(_bytes);

  final Uint8List _bytes;
  final ByteData _data;
  int _offset = 0;

  int get remaining => _bytes.length - _offset;
  int get offset => _offset;

  int u8() {
    _require(1);
    return _bytes[_offset++];
  }

  int u16() {
    _require(2);
    final value = _data.getUint16(_offset, Endian.little);
    _offset += 2;
    return value;
  }

  int u32() {
    _require(4);
    final value = _data.getUint32(_offset, Endian.little);
    _offset += 4;
    return value;
  }

  int u64() {
    _require(8);
    final value = _data.getUint64(_offset, Endian.little);
    _offset += 8;
    return value;
  }

  String string() {
    final size = u32();
    final value = utf8.decode(bytes(size));
    return value;
  }

  Uint8List bytes(int size) {
    _require(size);
    final value = Uint8List.sublistView(_bytes, _offset, _offset + size);
    _offset += size;
    return value;
  }

  Uint8List rest() => bytes(remaining);

  void _require(int size) {
    if (size < 0 || _offset + size > _bytes.length) {
      throw const FormatException('Truncated MCAP record');
    }
  }
}
