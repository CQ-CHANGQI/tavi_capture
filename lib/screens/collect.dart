import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/live_preview.dart';
import '../core/models.dart';
import '../core/scope.dart';
import '../core/theme.dart';
import '../ui/camera.dart';

/// 数据采集：任务/人员选择 + 相机实时预览 + 计时 + 录制。
class CollectScreen extends StatelessWidget {
  const CollectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final task = app.collectTaskItem;
    final wide = MediaQuery.sizeOf(context).width >= 1000;

    final header = LayoutBuilder(
      builder: (context, constraints) {
        final taskItems = [
          for (final item in app.localTasks) (item.name, item.name),
        ];
        final taskValue = taskItems.any((item) => item.$1 == app.collectTask)
            ? app.collectTask
            : taskItems.isEmpty
            ? ''
            : taskItems.first.$1;
        final persons = task?.persons ?? const <String>[];
        final personItems = persons.isEmpty
            ? [('', '请选择人员')]
            : [for (final person in persons) (person, person)];
        final personValue =
            personItems.any((item) => item.$1 == app.collectPerson)
            ? app.collectPerson
            : personItems.first.$1;

        final items = <Widget>[
          const Text(
            '数据采集',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          AppSelect<String>(
            value: taskValue,
            width: 220,
            enabled: !app.recording && taskItems.isNotEmpty,
            items: taskItems,
            onChanged: (value) => app.requestCollectTask(value ?? ''),
          ),
          AppSelect<String>(
            value: personValue,
            width: 150,
            enabled: !app.recording && persons.isNotEmpty,
            items: personItems,
            onChanged: (value) => app.requestCollectPerson(value ?? ''),
          ),
          AppButton(
            '采集说明',
            kind: BtnKind.ghost,
            height: 46,
            onPressed: task == null ? null : () => app.showBrief(task.name),
          ),
        ];
        if (constraints.maxWidth < 900) {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: items,
          );
        }
        return Row(children: items);
      },
    );

    final panels = <Widget>[
      _takeList(app),
      _cameras(app),
      _controls(app, task),
    ];

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
                      Expanded(flex: 50, child: panels[0]),
                      const SizedBox(width: 10),
                      Expanded(flex: 170, child: panels[1]),
                      const SizedBox(width: 10),
                      Expanded(flex: 60, child: panels[2]),
                    ],
                  )
                : ListView(
                    children: [
                      SizedBox(height: 360, child: panels[1]),
                      const SizedBox(height: 10),
                      panels[2],
                      const SizedBox(height: 10),
                      SizedBox(height: 280, child: panels[0]),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _takeList(AppState app) {
    final rows = app.collectRows;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle('采集数据'),
          const SizedBox(height: 8),
          Expanded(
            child: rows.isEmpty
                ? const Align(
                    alignment: Alignment.topLeft,
                    child: Hint('还没有采集数据'),
                  )
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final take = rows[index];
                      final latest = index == 0;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: latest ? C.panel2 : C.input,
                          border: Border.all(
                            color: latest ? C.brand : Colors.transparent,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              take.takeName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                color: C.legendInk,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${take.time} · ${take.size}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Pill(
                                  take.valid ? '有效' : '无效',
                                  kind: take.valid
                                      ? PillKind.run
                                      : PillKind.fix,
                                ),
                              ],
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

  Widget _cameras(AppState app) {
    final live = app.live;
    if (live == null) return _cameraPanel(null);
    return ListenableBuilder(
      listenable: live,
      builder: (context, _) => _cameraPanel(live),
    );
  }

  Widget _cameraPanel(LivePreview? live) {
    final online = live?.allCamerasOnline ?? false;
    return Panel(
      child: Column(
        children: [
          Row(
            children: [
              const SectionTitle('相机'),
              const Spacer(),
              if (live != null && live.error != null)
                const Text('接收异常', style: TextStyle(fontSize: 12, color: C.bad))
              else
                Text(
                  live == null
                      ? '未启动'
                      : online
                      ? '实时'
                      : '等待数据',
                  style: TextStyle(
                    fontSize: 12,
                    color: online ? C.ok : C.muted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: CameraGrid(
              images: live?.images ?? const {},
              fps: live?.fps,
              dead: live == null
                  ? const {}
                  : {
                      for (final camera in CameraId.values)
                        if (live.hasFrame(camera.channel) &&
                            !live.isOnline(camera.channel))
                          camera.channel,
                    },
            ),
          ),
          if (live?.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                live!.error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: C.bad),
              ),
            ),
        ],
      ),
    );
  }

  Widget _controls(AppState app, TaskItem? task) {
    final done = app.collectDone;
    final total = app.collectTotal;
    final left = app.collectLeft;
    final fsmColor = app.fsmState == 'HOME点'
        ? C.ok
        : app.fsmState == 'HOLD'
        ? C.warn
        : C.bad;

    return Panel(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(task?.name ?? '任务进度'),
            StatRow('已采集', '$done / $total'),
            ProgressBar(value: total == 0 ? 0 : done / total),
            const SizedBox(height: 4),
            Hint(total == 0 ? '未设置目标' : '还差 $left 条'),
            const SizedBox(height: 16),
            const SectionTitle('本条计时'),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Text('本条', style: TextStyle(fontSize: 15)),
                  const Spacer(),
                  Text(
                    formatClock(app.elapsedSec),
                    style: const TextStyle(
                      fontSize: 22,
                      color: Colors.white,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const SectionTitle('录制状态'),
            StatRow(
              '当前',
              app.recording ? '录制中' : '空闲',
              valueColor: app.recording ? C.ok : C.muted,
            ),
            StatRow(
              '上一条',
              app.lastTakeState,
              valueColor: app.lastTakeState == '已保存'
                  ? C.ok
                  : app.lastTakeState == '已作废'
                  ? C.bad
                  : C.muted,
            ),
            const SizedBox(height: 12),
            const SectionTitle('FSM状态'),
            StatRow('当前', app.fsmState, valueColor: fsmColor),
            const SizedBox(height: 24),
            AppButton(
              app.recording ? '停止并保存' : '开始采集',
              kind: app.recording ? BtnKind.bad : BtnKind.ok,
              height: 58,
              fontSize: 20,
              onPressed: app.recording
                  ? app.stopCollect
                  : app.canStartCollect
                  ? app.startCollect
                  : null,
            ),
            const SizedBox(height: 20),
            AppButton(
              '作废',
              kind: BtnKind.danger,
              onPressed: app.recording ? app.dropTake : null,
            ),
          ],
        ),
      ),
    );
  }
}
