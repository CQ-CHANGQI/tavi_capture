import 'package:flutter/material.dart';

import '../../core/models/task.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/modal_panel.dart';

/// 更换任务弹窗：骨架阶段只展示“其他机器人上的同型号任务”。
class SwapPage extends StatelessWidget {
  const SwapPage({super.key});

  static const _otherTasks = [
    Task(
      name: '箱内码放',
      done: 0,
      total: 30,
      size: '0 GB',
      robot: '2号工位',
      model: 'Tavi-W2',
      brief: ['把取出的鞋盒码放到箱内指定格。'],
    ),
    Task(
      name: '货架取放',
      done: 5,
      total: 40,
      size: '1.6 GB',
      robot: '3号工位',
      model: 'Tavi-W1',
      brief: ['从货架指定层取出料盒，放到台面。'],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ModalPanel(
        title: '更换任务',
        width: 560,
        onClose: () => Navigator.maybePop(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '有网时把其他机上的任务接到当前这台。没网请先读取已下载的本地任务。',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 12),
            for (final task in _otherTasks) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.line),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.name,
                            style: const TextStyle(
                              fontSize: 15,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${task.robot} · ${task.model} · ${task.done} / ${task.total} · ${task.size}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AppButton(
                      '接到本机',
                      onPressed: () =>
                          showToast(context, '「${task.name}」已接到本机（模拟）'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}
