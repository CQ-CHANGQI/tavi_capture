import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/mcap/playback_controller.dart';
import '../../core/models/take.dart';
import '../../core/telemetry/sample.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_page.dart';
import '../../core/widgets/app_panel.dart';
import '../../core/widgets/camera_grid.dart';
import 'widgets/telemetry_panels.dart';

class ReviewPage extends StatelessWidget {
  const ReviewPage({super.key, required this.take});
  final Take take;
  @override
  Widget build(BuildContext context) => AppPage(
    showDevices: true,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(child: RecordingViewer(take: take)),
          const SizedBox(height: 10),
          AppButton(
            '返回列表',
            kind: AppButtonKind.secondary,
            onPressed: () => Navigator.maybePop(context),
          ),
        ],
      ),
    ),
  );
}

/// Shared by the standalone review page and the library's right-hand pane.
class RecordingViewer extends StatefulWidget {
  const RecordingViewer({
    super.key,
    required this.take,
    this.onChanged,
    this.onPrevious,
    this.onNext,
  });
  final Take take;
  final VoidCallback? onChanged, onPrevious, onNext;
  @override
  State<RecordingViewer> createState() => _RecordingViewerState();
}

class _RecordingViewerState extends State<RecordingViewer> {
  late PlaybackController _player;
  double? _drag;
  bool _resume = false;
  bool _maximized = false;
  @override
  void initState() {
    super.initState();
    _open();
  }

  void _open() {
    _player = PlaybackController(url: widget.take.sourceUrl);
    unawaited(_player.open());
  }

  @override
  void didUpdateWidget(RecordingViewer old) {
    super.didUpdateWidget(old);
    if (old.take.id != widget.take.id) {
      _player.dispose();
      _open();
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _player,
    builder: (context, _) => AppPanel(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '回放 · ${clockText(_player.duration)}',
                style: const TextStyle(fontSize: 14),
              ),
              Text(
                widget.take.valid ? '有效' : '无效',
                style: TextStyle(
                  color: widget.take.valid ? AppColors.ok : AppColors.bad,
                ),
              ),
              if (widget.onPrevious != null) _button('上一条', widget.onPrevious),
              if (widget.onNext != null) _button('下一条', widget.onNext),
              _button(
                _maximized ? '还原' : '最大化',
                () => setState(() => _maximized = !_maximized),
              ),
              _button(widget.take.valid ? '标记无效' : '标记有效', () {
                setState(() => widget.take.valid = !widget.take.valid);
                widget.onChanged?.call();
              }),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(child: _body()),
          const SizedBox(height: 8),
          _controls(),
        ],
      ),
    ),
  );
  Widget _button(String title, VoidCallback? action) => AppButton(
    title,
    kind: AppButtonKind.secondary,
    height: 32,
    fontSize: 12,
    onPressed: action,
  );
  Widget _body() {
    if (_player.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_player.error != null) {
      return Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('回放加载失败'),
              const SizedBox(height: 8),
              Text(
                _player.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 8),
              _button(
                '重试',
                () => setState(() {
                  _player.dispose();
                  _open();
                }),
              ),
            ],
          ),
        ),
      );
    }
    return Stack(
      children: [
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cameras = CameraGrid(frames: _player.cameras);
              if (_maximized) return cameras;
              if (constraints.maxWidth >= 600) {
                return Row(
                  children: [
                    Expanded(flex: 135, child: cameras),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 65,
                      child: TelemetryPanels(history: _player.history),
                    ),
                  ],
                );
              }
              return ListView(
                children: [
                  SizedBox(height: 300, child: cameras),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 380,
                    child: TelemetryPanels(history: _player.history),
                  ),
                ],
              );
            },
          ),
        ),
        if (_player.buffering)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }

  Widget _controls() => Column(
    children: [
      Slider(
        value: _drag ?? _player.progress,
        onChangeStart: (_) {
          _resume = _player.playing;
          _player.pause();
        },
        onChanged: _player.loading ? null : (v) => setState(() => _drag = v),
        onChangeEnd: (v) {
          setState(() => _drag = null);
          unawaited(
            _player.seek(
              _player.file.start +
                  ((_player.file.end - _player.file.start) * v).round(),
              resume: _resume,
            ),
          );
        },
      ),
      Wrap(
        spacing: 5,
        runSpacing: 5,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.center,
        children: [
          IconButton(
            tooltip: '后退 5 秒',
            onPressed: _player.loading
                ? null
                : () => _player.skip(const Duration(seconds: -5)),
            icon: const Icon(Icons.replay_5),
          ),
          IconButton(
            tooltip: '上一帧',
            onPressed: _player.loading ? null : () => _player.step(-1),
            icon: const Icon(Icons.skip_previous),
          ),
          _button(
            _player.playing ? '暂停' : (_player.buffering ? '缓冲中' : '播放'),
            _player.loading || _player.buffering
                ? null
                : (_player.playing ? _player.pause : _player.play),
          ),
          IconButton(
            tooltip: '下一帧',
            onPressed: _player.loading ? null : () => _player.step(1),
            icon: const Icon(Icons.skip_next),
          ),
          IconButton(
            tooltip: '前进 5 秒',
            onPressed: _player.loading
                ? null
                : () => _player.skip(const Duration(seconds: 5)),
            icon: const Icon(Icons.forward_5),
          ),
          Text(
            '${clockText(_player.elapsed)} / ${clockText(_player.duration)}',
            style: const TextStyle(fontSize: 12),
          ),
          DropdownButton<double>(
            value: _player.speed,
            underline: const SizedBox.shrink(),
            items: [
              for (final speed in [.5, 1.0, 2.0])
                DropdownMenuItem(value: speed, child: Text('${speed}x')),
            ],
            onChanged: (v) {
              if (v != null) _player.setSpeed(v);
            },
          ),
          IconButton(
            tooltip: '循环播放',
            onPressed: _player.toggleLoop,
            color: _player.loop ? AppColors.brand : AppColors.muted,
            icon: const Icon(Icons.repeat),
          ),
        ],
      ),
    ],
  );
}
