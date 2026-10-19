import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_toast.dart';

/// 掉线恢复弹窗。
class RecoveryPage extends StatelessWidget {
  const RecoveryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.panel,
                  border: Border.all(color: AppColors.badLine),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '采集中设备断开',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '先松开急停并确认周围安全。正在采集的这一条不完整，已丢弃，不能续采。恢复后回到初始位置，重新采集。',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        AppButton(
                          '重新连接',
                          onPressed: () {
                            showToast(context, '已重新连接（模拟）');
                            Navigator.maybePop(context);
                          },
                        ),
                        const SizedBox(width: 8),
                        AppButton(
                          '回到任务',
                          kind: AppButtonKind.secondary,
                          onPressed: () => Navigator.maybePop(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
