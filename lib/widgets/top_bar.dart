import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../connect_state.dart';

/// 顶部状态栏，所有页面共用。
class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    required this.state,
    required this.onSettings,
    required this.onDevices,
    required this.onMove,
    required this.onLogin,
  });

  final ConnectState state;
  final VoidCallback onSettings;
  final VoidCallback? onDevices;
  final VoidCallback? onMove;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.topBar,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 820;

          return Row(
            children: [
              _brand(compact),
              const SizedBox(width: 12),
              Expanded(child: Center(child: _status(compact))),
              if (!compact) ...[
                _barButton('底盘移动', onMove),
                const SizedBox(width: 8),
                _barButton('设备状态', onDevices),
                const SizedBox(width: 8),
                _barButton('设置', onSettings),
              ],
              const SizedBox(width: 12),
              _user(),
            ],
          );
        },
      ),
    );
  }

  Widget _brand(bool compact) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: const Color(0xFF1677FF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Center(
            child: Text(
              'T',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tavi Capture',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (!compact)
              const Text(
                '数据采集',
                style: TextStyle(fontSize: 11, color: AppColors.muted),
              ),
          ],
        ),
      ],
    );
  }

  Widget _status(bool compact) {
    if (state == ConnectState.connected) {
      if (compact) {
        return _chip('已连接', AppColors.ok);
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _chip('底盘就绪', AppColors.ok),
          const SizedBox(width: 6),
          _chip('剩余 805GB', AppColors.ok),
        ],
      );
    }

    if (state == ConnectState.connecting) {
      return _chip('连接中…', AppColors.warn);
    }

    return _chip('未连接机器人', AppColors.bad, danger: true);
  }

  Widget _chip(String text, Color dotColor, {bool danger = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.input,
        border: Border.all(color: danger ? AppColors.badLine : AppColors.line),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: danger ? AppColors.badInk : const Color(0xFFD5E2EF),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _barButton(String label, VoidCallback? onPressed) {
    return SizedBox(
      height: 32,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.line),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 12),
        ),
        child: Text(label),
      ),
    );
  }

  Widget _user() {
    return InkWell(
      onTap: onLogin,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '未登录',
              style: TextStyle(fontSize: 13, color: Color(0xFFD5E2EF)),
            ),
            const SizedBox(width: 8),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.panel,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.line),
              ),
              child: const Center(
                child: Text(
                  '?',
                  style: TextStyle(fontSize: 14, color: AppColors.ink),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
