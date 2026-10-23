import 'package:flutter/material.dart';

import '../core/playback.dart';
import '../core/theme.dart';
import 'camera.dart';
import 'joints.dart';
import 'playbar.dart';

/// 回放面板：标题 + 四路画面 + 三组关节 + 播放条。查看数据页使用。
class ReplayPanel extends StatelessWidget {
  const ReplayPanel({
    super.key,
    required this.player,
    required this.duration,
    required this.valid,
    this.actions = const [],
    this.onRetry,
    this.padding = 10,
    this.maximized = false,
  });

  final PlaybackController? player;
  final String duration;
  final bool valid;
  final List<Widget> actions;
  final VoidCallback? onRetry;
  final double padding;
  final bool maximized;

  @override
  Widget build(BuildContext context) {
    final current = player;
    if (current == null) return _build(null);
    return ListenableBuilder(
      listenable: current,
      builder: (context, _) => _build(current),
    );
  }

  Widget _build(PlaybackController? current) {
    return Panel(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final title = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      '回放 · $duration',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Pill(
                    valid ? '有效' : '无效',
                    kind: valid ? PillKind.run : PillKind.fix,
                  ),
                ],
              );
              if (constraints.maxWidth < 620) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    if (actions.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(spacing: 8, runSpacing: 6, children: actions),
                    ],
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: title),
                  if (actions.isNotEmpty)
                    Wrap(spacing: 8, runSpacing: 6, children: actions),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Expanded(child: _body(current)),
          if (current == null) ...[
            const SizedBox(height: 8),
            const EmptyPlayBar(),
          ] else if (!current.loading && current.error == null) ...[
            const SizedBox(height: 8),
            PlayBar(player: current),
          ],
        ],
      ),
    );
  }

  Widget _body(PlaybackController? player) {
    if (player == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🎬', style: TextStyle(fontSize: 42)),
            SizedBox(height: 12),
            Text(
              '请先选择左侧一条数据查看',
              style: TextStyle(fontSize: 14, color: C.muted),
            ),
          ],
        ),
      );
    }
    if (player.loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(height: 12),
            Text('正在读取 MCAP …', style: TextStyle(fontSize: 14, color: C.muted)),
          ],
        ),
      );
    }
    if (player.error != null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '回放加载失败',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                player.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: C.muted),
              ),
              const SizedBox(height: 10),
              AppButton(
                '重试',
                kind: BtnKind.ghost,
                height: 36,
                onPressed: onRetry,
              ),
            ],
          ),
        ),
      );
    }
    if (maximized) {
      return SingleChildScrollView(
        child: Column(
          children: [
            SizedBox(
              height: 340,
              child: CameraGrid(images: player.cameras, player: player),
            ),
            const SizedBox(height: 10),
            SizedBox(height: 700, child: JointColumn(player: player)),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return SingleChildScrollView(
            child: Column(
              children: [
                SizedBox(
                  height: 250,
                  child: CameraGrid(images: player.cameras, player: player),
                ),
                const SizedBox(height: 8),
                SizedBox(height: 420, child: JointColumn(player: player)),
              ],
            ),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 135,
              child: CameraGrid(images: player.cameras, player: player),
            ),
            const SizedBox(width: 8),
            Expanded(flex: 65, child: JointColumn(player: player)),
          ],
        );
      },
    );
  }
}
