import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/theme.dart';

/// 四路相机：主视角占满第一行，下面左腕/右腕/全景。
class CameraGrid extends StatelessWidget {
  const CameraGrid({
    super.key,
    required this.images,
    this.fps,
    this.dead = const {},
    this.gap = 8,
  });

  /// CameraId.channel → 已解码画面。
  final Map<String, ui.Image> images;
  final double Function(String camera)? fps;

  /// 明确显示“无画面”的相机（红字 + 红色条纹）。
  final Set<String> dead;
  final double gap;

  @override
  Widget build(BuildContext context) {
    Widget tile(CameraId camera) => CameraTile(
      camera: camera,
      image: images[camera.channel],
      fps: fps?.call(camera.channel),
      dead: dead.contains(camera.channel),
    );
    return Column(
      children: [
        Expanded(flex: 145, child: tile(CameraId.head)),
        SizedBox(height: gap),
        Expanded(
          flex: 85,
          child: Row(
            children: [
              Expanded(child: tile(CameraId.left)),
              SizedBox(width: gap),
              Expanded(child: tile(CameraId.right)),
              SizedBox(width: gap),
              Expanded(child: tile(CameraId.chest)),
            ],
          ),
        ),
      ],
    );
  }
}

class CameraTile extends StatelessWidget {
  const CameraTile({
    super.key,
    required this.camera,
    required this.image,
    this.fps,
    this.dead = false,
  });

  final CameraId camera;
  final ui.Image? image;
  final double? fps;
  final bool dead;

  @override
  Widget build(BuildContext context) {
    final label = dead
        ? '${camera.label} · 无画面'
        : fps == null || fps! <= 0
        ? camera.label
        : '${camera.label} · ${fps!.toStringAsFixed(0)} fps';
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ColoredBox(
        color: const Color(0xff101820),
        child: GestureDetector(
          onDoubleTap: image == null ? null : () => _fullscreen(context),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (image != null)
                RawImage(image: image, fit: BoxFit.contain)
              else
                const _CameraPlaceholder(),
              if (dead) const _DeadOverlay(),
              Positioned(
                left: 10,
                bottom: 8,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: dead ? C.bad : const Color(0xffc5d4e4),
                  ),
                ),
              ),
              if (image != null)
                Positioned(
                  right: 2,
                  top: 2,
                  child: IconButton(
                    tooltip: '全屏',
                    icon: const Icon(Icons.fullscreen, size: 20),
                    color: Colors.white70,
                    onPressed: () => _fullscreen(context),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _fullscreen(BuildContext context) async {
    final source = image;
    if (source == null) return;
    final clone = source.clone();
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: RawImage(image: clone, fit: BoxFit.contain),
            ),
            Positioned(
              right: 16,
              top: 16,
              child: SafeArea(
                child: AppButton(
                  '⛶ 退出全屏',
                  kind: BtnKind.ghost,
                  height: 40,
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    clone.dispose();
  }
}

class _DeadOverlay extends StatelessWidget {
  const _DeadOverlay();

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _StripePainter());
}

class _StripePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xff1a1214),
    );
    final paint = Paint()
      ..color = const Color(0xff241618)
      ..strokeWidth = 10;
    for (var x = -size.height; x < size.width; x += 20) {
      canvas.drawLine(
        Offset(x.toDouble(), size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 没画面时的占位：深色渐变 + 网格，和原型 `.cam .view` 一致。
class _CameraPlaceholder extends StatelessWidget {
  const _CameraPlaceholder();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: RadialGradient(
        center: Alignment(0, -0.24),
        radius: 1.1,
        colors: [Color(0xff3b5166), Color(0xff1a2633)],
      ),
    ),
    child: CustomPaint(painter: _GridPainter()),
  );
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 48) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += 36) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
