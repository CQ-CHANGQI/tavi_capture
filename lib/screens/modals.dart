import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../core/scope.dart';
import '../core/theme.dart';

/// 所有弹层：登录、采集说明、设置、手动控制、异常恢复、加载中。
class ModalHost extends StatelessWidget {
  const ModalHost({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final modal = app.modal;
    if (modal == null) return const SizedBox.shrink();
    final child = switch (modal) {
      ModalKind.login => const LoginModal(),
      ModalKind.brief => const BriefModal(),
      ModalKind.settings => const SettingsModal(),
      ModalKind.move => const MoveModal(),
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
// 登录
// ---------------------------------------------------------------------------

class LoginModal extends StatefulWidget {
  const LoginModal({super.key});

  @override
  State<LoginModal> createState() => _LoginModalState();
}

class _LoginModalState extends State<LoginModal> {
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _localPassword = TextEditingController();
  bool _local = false;
  Role _role = Role.operator;
  String _error = '';

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    _localPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final useLocal = !app.online || _local;
    return _Dialog(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                app.loggedIn
                    ? (useLocal ? '切换本地人员' : '切换账号')
                    : (useLocal ? '本地登录' : '云端登录'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              _closeButton(app),
            ],
          ),
          const SizedBox(height: 10),
          Hint(
            app.online
                ? (useLocal
                      ? '选择角色并输入本地密码登录。读取本机已缓存任务，不访问云端。'
                      : '有网：用云端账号和密码登录。登录后拉取该账号任务并落地到平板。')
                : '现场没网：选择角色并输入本地密码登录。读取本机已缓存任务。',
          ),
          if (app.online) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                AppButton(
                  '云端登录',
                  kind: useLocal ? BtnKind.ghost : BtnKind.primary,
                  onPressed: () => setState(() {
                    _local = false;
                    _error = '';
                  }),
                ),
                const SizedBox(width: 8),
                AppButton(
                  '本地登录',
                  kind: useLocal ? BtnKind.primary : BtnKind.ghost,
                  onPressed: () => setState(() {
                    _local = true;
                    _error = '';
                  }),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          if (!useLocal) _cloudForm(app) else _localForm(app),
        ],
      ),
    );
  }

  Widget _cloudForm(AppState app) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      const _Label('账号'),
      TextField(
        controller: _user,
        autofocus: true,
        decoration: const InputDecoration(hintText: '云端账号'),
      ),
      const _Label('密码'),
      TextField(
        controller: _password,
        obscureText: true,
        decoration: const InputDecoration(hintText: '密码'),
        onSubmitted: (_) => _submitCloud(app),
      ),
      _ErrorText(_error),
      AppButton(
        '登录',
        block: true,
        height: 44,
        onPressed: () => _submitCloud(app),
      ),
      const SizedBox(height: 10),
      const Hint(
        '原型：张三 / 1234 为工程师，可看本机数据；李四 / 1234 为采集员，只看自己的任务。账号由云端开，本端不能注册。',
        size: 14,
      ),
    ],
  );

  Widget _localForm(AppState app) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      const _Label('角色'),
      Row(
        children: [
          _roleChip(Role.engineer),
          const SizedBox(width: 18),
          _roleChip(Role.operator),
        ],
      ),
      const _Label('密码'),
      TextField(
        controller: _localPassword,
        obscureText: true,
        decoration: const InputDecoration(hintText: '本地登录密码'),
        onSubmitted: (_) => _submitLocal(app),
      ),
      _ErrorText(_error),
      AppButton(
        '登录',
        block: true,
        height: 44,
        onPressed: () => _submitLocal(app),
      ),
      const SizedBox(height: 10),
      const Hint('原型：工程师 weiyi1234 / 采集员 weiyi2018（密码后台写死）', size: 14),
    ],
  );

  Widget _roleChip(Role value) => InkWell(
    onTap: () => setState(() => _role = value),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _role == value ? Icons.radio_button_checked : Icons.radio_button_off,
          size: 20,
          color: _role == value ? C.brand : C.muted,
        ),
        const SizedBox(width: 6),
        Text(value.label, style: const TextStyle(fontSize: 16)),
      ],
    ),
  );

  void _submitCloud(AppState app) {
    final error = app.cloudLogin(_user.text.trim(), _password.text);
    if (!mounted) return;
    if (error != null) setState(() => _error = error);
  }

  void _submitLocal(AppState app) {
    final error = app.localLogin(_role, _localPassword.text);
    if (!mounted) return;
    if (error != null) setState(() => _error = error);
  }
}

// ---------------------------------------------------------------------------
// 采集说明
// ---------------------------------------------------------------------------

class BriefModal extends StatelessWidget {
  const BriefModal({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final task = app.briefTask.isEmpty ? app.dataFilter : app.briefTask;
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
  const SettingsModal({super.key});

  @override
  State<SettingsModal> createState() => _SettingsModalState();
}

class _SettingsModalState extends State<SettingsModal> {
  int _tab = 0;
  String? _ip;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ip ??= AppScope.of(context).savedIp;
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
    final readOnly = app.readOnlySettings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SectionTitle('机器人 IP'),
        const SizedBox(height: 4),
        const Hint('打开 App 会按这个地址自动连接。改完保存即重新连接。'),
        const SizedBox(height: 8),
        IpSegments(
          initialIp: _ip ?? app.savedIp,
          enabled: !readOnly,
          onChanged: (value) => _ip = value,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Hint(
                readOnly
                    ? '采集和查看数据页面中不能修改连接。'
                    : '开机自动打开 App、自动连接上次机器人、没网读本地任务。采集中不能改 IP。',
              ),
            ),
            const SizedBox(width: 12),
            AppButton(
              '保存并连接',
              kind: BtnKind.ok,
              height: 44,
              onPressed: readOnly
                  ? null
                  : () {
                      final ip = _ip ?? app.savedIp;
                      app.closeModal();
                      app.connect(ip);
                    },
            ),
          ],
        ),
      ],
    );
  }

  Widget _processes(AppState app) {
    final selected = app.services[app.selectedProc];
    final readOnly = app.readOnlySettings;
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
                    onPressed: readOnly || selected.running
                        ? null
                        : app.startProc,
                  ),
                  const SizedBox(width: 6),
                  AppButton(
                    '停止',
                    kind: BtnKind.ghost,
                    height: 32,
                    fontSize: 14,
                    onPressed: readOnly || !selected.running
                        ? null
                        : app.stopProc,
                  ),
                  const SizedBox(width: 6),
                  AppButton(
                    '重启',
                    kind: BtnKind.ghost,
                    height: 32,
                    fontSize: 14,
                    onPressed: readOnly ? null : app.restartProc,
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
          AppSelect<String>(
            value: app.logType,
            width: 180,
            items: [for (final key in AppState.logTypes.keys) (key, key)],
            onChanged: (value) =>
                setState(() => app.logType = value ?? app.logType),
          ),
          const SizedBox(width: 8),
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
            onPressed: () =>
                app.toast('已下载「${app.logType}」日志（${app.logRows.length} 条）'),
          ),
        ],
      ),
      const SizedBox(height: 10),
      _logBox([for (final line in app.logRows) line.text], height: 300),
    ],
  );

  Widget _devices(AppState app) {
    final rows = <(String, bool, String)>[
      ('机器人（工控）', app.robotOk, app.robotOk ? '已连接' : '未连接'),
      ('双臂服务', app.armOk, app.armOk ? '已上电 · 就绪' : '未启动'),
      ('夹爪', app.gripperOk, app.gripperOk ? '就绪' : '未连接'),
      ('底盘服务', app.baseOk, app.baseOk ? '就绪' : '未启动'),
      ('VR', app.vrOk, app.vrOk ? '在线' : '未连接'),
      (
        '主视角相机',
        app.live?.isOnline('cam_head') ?? false,
        app.live?.isOnline('cam_head') ?? false ? '正常' : '未连接',
      ),
      (
        '左腕相机',
        app.live?.isOnline('cam_left') ?? false,
        app.live?.isOnline('cam_left') ?? false ? '正常' : '未连接',
      ),
      (
        '右腕相机',
        app.live?.isOnline('cam_right') ?? false,
        app.live?.isOnline('cam_right') ?? false ? '正常' : '未连接',
      ),
      (
        '全景相机',
        app.live?.isOnline('cam_chest') ?? false,
        app.live?.isOnline('cam_chest') ?? false ? '正常' : '未连接',
      ),
      ('机载存储', app.storageOk, app.storageText),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Hint('各设备与服务的当前状态。待机时服务已停止，进入采集或手动控制时自动启动。'),
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
// 手动控制
// ---------------------------------------------------------------------------

class MoveModal extends StatefulWidget {
  const MoveModal({super.key});

  @override
  State<MoveModal> createState() => _MoveModalState();
}

class _MoveModalState extends State<MoveModal> {
  String _message = '按住方向按钮移动，松开停止。';
  int _speed = 50;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ready = app.baseOk && app.armOk;
    return _Dialog(
      width: 1000,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                '手动控制',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              AppButton(
                '完成',
                kind: BtnKind.ghost,
                height: 36,
                onPressed: app.closeModal,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(child: Hint('连接底盘和双臂后才能控制。')),
              AppButton(
                '一键连接',
                kind: BtnKind.primary,
                height: 46,
                minWidth: 160,
                onPressed: app.connectAll,
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 720;
              final left = _zone(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '双臂服务',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: C.legendInk,
                      ),
                    ),
                    const SizedBox(height: 8),
                    AppButton(
                      '回 home 点',
                      kind: BtnKind.ghost,
                      onPressed: ready ? app.cycleHome : null,
                    ),
                  ],
                ),
              );
              final right = _zone(_chassis(context, app, ready, narrow));
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [left, const SizedBox(height: 12), right],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 65, child: left),
                  const SizedBox(width: 16),
                  Expanded(flex: 135, child: right),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _zone(Widget child) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: C.input,
      border: Border.all(color: C.line),
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  );

  bool _ready = false;

  Widget _chassis(BuildContext context, AppState app, bool ready, bool narrow) {
    _ready = ready;
    return Column(
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '底盘控制',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: C.legendInk,
            ),
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 12.0;
            final size = ((constraints.maxWidth - 2 * gap - 16) / 5).clamp(
              40.0,
              104.0,
            );
            final radius = (size * 0.19).clamp(10.0, 20.0);
            Widget pad(String label, String direction) => SquareButton(
              label,
              size: size,
              radius: radius,
              fontSize: size * 0.44,
              onPressed: ready ? () {} : null,
            );
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _turn('↺', size, ready, () => _hold('左转中…')),
                const SizedBox(width: gap),
                _dpad(size, pad),
                const SizedBox(width: gap),
                _turn('↻', size, ready, () => _hold('右转中…')),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text('移动速度', style: TextStyle(fontSize: 14, color: C.muted)),
            const SizedBox(width: 12),
            Expanded(
              child: AppSelect<int>(
                value: _speed,
                items: const [
                  (25, '慢 25%'),
                  (50, '中 50%'),
                  (75, '快 75%'),
                  (100, '最快 100%'),
                ],
                onChanged: ready
                    ? (value) => setState(() => _speed = value ?? _speed)
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          _message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: C.muted),
        ),
      ],
    );
  }

  Widget _turn(String label, double size, bool ready, VoidCallback hold) =>
      Listener(
        onPointerDown: (_) {
          if (!ready) return;
          hold();
        },
        onPointerUp: (_) => ready ? _release() : null,
        onPointerCancel: (_) => ready ? _release() : null,
        child: SquareButton(
          label,
          size: size,
          radius: size / 2,
          fontSize: size * 0.42,
          color: C.warn,
          onPressed: ready ? () {} : null,
        ),
      );

  Widget _dpad(double size, Widget Function(String, String) pad) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: size, height: size),
          const SizedBox(width: 8),
          _holdButton(pad('↑', '前进')),
          const SizedBox(width: 8),
          SizedBox(width: size, height: size),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _holdButton(pad('←', '左移')),
          const SizedBox(width: 8),
          SizedBox(width: size, height: size),
          const SizedBox(width: 8),
          _holdButton(pad('→', '右移')),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: size, height: size),
          const SizedBox(width: 8),
          _holdButton(pad('↓', '后退')),
          const SizedBox(width: 8),
          SizedBox(width: size, height: size),
        ],
      ),
    ],
  );

  Widget _holdButton(Widget child) => Listener(
    onPointerDown: (_) {
      if (_ready) _hold('移动中…');
    },
    onPointerUp: (_) => _release(),
    onPointerCancel: (_) => _release(),
    child: child,
  );

  void _hold(String message) => setState(() => _message = message);

  void _release() => setState(() => _message = '已停止。');
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
          if (app.recoverKind == 'home') ...[
            const SizedBox(height: 12),
            const Center(child: _PoseView()),
          ],
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

  List<Widget> _actions(AppState app) => switch (app.recoverKind) {
    'drop' => [
      AppButton('确定', kind: BtnKind.ok, onPressed: () => app.resolveDrop(true)),
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
    'device' => [AppButton('确定', onPressed: app.abortToHome)],
    'service' => [
      AppButton(
        '去连接',
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

class _PoseView extends StatelessWidget {
  const _PoseView();

  @override
  Widget build(BuildContext context) => Container(
    width: 220,
    height: 150,
    decoration: BoxDecoration(
      color: C.input,
      borderRadius: BorderRadius.circular(8),
    ),
    child: CustomPaint(painter: _PosePainter()),
  );
}

class _PosePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()..color = const Color(0xff203044);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width / 2 - 35, size.height - 15, 70, 12),
        const Radius.circular(3),
      ),
      base,
    );
    canvas.drawRect(Rect.fromLTWH(size.width / 2 - 6, 95, 12, 40), base);
    final upper = Paint()
      ..color = C.brand
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    final lower = Paint()
      ..color = const Color(0xff7c6adf)
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    final shoulder = Offset(size.width / 2, 95);
    final elbow = Offset(size.width / 2 + 35, 55);
    final wrist = Offset(size.width / 2 + 70, 60);
    canvas.drawLine(shoulder, elbow, upper);
    canvas.drawLine(elbow, wrist, lower);
    canvas.drawCircle(shoulder, 6, Paint()..color = const Color(0xff2f6fb5));
    canvas.drawCircle(elbow, 5, Paint()..color = const Color(0xff5f54c0));
    canvas.drawCircle(wrist, 5, Paint()..color = C.warn);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 6),
    child: Text(text, style: const TextStyle(fontSize: 14, color: C.muted)),
  );
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 26,
    child: Align(
      alignment: Alignment.centerLeft,
      child: text.isEmpty
          ? null
          : Text(text, style: const TextStyle(fontSize: 14, color: C.bad)),
    ),
  );
}
