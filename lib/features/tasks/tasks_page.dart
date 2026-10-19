import 'package:flutter/material.dart';

import '../../app_routes.dart';
import '../../core/models/task.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_page.dart';
import '../../core/widgets/app_panel.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/status_pill.dart';

/// 我的任务列表。
class TasksPage extends StatelessWidget {
  const TasksPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPage(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(context),
            const SizedBox(height: 6),
            const Text(
              '本机任务',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: appState.tasks.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  return _TaskCard(task: appState.tasks[index]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '数据采集 · 我的任务',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '任务缓存在平板。采集文件写在机器人机载工控，不在平板。',
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ],
    );

    final ops = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (appState.isEngineer)
          AppButton(
            '切换模式',
            kind: AppButtonKind.secondary,
            onPressed: () => Navigator.maybePop(context),
          ),
        AppButton(
          '更换任务',
          kind: AppButtonKind.secondary,
          onPressed: () => Navigator.pushNamed(context, Routes.swap),
        ),
        AppButton(
          '拉取新任务',
          kind: AppButtonKind.secondary,
          onPressed: () => showToast(context, '已拉取新任务（模拟）'),
        ),
        AppButton(
          '下载',
          kind: AppButtonKind.secondary,
          onPressed: () => showToast(context, '任务已下载到平板（模拟）'),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, const SizedBox(height: 12), ops],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: title),
            ops,
          ],
        );
      },
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task});

  final Task task;

  void _open(BuildContext context) {
    appState.currentTask = task;
    Navigator.pushNamed(context, Routes.capture, arguments: task);
  }

  @override
  Widget build(BuildContext context) {
    final reached = task.done >= task.total;

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          task.name,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '已采集 ${task.done} 条 · ${task.robot} · ${task.model}',
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 220,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: task.progress,
              minHeight: 8,
              backgroundColor: AppColors.muted,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.ok),
            ),
          ),
        ),
      ],
    );

    final meta = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusPill(
          text: task.state,
          color: reached ? AppColors.brand : AppColors.ok,
        ),
        const SizedBox(width: 18),
        Text(
          '${task.done} / ${task.total}',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(width: 18),
        Text(
          task.size,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
      ],
    );

    final op = SizedBox(
      width: 92,
      child: AppButton('进入任务', onPressed: () => _open(context)),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(12),
        child: AppPanel(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 760) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    info,
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: meta),
                        op,
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: info),
                  meta,
                  const SizedBox(width: 16),
                  op,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
