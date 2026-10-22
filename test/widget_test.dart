import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tavi_capture/app.dart';
import 'package:tavi_capture/core/state/app_state.dart';

Future<void> _openLogin(WidgetTester tester) async {
  final pingResult = Completer<String?>();
  await tester.pumpWidget(
    TaviApp(ping: (_) => pingResult.future, enableVideo: false),
  );
  await tester.tap(find.text('重新连接'));
  await tester.pump();
  pingResult.complete(null);
  await tester.pumpAndSettle();
}

Future<void> _loginAsEngineer(WidgetTester tester) async {
  await _openLogin(tester);
  await tester.tap(find.byKey(const Key('loginButton')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    appState.reset();
  });

  testWidgets('ping 通后进入登录页', (WidgetTester tester) async {
    await _openLogin(tester);

    expect(find.byKey(const Key('loginButton')), findsOneWidget);
  });

  testWidgets('登录后进入首页', (WidgetTester tester) async {
    await _loginAsEngineer(tester);

    expect(find.text('进入采集'), findsOneWidget);
    expect(find.text('查看数据'), findsOneWidget);
    expect(appState.role, '工程师');
  });

  testWidgets('主链路页面都能打开', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1180, 738);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _loginAsEngineer(tester);

    await tester.tap(find.text('进入采集'));
    await tester.pumpAndSettle();
    expect(find.text('开始采集'), findsOneWidget);
    expect(find.text('采集数据'), findsOneWidget);
    expect(find.textContaining('全景'), findsOneWidget);
    await tester.tap(find.text('采集说明'));
    await tester.pumpAndSettle();
    expect(find.textContaining('compact_shoes · 采集说明'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('返回选择模式'));
    await tester.pumpAndSettle();
    expect(find.text('进入采集'), findsOneWidget);
  });

  testWidgets('顶栏的页面都能打开', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _loginAsEngineer(tester);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('基本设置'), findsOneWidget);
    await tester.tap(find.text('设备状态'));
    await tester.pumpAndSettle();
    expect(find.textContaining('主视角相机'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('手动控制'));
    await tester.pumpAndSettle();
    expect(find.text('一键连接'), findsOneWidget);
    expect(find.text('回 home 点'), findsOneWidget);
  });

  testWidgets('采集员登录后直接进采集', (WidgetTester tester) async {
    await _openLogin(tester);

    await tester.enterText(find.byKey(const Key('loginUser')), '李四');
    await tester.tap(find.byKey(const Key('loginButton')));
    await tester.pumpAndSettle();

    expect(find.text('开始采集'), findsOneWidget);
    expect(find.text('切换模式'), findsNothing);
    expect(appState.role, '采集员');
  });

  testWidgets('工程师可以查看本机全部数据', (WidgetTester tester) async {
    await _loginAsEngineer(tester);

    await tester.tap(find.text('进入查看'));
    await tester.pumpAndSettle();

    expect(find.text('查看数据'), findsOneWidget);
    expect(find.text('全部人员'), findsOneWidget);
    expect(find.text('上一条'), findsOneWidget);
    expect(find.text('下一条'), findsOneWidget);
  });

  testWidgets('手机宽度能使用采集页和设置菜单', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _loginAsEngineer(tester);
    await tester.tap(find.text('进入采集'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('基本设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ping 不通时显示失败原因', (WidgetTester tester) async {
    await tester.pumpWidget(
      TaviApp(ping: (ip) async => 'ping 不通 $ip', enableVideo: false),
    );

    await tester.tap(find.text('重新连接'));
    await tester.pumpAndSettle();

    expect(find.text('无法连接机器人'), findsOneWidget);
    expect(find.textContaining('ping 不通 192.168.13.4'), findsOneWidget);
  });

  testWidgets('IP 每段必须在 0-255', (WidgetTester tester) async {
    await tester.pumpWidget(
      TaviApp(ping: (_) async => null, enableVideo: false),
    );
    expect(find.byType(TextField), findsNWidgets(4));

    await tester.enterText(find.byType(TextField).last, '300');
    await tester.tap(find.text('重新连接'));
    await tester.pump();

    expect(find.textContaining('IP 地址格式不正确'), findsOneWidget);
    expect(find.text('重新连接'), findsOneWidget);
  });
}
