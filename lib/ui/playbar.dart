import 'package:flutter/material.dart';

import '../core/playback.dart';
import '../core/theme.dart';

/// 回放控制条：±5 秒、逐帧、播放/暂停、进度、倍速、循环。
class PlayBar extends StatefulWidget {
  const PlayBar({super.key, required this.player});

  final PlaybackController player;

  @override
  State<PlayBar> createState() => _PlayBarState();
}

class _PlayBarState extends State<PlayBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final disabled = player.loading || player.error != null;
    final track = _Track(
      value: _drag ?? player.progress,
      onStart: disabled ? null : (ratio) => setState(() => _drag = ratio),
      onUpdate: disabled ? null : (ratio) => setState(() => _drag = ratio),
      onEnd: disabled
          ? null
          : () {
              final ratio = _drag;
              setState(() => _drag = null);
              if (ratio != null) player.seekProgress(ratio);
            },
    );
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _icon(
          Icons.replay_5,
          '后退 5 秒',
          disabled ? null : () => player.skip(const Duration(seconds: -5)),
        ),
        _icon(
          Icons.skip_previous,
          '逐帧后退',
          disabled ? null : () => player.stepFrame(-1),
        ),
        AppButton(
          player.playing ? '暂停' : '播放',
          kind: BtnKind.primary,
          height: 40,
          minWidth: 72,
          onPressed: disabled ? null : player.toggle,
        ),
        _icon(
          Icons.skip_next,
          '逐帧前进',
          disabled ? null : () => player.stepFrame(1),
        ),
        _icon(
          Icons.forward_5,
          '前进 5 秒',
          disabled ? null : () => player.skip(const Duration(seconds: 5)),
        ),
      ],
    );
    final trailer = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${_clock(player.position)} / ${_clock(player.duration)}',
          style: const TextStyle(
            fontSize: 16,
            color: C.ink,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 8),
        AppButton(
          '${_rateLabel(player.speed)}x',
          kind: BtnKind.ghost,
          height: 36,
          minWidth: 52,
          fontSize: 15,
          onPressed: disabled ? null : _cycleRate,
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: '循环播放',
          onPressed: disabled ? null : player.toggleLoop,
          color: player.loop ? C.brand : C.muted,
          icon: Icon(player.loop ? Icons.repeat_one : Icons.repeat),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: C.panel,
        border: Border.all(color: C.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 760) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                track,
                const SizedBox(height: 2),
                FittedBox(fit: BoxFit.scaleDown, child: controls),
                const SizedBox(height: 2),
                FittedBox(fit: BoxFit.scaleDown, child: trailer),
              ],
            );
          }
          return Row(
            children: [
              controls,
              const SizedBox(width: 12),
              Expanded(child: track),
              const SizedBox(width: 12),
              trailer,
            ],
          );
        },
      ),
    );
  }

  void _cycleRate() {
    const rates = [1.0, 2.0, 4.0, 0.5];
    final index = rates.indexOf(widget.player.speed);
    widget.player.setSpeed(rates[(index + 1) % rates.length]);
  }

  static String _rateLabel(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';

  static String _clock(Duration duration) {
    final seconds = duration.inSeconds.clamp(0, 359999);
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _icon(IconData icon, String tooltip, VoidCallback? onPressed) =>
      IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        color: C.ink,
        iconSize: 22,
        icon: Icon(icon),
      );
}

class _Track extends StatelessWidget {
  const _Track({
    required this.value,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  final double value;
  final ValueChanged<double>? onStart;
  final ValueChanged<double>? onUpdate;
  final VoidCallback? onEnd;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      double ratio(Offset position) =>
          width <= 0 ? 0 : (position.dx / width).clamp(0.0, 1.0);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: onEnd == null
            ? null
            : (details) {
                onStart?.call(ratio(details.localPosition));
                onEnd!();
              },
        onHorizontalDragStart: onStart == null
            ? null
            : (details) => onStart!(ratio(details.localPosition)),
        onHorizontalDragUpdate: onUpdate == null
            ? null
            : (details) => onUpdate!(ratio(details.localPosition)),
        onHorizontalDragEnd: onEnd == null ? null : (_) => onEnd!(),
        child: SizedBox(
          height: 24,
          child: Center(
            child: Container(
              height: 10,
              decoration: BoxDecoration(
                color: C.muted,
                borderRadius: BorderRadius.circular(99),
              ),
              clipBehavior: Clip.antiAlias,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value.clamp(0, 1),
                child: Container(color: C.ok),
              ),
            ),
          ),
        ),
      );
    },
  );
}
