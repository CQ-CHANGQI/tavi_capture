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
    expect(find.text('数据采集 · 我的任务'), findsOneWidget);

    await tester.tap(find.text('更换任务'));
    await tester.pumpAndSettle();
    expect(find.text('接到本机'), findsWidgets);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('进入任务').first);
    await tester.pumpAndSettle();
    expect(find.text('开始采集'), findsOneWidget);

    await tester.ensureVisible(find.text('采集说明'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('采集说明'));
    await tester.pumpAndSettle();
    expect(find.textContaining('采集说明'), findsWidgets);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('查看已采集'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看已采集'));
    await tester.pumpAndSettle();
    expect(find.text('继续采集一条'), findsOneWidget);

    await tester.tap(find.text('回看').first);
    await tester.pumpAndSettle();
    expect(find.text('左臂关节角'), findsOneWidget);

    await tester.tap(find.text('返回列表'));
    await tester.pumpAndSettle();
    expect(find.text('继续采集一条'), findsOneWidget);
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
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('设备状态'));
    await tester.pumpAndSettle();
    expect(find.text('VR'), findsOneWidget);

    await tester.tap(find.text('模拟掉线（原型入口）'));
    await tester.pumpAndSettle();
    expect(find.text('采集中设备断开'), findsOneWidget);
    await tester.tap(find.text('回到任务'));
    await tester.pumpAndSettle();
    expect(find.text('VR'), findsOneWidget);

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('底盘移动'));
    await tester.pumpAndSettle();
    expect(find.text('底盘停止'), findsOneWidget);
  });

  testWidgets('采集员登录后直接进任务', (WidgetTester tester) async {
    await _openLogin(tester);

    await tester.enterText(find.byKey(const Key('loginUser')), '李四');
    await tester.tap(find.byKey(const Key('loginButton')));
    await tester.pumpAndSettle();

    expect(find.text('数据采集 · 我的任务'), findsOneWidget);
    expect(find.text('切换模式'), findsNothing);
    expect(appState.role, '采集员');
  });

  testWidgets('工程师可以查看本机全部数据', (WidgetTester tester) async {
    await _loginAsEngineer(tester);

    await tester.tap(find.text('进入查看'));
    await tester.pumpAndSettle();

    expect(find.text('查看数据 · 本机数据'), findsOneWidget);
    expect(find.textContaining('含所有人员'), findsOneWidget);

    await tester.ensureVisible(find.text('回看').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('回看').first);
    await tester.pumpAndSettle();
    expect(find.text('左臂关节角'), findsOneWidget);
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
