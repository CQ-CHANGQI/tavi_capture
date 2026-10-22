import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavi_capture/app.dart';
import 'package:tavi_capture/core/app_state.dart';
import 'package:tavi_capture/core/models.dart';

AppState _readyState() => AppState()
  ..booted = true
  ..robotOk = true
  ..connecting = false
  ..screen = ScreenId.home;

Future<void> _pumpApp(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(TaviApp(state: state));
  await tester.pumpAndSettle();
}

Future<void> _openCollect(WidgetTester tester) async {
  await tester.tap(find.text('进入采集'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void _tablet(WidgetTester tester) {
  tester.view.physicalSize = const Size(1180, 738);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test('登录：云端账号与角色', () {
    final state = AppState()..booted = true;
    expect(state.cloudLogin('张三', '1234'), isNull);
    expect(state.currentUser, '张三');
    expect(state.role, Role.engineer);
    expect(state.cloudLogin('李四', 'bad'), '账号或密码不对');
    expect(state.localLogin(Role.operator, 'weiyi2018'), isNull);
    expect(state.localSession, isTrue);
    expect(state.localLogin(Role.engineer, 'nope'), '密码不对');
    state.dispose();
  });

  test('保存采集条：计时、进度、存储', () {
    final state = AppState()..booted = true;
    final task = state.localTasks.firstWhere((t) => t.name == 'compact_shoes');
    state.currentTask = task;
    state.dataFilter = task.name;
    state.elapsedSec = 12;
    state.recording = true;

    final before = task.done;
    final storage = state.storageGb;
    state.saveTake();

    expect(state.takes.first.durationSeconds, 12);
    expect(state.takes.first.person, '张三');
    expect(state.takes.first.valid, isTrue);
    expect(task.done, before + 1);
    expect(state.storageGb, lessThan(storage));
    expect(state.recording, isFalse);
    state.dispose();
  });

  test('台账外的真实机器人 IP 也能看到全部 mock 数据', () {
    final state = AppState()
      ..booted = true
      ..savedIp = '192.168.13.4';
    expect(state.hereTasks.length, state.localTasks.length);
    expect(state.libAll.length, state.takes.length);
    expect(state.canCollect(state.hereTasks.first), isTrue);
    state.dispose();
  });

  test('有效/无效可以来回标记', () {
    final state = AppState()..booted = true;
    final take = state.takes.first;
    final wasValid = take.valid;
    state.toggleValid(take);
    expect(take.valid, !wasValid);
    state.toggleValid(take);
    expect(take.valid, wasValid);
    state.dispose();
  });

  testWidgets('平板：首页 → 采集 → 已采列表 → 回看', (tester) async {
    _tablet(tester);
    final state = _readyState();
    addTearDown(state.dispose);
    await _pumpApp(tester, state);

    expect(find.text('进入采集'), findsOneWidget);
    await _openCollect(tester);
    expect(find.text('开始采集'), findsOneWidget);
    expect(find.text('相机'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('已采 4 条'));
    await tester.pumpAndSettle();
    expect(find.text('继续采集一条'), findsOneWidget);
    expect(find.text('回看'), findsWidgets);

    await tester.tap(find.text('回看').first);
    await tester.pumpAndSettle();
    expect(find.text('返回列表'), findsOneWidget);
    expect(find.text('标记无效'), findsOneWidget);

    await tester.tap(find.text('返回列表'));
    await tester.pumpAndSettle();
    expect(find.text('继续采集一条'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('平板：查看数据（回放失败也能重试）', (tester) async {
    _tablet(tester);
    final state = _readyState();
    addTearDown(state.dispose);
    await _pumpApp(tester, state);

    await tester.tap(find.text('进入查看'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('共 8 条'), findsOneWidget);
    expect(find.text('回放加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置 / 手动控制 / 登录弹层', (tester) async {
    _tablet(tester);
    final state = _readyState();
    addTearDown(state.dispose);
    await _pumpApp(tester, state);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('基本设置'), findsOneWidget);
    await tester.tap(find.text('进程管理'));
    await tester.pumpAndSettle();
    expect(find.text('运行中'), findsWidgets);
    await tester.tap(find.text('日志查看'));
    await tester.pumpAndSettle();
    expect(find.text('系统日志'), findsWidgets);
    await tester.tap(find.text('设备状态'));
    await tester.pumpAndSettle();
    expect(find.text('机器人（工控）'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('手动控制'));
    await tester.pumpAndSettle();
    expect(find.text('一键连接'), findsOneWidget);
    await tester.tap(find.text('一键连接'));
    await tester.pump();
    expect(find.text('底盘和双臂已连接'), findsOneWidget);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('张三'));
    await tester.pumpAndSettle();
    expect(find.text('切换账号'), findsOneWidget);
    await tester.tap(find.text('本地登录'));
    await tester.pumpAndSettle();
    expect(find.text('本地登录密码'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('手机宽度：手动控制不溢出', (tester) async {
    _phone(tester);
    final state = _readyState();
    addTearDown(state.dispose);
    await _pumpApp(tester, state);

    await tester.tap(find.byTooltip('菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('手动控制'));
    await tester.pumpAndSettle();
    expect(find.text('底盘控制'), findsOneWidget);
    await tester.tap(find.text('一键连接'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('手机宽度：采集页和设置弹层不溢出', (tester) async {
    _phone(tester);
    final state = _readyState();
    addTearDown(state.dispose);
    await _pumpApp(tester, state);

    expect(tester.takeException(), isNull);
    await _openCollect(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('开始采集'), findsOneWidget);

    await tester.tap(find.byTooltip('菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('基本设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
