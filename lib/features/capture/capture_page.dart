import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_routes.dart';
import '../../core/lcm/live_preview.dart';
import '../../core/models/task.dart';
import '../../core/state/app_state.dart';
import '../../core/telemetry/sample.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_page.dart';
import '../../core/widgets/app_panel.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/camera_grid.dart';

class CapturePage extends StatefulWidget {
  const CapturePage({super.key, required this.task, this.enableVideo = true});
  final Task task;
  final bool enableVideo;
  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  final _preview = LivePreview();
  late Task _task;
  late String _person;
  @override
  void initState() {
    super.initState();
    _task = widget.task;
    _person = appState.userName ?? '张三';
    appState.currentTask = _task;
    if (widget.enableVideo) unawaited(_preview.start());
  }

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppPage(
    showDevices: true,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('数据采集', style: TextStyle(fontWeight: FontWeight.bold)),
              DropdownButton<String>(
                value: _task.name,
                items: [
                  for (final t in appState.tasks)
                    DropdownMenuItem(value: t.name, child: Text(t.name)),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _task = appState.tasks.firstWhere((t) => t.name == v);
                    appState.currentTask = _task;
                  });
                },
              ),
              DropdownButton<String>(
                value: _person,
                items: [
                  for (final p in {'张三', '李四', _person})
                    DropdownMenuItem(value: p, child: Text(p)),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _person = v);
                },
              ),
              AppButton(
                '采集说明',
                kind: AppButtonKind.secondary,
                onPressed: () => Navigator.pushNamed(
                  context,
                  Routes.brief,
                  arguments: _task,
                ),
              ),
              AppButton(
                '返回选择模式',
                kind: AppButtonKind.secondary,
                onPressed: () => Navigator.popUntil(
                  context,
                  (r) => r.settings.name == Routes.home || r.isFirst,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: AnimatedBuilder(
              animation: _preview,
              builder: (context, _) => LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 950) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 62, child: _records()),
                        const SizedBox(width: 10),
                        Expanded(flex: 130, child: _cameras()),
                        const SizedBox(width: 10),
                        Expanded(flex: 72, child: _controls()),
                      ],
                    );
                  }
                  return ListView(
                    children: [
                      SizedBox(height: 380, child: _cameras()),
                      const SizedBox(height: 10),
                      _controls(),
                      const SizedBox(height: 10),
                      SizedBox(height: 260, child: _records()),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    ),
  );
  Widget _cameras() => AppPanel(
    padding: const EdgeInsets.all(10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('相机'),
            const Spacer(),
            Text(
              _preview.online ? '实时' : '等待数据',
              style: TextStyle(
                color: _preview.online ? AppColors.ok : AppColors.muted,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: CameraGrid(frames: _preview.cameras, fps: _preview.fps),
        ),
        if (_preview.error != null)
          Text(
            _preview.error!,
            maxLines: 2,
            style: const TextStyle(color: AppColors.bad, fontSize: 11),
          ),
      ],
    ),
  );
  Widget _records() {
    final takes = appState.takes
        .where((t) => t.taskName == _task.name)
        .toList();
    return AppPanel(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('采集数据'),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              itemCount: takes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, i) {
                final take = takes[i];
                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.input,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${take.time} · ${take.duration}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${take.person} · ${take.valid ? '有效' : '无效'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: take.valid ? AppColors.ok : AppColors.bad,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls() => AppPanel(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_task.name, style: const TextStyle(color: AppColors.muted)),
        _stat('已采集', '${_task.done} / ${_task.total}'),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: _task.progress, color: AppColors.ok),
        const SizedBox(height: 6),
        Text(
          '还差 ${(_task.total - _task.done).clamp(0, _task.total)} 条',
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 18),
        const Text('本条计时', style: TextStyle(color: AppColors.muted)),
        _stat('本条', clockText(Duration.zero)),
        const SizedBox(height: 18),
        const Text('录制状态', style: TextStyle(color: AppColors.muted)),
        _stat('当前', '未接入录制服务'),
        _stat('上一条', '—'),
        const SizedBox(height: 18),
        const Text('FSM 状态', style: TextStyle(color: AppColors.muted)),
        _stat('当前', '未知'),
        const SizedBox(height: 24),
        AppButton(
          '开始采集',
          kind: AppButtonKind.success,
          height: 58,
          fontSize: 20,
          onPressed: () => showToast(context, '实时预览已接入，录制服务接口尚未提供'),
        ),
        const SizedBox(height: 8),
        const AppButton('作废', kind: AppButtonKind.dangerOutline),
      ],
    ),
  );
  Widget _stat(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    ),
  );
}
