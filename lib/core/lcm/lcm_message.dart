import 'dart:convert';
import 'dart:typed_data';

/// LCM udpm 的两种魔法字：'LC02'（短包）、'LC03'（分片长包）。
const int _shortMessage = 0x4c433032;
const int _longMessage = 0x4c433033;

/// 接收侧计数器。网络线程写，UI 线程只读快照。
class LcmCounters {
  int datagrams = 0;
  int messages = 0;
  int parseErrors = 0;
  int dropped = 0;
  int incomplete = 0;
  int corrupt = 0;

  void reset() {
    datagrams = 0;
    messages = 0;
    parseErrors = 0;
    dropped = 0;
    incomplete = 0;
    corrupt = 0;
  }
}

/// 一条完整 LCM 消息。payload 的前 8 字节是类型指纹，交给上层解码。
class LcmMessage {
  const LcmMessage(this.channel, this.payload);

  final String channel;
  final Uint8List payload;
}

/// 把 UDP 数据报还原成 LCM 消息。
///
/// 短包：
///   magic(4) | seq(4) | channel\0 | payload
/// 长包（分片）：
///   magic(4) | seq(4) | total(4) | offset(4) | index(2) | count(2)
///   | channel\0（只有第 0 片有） | chunk
///
/// 分片按「发送方 + seq」重组：同一 seq 只保留一份，2 秒收不齐就丢。
/// 判完整看的是字节覆盖，而不只是片数——重复/重叠的片不能拼出假消息。
class LcmMessageReader {
  LcmMessageReader({
    this.maxPartialMessages = 64,
    this.maxMessageBytes = 512 * 1024,
    this.timeout = const Duration(seconds: 2),
    LcmCounters? counters,
  }) : counters = counters ?? LcmCounters();

  final int maxPartialMessages;
  final int maxMessageBytes;
  final Duration timeout;
  final LcmCounters counters;

  final Map<String, _PartialMessage> _partials = {};

  int get pending => _partials.length;

  LcmMessage? read(Uint8List datagram, {required String sender}) {
    final reader = BigEndianReader(datagram);
    try {
      final magic = reader.int32;
      final sequence = reader.int32;

      if (magic == _shortMessage) {
        final channel = reader.cString();
        final payload = reader.rest;
        counters.messages++;
        return LcmMessage(channel, payload);
      }
      if (magic != _longMessage) {
        throw const FormatException('不是 LCM 数据报');
      }

      final total = reader.int32;
      final offset = reader.int32;
      final index = reader.uint16;
      final count = reader.uint16;
      final channel = index == 0 ? reader.cString() : null;
      final chunk = reader.rest;

      if (total <= 0 ||
          total > maxMessageBytes ||
          count == 0 ||
          count > 1024 ||
          index >= count ||
          offset < 0 ||
          chunk.isEmpty ||
          offset + chunk.length > total) {
        throw const FormatException('LCM 分片越界');
      }

      final key = '$sender#$sequence';
      var partial = _partials[key];
      if (partial == null) {
        if (_partials.length >= maxPartialMessages) {
          _partials.remove(_partials.keys.first);
          counters.dropped++;
        }
        partial = _PartialMessage(total, count);
        _partials[key] = partial;
      } else if (partial.total != total || partial.partCount != count) {
        _partials.remove(key);
        counters.parseErrors++;
        return null;
      }

      if (channel != null) {
        if (partial.channel != null && partial.channel != channel) {
          _partials.remove(key);
          counters.parseErrors++;
          return null;
        }
        partial.channel = channel;
      }

      partial.write(index, offset, chunk);
      if (!partial.complete) return null;

      _partials.remove(key);
      if (partial.channel == null || !partial.contiguous) {
        counters.dropped++;
        return null;
      }
      counters.messages++;
      return LcmMessage(partial.channel!, partial.bytes);
    } on FormatException {
      counters.parseErrors++;
      return null;
    }
  }

  /// 丢掉超时的半包；由接收端每两秒调一次。
  void expire() {
    final cutoff = DateTime.now().subtract(timeout);
    _partials.removeWhere((_, partial) {
      if (partial.updatedAt.isAfter(cutoff)) return false;
      counters.dropped++;
      return true;
    });
  }
}

class _PartialMessage {
  _PartialMessage(int total, int count) : buffer = FragmentBuffer(total, count);

  final FragmentBuffer buffer;
  String? channel;

  int get total => buffer.totalBytes;
  int get partCount => buffer.partCount;
  bool get complete => buffer.isComplete;
  bool get contiguous => buffer.isContiguous;
  Uint8List get bytes => buffer.bytes;
  DateTime get updatedAt => buffer.updatedAt;

  void write(int index, int offset, Uint8List chunk) =>
      buffer.write(index, offset, chunk);
}

/// 一组分片的公共缓冲区：记录已收到的片、字节覆盖范围和时间。
///
/// 相机帧（preview_package_t 1200 字节切片）和 LCM 长包都用它，
/// 区别只在「按什么 key 分组」和「片大小是否固定」。
class FragmentBuffer {
  FragmentBuffer(this.totalBytes, this.partCount)
    : bytes = Uint8List(totalBytes),
      _filled = List<bool>.filled(partCount, false);

  final int totalBytes;
  final int partCount;
  final Uint8List bytes;
  final List<bool> _filled;
  final List<(int, int)> _spans = [];

  DateTime updatedAt = DateTime.now();
  int _filledCount = 0;

  bool get isComplete => _filledCount == partCount;

  /// 写入第 [index] 片；重复片直接忽略。
  bool write(int index, int offset, Uint8List chunk) {
    if (index < 0 || index >= partCount) {
      throw const FormatException('分片序号越界');
    }
    if (offset < 0 || offset + chunk.length > totalBytes) {
      throw const FormatException('分片偏移越界');
    }
    if (_filled[index]) return false;
    bytes.setRange(offset, offset + chunk.length, chunk);
    _filled[index] = true;
    _spans.add((offset, offset + chunk.length));
    _filledCount++;
    updatedAt = DateTime.now();
    return true;
  }

  /// 所有字节都被覆盖且没有空洞，才算真正拼好。
  bool get isContiguous {
    if (_spans.isEmpty) return totalBytes == 0;
    final spans = [..._spans]..sort((a, b) => a.$1.compareTo(b.$1));
    var end = 0;
    for (final span in spans) {
      if (span.$1 != end) return false;
      end = span.$2;
    }
    return end == totalBytes;
  }
}

/// 大端字节游标，LCM、preview_package_t、joint_batch_t 共用。
class BigEndianReader {
  BigEndianReader(this.bytes) : _data = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final ByteData _data;
  int _offset = 0;

  int get offset => _offset;
  int get remaining => bytes.length - _offset;

  void _need(int count) {
    if (count < 0 || _offset + count > bytes.length) {
      throw const FormatException('数据不够读');
    }
  }

  void skip(int count) {
    _need(count);
    _offset += count;
  }

  int get int32 {
    _need(4);
    final value = _data.getInt32(_offset);
    _offset += 4;
    return value;
  }

  int get int64 {
    _need(8);
    final value = _data.getInt64(_offset);
    _offset += 8;
    return value;
  }

  int get uint16 {
    _need(2);
    final value = _data.getUint16(_offset);
    _offset += 2;
    return value;
  }

  double get float64 {
    _need(8);
    final value = _data.getFloat64(_offset);
    _offset += 8;
    return value;
  }

  /// 以 NUL 结尾的通道名。
  String cString() {
    final end = bytes.indexOf(0, _offset);
    if (end < 0 || end == _offset || end - _offset > 255) {
      throw const FormatException('LCM 通道名无效');
    }
    final value = utf8.decode(bytes.sublist(_offset, end));
    _offset = end + 1;
    return value;
  }

  /// LCM string：int32 长度（含结尾 NUL）+ 内容。
  String lcmString() {
    final length = int32;
    if (length < 1) throw const FormatException('LCM 字符串长度为 0');
    final raw = sublist(length);
    final end = raw.last == 0 ? length - 1 : length;
    return utf8.decode(raw.sublist(0, end), allowMalformed: true);
  }

  Uint8List sublist(int count) {
    _need(count);
    final value = Uint8List.sublistView(bytes, _offset, _offset + count);
    _offset += count;
    return value;
  }

  Uint8List get rest => sublist(remaining);
}
