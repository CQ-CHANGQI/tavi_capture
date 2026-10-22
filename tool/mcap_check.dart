import 'dart:io';

import 'package:tavi_capture/core/mcap/mcap_codecs.dart';
import 'package:tavi_capture/core/mcap/mcap_reader.dart';

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty
      ? args.first
      : 'http://192.168.13.4:8090/rosbag_0.mcap';
  final topic = args.length > 1 ? args[1] : null;
  final file = McapRemoteFile(Uri.parse(url));
  final stopwatch = Stopwatch()..start();
  try {
    await file.open();
    final summary = await McapSummary.load(file);
    stdout.writeln(
      'size=${file.length} profile=${summary.profile} '
      'library=${summary.library}',
    );
    stdout.writeln(
      'messages=${summary.messageCount} channels=${summary.channels.length} '
      'schemas=${summary.schemas.length} chunks=${summary.chunks.length} '
      'duration=${summary.duration}',
    );
    for (final channel in summary.channels) {
      final schema = summary.schemaOf(channel);
      stdout.writeln(
        '${channel.topic}  ${schema?.name ?? '?'}  '
        '${summary.messageCountOf(channel)}',
      );
    }

    final reader = McapMessageReader(file, summary);
    final channel = topic == null
        ? summary.channels.firstWhere(
            (channel) => summary.messageCountOf(channel) > 0,
            orElse: () => summary.channels.first,
          )
        : summary.channels.firstWhere((channel) => channel.topic == topic);
    final messages = await reader.firstMessages(channel, limit: 3);
    stdout.writeln('first ${messages.length} messages of ${channel.topic}:');
    for (final message in messages) {
      stdout.writeln(
        '  seq=${message.sequence} log=${message.logTimeNs} '
        'size=${message.data.length}',
      );
    }

    final imageChannel = _firstChannel(summary, 'sensor_msgs/msg/Image');
    if (imageChannel != null) {
      final message = (await reader.firstMessages(
        imageChannel,
        limit: 1,
      )).first;
      final image = decodeRosImage(message.data);
      stdout.writeln(
        'image ${image.width}x${image.height} ${image.encoding} '
        'rgba=${image.rgba.length}',
      );
    }

    final compressedChannel = _firstChannel(
      summary,
      'sensor_msgs/msg/CompressedImage',
    );
    if (compressedChannel != null) {
      final message = (await reader.firstMessages(
        compressedChannel,
        limit: 1,
      )).first;
      final image = decodeRosCompressedImage(message.data);
      stdout.writeln(
        'compressed ${image.format} data=${image.data.length} '
        'head=${image.data.take(4).toList()}',
      );
    }

    final statisticsChannel = _firstChannel(
      summary,
      'pal_statistics_msgs/msg/Statistics',
    );
    if (statisticsChannel != null) {
      final message = (await reader.firstMessages(
        statisticsChannel,
        limit: 1,
      )).first;
      final stats = decodeRosStatistics(message.data);
      stdout.writeln('statistics count=${stats.statistics.length}');
      for (final statistic in stats.statistics.take(5)) {
        stdout.writeln('  ${statistic.name} = ${statistic.value}');
      }
    }

    final jointChannel = _firstChannel(summary, 'sensor_msgs/msg/JointState');
    if (jointChannel != null) {
      final message = (await reader.firstMessages(
        jointChannel,
        limit: 1,
      )).first;
      final joint = decodeRosJointState(message.data);
      stdout.writeln(
        'joint ${joint.names.length} names=${joint.names} '
        'positions=${joint.positions}',
      );
    }
    final playIds = {
      if (imageChannel != null) imageChannel.id,
      if (compressedChannel != null) compressedChannel.id,
      if (jointChannel != null) jointChannel.id,
    };
    if (playIds.isNotEmpty) {
      final cursor = McapChunkCursor(
        file,
        summary,
        startTimeNs: summary.startTimeNs,
        channelIds: playIds,
      );
      stdout.writeln('playback cursor:');
      for (var i = 0; i < 10; i++) {
        final message = await cursor.next();
        if (message == null) break;
        final channel = summary.channels.firstWhere(
          (channel) => channel.id == message.channelId,
        );
        stdout.writeln(
          '  ${channel.topic} log=${message.logTimeNs} '
          'size=${message.data.length}',
        );
      }
    }
    stdout.writeln('elapsed=${stopwatch.elapsed}');
  } finally {
    file.close();
  }
}

McapChannel? _firstChannel(McapSummary summary, String schemaName) {
  for (final channel in summary.channels) {
    if (summary.schemaOf(channel)?.name == schemaName) return channel;
  }
  return null;
}
