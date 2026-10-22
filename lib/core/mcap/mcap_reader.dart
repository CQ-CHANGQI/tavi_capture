import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// MCAP file magic: `\x89MCAP0\r\n`.
const List<int> _magic = <int>[0x89, 0x4d, 0x43, 0x41, 0x50, 0x30, 0x0d, 0x0a];

const int _opHeader = 0x01;
const int _opFooter = 0x02;
const int _opSchema = 0x03;
const int _opChannel = 0x04;
const int _opMessage = 0x05;
const int _opChunk = 0x06;
const int _opChunkIndex = 0x08;
const int _opStatistics = 0x0B;

/// Footer record payload is 20 bytes; the record itself is 29 bytes.
const int _footerRecordSize = 29;
const int _footerMagicSize = 8;
const int _footerTotalSize = _footerRecordSize + _footerMagicSize;

class McapException implements Exception {
  McapException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Random-access view of an MCAP file served by Caddy.
///
/// Only the footer and summary section are fetched to build [McapSummary];
/// chunks are fetched on demand when messages are read.
class McapRemoteFile {
  McapRemoteFile(this.uri, {HttpClient? client})
    : _client =
          client ??
          (HttpClient()..connectionTimeout = const Duration(seconds: 8));

  final Uri uri;
  final HttpClient _client;
  int? _length;

  int get length {
    final length = _length;
    if (length == null) throw StateError('call open() first');
    return length;
  }

  Future<void> open() async {
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw McapException('只支持 http/https URL');
    }

    final headRequest = await _client.headUrl(uri);
    headRequest.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    final head = await headRequest.close();
    if (head.statusCode == HttpStatus.ok && head.contentLength > 0) {
      _length = head.contentLength;
      await head.drain<void>();
      return;
    }
    await head.drain<void>();

    final response = await _request(0, 0);
    if (response.statusCode != HttpStatus.partialContent) {
      final status = response.statusCode;
      await _abort(response);
      throw McapException('Caddy 未返回 206（HTTP $status），检查 Range 支持');
    }
    final range = response.headers.value(HttpHeaders.contentRangeHeader);
    await response.drain<void>();
    final total = int.tryParse(range?.split('/').last ?? '');
    if (total == null || total <= 0) {
      throw McapException('无法从 Content-Range 获取文件大小');
    }
    _length = total;
  }

  Future<Uint8List> read(int start, int endInclusive) async {
    final total = length;
    if (start < 0 || endInclusive < start || endInclusive >= total) {
      throw McapException('Range 越界: $start-$endInclusive / $total');
    }

    final response = await _request(start, endInclusive);
    if (response.statusCode != HttpStatus.partialContent) {
      final status = response.statusCode;
      await _abort(response);
      throw McapException('Range 请求失败: HTTP $status');
    }

    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    final expected = endInclusive - start + 1;
    if (bytes.length != expected) {
      throw McapException('Range 返回 ${bytes.length} 字节，期望 $expected');
    }
    return bytes;
  }

  Future<HttpClientResponse> _request(int start, int endInclusive) async {
    final request = await _client.getUrl(uri);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$endInclusive');
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    return request.close();
  }

  Future<void> _abort(HttpClientResponse response) async {
    try {
      final socket = await response.detachSocket();
      socket.destroy();
    } catch (_) {
      // The connection is already going away; nothing else to clean up.
    }
  }

  void close() => _client.close(force: true);
}

class McapSchema {
  McapSchema({
    required this.id,
    required this.name,
    required this.encoding,
    required this.data,
  });

  final int id;
  final String name;
  final String encoding;
  final Uint8List data;
}

class McapChannel {
  McapChannel({
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

class McapChunkIndex {
  McapChunkIndex({
    required this.messageStartTimeNs,
    required this.messageEndTimeNs,
    required this.chunkStartOffset,
    required this.chunkLength,
    required this.messageIndexOffsets,
    required this.compression,
    required this.compressedSize,
    required this.uncompressedSize,
  });

  final int messageStartTimeNs;
  final int messageEndTimeNs;
  final int chunkStartOffset;
  final int chunkLength;
  final Map<int, int> messageIndexOffsets;
  final String compression;
  final int compressedSize;
  final int uncompressedSize;
}

class McapMessage {
  McapMessage({
    required this.channelId,
    required this.sequence,
    required this.logTimeNs,
    required this.publishTimeNs,
    required this.data,
  });

  final int channelId;
  final int sequence;
  final int logTimeNs;
  final int publishTimeNs;
  final Uint8List data;
}

class McapSummary {
  McapSummary({
    required this.profile,
    required this.library,
    required this.messageCount,
    required this.schemaCount,
    required this.channelCount,
    required this.chunkCount,
    required this.startTimeNs,
    required this.endTimeNs,
    required this.schemas,
    required this.channels,
    required this.chunks,
    required this.channelMessageCounts,
  });

  final String profile;
  final String library;
  final int messageCount;
  final int schemaCount;
  final int channelCount;
  final int chunkCount;
  final int startTimeNs;
  final int endTimeNs;
  final Map<int, McapSchema> schemas;
  final List<McapChannel> channels;
  final List<McapChunkIndex> chunks;
  final Map<int, int> channelMessageCounts;

  Duration get duration {
    final ns = endTimeNs - startTimeNs;
    return ns > 0 ? Duration(microseconds: ns ~/ 1000) : Duration.zero;
  }

  McapSchema? schemaOf(McapChannel channel) => schemas[channel.schemaId];

  int messageCountOf(McapChannel channel) =>
      channelMessageCounts[channel.id] ?? 0;

  static Future<McapSummary> load(McapRemoteFile file) async {
    final header = await _readHeader(file);
    final footer = await _readFooter(file);
    if (footer.summaryStart == 0) {
      throw McapException('该 MCAP 没有 summary 段，暂不支持无索引文件');
    }

    final summaryEnd = footer.summaryOffsetStart > footer.summaryStart
        ? footer.summaryOffsetStart
        : file.length - _footerTotalSize;
    if (summaryEnd <= footer.summaryStart) {
      throw McapException('MCAP summary 区间无效');
    }

    final bytes = await file.read(footer.summaryStart, summaryEnd - 1);
    final schemas = <int, McapSchema>{};
    final channels = <int, McapChannel>{};
    final chunks = <McapChunkIndex>[];
    _McapStatistics? statistics;

    final reader = _Reader(bytes);
    while (reader.remaining > 0) {
      final recordStart = reader.offset;
      final opcode = reader.u8();
      final length = reader.u64();
      final recordEnd = reader.offset + length;
      if (recordEnd > bytes.length) {
        throw McapException('summary 记录越界: offset $recordStart');
      }

      switch (opcode) {
        case _opSchema:
          final id = reader.u16();
          final name = reader.str();
          final encoding = reader.str();
          final data = reader.bytes(reader.u32());
          schemas[id] = McapSchema(
            id: id,
            name: name,
            encoding: encoding,
            data: data,
          );
        case _opChannel:
          final id = reader.u16();
          final schemaId = reader.u16();
          final topic = reader.str();
          final messageEncoding = reader.str();
          final metadata = reader.stringMap();
          channels[id] = McapChannel(
            id: id,
            schemaId: schemaId,
            topic: topic,
            messageEncoding: messageEncoding,
            metadata: metadata,
          );
        case _opStatistics:
          final messageCount = reader.u64();
          final schemaCount = reader.u16();
          final channelCount = reader.u32();
          reader.u32(); // attachment_count
          reader.u32(); // metadata_count
          final chunkCount = reader.u32();
          final startTimeNs = reader.u64();
          final endTimeNs = reader.u64();
          final channelMessageCounts = reader.intMap();
          statistics = _McapStatistics(
            messageCount: messageCount,
            schemaCount: schemaCount,
            channelCount: channelCount,
            chunkCount: chunkCount,
            startTimeNs: startTimeNs,
            endTimeNs: endTimeNs,
            channelMessageCounts: channelMessageCounts,
          );
        case _opChunkIndex:
          final messageStartTimeNs = reader.u64();
          final messageEndTimeNs = reader.u64();
          final chunkStartOffset = reader.u64();
          final chunkLength = reader.u64();
          final messageIndexOffsets = reader.intMap();
          reader.u64(); // message_index_length
          final compression = reader.str();
          final compressedSize = reader.u64();
          final uncompressedSize = reader.u64();
          chunks.add(
            McapChunkIndex(
              messageStartTimeNs: messageStartTimeNs,
              messageEndTimeNs: messageEndTimeNs,
              chunkStartOffset: chunkStartOffset,
              chunkLength: chunkLength,
              messageIndexOffsets: messageIndexOffsets,
              compression: compression,
              compressedSize: compressedSize,
              uncompressedSize: uncompressedSize,
            ),
          );
      }

      reader.offset = recordEnd;
    }

    final sortedChannels = channels.values.toList()
      ..sort((a, b) => a.topic.compareTo(b.topic));
    final counts = statistics?.channelMessageCounts ?? const <int, int>{};
    var startTimeNs = statistics?.startTimeNs ?? 0;
    var endTimeNs = statistics?.endTimeNs ?? 0;
    if (startTimeNs == 0 && chunks.isNotEmpty) {
      startTimeNs = chunks
          .map((chunk) => chunk.messageStartTimeNs)
          .reduce(math.min);
      endTimeNs = chunks
          .map((chunk) => chunk.messageEndTimeNs)
          .reduce(math.max);
    }

    return McapSummary(
      profile: header.profile,
      library: header.library,
      messageCount: statistics?.messageCount ?? 0,
      schemaCount: statistics?.schemaCount ?? schemas.length,
      channelCount: statistics?.channelCount ?? channels.length,
      chunkCount: statistics?.chunkCount ?? chunks.length,
      startTimeNs: startTimeNs,
      endTimeNs: endTimeNs,
      schemas: schemas,
      channels: sortedChannels,
      chunks: chunks,
      channelMessageCounts: counts,
    );
  }

  static Future<_Header> _readHeader(McapRemoteFile file) async {
    final end = math.min(file.length, 4096) - 1;
    final bytes = await file.read(0, end);
    if (!_hasMagic(bytes, 0)) {
      throw McapException('不是 MCAP 文件（magic 不匹配）');
    }

    final reader = _Reader(bytes, _magic.length);
    final opcode = reader.u8();
    final length = reader.u64();
    if (opcode != _opHeader) {
      throw McapException('MCAP Header 记录缺失');
    }
    if (reader.offset + length > bytes.length) {
      throw McapException('MCAP Header 记录过大');
    }
    return _Header(profile: reader.str(), library: reader.str());
  }

  static Future<_Footer> _readFooter(McapRemoteFile file) async {
    final start = math.max(0, file.length - 64);
    final bytes = await file.read(start, file.length - 1);
    if (!_hasMagic(bytes, bytes.length - _footerMagicSize)) {
      throw McapException('MCAP 尾部 magic 不匹配');
    }

    final reader = _Reader(bytes, bytes.length - _footerTotalSize);
    final opcode = reader.u8();
    final length = reader.u64();
    if (opcode != _opFooter || length != 20) {
      throw McapException('MCAP Footer 记录无效');
    }
    final summaryStart = reader.u64();
    final summaryOffsetStart = reader.u64();
    reader.u32(); // summary_crc
    return _Footer(
      summaryStart: summaryStart,
      summaryOffsetStart: summaryOffsetStart,
    );
  }
}

/// Reads messages for one channel, fetching only the chunks that contain it.
/// Sequential message cursor over chunks, used by the MCAP player.
///
/// Chunks are fetched lazily, one at a time. With [channelIds] set, messages
/// for other channels are skipped before they reach the caller.
class McapChunkCursor {
  McapChunkCursor(
    this.file,
    this.summary, {
    int startTimeNs = 0,
    this.channelIds,
    this.maxChunks = 1 << 30,
  }) : _chunks = _playableChunks(summary.chunks, channelIds)
         ..sort((a, b) => a.messageStartTimeNs.compareTo(b.messageStartTimeNs)),
       _startTimeNs = startTimeNs {
    _index = _findChunk(startTimeNs);
  }

  final McapRemoteFile file;
  final McapSummary summary;
  final Set<int>? channelIds;
  final int maxChunks;
  final List<McapChunkIndex> _chunks;

  int _startTimeNs;
  int _index = 0;
  int _loadedChunks = 0;
  _Reader? _reader;

  void seek(int timeNs) {
    _startTimeNs = timeNs;
    _index = _findChunk(timeNs);
    _loadedChunks = 0;
    _reader = null;
  }

  int _findChunk(int timeNs) {
    for (var i = 0; i < _chunks.length; i++) {
      if (_chunks[i].messageEndTimeNs >= timeNs) return i;
    }
    return _chunks.length;
  }

  Future<McapMessage?> next() async {
    while (true) {
      final reader = _reader;
      if (reader != null) {
        if (reader.remaining == 0) {
          _reader = null;
          continue;
        }

        final opcode = reader.u8();
        final length = reader.u64();
        final recordEnd = reader.offset + length;
        if (recordEnd > reader.data.length) {
          throw McapException('chunk 记录越界');
        }

        if (opcode == _opMessage) {
          final channelId = reader.u16();
          final sequence = reader.u32();
          final logTimeNs = reader.u64();
          final publishTimeNs = reader.u64();
          final selected =
              (channelIds == null || channelIds!.contains(channelId)) &&
              logTimeNs >= _startTimeNs;
          if (selected) {
            final data = Uint8List.sublistView(
              reader.data,
              reader.offset,
              recordEnd,
            );
            reader.offset = recordEnd;
            return McapMessage(
              channelId: channelId,
              sequence: sequence,
              logTimeNs: logTimeNs,
              publishTimeNs: publishTimeNs,
              data: data,
            );
          }
        }
        reader.offset = recordEnd;
        continue;
      }

      if (_index >= _chunks.length || _loadedChunks >= maxChunks) {
        return null;
      }
      final chunk = _chunks[_index++];
      _loadedChunks++;
      final bytes = await file.read(
        chunk.chunkStartOffset,
        chunk.chunkStartOffset + chunk.chunkLength - 1,
      );
      _reader = _Reader(_decodeChunkRecords(bytes));
    }
  }
}

class McapMessageReader {
  McapMessageReader(this.file, this.summary);

  final McapRemoteFile file;
  final McapSummary summary;

  Future<List<McapMessage>> firstMessages(
    McapChannel channel, {
    int limit = 50,
    int maxChunks = 5,
  }) async {
    final cursor = McapChunkCursor(
      file,
      summary,
      channelIds: {channel.id},
      maxChunks: maxChunks,
    );
    final messages = <McapMessage>[];
    while (messages.length < limit) {
      final message = await cursor.next();
      if (message == null) break;
      messages.add(message);
    }
    return messages;
  }
}

List<McapChunkIndex> _playableChunks(
  List<McapChunkIndex> chunks,
  Set<int>? channelIds,
) {
  if (channelIds == null) return List<McapChunkIndex>.of(chunks);
  return chunks
      .where(
        (chunk) =>
            chunk.messageIndexOffsets.isEmpty ||
            chunk.messageIndexOffsets.keys.any(channelIds.contains),
      )
      .toList();
}

Uint8List _decodeChunkRecords(Uint8List bytes) {
  final reader = _Reader(bytes);
  final opcode = reader.u8();
  final length = reader.u64();
  if (opcode != _opChunk || length != bytes.length - 9) {
    throw McapException('MCAP Chunk 记录无效');
  }
  reader.u64(); // message_start_time
  reader.u64(); // message_end_time
  reader.u64(); // uncompressed_size
  reader.u32(); // uncompressed_crc
  final compression = reader.str();
  final records = reader.bytes64();

  if (compression.isEmpty) return records;
  if (compression == 'zlib') {
    return Uint8List.fromList(ZLibDecoder().convert(records));
  }
  // ponytail: only uncompressed/zlib chunks; add zstd/lz4 if the robot writes them.
  throw McapException('不支持的 chunk 压缩: $compression');
}

class _Header {
  _Header({required this.profile, required this.library});

  final String profile;
  final String library;
}

class _Footer {
  _Footer({required this.summaryStart, required this.summaryOffsetStart});

  final int summaryStart;
  final int summaryOffsetStart;
}

class _McapStatistics {
  _McapStatistics({
    required this.messageCount,
    required this.schemaCount,
    required this.channelCount,
    required this.chunkCount,
    required this.startTimeNs,
    required this.endTimeNs,
    required this.channelMessageCounts,
  });

  final int messageCount;
  final int schemaCount;
  final int channelCount;
  final int chunkCount;
  final int startTimeNs;
  final int endTimeNs;
  final Map<int, int> channelMessageCounts;
}

class _Reader {
  _Reader(this.data, [this.offset = 0]) : _view = ByteData.sublistView(data);

  final Uint8List data;
  final ByteData _view;
  int offset;

  int get remaining => data.length - offset;

  void _need(int count) {
    if (count < 0 || offset + count > data.length) {
      throw McapException('MCAP 记录越界: offset $offset, need $count');
    }
  }

  int u8() {
    _need(1);
    return data[offset++];
  }

  int u16() {
    _need(2);
    final value = _view.getUint16(offset, Endian.little);
    offset += 2;
    return value;
  }

  int u32() {
    _need(4);
    final value = _view.getUint32(offset, Endian.little);
    offset += 4;
    return value;
  }

  int u64() {
    _need(8);
    final value = _view.getUint64(offset, Endian.little);
    offset += 8;
    return value;
  }

  String str() {
    final length = u32();
    final bytes = this.bytes(length);
    return utf8.decode(bytes, allowMalformed: true);
  }

  Uint8List bytes(int length) {
    _need(length);
    final value = Uint8List.sublistView(data, offset, offset + length);
    offset += length;
    return value;
  }

  Uint8List bytes64() {
    final length = u64();
    return bytes(length);
  }

  Map<int, int> intMap() {
    final length = u32();
    final end = offset + length;
    if (end > data.length) throw McapException('MCAP map 越界');
    final map = <int, int>{};
    while (offset < end) {
      map[u16()] = u64();
    }
    return map;
  }

  Map<String, String> stringMap() {
    final length = u32();
    final end = offset + length;
    if (end > data.length) throw McapException('MCAP map 越界');
    final map = <String, String>{};
    while (offset < end) {
      map[str()] = str();
    }
    return map;
  }
}

bool _hasMagic(Uint8List bytes, int offset) {
  if (offset < 0 || offset + _magic.length > bytes.length) return false;
  for (var i = 0; i < _magic.length; i++) {
    if (bytes[offset + i] != _magic[i]) return false;
  }
  return true;
}
