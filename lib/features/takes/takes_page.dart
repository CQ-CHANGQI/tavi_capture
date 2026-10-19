import 'package:flutter/material.dart';

import '../../app_routes.dart';
import '../../core/models/take.dart';
import '../../core/models/task.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_page.dart';
import '../../core/widgets/app_panel.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/status_pill.dart';

/// 采集条列表。allPeople = true 时给工程师看本机所有人的数据。
class TakesPage extends StatefulWidget {
  const TakesPage({super.key, required this.allPeople});

  final bool allPeople;

  @override
  State<TakesPage> createState() => _TakesPageState();
}

class _TakesPageState extends State<TakesPage> {
  String _filter = 'all';

  void _toggle(Take take) {
    setState(() => take.valid = !take.valid);
    showToast(context, take.valid ? '已标记为有效' : '已标记为无效');
  }

  void _backToTasks(BuildContext context) {
    Navigator.popUntil(
      context,
      (route) =>
          route.settings.name == Routes.home ||
          route.settings.name == Routes.tasks,
    );
  }

  void _continueTake(BuildContext context) {
    final task =
        appState.currentTask ??
        (appState.tasks.isEmpty ? null : appState.tasks.first);
    if (task == null) {
      return;
    }
    Navigator.pushNamed(context, Routes.capture, arguments: task);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.allPeople && !appState.isEngineer) {
      return const AppPage(
        child: Center(
          child: Text(
            '只有工程师可以查看全部数据',
            style: TextStyle(color: AppColors.muted),
          ),
        ),
      );
    }

    final Task? task = appState.currentTask;
    final title = widget.allPeople ? '查看数据 · 本机数据' : (task?.name ?? '任务已采');
    final hint = widget.allPeople
        ? '这台机器人机载工控上的全部采集条，含所有人员。文件不在平板。'
        : task == null
        ? ''
        : '已采集 ${task.done} / ${task.total} 条，还差 ${task.total - task.done < 0 ? 0 : task.total - task.done} 条。本机 ${task.robot} · ${task.model}。文件在当时那台工控。';

    final all = appState.takes.where((take) {
      if (widget.allPeople) {
        return true;
      }
      return take.person == appState.userName &&
          (task == null || take.taskName == task.name);
    }).toList();

    final rows = all.where((take) {
      if (_filter == 'valid') {
        return take.valid;
      }
      if (_filter == 'invalid') {
        return !take.valid;
      }
      return true;
    }).toList();

    return AppPage(
      showDevices: true,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(context, title: title, hint: hint, task: task),
            const SizedBox(height: 6),
            _Tabs(
              value: _filter,
              onChanged: (value) => setState(() => _filter = value),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: rows.isEmpty
                  ? Center(
                      child: Text(
                        widget.allPeople
                            ? '本机还没有采集条'
                            : '当前任务下没有你的采集条\n换一个任务试试，或用工程师账号查看全部数据',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          height: 1.6,
                          color: AppColors.muted,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        return _TakeRow(
                          take: rows[index],
                          onToggle: () => _toggle(rows[index]),
                        );
                      },
                    ),
            ),
            if (!widget.allPeople) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  SizedBox(
                    width: 180,
                    child: AppButton(
                      '返回任务',
                      kind: AppButtonKind.secondary,
                      onPressed: () => _backToTasks(context),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppButton(
                      '继续采集一条',
                      kind: AppButtonKind.success,
                      height: 52,
                      fontSize: 18,
                      onPressed: () => _continueTake(context),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(
    BuildContext context, {
    required String title,
    required String hint,
    required Task? task,
  }) {
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.ink,
          ),
        ),
        if (hint.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            hint,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
        if (!widget.allPeople && task != null) ...[
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
      ],
    );

    final action = widget.allPeople
        ? AppButton(
            '切换模式',
            kind: AppButtonKind.secondary,
            onPressed: () => Navigator.maybePop(context),
          )
        : AppButton(
            '采集说明',
            kind: AppButtonKind.secondary,
            onPressed: task == null
                ? null
                : () => Navigator.pushNamed(
                    context,
                    Routes.brief,
                    arguments: task,
                  ),
          );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: titleBlock),
        action,
      ],
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  static const _items = [('all', '全部'), ('valid', '有效'), ('invalid', '无效')];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          for (final item in _items)
            InkWell(
              onTap: () => onChanged(item.$1),
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      width: 2,
                      color: value == item.$1
                          ? AppColors.brand
                          : Colors.transparent,
                    ),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  item.$2,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: value == item.$1
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: value == item.$1 ? AppColors.brand : AppColors.muted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TakeRow extends StatelessWidget {
  const _TakeRow({required this.take, required this.onToggle});

  final Take take;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          take.taskName,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${take.time} · ${take.person} · ${take.robot}',
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ],
    );

    final meta = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusPill(
          text: take.valid ? '有效' : '无效',
          color: take.valid ? AppColors.ok : AppColors.bad,
        ),
        const SizedBox(width: 18),
        Text(
          take.duration,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(width: 18),
        Text(
          take.size,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
      ],
    );

    final ops = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppButton(
          '回看',
          kind: AppButtonKind.secondary,
          onPressed: () =>
              Navigator.pushNamed(context, Routes.review, arguments: take),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 100,
          child: AppButton(
            take.valid ? '标记无效' : '标记有效',
            kind: take.valid ? AppButtonKind.danger : AppButtonKind.success,
            onPressed: onToggle,
          ),
        ),
      ],
    );

    return AppPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 860) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                info,
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: meta),
                    ops,
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
              ops,
            ],
          );
        },
      ),
    );
  }
}
