import '../models/connect_state.dart';
import '../models/device_status.dart';
import '../models/take.dart';
import '../models/task.dart';

/// 连接页默认 IP，可用 --dart-define=ROBOT_IP=... 覆盖。
const defaultRobotIp = String.fromEnvironment(
  'ROBOT_IP',
  defaultValue: '192.168.13.4',
);

/// 骨架阶段的全局状态 + 模拟数据。
///
/// 先用一个全局单例，页面之间共享“当前机器人/当前用户/任务/采集条”。
/// 后面接真接口时，这里换成 Provider/Riverpod，页面按需改。
final appState = AppState();

class AppState {
  ConnectState connection = ConnectState.failed;
  String robotIp = defaultRobotIp;
  String? userName;
  String role = '采集员';
  Task? currentTask;

  bool get isEngineer => role == '工程师';

  final List<Task> tasks = const [
    Task(
      name: 'compact_shoes',
      done: 60,
      total: 100,
      size: '18.6 GB',
      robot: '1号工位',
      model: 'Tavi-W2',
      brief: [
        '从满箱中逐件取出鞋盒，放到输送位。',
        '动作顺序：接近、夹取、提出、放置。',
        '鞋盒正放、侧放各要覆盖，不采堆叠过高的情况。',
        '合格：一次夹稳并放正。抓空、滑落、碰撞的不要。',
      ],
    ),
    Task(
      name: '鞋盒空箱判定',
      done: 40,
      total: 40,
      size: '12.8 GB',
      robot: '1号工位',
      model: 'Tavi-W2',
      brief: [
        '箱内鞋盒取完后，保持腕部相机能看清箱底。',
        '采集空箱、剩一只、剩多只三类画面。',
        '合格：箱底清晰可见。遮挡和过暗的不要。',
      ],
    ),
    Task(
      name: '补采-抓空',
      done: 8,
      total: 20,
      size: '2.4 GB',
      robot: '1号工位',
      model: 'Tavi-W2',
      brief: [
        '只补上次抓空的情况，不重复正常抓取。',
        '从夹空开始，重新对准后再夹一次。',
        '合格：能看清第一次为什么夹空，以及第二次是否夹稳。',
      ],
    ),
  ];

  final List<Take> takes = [
    Take(
      id: 1,
      taskName: 'compact_shoes',
      time: '10-10 14:21',
      durationSeconds: 34,
      size: '1.2 GB',
      person: '张三',
      robot: '1号工位',
      valid: true,
    ),
    Take(
      id: 2,
      taskName: 'compact_shoes',
      time: '10-10 14:08',
      durationSeconds: 29,
      size: '980 MB',
      person: '张三',
      robot: '1号工位',
      valid: true,
    ),
    Take(
      id: 3,
      taskName: 'compact_shoes',
      time: '10-10 13:20',
      durationSeconds: 28,
      size: '1.0 GB',
      person: '张三',
      robot: '1号工位',
      valid: false,
    ),
    Take(
      id: 4,
      taskName: '补采-抓空',
      time: '10-10 13:42',
      durationSeconds: 41,
      size: '1.5 GB',
      person: '李四',
      robot: '1号工位',
      valid: false,
    ),
    Take(
      id: 5,
      taskName: '补采-抓空',
      time: '10-10 13:11',
      durationSeconds: 36,
      size: '1.3 GB',
      person: '李四',
      robot: '1号工位',
      valid: true,
    ),
    Take(
      id: 6,
      taskName: '鞋盒空箱判定',
      time: '10-10 11:16',
      durationSeconds: 27,
      size: '860 MB',
      person: '张三',
      robot: '1号工位',
      valid: true,
    ),
    Take(
      id: 7,
      taskName: 'compact_shoes',
      time: '10-10 14:30',
      durationSeconds: 33,
      size: '1.7 GB',
      person: '李四',
      robot: '1号工位',
      valid: true,
    ),
    Take(
      id: 8,
      taskName: '鞋盒空箱判定',
      time: '10-10 12:05',
      durationSeconds: 31,
      size: '1.1 GB',
      person: '李四',
      robot: '1号工位',
      valid: true,
    ),
    Take(
      id: 9,
      taskName: '补采-抓空',
      time: '10-10 15:02',
      durationSeconds: 35,
      size: '1.4 GB',
      person: '张三',
      robot: '1号工位',
      valid: true,
    ),
  ];

  final List<DeviceStatus> devices = [
    DeviceStatus(name: 'VR', detail: '头显和手柄已连接', ok: true),
    DeviceStatus(name: '双臂', detail: '已连接，已回初始位置', ok: true),
    DeviceStatus(name: '三路相机', detail: '主视角、左腕、右腕画面正常', ok: true),
    DeviceStatus(name: '机载存储', detail: '剩余 805 GB', ok: true),
  ];

  /// 测试用：把会话相关字段恢复成初始值。
  void reset() {
    connection = ConnectState.failed;
    robotIp = defaultRobotIp;
    userName = null;
    role = '采集员';
    currentTask = null;
  }
}
