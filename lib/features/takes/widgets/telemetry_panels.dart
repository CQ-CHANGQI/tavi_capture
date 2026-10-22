import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/telemetry/sample.dart';
import '../../../core/theme/app_colors.dart';

const _colors = [
  Color(0xff3b82c4),
  Color(0xff2f9e62),
  Color(0xffd39a3a),
  Color(0xff7c6adf),
  Color(0xffd4544a),
  Color(0xff4db6c4),
  Color(0xffc47a3b),
];

class TelemetryPanels extends StatelessWidget {
  const TelemetryPanels({super.key, required this.history});
  final List<JointSample> history;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final (prefix, label) in [
        ('left_joint', '左臂'),
        ('right_joint', '右臂'),
        ('body_joint', '身体'),
      ]) ...[
        if (prefix != 'left_joint') const SizedBox(height: 8),
        Expanded(
          child: _JointPanel(prefix: prefix, label: label, history: history),
        ),
      ],
    ],
  );
}

class _JointPanel extends StatefulWidget {
  const _JointPanel({
    required this.prefix,
    required this.label,
    required this.history,
  });
  final String prefix, label;
  final List<JointSample> history;
  @override
  State<_JointPanel> createState() => _JointPanelState();
}

class _JointPanelState extends State<_JointPanel> {
  String _mode = '指令';
  @override
  Widget build(BuildContext context) {
    final names = <String>{};
    for (final sample in widget.history) {
      names.addAll(sample.state.keys.where((n) => n.startsWith(widget.prefix)));
      names.addAll(
        sample.command.keys.where((n) => n.startsWith(widget.prefix)),
      );
    }
    final sorted = names.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            Text(
              '${widget.label} · $_mode',
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final mode in ['指令', '状态', '全部'])
                  Padding(
                    padding: const EdgeInsets.only(left: 3),
                    child: InkWell(
                      onTap: () => setState(() => _mode = mode),
                      borderRadius: BorderRadius.circular(5),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _mode == mode
                              ? AppColors.brand
                              : AppColors.input,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(mode, style: const TextStyle(fontSize: 11)),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 5),
        Expanded(
          child: ColoredBox(
            color: AppColors.input,
            child: sorted.isEmpty
                ? const Center(
                    child: Text(
                      '暂无关节数据',
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  )
                : CustomPaint(
                    painter: _CurvePainter(
                      List.of(widget.history),
                      sorted,
                      _mode,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            for (var i = 0; i < sorted.length; i++)
              Text(
                '━ J${i + 1}',
                style: TextStyle(
                  fontSize: 10,
                  color: _colors[i % _colors.length],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter(this.history, this.names, this.mode);
  final List<JointSample> history;
  final List<String> names;
  final String mode;
  @override
  void paint(Canvas canvas, Size size) {
    if (history.isEmpty) return;
    final sets = [if (mode != '状态') true, if (mode != '指令') false];
    var low = double.infinity, high = -double.infinity;
    for (final sample in history) {
      for (final command in sets) {
        final values = command ? sample.command : sample.state;
        for (final name in names) {
          final value = values[name];
          if (value != null) {
            low = math.min(low, value);
            high = math.max(high, value);
          }
        }
      }
    }
    if (!low.isFinite) return;
    if (high - low < .001) {
      low -= .1;
      high += .1;
    }
    final span = math.max(1, history.last.timeNs - history.first.timeNs);
    for (var i = 0; i < names.length; i++) {
      for (final command in sets) {
        final path = Path();
        var began = false;
        for (final sample in history) {
          final value = (command ? sample.command : sample.state)[names[i]];
          if (value == null) {
            began = false;
            continue;
          }
          final x = (sample.timeNs - history.first.timeNs) / span * size.width;
          final y =
              5 +
              (1 - (value - low) / (high - low)) *
                  math.max(0, size.height - 10);
          if (began) {
            path.lineTo(x, y);
          } else {
            path.moveTo(x, y);
            began = true;
          }
        }
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = command ? 1.7 : 1
            ..color = _colors[i % _colors.length].withValues(
              alpha: command ? 1 : .55,
            ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) => true;
}
