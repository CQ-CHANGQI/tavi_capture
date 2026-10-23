// 原型里的全部业务数据模型。业务数据仍是模拟数据：
// 机器人台账、任务目录、采集条；实时画面和回放走真实链路。

/// 三个模式，和顶部三个按钮一一对应。
enum PageMode {
  collect('数据采集'),
  review('查看数据'),
  control('手动模式');

  const PageMode(this.label);
  final String label;
}

enum ModalKind { brief, settings, recover, loading }

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
    required this.total,
    this.persons = const ['张三', '李四'],
    this.brief = const [],
  });

  final String name;
  final int total;
  final List<String> persons;
  final List<String> brief;
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
  String get personName => person;
  String get robotName => robot;

  String get fileName =>
      '${task}_${time.replaceAll(' ', '_').replaceAll(':', '')}.mcap';
  String get storagePath =>
      '/data/episodes/$task/${time.replaceAll(' ', '_').replaceAll(':', '')}/';
  String get takeName => fileName.substring(0, fileName.length - 5);

  TakeRecord copy() => TakeRecord(
    task: task,
    time: time,
    durationSeconds: durationSeconds,
    size: size,
    person: person,
    robot: robot,
    valid: valid,
  );

  String get statusText => valid ? '有效' : '无效';
}

class LogLine {
  const LogLine(this.text, this.ageHours);

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
