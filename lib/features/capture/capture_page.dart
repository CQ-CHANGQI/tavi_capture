import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_routes.dart';
import '../../core/models/task.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/video/video_config.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_page.dart';
import '../../core/widgets/app_panel.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/camera_tile.dart';
import 'widgets/camera_stream_tile.dart';

/// 采集页：三路实时 MJPEG + 进度 + 计时 + 开始/停止。
class CapturePage extends StatefulWidget {
  const CapturePage({super.key, required this.task, this.enableVideo = true});

  final Task task;

  /// 测试时可以关闭视频，避免启动真实网络连接和定时器。
  final bool enableVideo;

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  Timer? _timer;
  int _seconds = 0;
  late Task _task;

  bool get _recording => _timer != null;

  String get _clock {
    final minutes = (_seconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void initState() {
    super.initState();
    _task = widget.task;
    appState.currentTask = _task;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggleRec() {
    if (_timer != null) {
      _timer!.cancel();
      setState(() {
        _timer = null;
        _seconds = 0;
      });
      showToast(context, '已保存一条（模拟），继续采下一条');
      return;
    }

    setState(() {
      _seconds = 0;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) {
          return;
        }
        setState(() => _seconds++);
      });
    });
  }

  void _discard() {
    _timer?.cancel();
    setState(() {
      _timer = null;
      _seconds = 0;
    });
    showToast(context, '本条已作废，未保存');
  }

  void _switchTask(String name) {
    final task = appState.tasks.firstWhere((item) => item.name == name);
    setState(() => _task = task);
    appState.currentTask = task;
  }

  String _stream(String topic, {required int width, required int quality}) {
    return cameraStreamUrl(
      robotIp: appState.robotIp,
      topic: topic,
      width: width,
      quality: quality,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      showDevices: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;

          if (wide) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 170, child: _cameraPanel()),
                  const SizedBox(width: 10),
                  Expanded(flex: 72, child: _sidePanel(context, bounded: true)),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SizedBox(height: 320, child: _cameraPanel()),
                const SizedBox(height: 10),
                _sidePanel(context, bounded: false),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _cameraPanel() {
    final main = widget.enableVideo
        ? CameraStreamTile(
            label: '主视角',
            url: _stream(camMainTopic, width: 640, quality: 75),
          )
        : const CameraTile(label: '主视角 · 30 fps');

    final left = widget.enableVideo
        ? CameraStreamTile(
            label: '左腕',
            url: _stream(camLeftTopic, width: 480, quality: 70),
          )
        : const CameraTile(label: '左腕 · 30 fps');

    final right = widget.enableVideo
        ? CameraStreamTile(
            label: '右腕',
            url: _stream(camRightTopic, width: 480, quality: 70),
          )
        : const CameraTile(label: '右腕 · 30 fps');

    return AppPanel(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '相机',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFFB7C8DA),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Column(
              children: [
                Expanded(flex: 145, child: main),
                const SizedBox(height: 8),
                Expanded(
                  flex: 85,
                  child: Row(
                    children: [
                      Expanded(child: left),
                      const SizedBox(width: 8),
                      Expanded(child: right),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidePanel(BuildContext context, {required bool bounded}) {
    final task = _task;
    final left = task.total - task.done < 0 ? 0 : task.total - task.done;

    return AppPanel(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.input,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: task.name,
                isExpanded: true,
                dropdownColor: AppColors.panel,
                style: const TextStyle(fontSize: 14, color: AppColors.ink),
                items: [
                  for (final item in appState.tasks)
                    DropdownMenuItem(value: item.name, child: Text(item.name)),
                ],
                onChanged: _recording
                    ? null
                    : (value) {
                        if (value != null) {
                          _switchTask(value);
                        }
                      },
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  '采集说明',
                  kind: AppButtonKind.secondary,
                  onPressed: () => Navigator.pushNamed(
                    context,
                    Routes.brief,
                    arguments: task,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppButton(
                  '查看已采集',
                  kind: AppButtonKind.secondary,
                  onPressed: () => Navigator.pushNamed(context, Routes.takes),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            '任务进度',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFFB7C8DA),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '已采集',
                style: TextStyle(fontSize: 13, color: AppColors.ink),
              ),
              Text(
                '${task.done} / ${task.total}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: task.progress,
              minHeight: 8,
              backgroundColor: AppColors.muted,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.ok),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '还差 $left 条',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          const Text(
            '本条计时',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFFB7C8DA),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '本条',
                style: TextStyle(fontSize: 13, color: AppColors.ink),
              ),
              Text(
                _clock,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
          if (bounded) const Spacer() else const SizedBox(height: 16),
          AppButton(
            _recording ? '停止并保存' : '开始采集',
            kind: _recording ? AppButtonKind.danger : AppButtonKind.success,
            onPressed: _toggleRec,
            height: 58,
            fontSize: 20,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  '作废',
                  kind: AppButtonKind.dangerOutline,
                  onPressed: _recording ? _discard : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppButton(
                  '返回任务',
                  kind: AppButtonKind.secondary,
                  onPressed: () => Navigator.maybePop(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
