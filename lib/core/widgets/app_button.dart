import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum AppButtonKind { primary, secondary, danger, dangerOutline, success }

/// 统一按钮样式。
class AppButton extends StatelessWidget {
  const AppButton(
    this.label, {
    super.key,
    this.onPressed,
    this.kind = AppButtonKind.primary,
    this.height = 40,
    this.fontSize = 14,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonKind kind;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final child = Text(label, style: TextStyle(fontSize: fontSize));

    switch (kind) {
      case AppButtonKind.primary:
        return _filled(
          background: AppColors.brand,
          disabledBackground: const Color(0x663B82C4),
          child: child,
        );
      case AppButtonKind.success:
        return _filled(background: AppColors.ok, child: child);
      case AppButtonKind.danger:
        return _filled(background: AppColors.bad, child: child);
      case AppButtonKind.secondary:
        return SizedBox(
          height: height,
          child: OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.ink,
              side: const BorderSide(color: AppColors.line),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: child,
          ),
        );
      case AppButtonKind.dangerOutline:
        return SizedBox(
          height: height,
          child: OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.bad,
              side: const BorderSide(color: AppColors.bad),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: child,
          ),
        );
    }
  }

  Widget _filled({
    required Color background,
    Color? disabledBackground,
    required Widget child,
  }) {
    return SizedBox(
      height: height,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: background,
          disabledBackgroundColor: disabledBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: child,
      ),
    );
  }
}
