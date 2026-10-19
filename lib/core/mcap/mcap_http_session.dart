import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'mcap_reader.dart';
import 'mcap_review_index.dart';

typedef McapProgressListener = void Function(int received, int? total);
typedef McapIndexListener = void Function(McapReviewIndex index);
typedef McapErrorListener = void Function(Object error);

/// 边下边解析：HTTP 字节流同时写入临时文件，并递增地建帧/关节索引。
///
/// 播放器可以立刻用已解析出的帧开始播；seek 只能落在已下载范围。
class McapHttpSession {
  McapHttpSession._(
    this.url,
    this.cachePath,
    this.onProgress,
    this.onIndex,
    this.onError,
    this._client,
    this._response,
    this._cache,
    this._total,
  );

  final String url;
  final String cachePath;
  final McapProgressListener? onProgress;
  final McapIndexListener? onIndex;
  final McapErrorListener? onError;

  final http.Client _client;
  final http.StreamedResponse _response;
  final RandomAccessFile _cache;
  final _builder = McapReviewIndexBuilder();
  final _done = Completer<void>();

  int _received = 0;
  final int? _total;
  bool _closed = false;
  bool _finished = false;
  bool _deleteOnFinish = false;
  Object? _error;
  McapReviewIndex? _latestIndex;

  static Future<McapHttpSession> start(
    String url, {
    McapProgressListener? onProgress,
    McapIndexListener? onIndex,
    McapErrorListener? onError,
  }) async {
    final client = http.Client();
    final request = http.Request('GET', Uri.parse(url))
      ..headers['Accept-Encoding'] = 'identity';
    final response = await client.send(request);
    if (response.statusCode != 200) {
      client.close();
      throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
    }

    final dir = await Directory.systemTemp.createTemp('tavi_mcap_');
    final cachePath = '${dir.path}/data.mcap';
    final cache = File(cachePath).openSync(mode: FileMode.write);
    final session = McapHttpSession._(
      url,
      cachePath,
      onProgress,
      onIndex,
      onError,
      client,
      response,
      cache,
      response.contentLength,
    );
    unawaited(session._pump());
    return session;
  }

  int get received => _received;
  int? get total => _total;
  bool get isDone => _finished;
  Object? get error => _error;
  McapReviewIndex? get latestIndex => _latestIndex;
  Future<void> get done => _done.future;

  double? get progress {
    final total = _total;
    if (total == null || total <= 0) return null;
    return (_received / total).clamp(0.0, 1.0);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _client.close();
    if (_finished) {
      _deleteCache();
    } else {
      _deleteOnFinish = true;
    }
  }

  Future<void> _pump() async {
    final watch = Stopwatch()..start();
    var lastProgress = -1000;
    var lastIndex = -1000;
    try {
      final stream = _response.stream.map((chunk) {
        if (!_closed) {
          _cache.writeFromSync(chunk);
          _received += chunk.length;
          final now = watch.elapsedMilliseconds;
          if (now - lastProgress >= 100) {
            lastProgress = now;
            onProgress?.call(_received, _total);
          }
        }
        return chunk;
      });

      await for (final record in McapStreamReader(
        stream,
        trackOffsets: true,
      ).records()) {
        _builder.add(record);
        final now = watch.elapsedMilliseconds;
        if (now - lastIndex >= 200 && _builder.messageCount > 0) {
          lastIndex = now;
          _emitIndex();
        }
      }
      _emitIndex();
    } catch (error) {
      if (!_closed) {
        _error = error;
        onError?.call(error);
      }
    } finally {
      _finished = true;
      try {
        _cache.closeSync();
      } catch (_) {}
      if (!_closed) onProgress?.call(_received, _total);
      _client.close();
      if (!_done.isCompleted) _done.complete();
      if (_deleteOnFinish) _deleteCache();
    }
  }

  void _emitIndex() {
    if (_closed || _builder.messageCount == 0) return;
    try {
      final index = _builder.snapshot(cachePath);
      _latestIndex = index;
      onIndex?.call(index);
    } on FormatException {
      // 还没攒够消息，等下一次。
    }
  }

  void _deleteCache() {
    try {
      File(cachePath).parent.deleteSync(recursive: true);
    } catch (_) {
      // Windows 上文件仍被占用时删不掉，留给系统临时目录清理。
    }
  }
}
