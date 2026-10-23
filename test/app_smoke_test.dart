import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavi_capture/app.dart';
import 'package:tavi_capture/core/app_state.dart';
import 'package:tavi_capture/core/models.dart';

AppState _readyState() => AppState()
  ..booted = true
  ..robotOk = true
  ..connecting = false;

Future<void> _pumpApp(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(TaviApp(state: state));
  await tester.pumpAndSettle();
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

Future<void> _enterCollect(WidgetTester tester) async {
  await tester.tap(find.text('数据采集').first);
  await tester.pumpAndSettle();
}

Future<void> _selectTaskAndPerson(WidgetTester tester, AppState state) async {
  state.setCollectTask('compact_shoes');
  state.setCollectPerson('张三');
  await tester.pumpAndSettle();
}

void main() {
  test('模式和采集条状态', () {
    final state = _readyState();
    addTearDown(state.dispose);

    expect(state.mode, PageMode.review);
    expect(state.armOk, isTrue);
    expect(state.armServiceOk, isFalse);

    expect(state.enterMode(PageMode.collect), isTrue);
    expect(state.armServiceOk, isTrue);
    expect(state.collectTask, isEmpty);
    expect(state.collectPerson, isEmpty);

    state.setCollectTask('compact_shoes');
    state.setCollectPerson('张三');
    state.startCollect();
    state.elapsedSec = 12;
    state.stopCollect();

    expect(state.recording, isFalse);
    expect(state.takes.first.task, 'compact_shoes');
    expect(state.takes.first.person, '张三');
    expect(state.takes.first.valid, isTrue);
    expect(state.collectDone, 5);
    expect(state.lastTakeState, '已保存');

    expect(state.enterMode(PageMode.review), isTrue);
    expect(state.armServiceOk, isFalse);
    expect(state.libSelected, isNull);
    expect(AppState.libPageSize, 10);
    expect(state.libRows.length, 7);
  });

  test('作废生成无效采集条', () async {
    final state = _readyState();
    addTearDown(state.dispose);
    state.enterMode(PageMode.collect);
    state.setCollectTask('compact_shoes');
    state.setCollectPerson('张三');
    state.startCollect();
    state.elapsedSec = 8;

    final pending = state.dropTake();
    state.resolveDrop(true);
    await pending;

    expect(state.recording, isFalse);
    expect(state.takes.first.valid, isFalse);
    expect(state.takes.first.durationSeconds, 8);
    expect(state.lastTakeState, '已作废');
    expect(state.collectDone, 5);
  });

  test('筛选清空选中，详情字段完整', () {
    final state = _readyState();
    addTearDown(state.dispose);
    state.enterMode(PageMode.review);
    final take = state.takes.first;
    state.libSelected = take;

    state.setLibTask('compact_shoes');
    expect(state.libSelected, isNull);
    expect(state.libPerson, isEmpty);
    expect(take.fileName, endsWith('.mcap'));
    expect(take.storagePath, startsWith('/data/episodes/'));

    state.toggleValid(take);
    expect(take.valid, isFalse);
  });

  test('设置 IP 只改配置，不改变当前连接', () {
    final state = _readyState();
    addTearDown(state.dispose);
    final connected = state.savedIp;
    expect(state.saveIp('192.168.13.9'), isTrue);
    expect(state.configuredIp, '192.168.13.9');
    expect(state.savedIp, connected);
    expect(state.saveIp('999.1.1.1'), isFalse);
  });

  testWidgets('未连接：停在连接页，模式按钮只提示', (tester) async {
    _tablet(tester);
    final state = AppState()..booted = true;
    addTearDown(state.dispose);
    await _pumpApp(tester, state);

    expect(find.text('连接机器人'), findsOneWidget);
    expect(find.text('保存并连接'), findsOneWidget);
    expect(find.text('查看数据'), findsWidgets);

    await tester.tap(find.text('数据采集'));
    await tester.pump();
    expect(find.text('请先连接机器人'), findsOneWidget);
    expect(find.text('保存并连接'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('查看数据：默认不选中，详情和标记可用', (tester) async {
    _tablet(tester);
    final state = _readyState();
    addTearDown(state.dispose);
    await _pumpApp(tester, state);

    expect(find.text('查看数据'), findsWidgets);
    expect(find.text('全部任务'), findsOneWidget);
    expect(find.text('全部人员'), findsOneWidget);
    expect(find.text('共 6 条'), findsOneWidget);
    expect(find.text('请先选择左侧一条数据查看'), findsOneWidget);
    expect(find.text('第 1 / 1 页'), findsOneWidget);

    await tester.tap(find.text('compact_shoes').first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('详情'), findsOneWidget);

    await tester.tap(find.text('详情'));
    await tester.pumpAndSettle();
    expect(find.text('文件名称'), findsOneWidget);
    expect(find.text('机器人'), findsOneWidget);
    expect(find.text('存储地址'), findsOneWidget);

    await tester.tap(find.text('关闭详情'));
    await tester.pumpAndSettle();
    expect(find.text('详情'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('采集：默认全部任务，选任务/人员后开始并保存', (tester) async {
    _tablet(tester);
    final state = _readyState();
    addTearDown(state.dispose);
    await _pumpApp(tester, state);
    await _enterCollect(tester);

    expect(find.text('全部任务'), findsOneWidget);
    expect(find.text('请选择人员'), findsOneWidget);
    expect(find.text('开始采集'), findsOneWidget);
    expect(find.text('0 / 0'), findsOneWidget);

    await _selectTaskAndPerson(tester, state);
    expect(find.text('4 / 100'), findsOneWidget);

    await tester.tap(find.text('开始采集'));
    await tester.pump();
    expect(find.text('停止并保存'), findsOneWidget);

    await tester.tap(find.text('停止并保存'));
    await tester.pumpAndSettle();
    expect(find.text('5 / 100'), findsOneWidget);
    expect(find.text('已保存'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('采集中模式按钮切换被拦下，设置 IP 只读', (tester) async {
    _tablet(tester);
    final state = _readyState();
    addTearDown(state.dispose);
    await _pumpApp(tester, state);
    await _enterCollect(tester);
    await _selectTaskAndPerson(tester, state);

    await tester.tap(find.text('开始采集'));
    await tester.pump();

    await tester.tap(find.text('查看数据'));
    await tester.pump();
    expect(find.text('请先结束采集'), findsOneWidget);
    expect(find.text('停止并保存'), findsOneWidget);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('采集中不能修改 IP。'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('停止并保存'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('手动模式：无一键连接，回 home 弹确认', (tester) async {
    _tablet(tester);
    final state = _readyState();
    addTearDown(state.dispose);
    await _pumpApp(tester, state);

    await tester.tap(find.text('手动模式'));
    await tester.pumpAndSettle();

    expect(find.text('双臂服务'), findsOneWidget);
    expect(find.text('底盘控制'), findsOneWidget);
    expect(find.text('回 home 点'), findsOneWidget);
    expect(find.text('一键连接'), findsNothing);

    await tester.tap(find.text('回 home 点'));
    await tester.pumpAndSettle();
    expect(find.text('回位确认'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置：四个 tab，设备状态无机器人/VR', (tester) async {
    _tablet(tester);
    final state = _readyState();
    addTearDown(state.dispose);
    await _pumpApp(tester, state);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('基本设置'), findsOneWidget);
    expect(find.text('修改后只保存到配置，下次启动生效。当前连接不变。'), findsOneWidget);

    await tester.tap(find.text('进程管理'));
    await tester.pumpAndSettle();
    expect(find.text('运行中'), findsWidgets);

    await tester.tap(find.text('日志查看'));
    await tester.pumpAndSettle();
    expect(find.text('操作日志'), findsOneWidget);
    expect(find.text('系统日志'), findsNothing);

    await tester.tap(find.text('设备状态'));
    await tester.pumpAndSettle();
    expect(find.text('双臂'), findsWidgets);
    expect(find.text('机器人（工控）'), findsNothing);
    expect(find.text('VR'), findsNothing);

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机宽度：查看数据/采集/设置不溢出', (tester) async {
    _phone(tester);
    final state = _readyState();
    addTearDown(state.dispose);
    await _pumpApp(tester, state);
    expect(tester.takeException(), isNull);

    await _enterCollect(tester);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('基本设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
