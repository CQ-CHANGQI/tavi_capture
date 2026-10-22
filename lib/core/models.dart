// 原型里的全部业务数据模型。业务数据仍是原型里的模拟数据：
// 机器人台账、云端任务目录、已采采集条；实时画面和回放走真数据。

enum ScreenId { setup, home, tasks, done, library, collect, review }

enum Role {
  engineer('工程师'),
  operator('采集员');

  const Role(this.label);
  final String label;
}

enum ModalKind { login, brief, settings, move, recover, loading }

enum JointMode {
  command('指令'),
  state('状态'),
  all('全部');

  const JointMode(this.label);
  final String label;
}

/// 四路相机的固定槽位。channel 是 LCM 通道名后缀，也用于 MCAP 话题匹配。
enum CameraId {
  head('主视角', 'cam_head'),
  left('左腕', 'cam_left'),
  right('右腕', 'cam_right'),
  chest('全景', 'cam_chest');

  const CameraId(this.label, this.channel);
  final String label;
  final String channel;
}

/// 机械臂分组。关节名形如 `left_joint1`、`body_joint2`、`head_joint1`。
enum JointGroup {
  left('左臂', 'left'),
  right('右臂', 'right'),
  body('身体', 'body');

  const JointGroup(this.label, this.prefix);
  final String label;
  final String prefix;
}

class TaskItem {
  TaskItem({
    required this.name,
    required this.done,
    required this.total,
    required this.size,
    required this.robot,
    required this.ip,
    required this.model,
    this.state = '采集中',
    this.brief = const [],
  });

  final String name;
  int done;
  final int total;
  String size;
  final String robot;
  final String ip;
  final String model;
  String state;
  final List<String> brief;

  double get progress => total <= 0 ? 0 : (done / total).clamp(0, 1);
  int get left => (total - done).clamp(0, total);

  /// 原型 `taskState()`：0 条 = 未开始，达标 = 已达标，否则采集中。
  String get shownState {
    if (done <= 0) return '未开始';
    if (total > 0 && done >= total) return '已达标';
    return '采集中';
  }

  TaskItem copyWith({int? done, String? state, String? size}) => TaskItem(
    name: name,
    done: done ?? this.done,
    total: total,
    size: size ?? this.size,
    robot: robot,
    ip: ip,
    model: model,
    state: state ?? this.state,
    brief: brief,
  );
}

class TakeRecord {
  TakeRecord({
    required this.task,
    required this.time,
    required this.durationSeconds,
    required this.size,
    required this.person,
    required this.robot,
    required this.valid,
  });

  final String task;
  final String time;
  final int durationSeconds;
  final String size;
  final String person;
  final String robot;

  /// 有效/无效可以改，所以不是 final。
  bool valid;

  String get duration => formatClock(durationSeconds);

  TakeRecord copy() => TakeRecord(
    task: task,
    time: time,
    durationSeconds: durationSeconds,
    size: size,
    person: person,
    robot: robot,
    valid: valid,
  );
}

class LogLine {
  const LogLine(this.category, this.text, this.ageHours);

  final String category;
  final String text;
  final double ageHours;
}

class RobotService {
  RobotService(this.name, this.pid, this.running, this.logs);

  final String name;
  final int pid;
  bool running;
  final List<String> logs;
}

String formatClock(int seconds) {
  final s = seconds.clamp(0, 359999);
  final m = (s ~/ 60).toString().padLeft(2, '0');
  return '$m:${(s % 60).toString().padLeft(2, '0')}';
}

/// `10-10 14:21`
String stampNow(DateTime now) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(now.month)}-${two(now.day)} ${two(now.hour)}:${two(now.minute)}';
}

bool isValidIp(String ip) {
  final parts = ip.split('.');
  return parts.length == 4 &&
      parts.every((p) {
        final v = int.tryParse(p);
        return p.isNotEmpty && p.length <= 3 && v != null && v >= 0 && v <= 255;
      });
}
