import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 三路相机的占位画面，采集页和回放页共用。
class CameraTile extends StatelessWidget {
  const CameraTile({
    super.key,
    required this.label,
    this.dead = false,
    this.image,
  });

  final String label;
  final bool dead;
  final ui.Image? image;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: dead ? const Color(0xFF1A1214) : null,
          gradient: dead
              ? null
              : const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF3B5166), Color(0xFF1A2633)],
                ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (image != null)
              Positioned.fill(
                child: RawImage(
                  image: image,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.low,
                ),
              )
            else if (!dead)
              const Positioned.fill(
                child: CustomPaint(painter: _CameraGridPainter()),
              ),
            if (dead)
              const Center(
                child: Icon(
                  Icons.videocam_off_outlined,
                  color: AppColors.bad,
                  size: 28,
                ),
              ),
            Positioned(
              left: 10,
              bottom: 8,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: dead ? AppColors.bad : const Color(0xFFC5D4E4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraGridPainter extends CustomPainter {
  const _CameraGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;

    for (var x = 0.0; x < size.width; x += 48) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += 36) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_CameraGridPainter oldDelegate) => false;
}
