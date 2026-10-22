// 端到端检查：Python 发布端 → Dart 接收端（真实 UDP + 真实分片）。
//
//   dart run tool/e2e_check.dart
//
// 不启动 Flutter，覆盖 LCM 分帧、preview_package_t 重组、joint_batch_t 解码。
//
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:tavi_capture/core/lcm/lcm_receiver.dart';
import 'package:tavi_capture/core/lcm/preview_protocol.dart';

const _cameras = ['cam_head', 'cam_chest', 'cam_left', 'cam_right'];

Future<void> main() async {
  final port = 45000 + Random().nextInt(2000);
  final receiver = LcmReceiver(
    cameraPort: port,
    jointGroup: lcmCameraGroup,
    jointPort: port,
    interfaceName: '',
  );

  final frames = <CameraFrame>[];
  final joints = <JointBatch>[];
  final frameSub = receiver.frames.listen(frames.add);
  final jointSub = receiver.joints.listen(joints.addAll);

  await receiver.start(_cameras.map((c) => '$cameraChannelPrefix$c'));

  final process = await Process.start('python3', <String>[
    'tool/mock_publisher.py',
    '--host',
    '127.0.0.1',
    '--port',
    '$port',
    '--count',
    '3',
    '--preview-hz',
    '5',
    '--joint-hz',
    '5',
  ]);
  final stdoutFuture = process.stdout.transform(utf8.decoder).join();
  final stderrFuture = process.stderr.transform(utf8.decoder).join();
  final code = await process.exitCode;
  final stdout = await stdoutFuture;
  final stderr = await stderrFuture;

  await Future<void>.delayed(const Duration(milliseconds: 400));
  await frameSub.cancel();
  await jointSub.cancel();
  final stats = receiver.stats;
  await receiver.dispose();

  if (code != 0) {
    throw StateError('mock publisher failed ($code)\n$stdout\n$stderr');
  }

  final receivedCameras = frames.map((frame) => frame.camera).toSet();
  final image = frames.isEmpty ? <int>[] : frames.first.image;

  _check(frames.length == 12, '收到 12 帧（4 相机 × 3 轮），实际 ${frames.length}');
  _check(
    receivedCameras.length == 4 && receivedCameras.containsAll(_cameras),
    '四路相机都收到：$receivedCameras',
  );
  _check(
    image.length > 2 && image[0] == 0xFF && image[1] == 0xD8,
    '画面是 JPEG（${image.length} bytes）',
  );
  _check(joints.length == 3, '收到 3 批关节，实际 ${joints.length}');
  _check(
    joints.isNotEmpty && joints.first.state.length == 20,
    '关节按名字解出 20 个位置值',
  );
  _check(
    stats.datagrams > 0 && stats.corrupt == 0,
    '没有坏包（datagrams=${stats.datagrams}, corrupt=${stats.corrupt}）',
  );
  print('stats: $stats');
  print('All LCM end-to-end checks passed.');
}

void _check(bool condition, String message) {
  if (!condition) throw StateError('FAIL $message');
  print('ok  $message');
}
