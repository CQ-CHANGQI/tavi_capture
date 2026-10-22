// Live check against the real robot: listens on the LCM group and prints
// decoded frames/joints. Run while the robot publisher is active.
//
//   dart run tool/live_check.dart [seconds]
//
// Environment overrides (no rebuild needed):
//
//   LCM_GROUP=239.255.76.67 LCM_PORT=7667 LCM_IFACE=en6 dart run tool/live_check.dart 10
//
// This uses the same assembler as the app (`ChunkedPreviewAssembler`), so a
// success here means the UI will also receive frames. The final line is the
// same diagnostic set the app shows: which interfaces are joined, datagrams
// in, messages decoded, frames assembled, and frames abandoned because a
// chunk was lost.
//
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:tavi_capture/core/lcm/chunked_preview.dart';
import 'package:tavi_capture/core/lcm/codec.dart';
import 'package:tavi_capture/core/lcm/lcm_udp_client.dart';

Future<void> main(List<String> args) async {
  final seconds = args.isEmpty ? 5 : int.tryParse(args.first) ?? 5;
  final group = Platform.environment['LCM_GROUP'] ?? '239.255.76.67';
  final port = int.tryParse(Platform.environment['LCM_PORT'] ?? '') ?? 7667;
  final iface = Platform.environment['LCM_IFACE'];

  final client = LcmUdpClient(group: group, port: port, interfaceName: iface);
  final assembler = ChunkedPreviewAssembler(stats: client.stats);
  final cameras = <String, int>{};
  var frames = 0;
  var joints = 0;

  final subscription = client.messages.listen((message) {
    final package = decodePreviewPackage(message.payload);
    if (package != null) {
      final chunked = assembler.addPackage(message.channel, package);
      if (chunked != null) {
        frames++;
        cameras[chunked.camera] = (cameras[chunked.camera] ?? 0) + 1;
        if (frames <= 3) {
          print(
            'chunked ${message.channel} ${chunked.width}x${chunked.height} '
            '${chunked.bytes.length}B',
          );
        }
      }
      return;
    }

    final joint = decodeJointBatch(message.payload);
    if (joint != null) {
      joints++;
      if (joints <= 3) {
        print(
          'joint ${message.channel} frames=${joint.length} '
          'state=${joint.first.stateValues.length}',
        );
      }
    }
  });

  try {
    await client.start(const <String>[], all: true);
  } catch (error) {
    print('cannot listen on $group:$port: $error');
    await subscription.cancel();
    await client.dispose();
    exitCode = 2;
    return;
  }
  print(
    'listening on $group:$port for ${seconds}s '
    'via ${client.stats.joinedInterfaces.join(', ')}'
    '${iface == null ? '' : ' (pinned $iface)'}...',
  );

  await Future<void>.delayed(Duration(seconds: seconds));

  final stats = client.stats;
  final rates = <String, String>{
    for (final entry in cameras.entries)
      entry.key: '${(entry.value / seconds).toStringAsFixed(1)} fps',
  };
  print(
    'frames=$frames joints=$joints cameras=$cameras\n'
    'rate=$rates\n'
    'link=${stats.joinedInterfaces} datagrams=${stats.datagrams} '
    'messages=${stats.messages} incomplete=${stats.incompleteFrames} '
    'corrupt=${stats.corruptFrames} parseErrors=${stats.parseErrors} '
    'pending=${assembler.pendingFrames}',
  );

  await subscription.cancel();
  await client.dispose();
}
