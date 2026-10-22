import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tavi_capture/core/ros/joint_state_feed.dart';
import 'package:tavi_capture/core/ros/ros_bridge_client.dart';

/// 假 rosbridge：收客户端发的 JSON 帧，也能手动推 topic 消息。
class _MockRosBridge {
  _MockRosBridge(this._server) {
    _server.listen(_handle);
  }

  final HttpServer _server;
  final frames = <Map<String, dynamic>>[];
  final connections = <WebSocket>[];

  Uri get uri => Uri.parse('ws://127.0.0.1:${_server.port}');

  Future<void> _handle(HttpRequest request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    connections.add(socket);
    socket.listen((frame) {
      frames.add(
        Map<String, dynamic>.from(jsonDecode(frame as String) as Map),
      );
    });
  }

  void send(Map<String, Object?> frame) => connections.last.add(jsonEncode(frame));

  void sendJointState(List<String> names, List<double> positions) {
    send({
      'op': 'publish',
      'topic': '/joint_states',
      'msg': {
        'header': {
          'stamp': {'sec': 100, 'nanosec': 500000000},
          'frame_id': 'base_link',
        },
        'name': names,
        'position': positions,
        'velocity': <double>[],
        'effort': <double>[],
      },
    });
  }

  Future<void> close() => _server.close(force: true);
}

Future<void> _waitFor(bool Function() condition, {String? reason}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('等待超时${reason == null ? '' : '：$reason'}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

const _jointNames = ['j1', 'j2', 'j3', 'j4', 'j5', 'j6'];

void main() {
  test('订阅 /joint_states，按 name 映射成六轴并记历史', () async {
    final bridge = _MockRosBridge(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    addTearDown(bridge.close);
    final client = RosBridgeClient(
      bridge.uri,
      retryDelay: const Duration(milliseconds: 20),
    );
    addTearDown(client.dispose);
    final feed = JointStateFeed(client);
    addTearDown(feed.dispose);

    await feed.start();
    await _waitFor(() => bridge.frames.isNotEmpty, reason: '没收到 subscribe');

    final subscribe = bridge.frames.first;
    expect(subscribe['op'], 'subscribe');
    expect(subscribe['topic'], '/joint_states');
    expect(subscribe['queue_length'], 1);
    expect(client.status, RosBridgeStatus.open);

    bridge.sendJointState(_jointNames, [0.1, 0.2, 0.3, 0.4, 0.5, 0.6]);
    await _waitFor(() => feed.positions.length == 6, reason: '没解析出关节');

    expect(feed.names, _jointNames);
    expect(feed.positions[5], closeTo(0.6, 1e-9));
    expect(feed.degrees[0], closeTo(5.73, 0.01));
    expect(feed.lastStampNanos, 100 * 1000000000 + 500000000);
    expect(feed.history.length, 6);
    expect(feed.history.first, [0.1]);

    bridge.sendJointState(_jointNames, [0.1, 0.2, 0.3, 0.4, 0.5, 0.9]);
    await _waitFor(() => feed.revision == 2, reason: '第二帧没到');
    expect(feed.history[5], [0.6, 0.9]);
    expect(feed.rateHz, greaterThan(0));
  });

  test('publish 先 advertise 一次，再发消息', () async {
    final bridge = _MockRosBridge(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    addTearDown(bridge.close);
    final client = RosBridgeClient(bridge.uri);
    addTearDown(client.dispose);

    await client.start();
    client.publish(
      '/cmd_vel',
      {
        'linear': {'x': 0.2, 'y': 0.0, 'z': 0.0},
      },
      type: 'geometry_msgs/msg/Twist',
    );
    client.publish(
      '/cmd_vel',
      {
        'linear': {'x': 0.0, 'y': 0.0, 'z': 0.0},
      },
      type: 'geometry_msgs/msg/Twist',
    );
    await _waitFor(() => bridge.frames.length == 3, reason: '发布帧不全');

    expect(bridge.frames[0]['op'], 'advertise');
    expect(bridge.frames[0]['type'], 'geometry_msgs/msg/Twist');
    expect(bridge.frames[1]['op'], 'publish');
    expect(bridge.frames[2]['op'], 'publish');
  });

  test('断线后自动重连并补订阅', () async {
    final bridge = _MockRosBridge(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    addTearDown(bridge.close);
    final client = RosBridgeClient(
      bridge.uri,
      retryDelay: const Duration(milliseconds: 20),
    );
    addTearDown(client.dispose);
    final feed = JointStateFeed(client);
    addTearDown(feed.dispose);

    await feed.start();
    await _waitFor(() => bridge.connections.length == 1);
    final firstFrames = bridge.frames.length;

    await bridge.connections.first.close();
    await _waitFor(
      () => bridge.connections.length == 2,
      reason: '没有发起第二次连接',
    );
    await _waitFor(
      () => bridge.frames.length > firstFrames,
      reason: '重连后没有补订阅',
    );

    expect(bridge.frames.last['op'], 'subscribe');
    expect(bridge.frames.last['topic'], '/joint_states');
    await _waitFor(() => client.status == RosBridgeStatus.open);

    bridge.sendJointState(_jointNames, [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]);
    await _waitFor(() => feed.positions.length == 6, reason: '重连后收不到数据');
  });
}
