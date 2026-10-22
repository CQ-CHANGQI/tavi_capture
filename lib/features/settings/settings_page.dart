import 'package:flutter/material.dart';

import '../../app_routes.dart';
import '../../core/models/connect_state.dart';
import '../../core/network/ping_service.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/ip_input.dart';
import '../../core/widgets/modal_panel.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.readOnly = false});
  final bool readOnly;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _tab = '基本设置', _process = '采集服务', _logType = '系统日志', _range = '全部时间';
  late String _ip = appState.robotIp;
  bool _saving = false;
  String? _error;
  Future<void> _save() async {
    final parts = _ip.split('.');
    if (parts.length != 4 ||
        parts.any(
          (p) =>
              int.tryParse(p) == null || int.parse(p) < 0 || int.parse(p) > 255,
        )) {
      setState(() => _error = 'IP 地址格式不正确');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await PingService.ping(_ip);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = error;
    });
    if (error != null) return;
    appState.robotIp = _ip;
    appState.connection = ConnectState.connected;
    Navigator.pushNamedAndRemoveUntil(context, Routes.home, (_) => false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: ModalPanel(
      title: '设置',
      width: 960,
      onClose: () => Navigator.maybePop(context),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tabs = ['基本设置', '进程管理', '日志查看', '设备状态'];
          final menu = [
            for (final tab in tabs)
              TextButton(
                onPressed: () => setState(() => _tab = tab),
                style: TextButton.styleFrom(
                  foregroundColor: _tab == tab
                      ? AppColors.brand
                      : AppColors.muted,
                ),
                child: Text(tab),
              ),
          ];
          if (constraints.maxWidth < 650) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(children: menu),
                const SizedBox(height: 12),
                _content(),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 140,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: menu,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 380),
                  child: _content(),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
  Widget _content() => switch (_tab) {
    '进程管理' => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          children: [
            for (final p in ['采集服务', '设备连接服务', '网络同步服务', '数据存储服务', '日志服务'])
              ChoiceChip(
                label: Text(p),
                selected: _process == p,
                onSelected: (_) => setState(() => _process = p),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Wrap(
          spacing: 8,
          children: [AppButton('启用'), AppButton('停止'), AppButton('重启')],
        ),
        const SizedBox(height: 12),
        _empty('$_process：尚未接入进程管理服务'),
      ],
    ),
    '日志查看' => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          children: [
            _select(_logType, [
              '系统日志',
              '采集日志',
              '设备日志',
              '错误日志',
            ], (v) => _logType = v),
            _select(_range, [
              '全部时间',
              '最近 1 小时',
              '最近 24 小时',
              '最近 7 天',
            ], (v) => _range = v),
            const AppButton('下载', kind: AppButtonKind.secondary),
          ],
        ),
        const SizedBox(height: 12),
        _empty('尚未接入机器人日志服务'),
      ],
    ),
    '设备状态' => Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final name in [
          '机器人（工控）',
          '双臂服务',
          '夹爪',
          '底盘服务',
          'VR',
          '主视角相机',
          '左腕相机',
          '右腕相机',
          '全景相机',
          '机载存储',
        ])
          SizedBox(
            width: 230,
            child: _empty(
              '$name\n${name == '机器人（工控）' ? (appState.connection == ConnectState.connected ? '已连接' : '未连接') : '状态待查询'}',
            ),
          ),
      ],
    ),
    _ => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('机器人 IP'),
        const SizedBox(height: 8),
        IpInput(
          initialIp: _ip,
          enabled: !widget.readOnly && !_saving,
          onChanged: (v) => _ip = v,
        ),
        const SizedBox(height: 12),
        Text(
          widget.readOnly ? '采集和回放页面中不能修改连接。' : '保存后检查机器人连接。',
          style: const TextStyle(color: AppColors.muted),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_error!, style: const TextStyle(color: AppColors.bad)),
          ),
        const SizedBox(height: 12),
        AppButton(
          _saving ? '连接中…' : '保存并连接',
          onPressed: widget.readOnly || _saving ? null : _save,
        ),
        const SizedBox(height: 24),
        Text('当前账号：${appState.userName ?? '未登录'} · ${appState.role}'),
        TextButton(
          onPressed: () => Navigator.pushNamed(context, Routes.login),
          child: const Text('切换账号'),
        ),
      ],
    ),
  };
  Widget _empty(String text) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.input,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: const TextStyle(color: AppColors.muted, height: 1.7),
    ),
  );
  Widget _select(
    String value,
    List<String> values,
    void Function(String) change,
  ) => DropdownButton<String>(
    value: value,
    items: [for (final v in values) DropdownMenuItem(value: v, child: Text(v))],
    onChanged: (v) {
      if (v != null) setState(() => change(v));
    },
  );
}
