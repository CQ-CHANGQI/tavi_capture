import 'dart:typed_data';

/// 把连续的 MJPEG 字节流切成一张张完整的 JPEG。
///
/// MJPEG 响应体是多张 JPEG 首尾相接，中间夹着 multipart 分段头。这里不解析
/// 那些头，只按 JPEG 自身的标记切分：0xFFD8（SOI）开始，0xFFD9（EOI）结束。
/// 熵编码数据中的 0xFF 必定被填充为 0xFF00，因此这两个标记不会误匹配。
class JpegFrameParser {
  /// 缓冲区上限。正常一帧几十 KB，达到该值说明数据已经错位，直接丢弃重新同步。
  static const _maxBuffer = 1 << 20;

  final _buf = <int>[];

  /// 追加新收到的数据。
  void feed(List<int> chunk) {
    _buf.addAll(chunk);
  }

  /// 取出缓冲区里最后一张完整的 JPEG，并丢弃它之前的所有字节。
  ///
  /// 只返回最后一张，中间积压的旧帧直接丢弃，避免延迟累积。
  /// 没有完整帧时返回 null，未收全的数据留在缓冲区等待后续数据。
  Uint8List? takeFrame() {
    int? start;
    int? lastStart;
    int? lastEnd;

    for (var i = 0; i + 1 < _buf.length; i++) {
      if (_buf[i] != 0xFF) continue;
      if (_buf[i + 1] == 0xD8) {
        start = i;
      } else if (_buf[i + 1] == 0xD9 && start != null) {
        lastStart = start;
        lastEnd = i + 1;
        start = null;
      }
    }

    if (lastStart == null) {
      if (_buf.length > _maxBuffer) _buf.clear();
      return null;
    }

    final frame = Uint8List.fromList(_buf.sublist(lastStart, lastEnd! + 1));
    _buf.removeRange(0, lastEnd + 1);
    return frame;
  }
}
