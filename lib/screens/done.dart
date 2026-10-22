import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/scope.dart';
import '../core/theme.dart';

/// 任务已采：这一条任务下所有采集条，可回看、改有效/无效。
class DoneScreen extends StatelessWidget {
  const DoneScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final all = app.takesOf(app.dataFilter);
    final total = app.doneTotal;
    final left = (total - all.length).clamp(0, total);
    final rows = app.doneRows;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.dataFilter.isEmpty ? '任务已采' : app.dataFilter,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Hint(
                      app.dataFilter.isEmpty
                          ? ''
                          : '已采集 ${all.length} / $total 条，还差 $left 条。本机 ${app.currentRobotName} · ${app.currentRobotModel}。文件在当时那台工控。',
                    ),
                    const SizedBox(height: 6),
                    ProgressBar(
                      value: total == 0 ? 0 : all.length / total,
                      width: 220,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Wrap(
                spacing: 8,
                children: [
                  AppButton(
                    '采集说明',
                    kind: BtnKind.ghost,
                    onPressed: () => app.showBrief(app.dataFilter),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          AppTabs(
            labels: const ['全部', '有效', '无效'],
            index: app.doneTab,
            onChanged: app.setDoneTab,
          ),
          const SizedBox(height: 10),
          Expanded(
            child: rows.isEmpty
                ? const Center(
                    child: Text(
                      '这个任务还没有采集条',
                      style: TextStyle(fontSize: 14, color: C.muted),
                    ),
                  )
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) =>
                        _TakeRow(take: rows[index]),
                  ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 180,
                child: AppButton(
                  '返回选择模式',
                  kind: BtnKind.ghost,
                  height: 52,
                  onPressed: app.backHomeFromDone,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppButton(
                  '继续采集一条',
                  kind: BtnKind.ok,
                  height: 52,
                  fontSize: 18,
                  onPressed: app.addTake,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TakeRow extends StatelessWidget {
  const _TakeRow({required this.take});

  final TakeRecord take;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          take.task,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Hint('${take.time} · ${take.person} · ${take.robot}', size: 14),
      ],
    );
    final meta = Wrap(
      spacing: 18,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Pill(
          take.valid ? '有效' : '无效',
          kind: take.valid ? PillKind.run : PillKind.fix,
        ),
        Text(take.duration, style: const TextStyle(fontSize: 16)),
        Text(take.size, style: const TextStyle(fontSize: 16)),
      ],
    );
    final ops = Wrap(
      spacing: 8,
      runSpacing: 6,
      alignment: WrapAlignment.end,
      children: [
        AppButton(
          '回看',
          kind: BtnKind.ghost,
          height: 40,
          onPressed: () => app.replay(take),
        ),
        AppButton(
          take.valid ? '标记无效' : '标记有效',
          kind: take.valid ? BtnKind.bad : BtnKind.ok,
          height: 40,
          onPressed: () => app.toggleValid(take),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: C.panel,
        border: Border.all(color: C.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 680) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                info,
                const SizedBox(height: 8),
                meta,
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: ops),
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
