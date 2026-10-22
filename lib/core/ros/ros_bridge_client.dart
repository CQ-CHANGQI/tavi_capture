import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// rosbridge 连接状态。
enum RosBridgeStatus { idle, connecting, open, reconnecting, closed }

/// 一条 topic 消息。[msg] 就是 rosbridge 的 JSON，字段名与 ROS2 msg 一致。
class RosTopicMessage {
  const RosTopicMessage({
    required this.topic,
    required this.msg,
    required this.receivedAt,
  });

  final String topic;
  final Map<String, dynamic> msg;
  final DateTime receivedAt;
}

/// rosbridge_suite 的 WebSocket 客户端（ROS2）。
///
/// 机器人侧：
///   ros2 launch rosbridge_server rosbridge_websocket_launch.xml
/// 本端：
///   final client = RosBridgeClient(Uri.parse('ws://192.168.13.4:9090'));
///   client.subscribe('/joint_states', queueLength: 1);
///   client.messages.listen((m) => print(m.msg['position']));
///   await client.start();
///
/// 只做协议层、不依赖 Flutter；断线自动重连并补订阅，重连前调用的
/// [subscribe] 也会在连上后自动补发。
class RosBridgeClient {
  RosBridgeClient(
    this.uri, {
    this.retryDelay = const Duration(milliseconds: 500),
    this.maxRetryDelay = const Duration(seconds: 5),
  });

  final Uri uri;
  final Duration retryDelay;
  final Duration maxRetryDelay;

  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSub;
  Timer? _retryTimer;
  int _retry = 0;
  int _nextId = 0;
  bool _started = false;
  bool _disposed = false;

  final _messages = StreamController<RosTopicMessage>.broadcast();
  final _statusChanges = StreamController<RosBridgeStatus>.broadcast();
  final _subscriptions = <String, _Subscription>{};
  final _advertised = <String, String>{};

  RosBridgeStatus _status = RosBridgeStatus.idle;
  String? _lastError;

  RosBridgeStatus get status => _status;
  String? get lastError => _lastError;
  Stream<RosTopicMessage> get messages => _messages.stream;
  Stream<RosBridgeStatus> get statusChanges => _statusChanges.stream;

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    await _connect();
  }

  /// 订阅 topic。
  ///
  /// [queueLength] = 1 表示只保留最新一帧，实时显示首选；调大会在 rosbridge
  /// 端排队，网络卡的时候反而看到旧数据。
  /// [throttleRateMs] > 0 时由 rosbridge 端限流（比如 20 = 最多 50Hz）。
  void subscribe(
    String topic, {
    int queueLength = 1,
    int throttleRateMs = 0,
    String? type,
  }) {
    // 同一 topic 只保留一个订阅：重订阅不注销旧的，rosbridge 会重复推送。
    if (_subscriptions.containsKey(topic)) return;
    final sub = _Subscription(
      topic: topic,
      id: 'sub${_nextId++}',
      queueLength: queueLength,
      throttleRateMs: throttleRateMs,
      type: type,
    );
    _subscriptions[topic] = sub;
    if (_status == RosBridgeStatus.open) _send(sub.toJson());
  }

  void unsubscribe(String topic) {
    _subscriptions.remove(topic);
    if (_status == RosBridgeStatus.open) {
      _send({'op': 'unsubscribe', 'topic': topic});
    }
  }

  /// 发布一条消息。首次发布会自动 advertise，重连后也会重新 advertise。
  ///
  /// [type] 用 ROS2 写法：`geometry_msgs/msg/Twist`。
  void publish(String topic, Map<String, Object?> msg, {required String type}) {
    if (_status != RosBridgeStatus.open) return;
    if (_advertised[topic] != type) {
      _advertised[topic] = type;
      _send({'op': 'advertise', 'topic': topic, 'type': type});
    }
    _send({'op': 'publish', 'topic': topic, 'msg': msg});
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _retryTimer?.cancel();
    await _socketSub?.cancel();
    _socketSub = null;
    final socket = _socket;
    _socket = null;
    await socket?.close();
    _emit(RosBridgeStatus.closed);
    await _messages.close();
    await _statusChanges.close();
  }

  Future<void> _connect() async {
    if (_disposed) return;
    _emit(_retry == 0 ? RosBridgeStatus.connecting : RosBridgeStatus.reconnecting);
    try {
      final socket = await WebSocket.connect(uri.toString());
      if (_disposed) {
        await socket.close();
        return;
      }
      _socket = socket;
      _retry = 0;
      // 底层 ping/pong：WiFi 休眠、拔网线这类“假在线”能被发现并触发重连。
      socket.pingInterval = const Duration(seconds: 5);
      _socketSub = socket.listen(
        _onFrame,
        onDone: _onClosed,
        onError: (Object error) {
          _lastError = '$error';
          _onClosed();
        },
        cancelOnError: true,
      );
      for (final sub in _subscriptions.values) {
        _send(sub.toJson());
      }
      for (final entry in _advertised.entries) {
        _send({'op': 'advertise', 'topic': entry.key, 'type': entry.value});
      }
      _emit(RosBridgeStatus.open);
    } catch (error) {
      _lastError = '$error';
      _onClosed();
    }
  }

  void _onFrame(dynamic frame) {
    if (frame is! String) return;
    late final Object? decoded;
    try {
      decoded = jsonDecode(frame);
    } on FormatException catch (error) {
      _lastError = '坏帧：$error';
      return;
    }
    // rosbridge 有时把多条消息打包成数组发过来。
    final items = decoded is List ? decoded : [decoded];
    for (final item in items) {
      if (item is! Map) continue;
      switch (item['op']) {
        case 'publish':
          final topic = item['topic'];
          final msg = item['msg'];
          if (topic is String && msg is Map) {
            _messages.add(
              RosTopicMessage(
                topic: topic,
                msg: Map<String, dynamic>.from(msg),
                receivedAt: DateTime.now(),
              ),
            );
          }
        case 'status':
          if (item['level'] == 'error') _lastError = '${item['msg']}';
      }
    }
  }

  void _onClosed() {
    if (_disposed) return;
    _socketSub?.cancel();
    _socketSub = null;
    final socket = _socket;
    _socket = null;
    if (socket != null && socket.readyState != WebSocket.closed) {
      socket.close();
    }
    _emit(RosBridgeStatus.reconnecting);
    _retry++;
    final attempt = math.min(_retry, 5);
    final delay = retryDelay * (1 << (attempt - 1));
    _retryTimer?.cancel();
    _retryTimer = Timer(
      delay > maxRetryDelay ? maxRetryDelay : delay,
      _connect,
    );
  }

  void _send(Map<String, Object?> payload) {
    _socket?.add(jsonEncode(payload));
  }

  void _emit(RosBridgeStatus status) {
    if (_status == status || _statusChanges.isClosed) return;
    _status = status;
    _statusChanges.add(status);
  }
}

class _Subscription {
  const _Subscription({
    required this.topic,
    required this.id,
    required this.queueLength,
    required this.throttleRateMs,
    this.type,
  });

  final String topic;
  final String id;
  final int queueLength;
  final int throttleRateMs;
  final String? type;

  Map<String, Object?> toJson() => {
    'op': 'subscribe',
    'id': id,
    'topic': topic,
    'queue_length': queueLength,
    if (throttleRateMs > 0) 'throttle_rate': throttleRateMs,
    if (type != null) 'type': type,
  };
}
