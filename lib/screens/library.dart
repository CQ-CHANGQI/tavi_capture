import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/scope.dart';
import '../core/theme.dart';
import '../ui/replay_panel.dart';

/// 查看数据：筛选 + 采集条列表 + 回放。
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool _maximized = false;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final take = app.libSelected;
    final player = app.playback;
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final taskNames = <String>{'', for (final t in app.libAll) t.task};
    final taskValue = taskNames.contains(app.libTask) ? app.libTask : '';

    final panel = ReplayPanel(
      player: player,
      duration: take?.duration ?? '00:00',
      valid: take?.valid ?? true,
      onRetry: app.retryPlayback,
      actions: [
        if (take != null) ...[
          AppButton(
            '上一条',
            kind: BtnKind.ghost,
            height: 32,
            fontSize: 14,
            onPressed: app.libPrev,
          ),
          AppButton(
            '下一条',
            kind: BtnKind.ghost,
            height: 32,
            fontSize: 14,
            onPressed: app.libNext,
          ),
          AppButton(
            _maximized ? '还原' : '最大化',
            kind: BtnKind.ghost,
            height: 32,
            fontSize: 14,
            onPressed: () => setState(() => _maximized = !_maximized),
          ),
          AppButton(
            take.valid ? '标记无效' : '标记有效',
            kind: take.valid ? BtnKind.bad : BtnKind.ok,
            height: 32,
            fontSize: 14,
            onPressed: () => app.toggleValid(take),
          ),
        ],
      ],
    );

    final filters = <Widget>[
      const Text(
        '查看数据',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
      AppSelect<String>(
        value: taskValue,
        width: 220,
        items: [
          ('', '全部任务'),
          for (final name in taskNames.where((n) => n.isNotEmpty)) (name, name),
        ],
        onChanged: (value) => app.setLibTask(value ?? ''),
      ),
      AppSelect<String>(
        value: app.libPerson,
        width: 140,
        items: const [('', '全部人员'), ('张三', '张三'), ('李四', '李四')],
        onChanged: (value) => app.setLibPerson(value ?? ''),
      ),
      AppTabs(
        labels: const ['全部', '有效', '无效'],
        index: app.libTab,
        onChanged: app.setLibTab,
        dense: true,
      ),
      Text('共 ${app.libRows.length} 条', style: const TextStyle(fontSize: 16)),
    ];
    final back = AppButton(
      '返回选择模式',
      kind: BtnKind.ghost,
      height: 46,
      onPressed: () => app.go(ScreenId.home),
    );
    final header = LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [...filters, back],
          );
        }
        return Row(
          children: [
            for (final item in filters) ...[item, const SizedBox(width: 10)],
            const Spacer(),
            back,
          ],
        );
      },
    );

    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: app.libPageRows.isEmpty
              ? const Center(
                  child: Text(
                    '这台机器人上还没有采集条',
                    style: TextStyle(fontSize: 14, color: C.muted),
                  ),
                )
              : ListView.separated(
                  itemCount: app.libPageRows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final row = app.libPageRows[index];
                    return _LibraryRow(
                      take: row,
                      selected: row == take,
                      onTap: () => app.selectTake(row),
                    );
                  },
                ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppButton(
              '上一页',
              kind: BtnKind.ghost,
              height: 44,
              fontSize: 15,
              onPressed: app.libPage > 0 ? app.libPrevPage : null,
            ),
            const SizedBox(width: 12),
            Text(
              '第 ${app.libPage + 1} / ${app.libPageCount} 页',
              style: const TextStyle(fontSize: 15, color: C.muted),
            ),
            const SizedBox(width: 12),
            AppButton(
              '下一页',
              kind: BtnKind.ghost,
              height: 44,
              fontSize: 15,
              onPressed: app.libPage + 1 < app.libPageCount
                  ? app.libNextPage
                  : null,
            ),
          ],
        ),
      ],
    );

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: 10),
              Expanded(
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: 320, child: list),
                          const SizedBox(width: 10),
                          Expanded(child: panel),
                        ],
                      )
                    : ListView(
                        children: [
                          SizedBox(height: 560, child: panel),
                          const SizedBox(height: 10),
                          SizedBox(height: 300, child: list),
                        ],
                      ),
              ),
            ],
          ),
        ),
        if (_maximized)
          Positioned.fill(
            child: ColoredBox(
              color: C.bg,
              child: Padding(padding: const EdgeInsets.all(14), child: panel),
            ),
          ),
      ],
    );
  }
}

class _LibraryRow extends StatelessWidget {
  const _LibraryRow({
    required this.take,
    required this.selected,
    required this.onTap,
  });

  final TakeRecord take;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? C.panel2 : C.panel,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(color: selected ? C.brand : C.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    take.task,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Pill(
                  take.valid ? '有效' : '无效',
                  kind: take.valid ? PillKind.run : PillKind.fix,
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${take.time} · ${take.duration} · ${take.size}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: C.muted),
            ),
          ],
        ),
      ),
    ),
  );
}
