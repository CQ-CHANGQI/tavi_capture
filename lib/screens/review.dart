import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../core/playback.dart';
import '../core/scope.dart';
import '../core/theme.dart';
import '../ui/playbar.dart';
import '../ui/replay_panel.dart';

/// 查看数据：筛选 + 采集条列表 + 本条信息 / 回放三态 + 最大化。
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  bool _detail = false;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final take = app.libSelected;
    final player = app.playback;
    final wide = MediaQuery.sizeOf(context).width >= 1000;

    final task = app.localTasks.where((t) => t.name == app.libTask).firstOrNull;
    final persons = app.libTask.isEmpty
        ? app.allPersons
        : (task?.persons ?? const <String>[]);
    final personItems = <(String, String)>[
      ('', app.libTask.isEmpty ? '全部人员' : '请选择人员'),
      for (final person in persons) (person, person),
    ];
    final personValue = personItems.any((item) => item.$1 == app.libPerson)
        ? app.libPerson
        : '';

    final actions = <Widget>[
      AppButton(
        '上一条',
        kind: BtnKind.ghost,
        height: 32,
        fontSize: 14,
        onPressed: take == null
            ? null
            : () {
                setState(() => _detail = true);
                app.libPrev();
              },
      ),
      AppButton(
        '下一条',
        kind: BtnKind.ghost,
        height: 32,
        fontSize: 14,
        onPressed: take == null
            ? null
            : () {
                setState(() => _detail = true);
                app.libNext();
              },
      ),
      AppButton(
        _detail ? '关闭详情' : '详情',
        kind: BtnKind.ghost,
        height: 32,
        fontSize: 14,
        onPressed: take == null
            ? null
            : () => setState(() => _detail = !_detail),
      ),
      AppButton(
        '最大化',
        kind: BtnKind.ghost,
        height: 32,
        fontSize: 14,
        onPressed: take == null ? null : () => _openMaximized(context, app),
      ),
      AppButton(
        take?.valid == false ? '标记有效' : '标记无效',
        kind: take?.valid == false ? BtnKind.ok : BtnKind.bad,
        height: 32,
        fontSize: 14,
        onPressed: take == null ? null : () => app.toggleValid(take),
      ),
    ];

    final panel = take != null && _detail
        ? _TakeDetailPanel(
            app: app,
            take: take,
            player: player,
            actions: actions,
            onPlay: () => setState(() => _detail = false),
          )
        : ReplayPanel(
            player: player,
            duration: take?.duration ?? '00:00',
            valid: take?.valid ?? true,
            actions: actions,
            onRetry: app.retryPlayback,
          );

    final filters = <Widget>[
      const Text(
        '查看数据',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
      AppSelect<String>(
        value: app.libTask,
        width: 220,
        items: [
          ('', '全部任务'),
          for (final item in app.localTasks) (item.name, item.name),
        ],
        onChanged: (value) {
          setState(() => _detail = false);
          app.setLibTask(value ?? '');
        },
      ),
      AppSelect<String>(
        value: personValue,
        width: 150,
        items: personItems,
        onChanged: (value) {
          setState(() => _detail = false);
          app.setLibPerson(value ?? '');
        },
      ),
      AppTabs(
        labels: const ['全部', '有效', '无效'],
        index: app.libTab,
        onChanged: (value) {
          setState(() => _detail = false);
          app.setLibTab(value);
        },
        dense: true,
      ),
      Text('共 ${app.libRows.length} 条', style: const TextStyle(fontSize: 16)),
    ];

    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: app.libPageRows.isEmpty
              ? const Center(
                  child: Text(
                    '还没有采集数据',
                    style: TextStyle(fontSize: 14, color: C.muted),
                  ),
                )
              : ListView.separated(
                  itemCount: app.libPageRows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final row = app.libPageRows[index];
                    return _ReviewRow(
                      take: row,
                      selected: row == take,
                      onTap: () {
                        setState(() => _detail = true);
                        app.selectTake(row);
                      },
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
              height: 40,
              fontSize: 14,
              onPressed: app.libPage > 0 ? app.libPrevPage : null,
            ),
            const SizedBox(width: 10),
            Text(
              '第 ${app.libPage + 1} / ${app.libPageCount} 页',
              style: const TextStyle(fontSize: 14, color: C.muted),
            ),
            const SizedBox(width: 10),
            AppButton(
              '下一页',
              kind: BtnKind.ghost,
              height: 40,
              fontSize: 14,
              onPressed: app.libPage + 1 < app.libPageCount
                  ? app.libNextPage
                  : null,
            ),
          ],
        ),
      ],
    );

    final header = LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: filters,
          );
        }
        return Row(
          children: [
            for (final item in filters) ...[item, const SizedBox(width: 10)],
          ],
        );
      },
    );

    return Padding(
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
    );
  }

  Future<void> _openMaximized(BuildContext context, AppState app) async {
    if (app.libSelected == null) return;
    app.telemetry.track('click_replay_max', {'action': 'maximize'});
    var detail = _detail;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) {
          final currentApp = AppScope.of(context);
          final take = currentApp.libSelected;
          final player = currentApp.playback;
          final actions = <Widget>[
            AppButton(
              '上一条',
              kind: BtnKind.ghost,
              height: 30,
              fontSize: 13,
              onPressed: take == null
                  ? null
                  : () {
                      setLocal(() => detail = true);
                      currentApp.libPrev();
                    },
            ),
            AppButton(
              '下一条',
              kind: BtnKind.ghost,
              height: 30,
              fontSize: 13,
              onPressed: take == null
                  ? null
                  : () {
                      setLocal(() => detail = true);
                      currentApp.libNext();
                    },
            ),
            AppButton(
              detail ? '关闭详情' : '详情',
              kind: BtnKind.ghost,
              height: 30,
              fontSize: 13,
              onPressed: take == null
                  ? null
                  : () => setLocal(() => detail = !detail),
            ),
            AppButton(
              '还原',
              kind: BtnKind.ghost,
              height: 30,
              fontSize: 13,
              onPressed: () {
                currentApp.telemetry.track('click_replay_max', {
                  'action': 'restore',
                });
                Navigator.pop(dialogContext);
              },
            ),
            AppButton(
              take?.valid == false ? '标记有效' : '标记无效',
              kind: take?.valid == false ? BtnKind.ok : BtnKind.bad,
              height: 30,
              fontSize: 13,
              onPressed: take == null
                  ? null
                  : () {
                      currentApp.toggleValid(take);
                      setLocal(() {});
                    },
            ),
          ];
          final Widget content = take == null
              ? ReplayPanel(
                  player: null,
                  duration: '00:00',
                  valid: true,
                  actions: actions,
                )
              : detail
              ? _TakeDetailPanel(
                  app: currentApp,
                  take: take,
                  player: player,
                  actions: actions,
                  onPlay: () => setLocal(() => detail = false),
                )
              : ReplayPanel(
                  player: player,
                  duration: take.duration,
                  valid: take.valid,
                  actions: actions,
                  onRetry: currentApp.retryPlayback,
                  maximized: true,
                );
          return Dialog.fullscreen(
            backgroundColor: C.bg,
            child: Padding(padding: const EdgeInsets.all(14), child: content),
          );
        },
      ),
    );
  }
}

/// 本条信息面板：详情和最大化共用。
class _TakeDetailPanel extends StatelessWidget {
  const _TakeDetailPanel({
    required this.app,
    required this.take,
    required this.player,
    required this.actions,
    this.onPlay,
  });

  final AppState app;
  final TakeRecord take;
  final PlaybackController? player;
  final List<Widget> actions;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final current = player;
    if (current == null) return _build(context);
    return ListenableBuilder(
      listenable: current,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final title = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    '回放 · ${take.duration}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Pill(
                  take.valid ? '有效' : '无效',
                  kind: take.valid ? PillKind.run : PillKind.fix,
                ),
              ],
            );
            if (constraints.maxWidth < 760) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title,
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 6, children: actions),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: title),
                Wrap(spacing: 8, runSpacing: 6, children: actions),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _InfoRow('采集时间', take.time),
                _InfoRow('采集文件名称', take.fileName),
                _InfoRow('任务名称', take.task),
                _InfoRow('采集人员', take.person),
                _InfoRow('机器人', take.robot),
                _InfoRow('存储地址', take.storagePath),
                _InfoRow('文件大小', take.size),
                _InfoRow('视频时长', take.duration),
                const SizedBox(height: 10),
                AppButton(
                  '采集说明',
                  kind: BtnKind.ghost,
                  height: 38,
                  onPressed: () => app.showBrief(take.task),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (player == null)
          const EmptyPlayBar()
        else
          PlayBar(player: player!, onPlay: onPlay),
      ],
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xff24364a))),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, color: C.muted),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 14, color: C.ink),
          ),
        ),
      ],
    ),
  );
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                take.takeName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              take.size,
              style: const TextStyle(fontSize: 13, color: C.muted),
            ),
            const SizedBox(width: 8),
            Pill(
              take.valid ? '有效' : '无效',
              kind: take.valid ? PillKind.run : PillKind.fix,
            ),
          ],
        ),
      ),
    ),
  );
}
