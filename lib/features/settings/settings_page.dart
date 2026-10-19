import 'package:flutter/material.dart';

import '../../core/state/app_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/ip_input.dart';
import '../../core/widgets/modal_panel.dart';

/// 设置弹窗：基本设置 / 进程管理 / 日志查看。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _tab = 'basic';
  late String _ip = appState.robotIp;

  void _save() {
    appState.robotIp = _ip;
    showToast(context, 'IP 已保存：$_ip（模拟）');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ModalPanel(
        title: '设置',
        width: 780,
        onClose: () => Navigator.maybePop(context),
        child: SizedBox(
          height: 430,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 140, child: _sideMenu()),
              const SizedBox(width: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: switch (_tab) {
                    'proc' => _processContent(),
                    'log' => _logContent(),
                    _ => _basicContent(),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sideMenu() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: AppColors.line)),
      ),
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        children: [
          _sideButton('基本设置', 'basic'),
          _sideButton('进程管理', 'proc'),
          _sideButton('日志查看', 'log'),
        ],
      ),
    );
  }

  Widget _sideButton(String label, String value) {
    final active = _tab == value;

    return SizedBox(
      width: double.infinity,
      height: 40,
      child: TextButton(
        onPressed: () => setState(() => _tab = value),
        style: TextButton.styleFrom(
          alignment: Alignment.centerLeft,
          backgroundColor: active
              ? const Color(0xFF203044)
              : Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? AppColors.brand : AppColors.muted,
          ),
        ),
      ),
    );
  }

  Widget _basicContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '机器人 IP',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '打开 App 会按这个地址自动连接。改完保存即重新连接。',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(height: 8),
              IpInput(
                initialIp: _ip,
                enabled: true,
                onChanged: (ip) => _ip = ip,
                onSubmitted: _save,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(
              child: Text(
                '开机自动打开 App、自动连接上次机器人、没网读本地任务。采集中不能改 IP。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: AppColors.muted,
                ),
              ),
            ),
            const SizedBox(width: 12),
            AppButton('保存', kind: AppButtonKind.success, onPressed: _save),
          ],
        ),
      ],
    );
  }

  Widget _processContent() {
    return Column(
      children: [
        _ProcessItem(name: '采集服务', pid: '1284'),
        const SizedBox(height: 10),
        _ProcessItem(name: '设备连接服务', pid: '1310'),
        const SizedBox(height: 10),
        _ProcessItem(name: '网络同步服务', pid: '1202'),
      ],
    );
  }

  Widget _logContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '最近日志（按时间倒序）',
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        const SizedBox(height: 8),
        for (final line in const [
          '10:32:01 [INFO] 任务 compact_shoes 已保存到机载工控',
          '10:31:40 [INFO] 开始采集 compact_shoes',
          '10:30:15 [WARN] 右腕相机帧率偏低（28 fps）',
          '10:29:52 [INFO] 双臂已连接',
          '10:28:10 [INFO] 已连接机器人 192.168.1.21',
        ]) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.input,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              line,
              style: const TextStyle(
                fontSize: 12,
                height: 1.5,
                color: AppColors.muted,
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _StepBox extends StatelessWidget {
  const _StepBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}

class _ProcessItem extends StatelessWidget {
  const _ProcessItem({required this.name, required this.pid});

  final String name;
  final String pid;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: const BoxDecoration(
              color: AppColors.ok,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontSize: 15, color: AppColors.ink),
                ),
                Text(
                  '运行中 · PID $pid',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          AppButton(
            '重启',
            kind: AppButtonKind.secondary,
            onPressed: () => showToast(context, '$name 已重启（模拟）'),
          ),
        ],
      ),
    );
  }
}
