import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

const _jointColors = [
  Color(0xFF3B82C4),
  Color(0xFF2F9E62),
  Color(0xFFD39A3A),
  Color(0xFF7C6ADF),
  Color(0xFFD4544A),
  Color(0xFF4DB6C4),
  Color(0xFFC47A3B),
];

/// 回放页的关节角曲线。传入 [series] 时画真实数据，否则用占位曲线。
class JointChart extends StatelessWidget {
  const JointChart({super.key, this.series, this.progress = 0});

  /// 每根关节一条曲线，横轴按采样点均匀铺开。
  final List<List<double>>? series;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        color: AppColors.input,
        child: CustomPaint(
          painter: _JointPainter(series: series, progress: progress),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// J1–J7 图例。
class JointLegend extends StatelessWidget {
  const JointLegend({super.key, this.count = 7});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        for (var i = 0; i < count; i++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 3,
                decoration: BoxDecoration(
                  color: _jointColors[i % _jointColors.length],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'J${i + 1}',
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ],
          ),
      ],
    );
  }
}

class _JointPainter extends CustomPainter {
  const _JointPainter({this.series, this.progress = 0});

  final List<List<double>>? series;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final lines = series;
    if (lines == null || lines.isEmpty) {
      _paintPlaceholder(canvas, size);
      return;
    }

    var min = double.infinity;
    var max = -double.infinity;
    for (final line in lines) {
      for (final value in line) {
        if (value < min) min = value;
        if (value > max) max = value;
      }
    }
    if (!min.isFinite || !max.isFinite) return;
    if (max - min < 0.000001) {
      min -= 1;
      max += 1;
    }
    final range = max - min;

    for (var j = 0; j < lines.length; j++) {
      final values = lines[j];
      if (values.isEmpty) continue;
      final paint = Paint()
        ..color = _jointColors[j % _jointColors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6;
      final path = Path();
      for (var i = 0; i < values.length; i++) {
        final x = values.length == 1
            ? 0.0
            : i / (values.length - 1) * size.width;
        final y = size.height - (values[i] - min) / range * size.height;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }

    final x = progress.clamp(0.0, 1.0) * size.width;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..strokeWidth = 1,
    );
  }

  void _paintPlaceholder(Canvas canvas, Size size) {
    for (var line = 0; line < _jointColors.length; line++) {
      final paint = Paint()
        ..color = _jointColors[line]
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6;

      final path = Path();
      for (var i = 0; i <= 48; i++) {
        final x = i / 48 * size.width;
        final y =
            size.height / 2 +
            sin(i / 48 * pi * 4 + line * 0.9) * size.height * 0.25;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_JointPainter oldDelegate) {
    return oldDelegate.series != series || oldDelegate.progress != progress;
  }
}
