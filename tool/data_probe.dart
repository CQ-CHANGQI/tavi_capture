import 'dart:async';
import 'dart:io';

import 'package:tavi_capture/core/lcm/lcm_client.dart';
import 'package:tavi_capture/core/mcap/remote_mcap.dart';
import 'package:tavi_capture/core/mcap/recording_decoder.dart';

/// Read-only LAN smoke check: dart run tool/data_probe.dart
Future<void> main() async {
  final live = LcmClient();
  final counts = <String, int>{};
  var jointCount = 0;
  LcmUpdate? last;
  final subscription = live.updates.listen((update) {
    last = update;
    for (final camera in update.cameras.keys) {counts[camera] = (counts[camera] ?? 0) + 1;}
    if (update.joints != null) jointCount++;
  }, onError: (Object e) => stderr.writeln(e));
  try {
    await live.start();
    await Future<void>.delayed(const Duration(seconds: 5));
    stdout.writeln('LCM cameras=$counts jointUpdates=$jointCount '
      'datagrams=${last?.datagrams} dropped=${last?.dropped} malformed=${last?.malformed} links=${last?.interfaces}');
    if (counts.length != 4 || jointCount == 0) throw StateError('LCM incomplete');
  } finally { await subscription.cancel(); live.dispose(); }
  final file = RemoteMcap(Uri.parse(recordingUrl));
  try {
    await file.open();
    stdout.writeln('MCAP bytes=${file.length} duration=${file.duration} channels=${file.channels.length} chunks=${file.chunks.length}');
    for (final time in [file.start, file.start + (file.end-file.start) ~/ 2, file.end - 200000000]) {
      final messages = await file.window(time, (time + 200000000).clamp(file.start,file.end));
      final cameras = <String>{};
      var joints = 0;
      for (final m in messages) {
        final channel = file.channels[m.channelId]!;
        final schema = file.schemas[channel.schemaId]!.name;
        if (schema == 'sensor_msgs/msg/CompressedImage') {
          final frame = decodeCompressedFrame(m);
          if (frame.bytes.length < 100) throw StateError('Empty frame');
          cameras.add(channel.topic);
        } else if (schema == 'pal_statistics_msgs/msg/Statistics') {
          final sample = decodeStatistics(m);
          if (!sample.state.containsKey('left_joint1') || !sample.command.containsKey('body_joint1')) throw StateError('Missing joints');
          joints++;
        }
      }
      stdout.writeln('window ${((time-file.start)/1e9).toStringAsFixed(2)}s: cameras=${cameras.length} jointSamples=$joints');
      if (cameras.length != 4 || joints == 0) throw StateError('MCAP incomplete');
    }
    stdout.writeln('Range transferred=${file.transferred} (${(file.transferred/file.length*100).toStringAsFixed(2)}% of file)');
  } finally { file.close(); }
}
