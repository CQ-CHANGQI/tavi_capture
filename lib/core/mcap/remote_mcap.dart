import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'mcap_reader.dart' show McapChannel, McapSchema, McapMessage;
export 'mcap_reader.dart' show McapChannel, McapSchema, McapMessage;

const recordingUrl = String.fromEnvironment(
  'MCAP_URL',
  defaultValue: 'http://192.168.13.4:8090/rosbag_0.mcap',
);

class ChunkIndex {
  const ChunkIndex(this.start, this.end, this.offset, this.length);
  final int start, end, offset, length;
}

/// Indexed HTTP reader. No full-file download or temporary files.
/// A byte-bounded LRU avoids downloading the same chunks while stepping.
class RemoteMcap {
  RemoteMcap(this.uri);
  final Uri uri;
  final _http = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  final schemas = <int, McapSchema>{};
  final channels = <int, McapChannel>{};
  final chunks = <ChunkIndex>[];
  final _cache = <int, Uint8List>{};
  int _cacheBytes = 0;
  int length = 0, start = 0, end = 0, transferred = 0;
  bool _closed = false;
  Duration get duration => Duration(microseconds: (end - start) ~/ 1000);

  Future<Uint8List> _range(int offset, int size) async {
    if (_closed) throw StateError('MCAP 已关闭');
    if (offset < 0 ||
        size <= 0 ||
        size > 64 * 1024 * 1024 ||
        (length > 0 && offset + size > length)) {
      throw const FormatException('MCAP 区间越界或过大');
    }
    final request = await _http.getUrl(uri);
    request.headers.set('Range', 'bytes=$offset-${offset + size - 1}');
    request.headers.set('Accept-Encoding', 'identity');
    final response = await request.close().timeout(const Duration(seconds: 10));
    final range = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$')
        .firstMatch(response.headers.value('content-range') ?? '');
    if (response.statusCode != 206 ||
        range == null ||
        int.parse(range[1]!) != offset ||
        int.parse(range[2]!) != offset + size - 1) {
      (await response.detachSocket()).destroy();
      throw HttpException('服务器未返回正确的 HTTP Range (206)', uri: uri);
    }
    final total = int.parse(range[3]!);
    if (length != 0 && length != total) {
      (await response.detachSocket()).destroy();
      throw const FormatException('回放文件在读取期间发生变化');
    }
    length = total;
    final bytes = BytesBuilder(copy: false);
    await for (final part in response.timeout(const Duration(seconds: 10))) {
      if (bytes.length + part.length > size) {
        throw const FormatException('Range 数据过长');
      }
      bytes.add(part);
      transferred += part.length;
    }
    if (bytes.length != size) throw const FormatException('Range 数据不完整');
    return bytes.takeBytes();
  }

  Future<void> open() async {
    final magic = await _range(0, 8);
    if (!_magic(magic)) throw const FormatException('不是 MCAP 文件');
    final tail = await _range(length - 37, 37);
    if (!_magic(Uint8List.sublistView(tail, 29))) {
      throw const FormatException('MCAP 尾部无效');
    }
    final footer = BinaryReader(tail);
    if (footer.u8() != 2 || footer.u64() != 20) {
      throw const FormatException('MCAP Footer 无效');
    }
    final summaryStart = footer.u64();
    final offsetsStart = footer.u64();
    if (summaryStart <= 0) {
      throw const FormatException('MCAP 缺少 Summary，不能按需回放');
    }
    final summaryEnd = offsetsStart > summaryStart ? offsetsStart : length - 37;
    final summary = await _range(summaryStart, summaryEnd - summaryStart);
    for (final (op, body) in _records(summary)) {
      final r = BinaryReader(body);
      switch (op) {
        case 3:
          final id = r.u16();
          final name = r.string();
          final encoding = r.string();
          schemas[id] = McapSchema(
            id: id,
            name: name,
            encoding: encoding,
            data: r.bytes(r.u32()),
          );
        case 4:
          final id = r.u16();
          final schemaId = r.u16();
          final topic = r.string();
          final encoding = r.string();
          final metadata = <String, String>{};
          final size = r.u32();
          final map = BinaryReader(r.bytes(size));
          while (map.remaining > 0) {
            final key = map.string();
            metadata[key] = map.string();
          }
          channels[id] = McapChannel(
            id: id,
            schemaId: schemaId,
            topic: topic,
            messageEncoding: encoding,
            metadata: metadata,
          );
        case 8:
          chunks.add(ChunkIndex(r.u64(), r.u64(), r.u64(), r.u64()));
      }
    }
    if (chunks.isEmpty) throw const FormatException('MCAP 没有 ChunkIndex');
    chunks.sort((a, b) => a.start.compareTo(b.start));
    start = chunks.first.start;
    end = chunks.map((c) => c.end).reduce((a, b) => a > b ? a : b);
  }

  Future<Uint8List> _chunk(ChunkIndex chunk) async {
    final cached = _cache.remove(chunk.offset);
    if (cached != null) {
      _cache[chunk.offset] = cached;
      return cached;
    }
    final bytes = await _range(chunk.offset, chunk.length);
    final outer = _records(bytes).first;
    if (outer.$1 != 6) throw const FormatException('索引没有指向 Chunk');
    final r = BinaryReader(outer.$2)..skip(16);
    final size = r.u64();
    r.skip(4);
    final compression = r.string();
    final payload = r.bytes(r.u64());
    if (size > 64 * 1024 * 1024) throw const FormatException('MCAP chunk 过大');
    final Uint8List records;
    if (compression.isEmpty) {
      records = payload;
    } else if (compression == 'zlib') {
      records = Uint8List.fromList(zlib.decode(payload));
    } else {
      throw UnsupportedError('暂不支持 MCAP 压缩：$compression');
    }
    if (records.length != size) throw const FormatException('MCAP chunk 长度不匹配');
    while (_cache.isNotEmpty &&
        _cacheBytes + records.length > 32 * 1024 * 1024) {
      _cacheBytes -= _cache.remove(_cache.keys.first)!.length;
    }
    _cache[chunk.offset] = records;
    _cacheBytes += records.length;
    return records;
  }

  /// Sort by message time even when adjacent chunks overlap in time.
  Future<List<McapMessage>> window(int from, int until) async {
    final selected = chunks
        .where((c) => c.end >= from && c.start <= until)
        .toList();
    final messages = <McapMessage>[];
    // Small parallel batches hide LAN round-trip latency without unbounded IO.
    for (var i = 0; i < selected.length; i += 4) {
      final bodies = await Future.wait(selected.skip(i).take(4).map(_chunk));
      for (final body in bodies) {
        for (final (op, bytes) in _records(body)) {
          if (op != 5) continue;
          final r = BinaryReader(bytes);
          final id = r.u16(),
              sequence = r.u32(),
              time = r.u64(),
              publish = r.u64();
          if (time < from || time > until) continue;
          messages.add(
            McapMessage(
              channelId: id,
              sequence: sequence,
              logTime: time,
              publishTime: publish,
              data: r.bytes(r.remaining),
            ),
          );
        }
      }
    }
    messages.sort((a, b) => a.logTime.compareTo(b.logTime));
    return messages;
  }

  void close() {
    _closed = true;
    _http.close(force: true);
    _cache.clear();
    _cacheBytes = 0;
  }
}

bool _magic(Uint8List b) =>
    b.length == 8 &&
    b[0] == 0x89 &&
    b[1] == 77 &&
    b[2] == 67 &&
    b[3] == 65 &&
    b[4] == 80 &&
    b[5] == 48 &&
    b[6] == 13 &&
    b[7] == 10;

Iterable<(int, Uint8List)> _records(Uint8List bytes) sync* {
  final r = BinaryReader(bytes);
  while (r.remaining > 0) {
    final op = r.u8();
    yield (op, r.bytes(r.u64()));
  }
}

class BinaryReader {
  BinaryReader(this.data) : view = ByteData.sublistView(data);
  final Uint8List data;
  final ByteData view;
  int offset = 0;
  int get remaining => data.length - offset;
  void skip(int size) {
    if (size < 0 || size > remaining) throw const FormatException('MCAP 数据越界');
    offset += size;
  }

  int u8() {
    skip(1);
    return data[offset - 1];
  }

  int u16() {
    skip(2);
    return view.getUint16(offset - 2, Endian.little);
  }

  int u32() {
    skip(4);
    return view.getUint32(offset - 4, Endian.little);
  }

  int u64() {
    skip(8);
    return view.getUint64(offset - 8, Endian.little);
  }

  Uint8List bytes(int size) {
    skip(size);
    return Uint8List.sublistView(data, offset - size, offset);
  }

  String string() => utf8.decode(bytes(u32()));
}
