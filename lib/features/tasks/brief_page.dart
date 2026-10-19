import 'package:flutter/material.dart';

import '../../core/models/task.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/modal_panel.dart';

/// 采集说明弹窗。
class BriefPage extends StatelessWidget {
  const BriefPage({super.key, required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ModalPanel(
        title: '${task.name} · 采集说明',
        width: 720,
        onClose: () => Navigator.maybePop(context),
        child: Column(
          children: [
            for (final line in task.brief) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: AppColors.input,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  line,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }
}
