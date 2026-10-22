import 'package:flutter/material.dart';

import '../core/scope.dart';
import '../core/theme.dart';
import '../ui/replay_panel.dart';

/// 回看：整屏回放 + 标记无效 / 返回列表。
class ReviewScreen extends StatelessWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final take = app.currentTake;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: ReplayPanel(
              player: app.playback,
              duration: take?.duration ?? '00:00',
              valid: take?.valid ?? true,
              onRetry: app.retryPlayback,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppButton(
                take?.valid == false ? '标记有效' : '标记无效',
                kind: take?.valid == false ? BtnKind.ok : BtnKind.bad,
                minWidth: 160,
                onPressed: app.discardCurrentTake,
              ),
              const SizedBox(width: 12),
              AppButton(
                '返回列表',
                kind: BtnKind.ghost,
                minWidth: 160,
                onPressed: app.keepLocal,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
