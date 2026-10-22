import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'ros_bridge_client.dart';

/// rosbridge 端口，可用 --dart-define=ROS_WS_PORT=9090 覆盖。
const rosBridgePort = int.fromEnvironment('ROS_WS_PORT', defaultValue: 9090);

/// 机械臂关节 topic，可用 --dart-define=ROS_JOINT_TOPIC=/joint_states 覆盖。
const rosJointTopic = String.fromEnvironment(
  'ROS_JOINT_TOPIC',
  defaultValue: '/joint_states',
);

/// 传感器时间戳（header.stamp）换算成纳秒。
///
/// ROS2 是 sec/nanosec，ROS1 和部分桥是 secs/nsecs，两种都认。
int? _stampNanos(Map<String, dynamic> msg) {
  final header = msg['header'];
  if (header is! Map) return null;
  final stamp = header['stamp'];
  if (stamp is! Map) return null;
  final sec = stamp['sec'] ?? stamp['secs'];
  final nanosec = stamp['nanosec'] ?? stamp['nsecs'];
  if (sec is! num) return null;
  return sec.toInt() * 1000000000 + (nanosec is num ? nanosec.toInt() : 0);
}

/// 机械臂关节实时数据源：最新角度 + 帧率 + 时钟差 + 历史曲线。
///
/// 只订阅 [topic]，消息按 `name` 对齐（不依赖数组顺序），UI 直接监听本对象。
class JointStateFeed extends ChangeNotifier {
  JointStateFeed(
    this.client, {
    this.topic = rosJointTopic,
    this.maxHistory = 240,
  }) {
    _statusSub = client.statusChanges.listen((status) {
      this.status = status;
      notifyListeners();
    });
    _messageSub = client.messages
        .where((message) => message.topic == topic)
        .listen(_onMessage);
  }

  final RosBridgeClient client;
  final String topic;
  final int maxHistory;

  late final StreamSubscription<RosBridgeStatus> _statusSub;
  late final StreamSubscription<RosTopicMessage> _messageSub;

  RosBridgeStatus status = RosBridgeStatus.idle;

  /// 关节名，例如 [j1, j2, ..., j6]，顺序来自 topic，通常是按轴排好的。
  List<String> names = const [];

  /// 与 [names] 一一对应的弧度值。
  List<double> positions = const [];

  int? lastStampNanos;
  DateTime? lastReceivedAt;

  /// 最近若干帧的本机接收时间，用来估算实际帧率（不是配置的发布频率）。
  final _received = <DateTime>[];

  /// 每根关节一条曲线，最多 [maxHistory] 个点。
  final _history = <List<double>>[];
  int revision = 0;

  /// 传入画图前拷贝一份：曲线组件按对象身份判断要不要重绘。
  List<List<double>> get history => [
    for (final line in _history) List<double>.of(line),
  ];

  double get rateHz {
    if (_received.length < 2) return 0;
    final span = _received.last.difference(_received.first).inMicroseconds;
    return span <= 0 ? 0 : (_received.length - 1) * 1000000 / span;
  }

  /// 机器人时间戳与本机时钟之差。两台机器没对时的话这个数会很大，
  /// 只有都跑了 NTP/chrony 才当延迟看。
  int? get clockSkewMillis {
    final stamp = lastStampNanos;
    if (stamp == null) return null;
    return (DateTime.now().microsecondsSinceEpoch * 1000 - stamp) ~/ 1000000;
  }

  /// 弧度转角度。
  List<double> get degrees => [for (final v in positions) v * 180 / math.pi];

  Future<void> start() async {
    client.subscribe(topic, queueLength: 1);
    await client.start();
  }

  void _onMessage(RosTopicMessage message) {
    final raw = message.msg['position'];
    if (raw is! List || raw.isEmpty) return;
    final values = <double>[];
    for (final item in raw) {
      if (item is! num) return;
      values.add(item.toDouble());
    }

    final rawNames = message.msg['name'];
    final messageNames = rawNames is List
        ? [for (final item in rawNames) '$item']
        : [for (var i = 0; i < values.length; i++) 'j${i + 1}'];
    // name 和 position 长度不一致说明 msg 结构不是 JointState，直接丢。
    if (messageNames.length != values.length) return;

    names = messageNames;
    positions = values;
    lastStampNanos = _stampNanos(message.msg);
    lastReceivedAt = message.receivedAt;

    if (_history.length != values.length) {
      _history
        ..clear()
        ..addAll([for (final _ in values) <double>[]]);
    }
    for (var i = 0; i < values.length; i++) {
      final line = _history[i];
      line.add(values[i]);
      if (line.length > maxHistory) line.removeAt(0);
    }

    _received.add(message.receivedAt);
    if (_received.length > 20) _received.removeAt(0);
    revision++;
    notifyListeners();
  }

  @override
  void dispose() {
    _statusSub.cancel();
    _messageSub.cancel();
    super.dispose();
  }
}
