import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavi_capture/core/playback.dart';
import 'package:tavi_capture/ui/replay_panel.dart';

void main() {
  testWidgets('空状态显示占位和播放条', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: ReplayPanel(player: null, duration: '00:00', valid: true),
          ),
        ),
      ),
    );

    expect(find.text('请先选择左侧一条数据查看'), findsOneWidget);
    expect(find.text('00:00 / 00:00'), findsOneWidget);
    expect(find.text('播放'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('回放失败显示错误和重试', (tester) async {
    final player = PlaybackController(url: 'http://127.0.0.1:1/missing.mcap')
      ..loading = false
      ..error = 'boom';
    addTearDown(player.dispose);
    var retried = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: ReplayPanel(
              player: player,
              duration: '00:00',
              valid: true,
              onRetry: () => retried = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('回放加载失败'), findsOneWidget);
    expect(find.text('boom'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.text('重试'));
    expect(retried, isTrue);
    expect(tester.takeException(), isNull);
  });
}
