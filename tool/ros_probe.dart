import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:tavi_capture/core/ros/ros_bridge_client.dart';

/// 用法：
///   dart run tool/ros_probe.dart ws://192.168.13.4:9090 /joint_states
///
/// 只依赖 dart:io，不启动 Flutter：先在电脑上确认 rosbridge 通了、topic 名对、
/// 数据长什么样，再去调 UI。
Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : 'ws://127.0.0.1:9090';
  final topic = args.length > 1 ? args[1] : '/joint_states';

  final client = RosBridgeClient(Uri.parse(url));
  client.statusChanges.listen((status) {
    final error = client.lastError;
    stderr.writeln('[${_clock()}] $status${error == null ? '' : '：$error'}');
  });

  var count = 0;
  client.messages.listen((message) {
    count++;
    final msg = message.msg;
    if (count == 1) {
      stdout.writeln('[${_clock()}] 第一帧：${jsonEncode(msg)}');
    }
    final positions = msg['position'];
    final names = msg['name'];
    if (positions is List && names is List && count % 20 == 1) {
      final degrees = [
        for (final value in positions)
          if (value is num)
            (value.toDouble() * 180 / 3.141592653589793).toStringAsFixed(2),
      ];
      stdout.writeln('[${_clock()}] $names → ${degrees.join('°, ')}°');
    }
  });

  client.subscribe(topic, queueLength: 1);
  await client.start();

  var lastCount = 0;
  Timer.periodic(const Duration(seconds: 1), (_) {
    final hz = count - lastCount;
    lastCount = count;
    if (count > 0) stdout.writeln('[${_clock()}] $topic $hz Hz，累计 $count 帧');
  });
}

String _clock() {
  final now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(now.hour)}:${two(now.minute)}:${two(now.second)}.'
      '${now.millisecond.toString().padLeft(3, '0')}';
}
