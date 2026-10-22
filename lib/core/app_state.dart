import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'live_preview.dart';
import 'models.dart';
import 'playback.dart';

const defaultRobotIp = String.fromEnvironment(
  'ROBOT_IP',
  defaultValue: '192.168.1.21',
);

/// 本地看 UI 用：跳过机器人探测。`--dart-define=DEMO=true`。
const demoMode = bool.fromEnvironment('DEMO');

/// 原型里全部页面的状态与动作，UI 只负责画。
class AppState extends ChangeNotifier {
  AppState() {
    _takes = _seedTakes();
    _catalog = _seedCatalog();
    localTasks = _catalog[currentUser]!.map(_copyTask).toList();
  }

  // ---------------------------------------------------------------- 导航
  ScreenId screen = ScreenId.setup;
  ModalKind? modal;
  String modalTitle = '';
  String modalText = '';
  String loadingText = '正在启动服务';
  String loadingSub = '机械臂 · 底盘 · VR · 四路相机';
  String briefTask = '';
  String recoverKind = '';
  int homeIndex = 0;

  void go(ScreenId target) {
    if (target != ScreenId.library && target != ScreenId.review) {
      _playback?.pause();
      if (target == ScreenId.home || target == ScreenId.tasks) {
        _disposePlayback();
      }
    }
    screen = target;
    notifyListeners();
  }

  void openModal(ModalKind kind, {String title = '', String text = ''}) {
    modal = kind;
    modalTitle = title;
    modalText = text;
    notifyListeners();
  }

  void closeModal() {
    modal = null;
    notifyListeners();
  }

  void showBrief(String task) {
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

  // ------------------------------------------------------------ 连接/会话
  String savedIp = defaultRobotIp;
  bool connecting = false;
  bool robotOk = false;
  String connectError = '';
  bool booted = false;

  bool get readOnlySettings =>
      screen == ScreenId.collect || screen == ScreenId.library;

  String get currentRobotName =>
      _ledger.where((r) => r.$1 == savedIp).firstOrNull?.$2 ?? savedIp;
  String get currentRobotModel =>
      _ledger.where((r) => r.$1 == savedIp).firstOrNull?.$3 ?? '—';

  static const _ledger = [
    ('192.168.1.21', '1号工位', 'Tavi-W2'),
    ('192.168.1.22', '2号工位', 'Tavi-W2'),
    ('192.168.1.23', '3号工位', 'Tavi-W1'),
  ];

  Future<void> boot() async {
    if (booted) return;
    booted = true;
    await connect(savedIp, auto: true);
  }

  Future<void> connect(String rawIp, {bool auto = false}) async {
    final ip = rawIp.trim();
    if (!isValidIp(ip)) {
      connecting = false;
      robotOk = false;
      connectError = 'IP 地址格式不正确。四段都要填写，每段 0–255。';
      screen = ScreenId.setup;
      notifyListeners();
      return;
    }

    connecting = true;
    robotOk = false;
    connectError = '';
    screen = ScreenId.setup;
    notifyListeners();

    final ok = demoMode || await _probe(ip);
    if (_disposed) return;
    connecting = false;

    if (!ok) {
      robotOk = false;
      connectError = auto
          ? '已按上次保存的 IP 自动连接，但机器人没有响应。确认上电和网段后，再保存连接。'
          : '机器人无响应。检查已上电、和平板同一网段、IP 是否写对。';
      screen = ScreenId.setup;
      notifyListeners();
      return;
    }

    savedIp = ip;
    robotOk = true;
    connectError = '';
    _startLive();
    screen = ScreenId.home;
    notifyListeners();
    toast('机器人已连接');
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

  // ------------------------------------------------------------ 账号
  String? currentUser = '张三';
  Role role = Role.engineer;
  bool localSession = false;
  bool loggedIn = true;
  bool online = true;

  bool get isEngineer => role == Role.engineer;
  bool get canViewLibrary => isEngineer || localSession;

  static const accounts = {'张三': '1234', '李四': '1234'};
  static const localPasswords = {'工程师': 'weiyi1234', '采集员': 'weiyi2018'};

  String? cloudLogin(String user, String password) {
    if (!online) return '现场没网，不能用云端登录。请改用本地登录';
    if (user.isEmpty || password.isEmpty) return '请填写账号和密码';
    if (accounts[user] != password) return '账号或密码不对';
    _enterAs(user, local: false);
    return null;
  }

  String? localLogin(Role selected, String password) {
    if (password.isEmpty) return '请输入密码';
    if (localPasswords[selected.label] != password) return '密码不对';
    _enterAs(selected == Role.engineer ? '张三' : '李四', local: true);
    return null;
  }

  void _enterAs(String name, {required bool local}) {
    currentUser = name;
    role = name == '张三' ? Role.engineer : Role.operator;
    localSession = local;
    loggedIn = true;
    modal = null;
    _loadTasksFor(name, local: local);
    notifyListeners();
    toast('$name 已${local ? '本地' : '云端'}登录');
    if (isEngineer) {
      go(ScreenId.home);
    } else {
      enterCollectMode();
    }
  }

  // ------------------------------------------------------------ 任务数据
  late final Map<String, List<TaskItem>> _catalog;
  final Map<String, List<TaskItem>> _taskCache = {};
  final List<TaskItem> _downloaded = [];
  final Set<String> _pulledExtra = {};
  List<TaskItem> localTasks = [];
  TaskItem? currentTask;

  static List<TaskItem> _copyOf(Iterable<TaskItem> source) =>
      source.map(_copyTask).toList();

  static TaskItem _copyTask(TaskItem source) => source.copyWith();

  void _loadTasksFor(String name, {required bool local}) {
    if (local) {
      _seedDownloaded();
      localTasks = _copyOf(_downloaded);
    } else {
      localTasks = _copyOf(_taskCache[name] ?? _catalog[name] ?? const []);
    }
  }

  List<TaskItem> get hereTasks => localTasks
      .where((t) => t.ip == savedIp || t.robot == currentRobotName)
      .toList();

  bool canCollect(TaskItem? task) =>
      task != null && (task.ip == savedIp || task.robot == currentRobotName);

  void pullTasks() {
    if (localSession) {
      _seedDownloaded();
      localTasks = _copyOf(_downloaded);
      notifyListeners();
      toast('已读取本地任务。本机 ${hereTasks.length} 个');
      return;
    }
    if (!online) {
      toast('离线时不能拉取云端任务，请读取本地任务');
      return;
    }
    final extra = _extraFor(currentUser ?? '');
    if (extra != null && !_pulledExtra.contains(currentUser)) {
      _pulledExtra.add(currentUser!);
      if (!localTasks.any((t) => t.name == extra.name)) {
        localTasks.add(_copyTask(extra));
      }
      notifyListeners();
      toast('已加载新任务「${extra.name}」');
      return;
    }
    toast('没有新的云端任务');
  }

  void downloadTasks() {
    if (localSession || !online) {
      toast('没网不能下载。请先云端登录');
      return;
    }
    _seedDownloaded();
    final seen = {for (final t in _downloaded) t.name: t};
    for (final task in localTasks) {
      seen[task.name] = _copyTask(task);
    }
    _downloaded
      ..clear()
      ..addAll(seen.values);
    _taskCache[currentUser ?? ''] = _copyOf(localTasks);
    toast('已下载 ${_downloaded.length} 个任务到本地');
    notifyListeners();
  }

  int get downloadedCount => _downloaded.length;

  void _seedDownloaded() {
    if (_downloaded.isNotEmpty) return;
    final seen = <String, TaskItem>{};
    for (final tasks in _catalog.values) {
      for (final task in tasks) {
        seen[task.name] = _copyTask(task);
      }
    }
    _downloaded.addAll(seen.values);
  }

  TaskItem? _extraFor(String user) => switch (user) {
    '张三' => TaskItem(
      name: '箱内码放',
      done: 0,
      total: 30,
      size: '0 GB',
      robot: '1号工位',
      ip: '192.168.1.21',
      model: 'Tavi-W2',
      brief: const ['把取出的鞋盒码放到箱内指定格。', '动作顺序：对准格口、放入、松开。', '合格：一次放正。压边、叠放的不要。'],
    ),
    '李四' => TaskItem(
      name: '空抓复核',
      done: 0,
      total: 12,
      size: '0 GB',
      robot: '1号工位',
      ip: '192.168.1.21',
      model: 'Tavi-W2',
      brief: const ['复核上次抓空的镜头。', '对准后再夹一次。', '合格：能看清为什么夹空。'],
    ),
    _ => null,
  };

  List<String> briefOf(String task) => _briefs[task] ?? const ['暂无采集说明'];

  static const _briefs = {
    'compact_shoes': [
      '从满箱中逐件取出鞋盒，放到输送位。',
      '动作顺序：接近、夹取、提出、放置。',
      '鞋盒正放、侧放各要覆盖，不采堆叠过高的情况。',
      '合格：一次夹稳并放正。抓空、滑落、碰撞的不要。',
    ],
    '鞋盒空箱判定': [
      '箱内鞋盒取完后，保持腕部相机能看清箱底。',
      '采集空箱、剩一只、剩多只三类画面。',
      '合格：箱底清晰可见。遮挡和过暗的不要。',
    ],
    '补采-抓空': [
      '只补上次抓空的情况，不重复正常抓取。',
      '从夹空开始，重新对准后再夹一次。',
      '合格：能看清第一次为什么夹空，以及第二次是否夹稳。',
    ],
    '传送带分拣': ['从传送带上取件，按颜色放到对应格。', '动作顺序：看清、夹取、分格、松开。', '合格：一次放对格。夹偏、掉件的不要。'],
    '货架取放': ['从货架指定层取出料盒，放到台面。', '对准层位后再伸臂。', '合格：一次取稳。撞架、拖底的不要。'],
    '箱盖扣合': ['把箱盖扣到箱体上，压实四角。', '合格：盖严、不翘边。'],
    '鞋盒码放': ['把取出的鞋盒码放到箱内指定格。', '动作顺序：对准格口、放入、松开。', '合格：一次放正。压边、叠放的不要。'],
  };

  static Map<String, List<TaskItem>> _seedCatalog() => {
    '张三': [
      TaskItem(
        name: 'compact_shoes',
        done: 60,
        total: 100,
        size: '18.6 GB',
        robot: '1号工位',
        ip: '192.168.1.21',
        model: 'Tavi-W2',
      ),
      TaskItem(
        name: '传送带分拣',
        done: 12,
        total: 50,
        size: '4.1 GB',
        robot: '2号工位',
        ip: '192.168.1.22',
        model: 'Tavi-W2',
      ),
      TaskItem(
        name: '鞋盒空箱判定',
        done: 40,
        total: 40,
        size: '12.8 GB',
        robot: '2号工位',
        ip: '192.168.1.22',
        model: 'Tavi-W2',
      ),
      TaskItem(
        name: '鞋盒码放',
        done: 30,
        total: 30,
        size: '9.6 GB',
        robot: '2号工位',
        ip: '192.168.1.22',
        model: 'Tavi-W2',
      ),
      TaskItem(
        name: '货架取放',
        done: 5,
        total: 40,
        size: '1.6 GB',
        robot: '3号工位',
        ip: '192.168.1.23',
        model: 'Tavi-W1',
      ),
    ],
    '李四': [
      TaskItem(
        name: '补采-抓空',
        done: 8,
        total: 20,
        size: '2.4 GB',
        robot: '1号工位',
        ip: '192.168.1.21',
        model: 'Tavi-W2',
      ),
      TaskItem(
        name: '箱盖扣合',
        done: 3,
        total: 20,
        size: '0.8 GB',
        robot: '2号工位',
        ip: '192.168.1.22',
        model: 'Tavi-W2',
      ),
    ],
  };

  void switchTask(String name) {
    if (recording) {
      toast('采集中不能切换任务');
      return;
    }
    final task = localTasks.where((t) => t.name == name).firstOrNull;
    if (!canCollect(task)) {
      toast('该任务不能采集');
      return;
    }
    openTask(name);
  }

  void switchPerson(String name) {
    if (recording) {
      toast('采集中不能切换人员');
      return;
    }
    currentUser = name;
    toast('当前人员：$name');
  }

  // ------------------------------------------------------------ 采集条
  late final List<TakeRecord> _takes;
  String dataFilter = '';

  List<TakeRecord> get takes => _takes;

  List<TakeRecord> takesOf(String task) =>
      _takes.where((t) => t.task == task).toList();

  int get doneCount => dataFilter.isEmpty ? 0 : takesOf(dataFilter).length;

  TaskItem? get doneTask =>
      localTasks.where((t) => t.name == dataFilter).firstOrNull;

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
    TakeRecord(
      task: '鞋盒空箱判定',
      time: '10-10 11:16',
      durationSeconds: 27,
      size: '860 MB',
      person: '张三',
      robot: '2号工位',
      valid: true,
    ),
    TakeRecord(
      task: '鞋盒空箱判定',
      time: '10-10 11:02',
      durationSeconds: 25,
      size: '820 MB',
      person: '张三',
      robot: '2号工位',
      valid: true,
    ),
  ];

  // ------------------------------------------------------------ 设备/服务
  bool _armReady = false;
  bool _baseReady = false;
  bool _vrReady = false;
  bool _camService = false;
  bool gripperOk = true;
  double storageGb = 805;
  static const storageWarnGb = 50.0;
  static const storageBlockGb = 20.0;

  bool get armOk => _armReady || (live?.jointsOnline ?? false);
  bool get baseOk => _baseReady;
  bool get vrOk => _vrReady;
  bool get camOk => _camService || (live?.allCamerasOnline ?? false);

  bool get storageOk => storageGb >= storageBlockGb;
  bool get storageWarn => storageGb < storageWarnGb && storageOk;
  String get storageText {
    final gb = storageGb.round();
    if (!storageOk) return '存储不足 ${gb}GB';
    if (storageWarn) return '剩余 ${gb}GB · 建议上传';
    return '剩余 ${gb}GB';
  }

  bool get gateOpen => camOk && vrOk && armOk;

  bool startServices() {
    if (!robotOk) {
      showRecover('启动服务失败', '机器人未连接，无法启动采集服务。请先连接机器人。', kind: 'service');
      return false;
    }
    _armReady = true;
    _baseReady = true;
    _vrReady = true;
    _camService = true;
    notifyListeners();
    return true;
  }

  void stopServices() {
    if (screen == ScreenId.collect) return;
    _armReady = false;
    _baseReady = false;
    _vrReady = false;
    _camService = false;
    notifyListeners();
  }

  void showRecover(
    String title,
    String text, {
    String kind = 'info',
    int? homeTarget,
  }) {
    modalTitle = title;
    modalText = text;
    recoverKind = kind;
    if (homeTarget != null) homeIndex = homeTarget;
    modal = ModalKind.recover;
    notifyListeners();
  }

  void connectAll() {
    if (baseOk && armOk) {
      toast('底盘和双臂已连接');
      return;
    }
    _baseReady = true;
    _armReady = true;
    notifyListeners();
    toast('底盘和双臂已连接');
  }

  void cycleHome() {
    if (!baseOk || !armOk) {
      toast('请先一键连接');
      return;
    }
    const points = [('home 点', '零点位姿'), ('打包位姿', '打包准备位姿'), ('待定位姿', '待确认位姿')];
    final point = points[homeIndex % points.length];
    showRecover(
      '回位确认',
      '下一个回位点：${point.$1}\n位姿：${point.$2}\n\n即将移动机械臂，请确认周边无障碍物、人员已远离，以免碰撞。',
      kind: 'home',
    );
  }

  void confirmHome() {
    const points = ['home 点', '打包位姿', '待定位姿'];
    final name = points[homeIndex % points.length];
    closeModal();
    homeIndex++;
    toast('双臂已回「$name」');
  }

  void deviceDown(String kind) {
    stopRecording(keepTake: false);
    if (kind == 'robot') {
      robotOk = false;
      showRecover('机器人断开', '机器人（工控）连接断开，本条采集已丢弃。', kind: 'device');
    } else if (kind == 'vr') {
      _vrReady = false;
      showRecover('VR 断开', 'VR 头显和手柄断开，本条采集已丢弃。', kind: 'device');
    } else {
      _camService = false;
      showRecover('相机断开', '四路相机中右腕相机无画面，本条采集已丢弃。', kind: 'device');
    }
  }

  void abortToHome() {
    closeModal();
    stopRecording(keepTake: false);
    screen = ScreenId.home;
    stopServices();
    toast('设备异常，已回到选择模式');
  }

  // ------------------------------------------------------------ 采集
  int elapsedSec = 0;
  bool recording = false;
  String lastTakeState = '—';
  String fsmState = 'HOME点';
  Timer? _recTimer;

  static const _fsmStates = ['HOME点', 'HOLD', '待确认'];

  void cycleFsm() {
    fsmState =
        _fsmStates[(_fsmStates.indexOf(fsmState) + 1) % _fsmStates.length];
    notifyListeners();
  }

  void openTask(String name) {
    final task = localTasks.where((t) => t.name == name).firstOrNull;
    if (task == null) return;
    dataFilter = name;
    currentTask = task;
    if (!recording) elapsedSec = 0;
    _withLoading('正在启动服务', '机械臂 · 底盘 · VR · 四路相机', () {
      startServices();
      screen = ScreenId.collect;
    });
  }

  void enterCollectMode() {
    if (!loggedIn) {
      openModal(ModalKind.login);
      return;
    }
    if (hereTasks.isEmpty) {
      screen = ScreenId.tasks;
      notifyListeners();
      toast('本机没有任务');
      return;
    }
    openTask(hereTasks.first.name);
  }

  void toggleRec() {
    if (!robotOk) {
      toast('机器人未连接，不能开始采集');
      openModal(ModalKind.settings);
      return;
    }
    if (!armOk) {
      toast('机械臂未连接，不能开始采集');
      return;
    }
    if (!vrOk || !camOk) {
      deviceDown(!vrOk ? 'vr' : 'cam');
      return;
    }
    if (!storageOk) {
      toast('存储不足 ${storageGb.round()}GB，请先上传/清理后再采集');
      return;
    }
    if (!recording) {
      recording = true;
      elapsedSec = 0;
      _recTimer?.cancel();
      _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_disposed) return;
        elapsedSec++;
        notifyListeners();
      });
      notifyListeners();
    } else {
      saveTake();
    }
  }

  void saveTake() {
    final name = currentTask?.name ?? dataFilter;
    final person = currentUser ?? '张三';
    final task = localTasks.where((t) => t.name == name).firstOrNull;
    _takes.insert(
      0,
      TakeRecord(
        task: name,
        time: stampNow(DateTime.now()),
        durationSeconds: elapsedSec,
        size: '1.1 GB',
        person: person,
        robot: currentRobotName,
        valid: true,
      ),
    );
    storageGb = math.max<double>(0, ((storageGb - 1.1) * 10).round() / 10);
    task?.done += 1;
    lastTakeState = '已保存';
    stopRecording(keepTake: true);
    notifyListeners();
    final done = task?.done ?? 0;
    final total = task?.total ?? 0;
    if (total > 0 && done >= total) {
      toast('本条已写入机载工控。已达标 $done / $total，可继续采集');
    } else {
      toast('本条已写入机载工控，未上传。继续采下一条');
    }
  }

  void stopRecording({required bool keepTake}) {
    _recTimer?.cancel();
    _recTimer = null;
    recording = false;
    elapsedSec = 0;
    if (!keepTake) lastTakeState = '已丢弃';
    notifyListeners();
  }

  Future<void> dropTake() async {
    if (!recording) return;
    final confirmed = await _confirm('作废本条？不保存、不计数。');
    if (!confirmed) return;
    stopRecording(keepTake: false);
    toast('本条已作废，未保存');
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

  void leaveCollect() {
    if (recording) {
      toast('采集中不能返回');
      return;
    }
    _withLoading('正在关闭服务', '', () {
      screen = ScreenId.home;
      stopServices();
      _playback?.dispose();
      _playback = null;
    });
  }

  Future<void> _withLoading(
    String title,
    String sub,
    VoidCallback action,
  ) async {
    loadingText = title;
    loadingSub = sub;
    modal = ModalKind.loading;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (_disposed) return;
    action();
    modal = null;
    notifyListeners();
  }

  // ------------------------------------------------------------ 已采
  int doneTab = 0;

  List<TakeRecord> get doneRows {
    final rows = takesOf(dataFilter);
    return switch (doneTab) {
      1 => rows.where((t) => t.valid).toList(),
      2 => rows.where((t) => !t.valid).toList(),
      _ => rows,
    };
  }

  int get doneTotal => doneTask?.total ?? takesOf(dataFilter).length;

  void setDoneTab(int tab) {
    doneTab = tab;
    notifyListeners();
  }

  void backHomeFromDone() {
    dataFilter = '';
    screen = ScreenId.home;
    notifyListeners();
  }

  void viewDone() {
    if (dataFilter.isEmpty) {
      toast('还没有任务');
      return;
    }
    if (recording) {
      toast('采集中不能查看已采集');
      return;
    }
    screen = ScreenId.done;
    notifyListeners();
    stopServices();
  }

  Future<void> addTake() async {
    final name = dataFilter;
    final task = localTasks.where((t) => t.name == name).firstOrNull;
    if (!canCollect(task)) {
      toast('不在本机，不能采集。只能看采集说明');
      showBrief(name);
      return;
    }
    if (!startServices()) return;
    openTask(name);
  }

  // ------------------------------------------------------------ 查看/回放
  int libTab = 0;
  String libTask = '';
  String libPerson = '';
  int libPage = 0;
  static const libPageSize = 20;
  TakeRecord? libSelected;
  TakeRecord? currentTake;
  ScreenId reviewFrom = ScreenId.done;
  PlaybackController? _playback;
  PlaybackController? get playback => _playback;

  List<TakeRecord> get libAll =>
      _takes.where((t) => t.robot == currentRobotName).toList();

  List<TakeRecord> get libRows {
    var rows = libAll;
    if (libPerson.isNotEmpty) {
      rows = rows.where((t) => t.person == libPerson).toList();
    }
    if (libTask.isNotEmpty) {
      rows = rows.where((t) => t.task == libTask).toList();
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

  void enterLibrary() {
    if (!canViewLibrary) {
      toast('查看数据仅工程师或本地登录可进');
      return;
    }
    if (!robotOk) {
      toast('本机数据在机器人机载工控上，请先连接机器人');
      openModal(ModalKind.settings);
      return;
    }
    _withLoading('正在启动服务', '', () {
      screen = ScreenId.library;
      libPage = 0;
      final rows = libRows;
      libSelected = rows.isEmpty ? null : rows.first;
      if (libSelected != null) _openPlayback(libSelected!);
    });
  }

  void setLibTask(String value) {
    libTask = value;
    libPage = 0;
    notifyListeners();
  }

  void setLibPerson(String value) {
    libPerson = value;
    libPage = 0;
    notifyListeners();
  }

  void setLibTab(int tab) {
    libTab = tab;
    libPage = 0;
    notifyListeners();
  }

  void selectTake(TakeRecord take) {
    if (libSelected == take) return;
    libSelected = take;
    _openPlayback(take);
    notifyListeners();
  }

  void libPrev() {
    final rows = libRows;
    final index = libSelected == null ? -1 : rows.indexOf(libSelected!);
    if (rows.isEmpty) return;
    selectTake(rows[index <= 0 ? 0 : index - 1]);
    _syncLibPageToSelection();
  }

  void libNext() {
    final rows = libRows;
    if (rows.isEmpty) return;
    final index = libSelected == null ? -1 : rows.indexOf(libSelected!);
    selectTake(rows[index < 0 ? 0 : math.min(index + 1, rows.length - 1)]);
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
    notifyListeners();
    toast(take.valid ? '已标记为有效' : '已标记为无效');
  }

  void replay(TakeRecord take) {
    reviewFrom = screen;
    currentTake = take;
    if (_playback == null || libSelected != take) {
      libSelected = take;
      _openPlayback(take);
    }
    screen = ScreenId.review;
    notifyListeners();
  }

  void keepLocal() {
    screen = reviewFrom;
    if (reviewFrom == ScreenId.done) {
      _disposePlayback();
    }
    notifyListeners();
  }

  void discardCurrentTake() {
    final take = currentTake;
    if (take == null) {
      screen = reviewFrom;
      notifyListeners();
      return;
    }
    toggleValid(take);
  }

  final Map<JointGroup, JointMode> jointModes = {
    for (final group in JointGroup.values) group: JointMode.command,
  };

  void setJointMode(JointGroup group, JointMode mode) {
    jointModes[group] = mode;
    notifyListeners();
  }

  void retryPlayback() {
    final take = libSelected ?? currentTake;
    if (take == null) return;
    _openPlayback(take);
    notifyListeners();
  }

  void _openPlayback(TakeRecord take) {
    _disposePlayback();
    final controller = PlaybackController(url: defaultMcapUrl(savedIp));
    _playback = controller;
    controller.addListener(_onPlayback);
    unawaited(controller.open());
  }

  void _onPlayback() {
    if (_disposed) return;
    notifyListeners();
  }

  void _disposePlayback() {
    final controller = _playback;
    _playback = null;
    controller?.removeListener(_onPlayback);
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
  String logType = '系统日志';
  String logRange = '全部时间';

  static const logTypes = <String, List<LogLine>>{
    '系统日志': [
      LogLine('系统日志', '[INFO] 系统启动完成', 0.5),
      LogLine('系统日志', '[INFO] 网络已连接', 2),
      LogLine('系统日志', '[INFO] 已连接机器人', 30),
    ],
    '采集日志': [
      LogLine('采集日志', '[INFO] 任务 compact_shoes 已保存', 0.2),
      LogLine('采集日志', '[INFO] 开始采集 compact_shoes', 1),
      LogLine('采集日志', '[INFO] VR 遥操中', 3),
    ],
    '设备日志': [
      LogLine('设备日志', '[WARN] 右腕相机帧率偏低（28 fps）', 0.5),
      LogLine('设备日志', '[INFO] 双臂已连接', 1.5),
      LogLine('设备日志', '[INFO] 三路相机已连接', 2),
    ],
    '错误日志': [
      LogLine('错误日志', '[WARN] 右腕相机帧率偏低', 0.5),
      LogLine('错误日志', '[ERROR] 网络连接超时', 26),
      LogLine('错误日志', '[ERROR] 磁盘写入失败', 50),
    ],
  };

  List<LogLine> get logRows {
    final range = switch (logRange) {
      '最近 1 小时' => 1.0,
      '最近 24 小时' => 24.0,
      '最近 7 天' => 168.0,
      _ => double.infinity,
    };
    return (logTypes[logType] ?? const [])
        .where((l) => l.ageHours <= range)
        .toList();
  }

  void selectProc(int index) {
    selectedProc = index;
    notifyListeners();
  }

  void startProc() {
    services[selectedProc].running = true;
    toast('${services[selectedProc].name} 已启用');
    notifyListeners();
  }

  void stopProc() {
    services[selectedProc].running = false;
    toast('${services[selectedProc].name} 已停止');
    notifyListeners();
  }

  void restartProc() {
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

  void _onLive() {
    if (_disposed) return;
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
