import 'package:flutter/material.dart';

import '../models/connect_state.dart';
import '../theme/app_colors.dart';

class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    required this.state,
    required this.onSettings,
    required this.onDevices,
    required this.onMove,
    required this.onLogin,
    this.userName,
    this.onStatusTap,
    this.showDevices = false,
  });
  final ConnectState state;
  final VoidCallback onSettings, onLogin;
  final VoidCallback? onDevices, onMove, onStatusTap;
  final String? userName;
  final bool showDevices;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 64),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: const BoxDecoration(
      color: AppColors.topBar,
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        final connected = state == ConnectState.connected;
        return Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xff1677ff),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('T'),
            ),
            const SizedBox(width: 8),
            if (!compact)
              const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tavi Capture',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '数据采集',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Center(
                child: InkWell(
                  onTap: onStatusTap,
                  child: Text(
                    connected
                        ? '机器人已连接'
                        : state == ConnectState.connecting
                        ? '连接中…'
                        : '未连接机器人',
                    style: TextStyle(
                      fontSize: 13,
                      color: connected ? AppColors.ok : AppColors.warn,
                    ),
                  ),
                ),
              ),
            ),
            if (!compact) ...[
              OutlinedButton(onPressed: onMove, child: const Text('手动控制')),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: onSettings, child: const Text('设置')),
            ] else
              PopupMenuButton<String>(
                tooltip: '菜单',
                onSelected: (value) {
                  if (value == 'settings') onSettings();
                  if (value == 'move') onMove?.call();
                  if (value == 'login') onLogin();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'settings', child: Text('设置')),
                  PopupMenuItem(
                    value: 'move',
                    enabled: onMove != null,
                    child: const Text('手动控制'),
                  ),
                  PopupMenuItem(
                    value: 'login',
                    child: Text(userName == null ? '登录' : '切换账号'),
                  ),
                ],
              ),
          ],
        );
      },
    ),
  );
}
