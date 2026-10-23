import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'config_store.dart';
import 'live_preview.dart';
import 'models.dart';
import 'playback.dart';
import 'telemetry.dart';

const defaultRobotIp = String.fromEnvironment(
  'ROBOT_IP',
  defaultValue: '192.168.13.4',
);

/// 本地看 UI 用：跳过机器人探测。`--dart-define=DEMO=true`。
const demoMode = bool.fromEnvironment('DEMO');

/// 全部页面的业务状态和动作。页面栈由 go_router 管理。
class AppState extends ChangeNotifier {
  AppState({ConfigStore? configStore})
    : configStore = configStore ?? ConfigStore() {
    _takes = _seedTakes();
    localTasks = _seedTasks();
  }

  final ConfigStore configStore;
  final Telemetry telemetry = Telemetry();

  /// 测试里可以设成 0，避免每个模式切换都等 1.5 秒。
  static Duration modeSwitchDelay = const Duration(milliseconds: 1500);

  // ---------------------------------------------------------------- 弹层
  ModalKind? modal;
  String modalTitle = '';
  String modalText = '';
  String loadingText = '正在启动服务';
  String loadingSub = '';
  String briefTask = '';
  String recoverKind = '';
  String confirmLabel = '确定';
  int homeIndex = 0;

  void openModal(ModalKind kind, {String title = '', String text = ''}) {
    modal = kind;
    modalTitle = title;
    modalText = text;
    notifyListeners();
  }

  void openLoading(String text, [String sub = '']) {
    loadingText = text;
    loadingSub = sub;
    modal = ModalKind.loading;
    notifyListeners();
  }

  void closeModal() {
    modal = null;
    notifyListeners();
  }

  void showBrief(String task) {
    telemetry.track('click_brief', {'task': task});
    briefTask = task;
    openModal(ModalKind.brief);
  }

  void toast(String message) {
    _toast = message;
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 1800), () {
      if (_disposed) return;
      _toast = null;
      notifyListeners();
    });
    notifyListeners();
  }

  String? _toast;
  String? get toastMessage => _toast;
  Timer? _toastTimer;

  // ------------------------------------------------------------ 连接/模式
  String savedIp = defaultRobotIp;
  String configuredIp = defaultRobotIp;
  bool hasSavedIp = false;
  bool connecting = false;
  bool robotOk = false;
  String connectError = '';

  PageMode mode = PageMode.review;

  static const _ledger = [
    ('192.168.13.4', '1号工位'),
    ('192.168.1.21', '1号工位'),
    ('192.168.1.22', '2号工位'),
    ('192.168.1.23', '3号工位'),
  ];

  String get currentRobotName =>
      _ledger.where((r) => r.$1 == savedIp).firstOrNull?.$2 ?? savedIp;

  /// 读本地配置；有已保存 IP 时自动连接一次。
  Future<void> init() async {
    final saved = await configStore.loadRobotIp();
    if (_disposed || saved == null) return;
    hasSavedIp = true;
    configuredIp = saved;
    notifyListeners();
    await autoConnect();
  }

  Future<void> autoConnect() async {
    if (_disposed || !hasSavedIp || robotOk || connecting) return;
    await connect(configuredIp);
  }

  /// 用户点“保存并连接”时调用；启动自动连接也走这里。
  Future<bool> connect(String rawIp) async {
    final ip = rawIp.trim();
    if (!isValidIp(ip)) {
      connecting = false;
      robotOk = false;
      connectError = 'IP 地址格式不正确。四段都要填写，每段 0–255。';
      notifyListeners();
      _showConnectFailure(ip, 'IP 地址格式不正确，请检查四段地址。');
      return false;
    }

    connecting = true;
    robotOk = false;
    connectError = '';
    notifyListeners();

    final ok = demoMode || await _probe(ip);
    if (_disposed) return false;
    connecting = false;

    if (!ok) {
      connectError = '机器人无响应。检查已上电、和平板同一网段、IP 是否写对。';
      notifyListeners();
      _showConnectFailure(ip, '机器人无响应。请确认已上电、与平板同一网段、IP 填写正确。');
      return false;
    }

    savedIp = ip;
    configuredIp = ip;
    hasSavedIp = true;
    robotOk = true;
    mode = PageMode.review;
    _resetReview();
    stopServices();
    _startLive();
    notifyListeners();
    await configStore.saveRobotIp(ip);
    toast('机器人已连接');
    await _showEntryLoading('正在进入查看数据');
    return true;
  }

  /// 设置页“保存并连接”：保持当前连接，成功后才切 IP。
  Future<bool> reconnect(String rawIp) async {
    final ip = rawIp.trim();
    if (!isValidIp(ip)) {
      toast('IP 地址格式不正确');
      return false;
    }
    if (!robotOk) return connect(ip);

    connecting = true;
    connectError = '';
    notifyListeners();

    final ok = demoMode || await _probe(ip);
    if (_disposed) return false;
    connecting = false;

    if (!ok) {
      notifyListeners();
      toast('连接失败，仍使用当前机器人');
      return false;
    }

    savedIp = ip;
    configuredIp = ip;
    hasSavedIp = true;
    notifyListeners();
    await configStore.saveRobotIp(ip);
    if (_live == null || !_live!.running) _startLive();
    toast('机器人已连接');
    return true;
  }

  void _showConnectFailure(String ip, String detail) {
    showRecover('连接机器人失败', '连不上 $ip。$detail', kind: 'connect');
  }

  Future<void> _showEntryLoading(String text) async {
    openLoading(text);
    await Future<void>.delayed(modeSwitchDelay);
    if (!_disposed && modal == ModalKind.loading) closeModal();
  }

  Future<bool> _probe(String ip) async {
    for (final port in const [8090, 8080]) {
      try {
        final socket = await Socket.connect(
          ip,
          port,
          timeout: const Duration(milliseconds: 800),
        );
        socket.destroy();
        return true;
      } catch (_) {
        // 换下一个端口。
      }
    }
    return false;
  }

  Future<bool> switchMode(PageMode next) async {
    if (!robotOk || recording || next == mode) return false;
    openLoading(
      next == PageMode.review ? '正在进入查看数据' : '正在启动服务',
      next == PageMode.collect
          ? '机械臂 · 底盘 · VR · 四路相机'
          : next == PageMode.control
          ? '双臂 · 底盘'
          : '',
    );
    await Future<void>.delayed(modeSwitchDelay);
    if (_disposed) return false;

    final entered = enterMode(next);
    if (!entered) {
      closeModal();
      return false;
    }
    if (!_modeServicesOk(next)) {
      _fallbackToReview();
      closeModal();
      _showServiceFailure(next);
      return false;
    }
    closeModal();
    return true;
  }

  bool _modeServicesOk(PageMode mode) => switch (mode) {
    PageMode.collect => armServiceOk && baseServiceOk && vrOk && camOk,
    PageMode.control => armServiceOk || baseServiceOk,
    PageMode.review => true,
  };

  void _fallbackToReview() {
    mode = PageMode.review;
    stopServices();
    _resetReview();
    notifyListeners();
  }

  void _showServiceFailure(PageMode failedMode) {
    showRecover(
      '启动服务失败',
      failedMode == PageMode.control
          ? '双臂、底盘服务都启动失败，已回到查看数据页。可从设置重新连接。'
          : '采集所需服务启动失败，已回到查看数据页。可从设置重新连接。',
      kind: 'service',
    );
  }

  bool enterMode(PageMode next) {
    if (next == mode) return false;
    if (recording) {
      toast('采集中不能切换模式');
      return false;
    }
    mode = next;
    telemetry.track('enter_mode', {'mode': next.name});
    telemetry.track('enter_page', {'page': next.name});
    closePlayback();
    switch (next) {
      case PageMode.collect:
        collectTask = localTasks.isEmpty ? '' : localTasks.first.name;
        collectPerson = collectTaskItem?.persons.firstOrNull ?? '';
        lastTakeState = '—';
        elapsedSec = 0;
        _startCollectServices();
      case PageMode.review:
        stopServices();
        _resetReview();
      case PageMode.control:
        _startControlServices();
    }
    notifyListeners();
    return true;
  }

  // ------------------------------------------------------------ 任务
  late final List<TaskItem> localTasks;
  String collectTask = '';
  String collectPerson = '';

  TaskItem? get collectTaskItem =>
      localTasks.where((t) => t.name == collectTask).firstOrNull;

  List<String> get allPersons =>
      {for (final t in localTasks) ...t.persons}.toList();

  static List<TaskItem> _seedTasks() => [
    TaskItem(
      name: 'compact_shoes',
      total: 100,
      persons: ['张三', '李四'],
      brief: [
        '从满箱中逐件取出鞋盒，放到输送位。',
        '动作顺序：接近、夹取、提出、放置。',
        '鞋盒正放、侧放各要覆盖，不采堆叠过高的情况。',
        '合格：一次夹稳并放正。抓空、滑落、碰撞的不要。',
      ],
    ),
    TaskItem(
      name: '补采-抓空',
      total: 20,
      persons: ['李四'],
      brief: [
        '只补上次抓空的情况，不重复正常抓取。',
        '从夹空开始，重新对准后再夹一次。',
        '合格：能看清第一次为什么夹空，以及第二次是否夹稳。',
      ],
    ),
    TaskItem(
      name: '鞋盒空箱判定',
      total: 40,
      persons: ['张三'],
      brief: [
        '箱内鞋盒取完后，保持腕部相机能看清箱底。',
        '采集空箱、剩一只、剩多只三类画面。',
        '合格：箱底清晰可见。遮挡和过暗的不要。',
      ],
    ),
    TaskItem(
      name: '传送带分拣',
      total: 50,
      persons: ['张三'],
      brief: ['从传送带上取件，按颜色放到对应格。', '动作顺序：看清、夹取、分格、松开。', '合格：一次放对格。夹偏、掉件的不要。'],
    ),
    TaskItem(
      name: '货架取放',
      total: 40,
      persons: ['张三'],
      brief: ['从货架指定层取出料盒，放到台面。', '对准层位后再伸臂。', '合格：一次取稳。撞架、拖底的不要。'],
    ),
    TaskItem(
      name: '箱盖扣合',
      total: 20,
      persons: ['李四'],
      brief: ['把箱盖扣到箱体上，压实四角。', '合格：盖严、不翘边。'],
    ),
    TaskItem(
      name: '鞋盒码放',
      total: 30,
      persons: ['张三'],
      brief: ['把取出的鞋盒码放到箱内指定格。', '动作顺序：对准格口、放入、松开。', '合格：一次放正。压边、叠放的不要。'],
    ),
  ];

  List<String> briefOf(String task) {
    final item = localTasks.where((t) => t.name == task).firstOrNull;
    return item?.brief ?? const ['暂无采集说明'];
  }

  // ------------------------------------------------------------ 采集条
  late final List<TakeRecord> _takes;

  List<TakeRecord> get takes => _takes;

  List<TakeRecord> takesOf(String task) =>
      _takes.where((t) => t.task == task).toList();

  List<TakeRecord> get collectRows =>
      collectTask.isEmpty ? _takes : takesOf(collectTask);

  int get collectDone => collectTask.isEmpty ? 0 : takesOf(collectTask).length;

  int get collectTotal => collectTaskItem?.total ?? 0;

  int get collectLeft => (collectTotal - collectDone).clamp(0, collectTotal);

  static List<TakeRecord> _seedTakes() => [
    TakeRecord(
      task: 'compact_shoes',
      time: '10-10 14:21',
      durationSeconds: 34,
      size: '1.2 GB',
      person: '张三',
      robot: '1号工位',
      valid: true,
    ),
    TakeRecord(
      task: 'compact_shoes',
      time: '10-10 14:08',
      durationSeconds: 29,
      size: '980 MB',
      person: '张三',
      robot: '1号工位',
      valid: true,
    ),
    TakeRecord(
      task: 'compact_shoes',
      time: '10-10 13:46',
      durationSeconds: 31,
      size: '1.1 GB',
      person: '张三',
      robot: '1号工位',
      valid: true,
    ),
    TakeRecord(
      task: 'compact_shoes',
      time: '10-10 13:20',
      durationSeconds: 28,
      size: '1.0 GB',
      person: '张三',
      robot: '1号工位',
      valid: false,
    ),
    TakeRecord(
      task: '补采-抓空',
      time: '10-10 13:42',
      durationSeconds: 41,
      size: '1.5 GB',
      person: '李四',
      robot: '1号工位',
      valid: false,
    ),
    TakeRecord(
      task: '补采-抓空',
      time: '10-10 13:11',
      durationSeconds: 36,
      size: '1.3 GB',
      person: '李四',
      robot: '1号工位',
      valid: true,
    ),
  ];

  Future<void> requestCollectTask(String name) async {
    if (recording || name == collectTask) return;
    final ok = await confirmAction(
      '切换任务',
      '确认切换到任务「$name」？切换后进入该任务的采集页。',
      label: '确认切换',
    );
    if (!ok) return;
    setCollectTask(name);
  }

  void setCollectTask(String name) {
    if (recording) {
      toast('采集中不能切换任务');
      return;
    }
    collectTask = name;
    collectPerson = collectTaskItem?.persons.firstOrNull ?? '';
    notifyListeners();
  }

  Future<void> requestCollectPerson(String name) async {
    if (recording || name == collectPerson) return;
    final ok = await confirmAction(
      '切换人员',
      '确认将当前采集员切换为「$name」？',
      label: '确认切换',
    );
    if (!ok) return;
    setCollectPerson(name);
  }

  void setCollectPerson(String name) {
    if (recording) {
      toast('采集中不能切换人员');
      return;
    }
    collectPerson = name;
    notifyListeners();
  }

  // ------------------------------------------------------------ 设备/服务
  bool _armService = false;
  bool _baseService = false;
  bool _vrService = false;
  bool _camService = false;

  /// 顶部状态表示硬件已上电，不表示服务已启动。
  bool get armOk => robotOk;
  bool get baseOk => robotOk;
  bool get gripperOk => robotOk;
  bool get vrOk => _vrService;
  bool get camOk => robotOk && _camService;

  bool get armServiceOk => _armService;
  bool get baseServiceOk => _baseService;

  double storageGb = 805;

  StorageLevel get storageLevel => storageGb >= 50
      ? StorageLevel.ok
      : storageGb >= 20
      ? StorageLevel.warn
      : StorageLevel.low;

  String get storageText {
    final gb = storageGb.round();
    return switch (storageLevel) {
      StorageLevel.ok => '剩余 $gb GB',
      StorageLevel.warn => '剩余 $gb GB · 建议上传',
      StorageLevel.low => '存储不足 $gb GB',
    };
  }

  void _startCollectServices() {
    _armService = true;
    _baseService = true;
    _vrService = true;
    _camService = true;
  }

  void _startControlServices() {
    _armService = true;
    _baseService = true;
    _vrService = false;
    _camService = false;
  }

  void stopServices() {
    _armService = false;
    _baseService = false;
    _vrService = false;
    _camService = false;
    notifyListeners();
  }

  void showRecover(String title, String text, {String kind = 'info'}) {
    modalTitle = title;
    modalText = text;
    recoverKind = kind;
    modal = ModalKind.recover;
    notifyListeners();
  }

  void cycleHome() {
    if (!armServiceOk) {
      toast('双臂服务未就绪');
      return;
    }
    telemetry.track('click_manual_home');
    const points = [('home 点', '零点位姿'), ('打包位姿', '打包准备位姿'), ('待定位姿', '待确认位姿')];
    final point = points[homeIndex % points.length];
    showRecover(
      '回位确认',
      '下一个回位点：${point.$1}\n位姿：${point.$2}\n\n即将移动机械臂，请确认周边无障碍物、人员已远离，以免碰撞。',
      kind: 'home',
    );
  }

  Future<void> confirmHome() async {
    const points = ['home 点', '打包位姿', '待定位姿'];
    final name = points[homeIndex % points.length];
    closeModal();
    openLoading('正在移动双臂');
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    if (_disposed) return;
    if (modal == ModalKind.loading) closeModal();
    homeIndex++;
    toast('双臂已回「$name」');
  }

  // ------------------------------------------------------------ 录制
  int elapsedSec = 0;
  bool recording = false;
  String lastTakeState = '—';
  String fsmState = 'HOME点';
  Timer? _recTimer;

  bool get canStartCollect =>
      robotOk &&
      collectTaskItem != null &&
      collectPerson.isNotEmpty &&
      armServiceOk &&
      baseServiceOk &&
      vrOk &&
      camOk &&
      storageGb >= 20;

  void startCollect() {
    if (recording) return;
    if (!robotOk) {
      toast('机器人未连接，不能开始采集');
      return;
    }
    if (!canStartCollect) {
      if (storageGb < 20) {
        toast('存储不足，请先上传/清理后再采集');
      } else if (collectTaskItem == null || collectPerson.isEmpty) {
        toast('请先选择任务和人员');
      } else {
        toast('双臂/底盘/VR/相机服务未就绪');
      }
      return;
    }
    recording = true;
    elapsedSec = 0;
    telemetry.track('click_start', {'task': collectTask});
    telemetry.track('capture_start', {'task': collectTask});
    _recTimer?.cancel();
    _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed) return;
      elapsedSec++;
      notifyListeners();
    });
    notifyListeners();
  }

  void stopCollect() {
    if (!recording) return;
    telemetry.track('click_save', {
      'task': collectTask,
      'duration': elapsedSec,
    });
    telemetry.track('capture_save', {
      'task': collectTask,
      'duration': elapsedSec,
    });
    _addTake(valid: true);
  }

  void _addTake({required bool valid}) {
    final task = collectTaskItem;
    if (task == null) return;
    _takes.insert(
      0,
      TakeRecord(
        task: task.name,
        time: stampNow(DateTime.now()),
        durationSeconds: elapsedSec,
        size: '1.1 GB',
        person: collectPerson.isEmpty ? '—' : collectPerson,
        robot: currentRobotName,
        valid: valid,
      ),
    );
    storageGb = math.max<double>(0, ((storageGb - 1.1) * 10).round() / 10);
    lastTakeState = valid ? '已保存' : '已丢弃';
    _recTimer?.cancel();
    _recTimer = null;
    recording = false;
    elapsedSec = 0;
    notifyListeners();
    toast(valid ? '本条已保存' : '本条已丢弃，保存为无效采集条');
  }

  Future<void> dropTake() async {
    if (!recording) return;
    final confirmed = await _confirm('确认作废本条？');
    if (!confirmed) return;
    telemetry.track('click_discard', {'task': collectTask});
    telemetry.track('capture_discard', {'task': collectTask});
    _addTake(valid: false);
  }

  Future<bool> _confirm(String text) async {
    final completer = Completer<bool>();
    modalText = text;
    modalTitle = '作废本条';
    recoverKind = 'drop';
    modal = ModalKind.recover;
    notifyListeners();
    _dropCompleter = completer;
    return completer.future;
  }

  Completer<bool>? _dropCompleter;

  void resolveDrop(bool value) {
    _dropCompleter?.complete(value);
    _dropCompleter = null;
    closeModal();
  }

  /// 通用的二次确认：任务/人员切换等。
  Future<bool> confirmAction(String title, String text, {String label = '确定'}) {
    final completer = Completer<bool>();
    modalTitle = title;
    modalText = text;
    confirmLabel = label;
    recoverKind = 'confirm';
    modal = ModalKind.recover;
    notifyListeners();
    _actionCompleter = completer;
    return completer.future;
  }

  Completer<bool>? _actionCompleter;

  void resolveConfirm(bool value) {
    _actionCompleter?.complete(value);
    _actionCompleter = null;
    closeModal();
  }

  // ------------------------------------------------------------ 查看数据
  int libTab = 0;
  String libTask = '';
  String libPerson = '';
  int libPage = 0;
  static const libPageSize = 10;
  TakeRecord? libSelected;
  PlaybackController? _playback;
  PlaybackController? get playback => _playback;

  List<TakeRecord> get libAll => _takes;

  List<TakeRecord> get libRows {
    var rows = libAll;
    if (libTask.isNotEmpty) {
      rows = rows.where((t) => t.task == libTask).toList();
    }
    if (libPerson.isNotEmpty) {
      rows = rows.where((t) => t.person == libPerson).toList();
    }
    return switch (libTab) {
      1 => rows.where((t) => t.valid).toList(),
      2 => rows.where((t) => !t.valid).toList(),
      _ => rows,
    };
  }

  int get libPageCount => math.max(1, (libRows.length / libPageSize).ceil());

  List<TakeRecord> get libPageRows =>
      libRows.skip(libPage * libPageSize).take(libPageSize).toList();

  void _resetReview() {
    libTask = '';
    libPerson = '';
    libTab = 0;
    libPage = 0;
    libSelected = null;
    _disposePlayback();
  }

  void _clearLibSelection() {
    libSelected = null;
    _disposePlayback();
    notifyListeners();
  }

  void setLibTask(String value) {
    libTask = value;
    libPerson = '';
    libPage = 0;
    _clearLibSelection();
  }

  void setLibPerson(String value) {
    libPerson = value;
    libPage = 0;
    _clearLibSelection();
  }

  void setLibTab(int tab) {
    libTab = tab;
    libPage = 0;
    _clearLibSelection();
  }

  void selectTake(TakeRecord take) {
    if (libSelected == take && _playback != null) return;
    libSelected = take;
    _openPlayback(take);
    notifyListeners();
  }

  void libPrev() {
    telemetry.track('click_prev');
    final rows = libRows;
    final index = libSelected == null ? -1 : rows.indexOf(libSelected!);
    if (index < 0) return;
    selectTake(rows[index <= 0 ? 0 : index - 1]);
    _syncLibPageToSelection();
  }

  void libNext() {
    telemetry.track('click_next');
    final rows = libRows;
    final index = libSelected == null ? -1 : rows.indexOf(libSelected!);
    if (index < 0) return;
    selectTake(rows[math.min(index + 1, rows.length - 1)]);
    _syncLibPageToSelection();
  }

  void _syncLibPageToSelection() {
    final index = libSelected == null ? -1 : libRows.indexOf(libSelected!);
    if (index >= 0) libPage = index ~/ libPageSize;
    notifyListeners();
  }

  void libPrevPage() {
    if (libPage > 0) {
      libPage--;
      notifyListeners();
    }
  }

  void libNextPage() {
    if (libPage + 1 < libPageCount) {
      libPage++;
      notifyListeners();
    }
  }

  void toggleValid(TakeRecord take) {
    take.valid = !take.valid;
    libPage = math.min(libPage, libPageCount - 1);
    if (libSelected == take && !libRows.contains(take)) {
      _clearLibSelection();
    } else {
      notifyListeners();
    }
    toast(take.valid ? '已标记为有效' : '已标记为无效');
  }

  final Map<JointGroup, JointMode> jointModes = {
    for (final group in JointGroup.values) group: JointMode.command,
  };

  void trackManualMove(String direction) {
    telemetry.track('manual_move', {'direction': direction});
  }

  void setJointMode(JointGroup group, JointMode mode) {
    telemetry.track('switch_joint_mode', {
      'group': group.name,
      'mode': mode.name,
    });
    jointModes[group] = mode;
    notifyListeners();
  }

  void retryPlayback() {
    final take = libSelected;
    if (take == null) return;
    _openPlayback(take);
    notifyListeners();
  }

  void _openPlayback(TakeRecord take) {
    _disposePlayback();
    final controller = PlaybackController(url: defaultMcapUrl(savedIp));
    _playback = controller;
    unawaited(controller.open());
  }

  void closePlayback() => _disposePlayback();

  void _disposePlayback() {
    final controller = _playback;
    _playback = null;
    controller?.dispose();
  }

  // ------------------------------------------------------------ 设置
  final List<RobotService> services = [
    RobotService('采集服务', 1284, true, [
      '10:32:01 任务 compact_shoes 已保存',
      '10:31:40 开始采集 compact_shoes',
      '10:30:15 相机帧率正常',
    ]),
    RobotService('设备连接服务', 1310, true, [
      '10:32:00 VR 已连接',
      '10:31:00 双臂已连接',
      '10:30:00 三路相机已连接',
    ]),
    RobotService('网络同步服务', 1202, true, ['10:30:00 心跳正常', '10:29:00 同步任务目录']),
    RobotService('数据存储服务', 1355, true, [
      '10:32:01 写入工控成功',
      '10:31:00 磁盘剩余 805GB',
    ]),
    RobotService('日志服务', 1180, true, ['10:32:01 日志写入', '10:31:00 日志轮转']),
  ];
  int selectedProc = 0;
  String logRange = '全部时间';

  final List<LogLine> operationLogs = [
    const LogLine('[操作] 停止并保存 compact_shoes', 0.2),
    const LogLine('[操作] 开始采集 compact_shoes', 0.5),
    const LogLine('[操作] 进入采集页', 1),
    const LogLine('[操作] 底盘移动 · 前进', 2),
    const LogLine('[操作] 手动控制 · 回 home 点', 3),
    const LogLine('[操作] 切换任务 · compact_shoes', 5),
    const LogLine('[操作] 切换人员 · 李四', 6),
  ];

  List<LogLine> get logRows {
    final range = switch (logRange) {
      '最近 1 小时' => 1.0,
      '最近 24 小时' => 24.0,
      '最近 7 天' => 168.0,
      _ => double.infinity,
    };
    return operationLogs.where((l) => l.ageHours <= range).toList();
  }

  void selectProc(int index) {
    selectedProc = index;
    notifyListeners();
  }

  void startProc() {
    telemetry.track('service_start', {'name': services[selectedProc].name});
    services[selectedProc].running = true;
    toast('${services[selectedProc].name} 已启用');
    notifyListeners();
  }

  void stopProc() {
    telemetry.track('service_stop', {'name': services[selectedProc].name});
    services[selectedProc].running = false;
    toast('${services[selectedProc].name} 已停止');
    notifyListeners();
  }

  void restartProc() {
    telemetry.track('service_start', {'name': services[selectedProc].name});
    services[selectedProc].running = true;
    toast('${services[selectedProc].name} 已重启');
    notifyListeners();
  }

  // ------------------------------------------------------------ 实时预览
  LivePreview? _live;
  LivePreview? get live => _live;

  void _startLive() {
    final existing = _live;
    if (existing == null) {
      final live = _live = LivePreview();
      live.addListener(_onLive);
      unawaited(live.start());
    } else if (!existing.running) {
      unawaited(existing.start());
    }
  }

  DateTime _lastLiveNotify = DateTime.fromMillisecondsSinceEpoch(0);

  void _onLive() {
    if (_disposed) return;
    // 状态栏只需要知道“在线/离线”，不用每帧重建整页。
    final now = DateTime.now();
    if (now.difference(_lastLiveNotify).inMilliseconds < 500) return;
    _lastLiveNotify = now;
    notifyListeners();
  }

  // ------------------------------------------------------------ 生命周期
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _recTimer?.cancel();
    _toastTimer?.cancel();
    _live?.removeListener(_onLive);
    _live?.dispose();
    _playback?.dispose();
    super.dispose();
  }
}
