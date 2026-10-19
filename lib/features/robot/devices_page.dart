import 'package:flutter/material.dart';

import '../../app_routes.dart';
import '../../core/models/device_status.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/modal_panel.dart';

/// 设备状态弹窗。
class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  void _restart() {
    setState(() {
      for (final device in appState.devices) {
        device.ok = true;
        if (device.name == 'VR') {
          device.detail = '头显和手柄已连接';
        } else if (device.name == '双臂') {
          device.detail = '已连接，已回初始位置';
        } else if (device.name == '三路相机') {
          device.detail = '主视角、左腕、右腕画面正常';
        }
      }
    });
    showToast(context, '设备服务已重启（模拟）');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ModalPanel(
        title: '设备状态',
        width: 680,
        onClose: () => Navigator.maybePop(context),
        child: Column(
          children: [
            for (final device in appState.devices) ...[
              _DeviceRow(device: device),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 4),
            AppButton('重启服务', onPressed: _restart),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.pushNamed(context, Routes.recovery),
              child: const Text(
                '模拟掉线（原型入口）',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device});

  final DeviceStatus device;

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
            decoration: BoxDecoration(
              color: device.ok ? AppColors.ok : AppColors.bad,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  style: const TextStyle(fontSize: 15, color: AppColors.ink),
                ),
                Text(
                  device.detail,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
