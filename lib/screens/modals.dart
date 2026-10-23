import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../core/scope.dart';
import '../core/theme.dart';
import '../router/app_routes.dart';

/// 设置、采集说明、异常恢复、加载中。
class ModalHost extends StatelessWidget {
  const ModalHost({super.key, required this.location});

  final String location;

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
        const Hint('修改后只保存到配置，下次启动生效。当前连接不变。'),
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
              child: Hint(
                widget.readOnly ? '采集中不能修改 IP。' : '当前连接的 IP 不会因为保存而改变。',
              ),
            ),
            const SizedBox(width: 12),
            AppButton(
              '保存',
              kind: BtnKind.ok,
              height: 44,
              onPressed: widget.readOnly
                  ? null
                  : () {
                      if (app.saveIp(_ip ?? app.configuredIp)) {
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
                    onPressed: selected.running ? null : app.startProc,
                  ),
                  const SizedBox(width: 6),
                  AppButton(
                    '停止',
                    kind: BtnKind.ghost,
                    height: 32,
                    fontSize: 14,
                    onPressed: selected.running ? app.stopProc : null,
                  ),
                  const SizedBox(width: 6),
                  AppButton(
                    '重启',
                    kind: BtnKind.ghost,
                    height: 32,
                    fontSize: 14,
                    onPressed: app.restartProc,
                  ),
                ],
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
            onPressed: () => app.toast('已下载操作日志（${app.logRows.length} 条）'),
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
      ('机载存储', true, app.storageText),
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
    final actions = _actions(context, app);
    return _Dialog(
      width: 760,
      border: const Color(0xff6e322d),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            app.modalTitle.isEmpty ? '设备异常' : app.modalTitle,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
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

  List<Widget> _actions(BuildContext context, AppState app) =>
      switch (app.recoverKind) {
        'drop' => [
          AppButton(
            '确定',
            kind: BtnKind.ok,
            onPressed: () => app.resolveDrop(true),
          ),
          AppButton(
            '取消',
            kind: BtnKind.ghost,
            onPressed: () => app.resolveDrop(false),
          ),
        ],
        'home' => [
          AppButton('确认移动', kind: BtnKind.ok, onPressed: app.confirmHome),
          AppButton('取消', kind: BtnKind.ghost, onPressed: app.closeModal),
        ],
        'device' => [
          AppButton(
            '确定',
            onPressed: () {
              final router = GoRouter.of(context);
              app.closeModal();
              router.go(AppRoutes.forMode(app.mode));
            },
          ),
        ],
        'service' => [
          AppButton(
            '去设置',
            onPressed: () {
              app.closeModal();
              app.openModal(ModalKind.settings);
            },
          ),
          AppButton('取消', kind: BtnKind.ghost, onPressed: app.closeModal),
        ],
        _ => [AppButton('确定', onPressed: app.closeModal)],
      };
}

// ---------------------------------------------------------------------------
// 加载
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
            width: 36,
            height: 36,
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
