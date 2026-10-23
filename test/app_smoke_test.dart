import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavi_capture/app.dart';
import 'package:tavi_capture/core/app_state.dart';
import 'package:tavi_capture/core/config_store.dart';
import 'package:tavi_capture/core/models.dart';

class _FakeConfigStore extends ConfigStore {
  _FakeConfigStore(this.saved);

  final String? saved;

  @override
  Future<String?> loadRobotIp() async => saved;

  @override
  Future<void> saveRobotIp(String ip) async {}
}

AppState _readyState() => AppState()
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
  setUp(() {
    AppState.modeSwitchDelay = Duration.zero;
  });

  test('模式和采集条状态', () {
    final state = _readyState();
    addTearDown(state.dispose);

    expect(state.mode, PageMode.review);
    expect(state.armOk, isTrue);
    expect(state.armServiceOk, isFalse);

    expect(state.enterMode(PageMode.collect), isTrue);
    expect(state.armServiceOk, isTrue);
    expect(state.collectTask, 'compact_shoes');
    expect(state.collectPerson, '张三');

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
    expect(state.lastTakeState, '已丢弃');
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

  test('连接 IP 格式校验', () async {
    final state = AppState();
    addTearDown(state.dispose);
    expect(await state.connect('999.1.1.1'), isFalse);
    expect(state.connectError, contains('格式'));
    expect(state.modal, ModalKind.recover);
    state.closeModal();
  });

  test('启动读取配置并尝试自动连接', () async {
    final state = AppState(configStore: _FakeConfigStore('999.1.1.1'));
    addTearDown(state.dispose);
    await state.init();
    expect(state.hasSavedIp, isTrue);
    expect(state.configuredIp, '999.1.1.1');
    expect(state.modal, ModalKind.recover);
    state.closeModal();
  });

  test('切换模式先 loading 再进页面', () async {
    final state = _readyState();
    addTearDown(state.dispose);
    expect(await state.switchMode(PageMode.collect), isTrue);
    expect(state.mode, PageMode.collect);
    expect(state.modal, isNull);
    expect(state.armServiceOk, isTrue);
  });

  test('存储分级和开始采集拦截', () {
    final state = _readyState();
    addTearDown(state.dispose);
    state.enterMode(PageMode.collect);

    state.storageGb = 50;
    expect(state.storageLevel, StorageLevel.ok);
    expect(state.storageText, '剩余 50 GB');
    expect(state.canStartCollect, isTrue);

    state.storageGb = 20;
    expect(state.storageLevel, StorageLevel.warn);
    expect(state.storageText, '剩余 20 GB · 建议上传');
    expect(state.canStartCollect, isTrue);

    state.storageGb = 19.9;
    expect(state.storageLevel, StorageLevel.low);
    expect(state.storageText, '存储不足 20 GB');
    expect(state.canStartCollect, isFalse);
  });

  test('采集条 takeName 和文件名', () {
    final state = _readyState();
    addTearDown(state.dispose);
    final take = state.takes.first;
    expect(take.takeName, 'compact_shoes_10-10_1421');
    expect(take.fileName, 'compact_shoes_10-10_1421.mcap');
  });

  test('切换任务确认后才生效', () async {
    final state = _readyState();
    addTearDown(state.dispose);
    state.enterMode(PageMode.collect);

    final cancelled = state.requestCollectTask('补采-抓空');
    state.resolveConfirm(false);
    await cancelled;
    expect(state.collectTask, 'compact_shoes');

    final confirmed = state.requestCollectTask('补采-抓空');
    state.resolveConfirm(true);
    await confirmed;
    expect(state.collectTask, '补采-抓空');
    expect(state.collectPerson, '李四');
  });

  test('关键操作写入埋点队列', () {
    final state = _readyState();
    addTearDown(state.dispose);
    state.enterMode(PageMode.collect);
    state.startCollect();
    state.elapsedSec = 3;
    state.stopCollect();

    expect(
      state.telemetry.events.map((event) => event.name),
      containsAll([
        'enter_mode',
        'enter_page',
        'click_start',
        'capture_start',
        'click_save',
        'capture_save',
      ]),
    );
  });

  test('标记后分页不会越界', () {
    final state = _readyState();
    addTearDown(state.dispose);
    for (var i = 0; i < 7; i++) {
      state.takes.add(
        TakeRecord(
          task: 'compact_shoes',
          time: '10-10 15:0$i',
          durationSeconds: 10,
          size: '1 GB',
          person: '张三',
          robot: '1号工位',
          valid: true,
        ),
      );
    }
    state.libTab = 1; // 只看有效
    state.libPage = 1;
    final last = state.libPageRows.last;
    state.libSelected = last;

    state.toggleValid(last);

    expect(state.libPageCount, 1);
    expect(state.libPage, 0);
    expect(state.libPageRows, hasLength(10));
    expect(state.libSelected, isNull);
  });

  testWidgets('未连接：停在连接页，模式按钮置灰', (tester) async {
    _tablet(tester);
    final state = AppState();
    addTearDown(state.dispose);
    await _pumpApp(tester, state);

    expect(find.text('连接机器人'), findsOneWidget);
    expect(find.text('保存并连接'), findsOneWidget);
    expect(find.text('查看数据'), findsWidgets);

    await tester.tap(find.text('数据采集'));
    await tester.pump();
    expect(find.text('请先连接机器人'), findsNothing);
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

    await tester.tap(find.text('compact_shoes_10-10_1421').first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('关闭详情'), findsOneWidget);
    expect(find.text('采集文件名称'), findsOneWidget);
    expect(find.text('机器人'), findsOneWidget);
    expect(find.text('存储地址'), findsOneWidget);

    await tester.tap(find.text('关闭详情'));
    await tester.pumpAndSettle();
    expect(find.text('详情'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('连接成功后从 P0 自动进入查看数据', (tester) async {
    _tablet(tester);
    final state = AppState();
    addTearDown(state.dispose);
    await _pumpApp(tester, state);
    expect(find.text('连接机器人'), findsOneWidget);

    state.robotOk = true;
    state.mode = PageMode.review;
    state.notifyListeners();
    await tester.pumpAndSettle();

    expect(find.text('查看数据'), findsWidgets);
    expect(find.text('连接机器人'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('最大化回放布局不溢出', (tester) async {
    _tablet(tester);
    final state = _readyState();
    addTearDown(state.dispose);
    await _pumpApp(tester, state);

    await tester.tap(find.text('compact_shoes_10-10_1421').first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('关闭详情'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('最大化'));
    await tester.pumpAndSettle();

    expect(find.text('还原'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('还原'));
    await tester.pumpAndSettle();
  });

  testWidgets('查看数据最大化和还原', (tester) async {
    _tablet(tester);
    final state = _readyState();
    addTearDown(state.dispose);
    await _pumpApp(tester, state);

    await tester.tap(find.text('compact_shoes_10-10_1421').first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('最大化'));
    await tester.pumpAndSettle();
    expect(find.text('还原'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('还原'));
    await tester.pumpAndSettle();
    expect(find.text('最大化'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('采集：默认第一个任务/人员，开始并保存', (tester) async {
    _tablet(tester);
    final state = _readyState();
    addTearDown(state.dispose);
    await _pumpApp(tester, state);
    await _enterCollect(tester);

    expect(find.text('compact_shoes'), findsWidgets);
    expect(find.text('张三'), findsWidgets);
    expect(find.text('开始采集'), findsOneWidget);
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
    expect(find.text('请先结束采集'), findsNothing);
    expect(find.text('停止并保存'), findsOneWidget);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('采集中不能修改 IP。'), findsOneWidget);
    await tester.tap(find.text('进程管理'));
    await tester.pumpAndSettle();
    expect(find.text('采集中进程管理只读，只能查看日志。'), findsOneWidget);
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
    expect(find.text('保存并连接会立即重连；采集中不能修改 IP。'), findsOneWidget);

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
