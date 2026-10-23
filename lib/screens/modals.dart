import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../core/scope.dart';
import '../core/theme.dart';

/// 设置、采集说明、异常恢复。
class ModalHost extends StatelessWidget {
  const ModalHost({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final modal = app.modal;
    if (modal == null) return const SizedBox.shrink();
    final child = switch (modal) {
      ModalKind.brief => const BriefModal(),
      ModalKind.settings => SettingsModal(readOnly: app.recording),
      ModalKind.recover => const RecoverModal(),
      ModalKind.loading => const LoadingModal(),
    };
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xB8070D15),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 弹窗外壳：底色 panel + 细边 + 14 圆角。
class _Dialog extends StatelessWidget {
  const _Dialog({required this.child, this.width = 420, this.border = C.line});

  final Widget child;
  final double width;
  final Color border;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxWidth: width,
      maxHeight: MediaQuery.sizeOf(context).height * 0.88,
    ),
    child: Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: C.panel,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    ),
  );
}

Widget _closeButton(AppState app) => AppButton(
  '关闭',
  kind: BtnKind.ghost,
  height: 32,
  fontSize: 14,
  onPressed: app.closeModal,
);

// ---------------------------------------------------------------------------
// 采集说明
// ---------------------------------------------------------------------------

class BriefModal extends StatelessWidget {
  const BriefModal({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final task = app.briefTask;
    return _Dialog(
      width: 720,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$task · 采集说明',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _closeButton(app),
            ],
          ),
          const SizedBox(height: 12),
          for (final line in app.briefOf(task))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: C.input,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(line, style: const TextStyle(fontSize: 15)),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 设置
// ---------------------------------------------------------------------------

class SettingsModal extends StatefulWidget {
  const SettingsModal({super.key, required this.readOnly});

  final bool readOnly;

  @override
  State<SettingsModal> createState() => _SettingsModalState();
}

class _SettingsModalState extends State<SettingsModal> {
  int _tab = 0;
  String? _ip;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ip ??= AppScope.of(context).configuredIp;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return _Dialog(
      width: 960,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                '设置',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              _closeButton(app),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 620;
              final menu = Wrap(
                spacing: 4,
                children: [
                  for (var i = 0; i < _tabs.length; i++)
                    InkWell(
                      onTap: () => setState(() => _tab = i),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.centerLeft,
                        decoration: BoxDecoration(
                          color: _tab == i ? C.panel2 : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _tabs[i],
                          style: TextStyle(
                            fontSize: 16,
                            color: _tab == i ? C.brand : C.muted,
                            fontWeight: _tab == i
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                ],
              );
              final content = ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 380),
                child: SingleChildScrollView(child: _content(app)),
              );
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [menu, const SizedBox(height: 12), content],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 140,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [menu],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 420,
                    color: C.line,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  Expanded(child: content),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  static const _tabs = ['基本设置', '进程管理', '日志查看', '设备状态'];

  Widget _content(AppState app) => switch (_tab) {
    1 => _processes(app),
    2 => _logs(app),
    3 => _devices(app),
    _ => _basic(app),
  };

  Widget _basic(AppState app) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SectionTitle('机器人 IP'),
        const SizedBox(height: 4),
        const Hint('保存并连接会立即重连；采集中不能修改 IP。'),
        const SizedBox(height: 8),
        IpSegments(
          initialIp: _ip ?? app.configuredIp,
          enabled: !widget.readOnly,
          onChanged: (value) => _ip = value,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Hint(widget.readOnly ? '采集中不能修改 IP。' : '重连成功前，当前连接保持不变。'),
            ),
            const SizedBox(width: 12),
            AppButton(
              '保存并连接',
              kind: BtnKind.ok,
              height: 44,
              onPressed: widget.readOnly
                  ? null
                  : () async {
                      if (await app.reconnect(_ip ?? app.configuredIp)) {
                        app.closeModal();
                      }
                    },
            ),
          ],
        ),
      ],
    );
  }

  Widget _processes(AppState app) {
    final selected = app.services[app.selectedProc];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 240,
          constraints: const BoxConstraints(maxHeight: 340),
          decoration: BoxDecoration(
            color: C.panel,
            border: Border.all(color: C.line),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (var i = 0; i < app.services.length; i++)
                  InkWell(
                    onTap: () => app.selectProc(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      color: i == app.selectedProc ? C.panel2 : null,
                      child: Row(
                        children: [
                          _dot(app.services[i].running),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              app.services[i].name,
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                          Hint(
                            app.services[i].running ? '运行中' : '已停止',
                            size: 14,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text(
                    '日志',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  AppButton(
                    '启用',
                    kind: BtnKind.ghost,
                    height: 32,
                    fontSize: 14,
                    onPressed: selected.running || widget.readOnly
                        ? null
                        : app.startProc,
                  ),
                  const SizedBox(width: 6),
                  AppButton(
                    '停止',
                    kind: BtnKind.ghost,
                    height: 32,
                    fontSize: 14,
                    onPressed: selected.running && !widget.readOnly
                        ? app.stopProc
                        : null,
                  ),
                  const SizedBox(width: 6),
                  AppButton(
                    '重启',
                    kind: BtnKind.ghost,
                    height: 32,
                    fontSize: 14,
                    onPressed: widget.readOnly ? null : app.restartProc,
                  ),
                ],
              ),
              if (widget.readOnly)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Hint('采集中进程管理只读，只能查看日志。'),
                ),
              const SizedBox(height: 8),
              _logBox([for (final line in selected.logs) line], height: 280),
            ],
          ),
        ),
      ],
    );
  }

  Widget _logs(AppState app) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          const Text(
            '操作日志',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 12),
          AppSelect<String>(
            value: app.logRange,
            width: 180,
            items: const [
              ('全部时间', '全部时间'),
              ('最近 1 小时', '最近 1 小时'),
              ('最近 24 小时', '最近 24 小时'),
              ('最近 7 天', '最近 7 天'),
            ],
            onChanged: (value) =>
                setState(() => app.logRange = value ?? app.logRange),
          ),
          const Spacer(),
          AppButton(
            '下载',
            kind: BtnKind.ghost,
            onPressed: () => app.toast('日志下载待文件服务接入'),
          ),
        ],
      ),
      const SizedBox(height: 10),
      _logBox([for (final line in app.logRows) line.text], height: 300),
    ],
  );

  Widget _devices(AppState app) {
    final rows = <(String, bool, String)>[
      ('双臂', app.armOk, app.armOk ? '已上电' : '未上电'),
      ('夹爪', app.gripperOk, app.gripperOk ? '已上电' : '未上电'),
      ('底盘', app.baseOk, app.baseOk ? '已上电' : '未上电'),
      (
        '主视角相机',
        app.live?.isOnline('cam_head') ?? false,
        app.live?.isOnline('cam_head') ?? false ? '已上电' : '未上电',
      ),
      (
        '左腕相机',
        app.live?.isOnline('cam_left') ?? false,
        app.live?.isOnline('cam_left') ?? false ? '已上电' : '未上电',
      ),
      (
        '右腕相机',
        app.live?.isOnline('cam_right') ?? false,
        app.live?.isOnline('cam_right') ?? false ? '已上电' : '未上电',
      ),
      (
        '全景相机',
        app.live?.isOnline('cam_chest') ?? false,
        app.live?.isOnline('cam_chest') ?? false ? '已上电' : '未上电',
      ),
      ('机载存储', true, '剩余 ${app.storageGb.round()} GB'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Hint('硬件上电状态。服务是否运行看“进程管理”；进入采集或手动模式会自动启动服务。'),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.maxWidth - 8) / 2;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (name, ok, detail) in rows)
                  SizedBox(
                    width: width,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: C.panel,
                        border: Border.all(color: C.line),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          _dot(ok),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(fontSize: 15),
                                ),
                                Text(
                                  detail,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: C.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _logBox(List<String> lines, {required double height}) => Container(
    height: height,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: C.log,
      border: Border.all(color: C.line),
      borderRadius: BorderRadius.circular(8),
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lines.isEmpty)
            const Text('暂无日志', style: TextStyle(fontSize: 14, color: C.muted)),
          for (final line in lines)
            Text(
              line,
              style: const TextStyle(
                fontSize: 14,
                height: 1.7,
                color: Color(0xffa8c8e8),
                fontFamily: 'monospace',
              ),
            ),
        ],
      ),
    ),
  );

  Widget _dot(bool ok) => Container(
    width: 14,
    height: 14,
    decoration: BoxDecoration(color: ok ? C.ok : C.bad, shape: BoxShape.circle),
  );
}

// ---------------------------------------------------------------------------
// 异常恢复
// ---------------------------------------------------------------------------

class RecoverModal extends StatelessWidget {
  const RecoverModal({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final actions = _actions(app);
    final isHome = app.recoverKind == 'home';
    final isError =
        app.recoverKind == 'drop' ||
        app.recoverKind == 'service' ||
        app.recoverKind == 'connect';
    return _Dialog(
      width: isHome ? 420 : 760,
      border: isError ? const Color(0xff6e322d) : C.line,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            app.modalTitle.isEmpty ? '设备异常' : app.modalTitle,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (isHome) ...[
            Container(
              height: 140,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: C.input,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const CustomPaint(painter: _PosePainter()),
            ),
          ],
          Text(
            app.modalText,
            style: const TextStyle(fontSize: 15, height: 1.6, color: C.softInk),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: actions,
          ),
        ],
      ),
    );
  }

  List<Widget> _actions(AppState app) => switch (app.recoverKind) {
    'drop' => [
      AppButton('确定', kind: BtnKind.ok, onPressed: () => app.resolveDrop(true)),
      AppButton(
        '取消',
        kind: BtnKind.ghost,
        onPressed: () => app.resolveDrop(false),
      ),
    ],
    'confirm' => [
      AppButton(
        app.confirmLabel,
        kind: BtnKind.ok,
        onPressed: () => app.resolveConfirm(true),
      ),
      AppButton(
        '取消',
        kind: BtnKind.ghost,
        onPressed: () => app.resolveConfirm(false),
      ),
    ],
    'home' => [
      AppButton('确认移动', kind: BtnKind.ok, onPressed: app.confirmHome),
      AppButton('取消', kind: BtnKind.ghost, onPressed: app.closeModal),
    ],
    'service' => [
      AppButton(
        '去连接',
        kind: BtnKind.ok,
        onPressed: () {
          app.closeModal();
          app.openModal(ModalKind.settings);
        },
      ),
      AppButton('确定', kind: BtnKind.ghost, onPressed: app.closeModal),
    ],
    _ => [AppButton('确定', onPressed: app.closeModal)],
  };
}

/// 回位确认里的双臂位姿示意。
class _PosePainter extends CustomPainter {
  const _PosePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()..color = const Color(0xff203044);
    final blue = Paint()
      ..color = const Color(0xff3b82c4)
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    final purple = Paint()
      ..color = const Color(0xff7c6adf)
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    final centerX = size.width / 2;
    final bottom = size.height - 15;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(centerX, bottom), width: 70, height: 12),
        const Radius.circular(3),
      ),
      base,
    );
    final joint = Offset(centerX, bottom - 40);
    canvas.drawRect(
      Rect.fromCenter(center: joint.translate(0, 20), width: 12, height: 40),
      base,
    );
    canvas.drawLine(joint, Offset(centerX, bottom - 80), blue);
    canvas.drawLine(
      Offset(centerX, bottom - 80),
      Offset(centerX + 35, bottom - 75),
      purple,
    );
    canvas.drawCircle(joint, 6, Paint()..color = const Color(0xff2f6fb5));
    canvas.drawCircle(
      Offset(centerX, bottom - 80),
      5,
      Paint()..color = const Color(0xff5f54c0),
    );
    canvas.drawCircle(
      Offset(centerX + 35, bottom - 75),
      5,
      Paint()..color = const Color(0xffd39a3a),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// 启动服务 / 页面切换
// ---------------------------------------------------------------------------

class LoadingModal extends StatelessWidget {
  const LoadingModal({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return _Dialog(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 14),
          Text(
            app.loadingText,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          if (app.loadingSub.isNotEmpty) ...[
            const SizedBox(height: 8),
            Hint(app.loadingSub),
          ],
        ],
      ),
    );
  }
}
