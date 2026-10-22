import '../mcap/remote_mcap.dart' show recordingUrl;

/// 一条采集记录。
class Take {
  Take({
    required this.id,
    required this.taskName,
    required this.time,
    required this.durationSeconds,
    required this.size,
    required this.person,
    required this.robot,
    required this.valid,
    this.sourceUrl = recordingUrl,
  });

  final int id;
  final String sourceUrl;
  final String taskName;
  final String time;
  final int durationSeconds;
  final String size;
  final String person;
  final String robot;

  /// 有效/无效可以改，所以不是 final。
  bool valid;

  String get duration {
    final minutes = (durationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (durationSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
