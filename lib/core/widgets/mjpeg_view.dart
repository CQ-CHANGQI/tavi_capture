import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../theme/app_colors.dart';
import '../video/jpeg_frame.dart';

/// 显示一路 MJPEG over HTTP 流（web_video_server 的
/// `/stream?topic=...&type=mjpeg`）。
///
/// 自行建立连接、切帧、解码，断开后按固定间隔重连。
/// [overlay] 用于在画面上叠加标题等信息，始终可见。
class MjpegView extends StatefulWidget {
  const MjpegView(this.url, {this.fit = BoxFit.cover, this.overlay, super.key});

  final String url;
  final BoxFit fit;
  final Widget? overlay;

  @override
  State<MjpegView> createState() => _MjpegViewState();
}

class _MjpegViewState extends State<MjpegView> {
  ui.Image? _image;

  /// 最近一次失败原因。已有画面时不显示，保留上一帧。
  String? _error;

  int _frames = 0;
  int _fps = 0;

  http.Client? _client;
  Timer? _timer;

  /// 代次。更换 URL 或销毁时自增，旧循环据此退出。
  int _state = 0;

  final _parser = JpegFrameParser();

  @override
  void initState() {
    super.initState();
    _run();
    // 用定时器统计而非收帧时累加，这样流中断后帧率会降为 0 而不是停在旧值。
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _showFps());
  }

  @override
  void didUpdateWidget(MjpegView old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _parser.takeFrame(); // 清掉旧流的残留字节，避免与新流拼接
      _run();
    }
  }

  @override
  void dispose() {
    _state++;
    _timer?.cancel();
    _client?.close(); // 否则要等下一帧到达才断开
    _image?.dispose(); // ui.Image 占用原生内存，不能依赖 GC
    super.dispose();
  }

  /// 连接、读取、重连。更换 URL 也走这里。
  ///
  /// 循环体内 await 解码形成背压：解码期间暂停读取 socket，服务端随之阻塞，
  /// 因此缓冲区不会积压陈旧数据。
  Future<void> _run() async {
    final me = ++_state;

    while (mounted && me == _state) {
      final client = _client = http.Client();
      try {
        final response = await client
            .send(http.Request('GET', Uri.parse(widget.url)))
            .timeout(const Duration(seconds: 5));

        await for (final chunk in response.stream) {
          if (me != _state) return;
          _parser.feed(chunk);
          await _decodeNext(me);
        }
      } catch (e) {
        if (me == _state && mounted) {
          setState(() => _error = '$e');
        }
      } finally {
        if (identical(_client, client)) {
          _client = null;
        }
        client.close();
      }

      if (!mounted || me != _state) return;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  Future<void> _decodeNext(int me) async {
    final jpeg = _parser.takeFrame();
    if (jpeg == null) {
      return;
    }

    try {
      final codec = await ui.instantiateImageCodec(jpeg);
      final frame = await codec.getNextFrame();
      codec.dispose();

      if (!mounted || me != _state) {
        frame.image.dispose();
        return;
      }

      setState(() {
        _image?.dispose();
        _image = frame.image;
        _error = null;
      });
      _frames++;
    } catch (_) {
      // 坏帧，跳过，等下一帧
    }
  }

  void _showFps() {
    if (!mounted) return;
    final fps = _frames;
    _frames = 0;
    if (fps != _fps) setState(() => _fps = fps);
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;

    // 必须用 RawImage：Image.memory 每帧都会产生新的缓存键，会把全局
    // ImageCache 占满并挤掉应用内其它图片。
    if (image != null) {
      return _layout(
        Stack(
          fit: StackFit.expand,
          children: [
            RawImage(image: image, fit: widget.fit),
            Positioned(right: 6, top: 6, child: _badge()),
          ],
        ),
      );
    }

    if (_error == null) {
      return _layout(const Center(child: CircularProgressIndicator()));
    }

    return _layout(_message('连接视频失败\n${widget.url}\n$_error'));
  }

  Widget _message(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.badInk,
            fontSize: 10,
            height: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _layout(Widget content) {
    final overlay = widget.overlay;
    if (overlay == null) {
      return content;
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        content,
        Positioned.fill(child: overlay),
      ],
    );
  }

  Widget _badge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$_fps fps',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          // 等宽数字，避免帧率位数变化时角标宽度跳动
          fontFeatures: [ui.FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
