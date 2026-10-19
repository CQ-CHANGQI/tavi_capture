import 'dart:convert';
import 'dart:typed_data';

/// ROS2 的 CDR（XCDR1）小端解码器。
///
/// 对齐基准是 4 字节 encapsulation 之后的位置，字段 offset 从 payload 开头算起。
class CdrReader {
  CdrReader(this._bytes) : _data = ByteData.sublistView(_bytes) {
    if (_bytes.length < 4 || _bytes[0] != 0 || _bytes[1] != 1) {
      throw FormatException(
        'Unsupported CDR encapsulation: '
        '${_bytes.length >= 2 ? '${_bytes[0]}:${_bytes[1]}' : 'short'}',
      );
    }
    _offset = 4;
  }

  final Uint8List _bytes;
  final ByteData _data;
  int _offset = 0;

  int get offset => _offset;
  int get remaining => _bytes.length - _offset;

  int u8() {
    _require(1);
    return _bytes[_offset++];
  }

  int u32() {
    _align(4);
    _require(4);
    final value = _data.getUint32(_offset, Endian.little);
    _offset += 4;
    return value;
  }

  int i32() {
    _align(4);
    _require(4);
    final value = _data.getInt32(_offset, Endian.little);
    _offset += 4;
    return value;
  }

  double f64() {
    _align(8);
    _require(8);
    final value = _data.getFloat64(_offset, Endian.little);
    _offset += 8;
    return value;
  }

  bool boolean() => u8() != 0;

  String string() {
    final size = u32();
    if (size == 0) return '';
    _require(size);
    // CDR string 的长度包含结尾的 \0。
    final value = utf8.decode(
      Uint8List.sublistView(_bytes, _offset, _offset + size - 1),
    );
    _offset += size;
    return value;
  }

  Uint8List bytes(int size) {
    _require(size);
    final value = Uint8List.sublistView(_bytes, _offset, _offset + size);
    _offset += size;
    return value;
  }

  void _align(int alignment) {
    final relative = _offset - 4;
    final padding = (alignment - relative % alignment) % alignment;
    _offset += padding;
  }

  void _require(int size) {
    if (size < 0 || _offset + size > _bytes.length) {
      throw const FormatException('Truncated CDR payload');
    }
  }
}
