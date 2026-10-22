// 现场检查：监听 LCM 组播，打印相机/关节帧率和接收端计数。
//
//   dart run tool/live_check.dart [seconds]
//
// 环境变量覆盖（不用改代码）：
//   LCM_GROUP / LCM_PORT / LCM_JOINT_GROUP / LCM_JOINT_PORT / LCM_IFACE
//
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:tavi_capture/core/lcm/lcm_receiver.dart';
import 'package:tavi_capture/core/lcm/preview_protocol.dart';

Future<void> main(List<String> args) async {
  final seconds = args.isEmpty ? 5 : int.tryParse(args.first) ?? 5;
  final env = Platform.environment;
  final receiver = LcmReceiver(
    cameraGroup: env['LCM_GROUP'] ?? lcmCameraGroup,
    cameraPort: int.tryParse(env['LCM_PORT'] ?? '') ?? lcmCameraPort,
    jointGroup: env['LCM_JOINT_GROUP'] ?? lcmJointGroup,
    jointPort: int.tryParse(env['LCM_JOINT_PORT'] ?? '') ?? lcmJointPort,
    interfaceName: env['LCM_IFACE'] ?? lcmInterface,
  );

  final frames = <String, int>{};
  var jointBatches = 0;
  final started = DateTime.now();
  final frameSub = receiver.frames.listen((frame) {
    frames[frame.camera] = (frames[frame.camera] ?? 0) + 1;
  });
  final jointSub = receiver.joints.listen((batch) {
    jointBatches += batch.length;
  });

  try {
    await receiver.start(const [
      '${cameraChannelPrefix}cam_head',
      '${cameraChannelPrefix}cam_chest',
      '${cameraChannelPrefix}cam_left',
      '${cameraChannelPrefix}cam_right',
    ]);
  } catch (error) {
    print(
      'cannot listen on ${receiver.cameraGroup}:${receiver.cameraPort}: $error',
    );
    await frameSub.cancel();
    await jointSub.cancel();
    await receiver.dispose();
    exitCode = 2;
    return;
  }

  print(
    'listening on ${receiver.cameraGroup}:${receiver.cameraPort} for '
    '${seconds}s via ${receiver.stats.interfaces.join(', ')}...',
  );

  await Future<void>.delayed(Duration(seconds: seconds));
  final stats = receiver.stats;
  final elapsed = DateTime.now().difference(started).inMilliseconds / 1000;
  await frameSub.cancel();
  await jointSub.cancel();
  await receiver.dispose();

  for (final camera in frames.keys.toList()..sort()) {
    final count = frames[camera]!;
    print(
      '$camera: $count frames (${(count / elapsed).toStringAsFixed(1)} fps)',
    );
  }
  print('joints: $jointBatches batches');
  print(
    'stats: datagrams=${stats.datagrams} messages=${stats.messages} '
    'parseErrors=${stats.parseErrors} dropped=${stats.dropped} '
    'incomplete=${stats.incomplete} corrupt=${stats.corrupt} '
    'pending=${stats.pending} coalesced=${stats.coalesced}',
  );
  if (frames.isEmpty) exitCode = 1;
}
