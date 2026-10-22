import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/scope.dart';
import '../core/theme.dart';

/// 数据采集 · 我的任务
class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final tasks = app.hereTasks;
    final downloaded = app.downloadedCount;
    final packed = downloaded > 0 ? '本地已有 $downloaded 个任务。' : '本地还没有任务。';
    final netText = app.localSession
        ? '本地登录：读取本机任务。$packed'
        : app.online
        ? '本机任务都可以采集。当前 ${app.currentRobotName} · ${app.currentRobotModel}。'
        : '现场没网：读取本机任务。不能云端登录、不能下载。';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final title = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '数据采集 · 我的任务',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Hint(netText),
                ],
              );
              final buttons = Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  if (app.isEngineer)
                    AppButton(
                      '切换模式',
                      kind: BtnKind.ghost,
                      onPressed: () => app.go(ScreenId.home),
                    ),
                  AppButton(
                    app.localSession || !app.online ? '读取本地任务' : '拉取新任务',
                    kind: BtnKind.ghost,
                    onPressed: app.pullTasks,
                  ),
                  if (app.online && !app.localSession)
                    AppButton(
                      '下载',
                      kind: BtnKind.ghost,
                      onPressed: app.downloadTasks,
                    ),
                ],
              );
              if (constraints.maxWidth < 760) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [title, const SizedBox(height: 8), buttons],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 12),
                  buttons,
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          const Hint('本机任务', size: 14),
          const SizedBox(height: 10),
          Expanded(
            child: tasks.isEmpty
                ? Center(
                    child: Text(
                      app.online && !app.localSession
                          ? '这台机器人上没有任务。有网可点「拉取新任务」加载。'
                          : '本机没有任务。点「读取本地任务」再加载一次。',
                      style: const TextStyle(fontSize: 14, color: C.muted),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    itemCount: tasks.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) =>
                        _TaskCard(task: tasks[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task});

  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          task.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Hint('已采集 ${task.done} 条 · ${task.robot} · ${task.model}', size: 14),
        const SizedBox(height: 6),
        ProgressBar(value: task.progress, width: 220),
      ],
    );
    final meta = Wrap(
      spacing: 18,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (task.shownState != '未开始')
          Pill(
            task.shownState,
            kind: task.shownState == '已达标' ? PillKind.done : PillKind.run,
          ),
        Text(
          '${task.done} / ${task.total}',
          style: const TextStyle(fontSize: 16),
        ),
        Text(task.size, style: const TextStyle(fontSize: 16)),
      ],
    );
    final action = AppButton(
      '进入任务',
      height: 40,
      minWidth: 92,
      onPressed: () => app.openTask(task.name),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: C.panel,
        border: Border.all(color: C.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 720) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                info,
                const SizedBox(height: 10),
                meta,
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: action),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: info),
              const SizedBox(width: 16),
              meta,
              const SizedBox(width: 16),
              action,
            ],
          );
        },
      ),
    );
  }
}
