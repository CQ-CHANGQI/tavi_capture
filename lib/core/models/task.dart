/// 一个采集任务。
class Task {
  const Task({
    required this.name,
    required this.done,
    required this.total,
    required this.size,
    required this.robot,
    required this.model,
    required this.brief,
  });

  final String name;
  final int done;
  final int total;
  final String size;
  final String robot;
  final String model;
  final List<String> brief;

  double get progress {
    if (total <= 0) {
      return 0;
    }
    return done >= total ? 1 : done / total;
  }

  String get state {
    if (done <= 0) {
      return '未开始';
    }
    if (done >= total) {
      return '已达标';
    }
    return '采集中';
  }
}
