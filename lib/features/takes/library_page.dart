import 'package:flutter/material.dart';

import '../../app_routes.dart';
import '../../core/models/take.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_page.dart';
import 'review_page.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  String _task = '', _person = '', _filter = '全部';
  int? _selected;
  int _page = 0;
  static const _pageSize = 7;
  List<Take> get _rows => appState.takes
      .where(
        (take) =>
            (_task.isEmpty || take.taskName == _task) &&
            (_person.isEmpty || take.person == _person) &&
            (_filter == '全部' || take.valid == (_filter == '有效')),
      )
      .toList();

  @override
  Widget build(BuildContext context) {
    if (!appState.isEngineer && !appState.localSession) {
      return const AppPage(child: Center(child: Text('只有工程师或本地登录可以查看全部数据')));
    }
    final rows = _rows;
    final current =
        rows.where((r) => r.id == _selected).firstOrNull ?? rows.firstOrNull;
    _selected = current?.id;
    final pageCount = ((rows.length + _pageSize - 1) ~/ _pageSize).clamp(
      1,
      100000,
    );
    _page = _page.clamp(0, pageCount - 1);
    Widget list() => Column(
      children: [
        Expanded(
          child: ListView.separated(
            itemCount: rows.skip(_page * _pageSize).take(_pageSize).length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final take = rows[_page * _pageSize + i];
              return Material(
                color: current?.id == take.id
                    ? const Color(0xff203044)
                    : AppColors.panel,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: () => setState(() => _selected = take.id),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: current?.id == take.id
                            ? AppColors.brand
                            : AppColors.line,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${take.time} · ${take.duration}',
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${take.person} · ${take.taskName}',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          take.valid ? '有效' : '无效',
                          style: TextStyle(
                            color: take.valid ? AppColors.ok : AppColors.bad,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: '上一页',
              onPressed: _page > 0 ? () => setState(() => _page--) : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Text('${_page + 1} / $pageCount'),
            IconButton(
              tooltip: '下一页',
              onPressed: _page + 1 < pageCount
                  ? () => setState(() => _page++)
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    );
    Widget viewer() => current == null
        ? const Center(child: Text('没有符合筛选条件的记录'))
        : RecordingViewer(
            take: current,
            onChanged: () => setState(() {}),
            onPrevious: rows.indexOf(current) > 0
                ? () => setState(
                    () => _selected = rows[rows.indexOf(current) - 1].id,
                  )
                : null,
            onNext: rows.indexOf(current) + 1 < rows.length
                ? () => setState(
                    () => _selected = rows[rows.indexOf(current) + 1].id,
                  )
                : null,
          );
    return AppPage(
      showDevices: true,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  '查看数据',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                _select(_task, {
                  '': '全部任务',
                  for (final t in appState.tasks) t.name: t.name,
                }, (v) => _task = v),
                _select(_person, {
                  '': '全部人员',
                  for (final t in appState.takes) t.person: t.person,
                }, (v) => _person = v),
                _select(_filter, {
                  for (final v in ['全部', '有效', '无效']) v: v,
                }, (v) => _filter = v),
                Text('共 ${rows.length} 条'),
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
              child: LayoutBuilder(
                builder: (context, constraints) => constraints.maxWidth >= 900
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: 260, child: list()),
                          const SizedBox(width: 10),
                          Expanded(child: viewer()),
                        ],
                      )
                    : ListView(
                        children: [
                          SizedBox(height: 230, child: list()),
                          const SizedBox(height: 10),
                          SizedBox(height: 760, child: viewer()),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _select(
    String value,
    Map<String, String> items,
    void Function(String) change,
  ) => DropdownButton<String>(
    value: value,
    items: [
      for (final e in items.entries)
        DropdownMenuItem(
          value: e.key,
          child: Text(e.value, style: const TextStyle(fontSize: 13)),
        ),
    ],
    onChanged: (v) {
      if (v != null) {
        setState(() {
          change(v);
          _page = 0;
        });
      }
    },
  );
}
