import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tavi_capture/main.dart';

void main() {
  testWidgets('ping 通后进入已连接', (WidgetTester tester) async {
    final pingResult = Completer<String?>();
    await tester.pumpWidget(TaviApp(ping: (_) => pingResult.future));

    expect(find.text('无法连接机器人'), findsOneWidget);
    expect(find.text('重新连接'), findsOneWidget);

    await tester.tap(find.text('重新连接'));
    await tester.pump();
    expect(find.textContaining('正在连接 192.168.1.21'), findsOneWidget);

    pingResult.complete(null);
    await tester.pump();
    expect(find.text('机器人已连接'), findsOneWidget);
    expect(find.text('保存并连接'), findsOneWidget);
  });

  testWidgets('ping 不通时显示失败原因', (WidgetTester tester) async {
    await tester.pumpWidget(TaviApp(ping: (ip) async => 'ping 不通 $ip'));

    await tester.tap(find.text('重新连接'));
    await tester.pump();

    expect(find.text('无法连接机器人'), findsOneWidget);
    expect(find.textContaining('ping 不通 192.168.1.21'), findsOneWidget);
  });

  testWidgets('IP 每段必须在 0-255', (WidgetTester tester) async {
    await tester.pumpWidget(TaviApp(ping: (_) async => null));
    expect(find.byType(TextField), findsNWidgets(4));

    await tester.enterText(find.byType(TextField).last, '300');
    await tester.tap(find.text('重新连接'));
    await tester.pump();

    expect(find.textContaining('IP 地址格式不正确'), findsOneWidget);
    expect(find.text('重新连接'), findsOneWidget);
  });
}
