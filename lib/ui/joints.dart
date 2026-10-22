import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/playback.dart';
import '../core/scope.dart';
import '../core/theme.dart';

/// 关节曲线面板：标题 + 指令/状态/全部 + 图 + 图例。
class JointPanel extends StatelessWidget {
  const JointPanel({
    super.key,
    required this.title,
    required this.curves,
    required this.mode,
    required this.onMode,
    this.progress,
  });

  final String title;
  final List<JointCurve> curves;
  final JointMode mode;
  final ValueChanged<JointMode> onMode;
  final double? progress;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              '$title · ${mode.label}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                color: C.legendInk,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _ModeTabs(mode: mode, onMode: onMode),
        ],
      ),
      const SizedBox(height: 4),
      Expanded(
        child: Container(
          decoration: BoxDecoration(
            color: C.input,
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: CustomPaint(
            painter: _ChartPainter(curves: curves, progress: progress),
            size: Size.infinite,
          ),
        ),
      ),
      const SizedBox(height: 4),
      Wrap(
        spacing: 10,
        runSpacing: 4,
        children: [
          for (final curve in curves)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 3,
                  decoration: BoxDecoration(
                    color: Color(curve.color),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  curve.name,
                  style: const TextStyle(fontSize: 12, color: C.muted),
                ),
              ],
            ),
        ],
      ),
    ],
  );
}

class _ModeTabs extends StatelessWidget {
  const _ModeTabs({required this.mode, required this.onMode});

  final JointMode mode;
  final ValueChanged<JointMode> onMode;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final item in JointMode.values) ...[
        if (item != JointMode.values.first) const SizedBox(width: 4),
        InkWell(
          onTap: () => onMode(item),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: item == mode ? C.brand : Colors.transparent,
              border: Border.all(color: item == mode ? C.brand : C.line),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              item.label,
              style: TextStyle(
                fontSize: 13,
                color: item == mode ? Colors.white : C.muted,
                fontWeight: item == mode ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ],
    ],
  );
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({required this.curves, required this.progress});

  final List<JointCurve> curves;
  final double? progress;

  static const _pad = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final dash = Paint()
      ..color = const Color(0xff24364a)
      ..strokeWidth = 1;
    for (var x = _pad; x < size.width - _pad; x += 8) {
      canvas.drawLine(Offset(x, centerY), Offset(x + 4, centerY), dash);
    }

    var minValue = double.infinity;
    var maxValue = -double.infinity;
    for (final curve in curves) {
      for (final v in curve.values) {
        if (!v.isFinite) continue;
        if (v < minValue) minValue = v;
        if (v > maxValue) maxValue = v;
      }
    }
    if (!minValue.isFinite) return;
    if (maxValue - minValue < 0.05) {
      final center = (maxValue + minValue) / 2;
      minValue = center - 0.025;
      maxValue = center + 0.025;
    }
    final span = maxValue - minValue;
    final height = size.height - _pad * 2;
    final width = size.width - _pad * 2;

    for (final curve in curves) {
      final values = curve.values;
      if (values.isEmpty) continue;
      final path = Path();
      for (var i = 0; i < values.length; i++) {
        final value = values[i].isFinite ? values[i] : minValue;
        final x = values.length == 1
            ? _pad + width
            : _pad + width * i / (values.length - 1);
        final y = _pad + height * (1 - (value - minValue) / span);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = Color(curve.color)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeJoin = StrokeJoin.round,
      );
    }

    final ratio = progress;
    if (ratio != null) {
      final x = _pad + width * ratio.clamp(0, 1);
      canvas.drawLine(
        Offset(x, 4),
        Offset(x, size.height - 4),
        Paint()
          ..color = C.ink
          ..strokeWidth = 1.4,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) =>
      oldDelegate.curves != curves || oldDelegate.progress != progress;
}

/// 把一组轨道转成图上的曲线（只取最近 [limit] 个点）。
List<JointCurve> visibleCurves(
  JointTrack? track,
  JointMode mode, {
  int limit = 240,
}) {
  if (track == null) return const [];
  return [
    for (final curve in track.curves(mode))
      JointCurve(
        curve.name,
        curve.values.length > limit
            ? curve.values.sublist(curve.values.length - limit)
            : curve.values,
        curve.color,
      ),
  ];
}

/// 回放右侧：左臂 / 右臂 / 身体 三块关节图，共用 AppState 里的模式。
class JointColumn extends StatelessWidget {
  const JointColumn({super.key, required this.player, this.gap = 10});

  final PlaybackController player;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Column(
      children: [
        for (final group in JointGroup.values) ...[
          if (group != JointGroup.values.first) SizedBox(height: gap),
          Expanded(
            child: Panel(
              child: JointPanel(
                title: group.label,
                mode: app.jointModes[group]!,
                onMode: (mode) => app.setJointMode(group, mode),
                curves: visibleCurves(
                  player.tracks[group],
                  app.jointModes[group]!,
                ),
                progress: player.progress,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
