// End-to-end check: Python publishes mock LCM traffic, Dart decodes it.
//
//   dart run tool/e2e_check.dart
//
// No Flutter UI required; this verifies the chunked preview and joint decoder.
//
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:tavi_capture/core/lcm/chunked_preview.dart';
import 'package:tavi_capture/core/lcm/codec.dart';
import 'package:tavi_capture/core/lcm/lcm_udp_client.dart';

Future<void> main() async {
  final port = 45000 + Random().nextInt(2000);
  final client = LcmUdpClient(port: port);
  final previews = <PreviewImage>[];
  final joints = <List<JointFrame>>[];
  final assembler = ChunkedPreviewAssembler(stats: client.stats);

  final subscription = client.messages.listen((message) {
    final package = decodePreviewPackage(message.payload);
    if (package != null) {
      final preview = assembler.addPackage(message.channel, package);
      if (preview != null) previews.add(preview);
    }
    final joint = decodeJointBatch(message.payload);
    if (joint != null) joints.add(joint);
  });

  await client.start(<String>[
    '/preview/cameras/cam_head',
    '/preview/cameras/cam_chest',
    '/preview/cameras/cam_left',
    '/preview/cameras/cam_right',
    '/preview/joint_batch',
  ]);

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

  await Future<void>.delayed(const Duration(milliseconds: 300));
  await subscription.cancel();
  await client.dispose();

  if (code != 0) {
    throw StateError('mock publisher failed ($code)\n$stdout\n$stderr');
  }

  final cameras = previews.map((preview) => preview.camera).toSet();

  _check(
    previews.length == 12,
    'received 12 preview frames (4 cameras × 3 rounds): ${previews.length}',
  );
  _check(
    cameras.length == 4 &&
        cameras.containsAll(<String>[
          'cam_head',
          'cam_chest',
          'cam_left',
          'cam_right',
        ]),
    'received 4 camera channels: $cameras',
  );
  _check(joints.length == 3, 'received 3 joint batches (${joints.length})');
  _check(
    previews.first.width == 640 && previews.first.height == 360,
    'preview dimensions survive the wire format',
  );
  _check(
    previews.first.bytes.length > 8 &&
        previews.first.bytes[0] == 0xFF &&
        previews.first.bytes[1] == 0xD8,
    'preview payload is a JPEG (mock)',
  );
  _check(
    joints.first.first.stateValues.length == 20,
    '20 joint state values survive the wire format',
  );
  _check(
    joints.first.first.commandValues.length == 20,
    '20 joint command values survive the wire format',
  );

  print('ok  Python publisher -> Dart decoder end-to-end');
  print(stdout.trim());
}

void _check(bool condition, String message) {
  if (!condition) throw StateError('FAIL: $message');
  print('ok  $message');
}
