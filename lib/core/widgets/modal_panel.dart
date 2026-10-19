import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'app_button.dart';

/// 原型里的弹窗面板：居中、深色、左上标题、右上关闭。
class ModalPanel extends StatelessWidget {
  const ModalPanel({
    super.key,
    required this.title,
    required this.onClose,
    required this.child,
    this.width = 560,
    this.borderColor = AppColors.line,
  });

  final String title;
  final VoidCallback onClose;
  final Widget child;
  final double width;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: width,
                maxHeight: maxHeight,
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.panel,
                  border: Border.all(color: borderColor),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          AppButton(
                            '关闭',
                            kind: AppButtonKind.secondary,
                            onPressed: onClose,
                            height: 32,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      child,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
