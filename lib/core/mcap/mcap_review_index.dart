import 'mcap_reader.dart';
import 'ros2_messages.dart';

/// 回放页需要的最小索引：关节序列 + 每帧图像在文件里的位置。
///
/// 不保存图像数据本身，seek 时按 [McapFrameRef.offset] 重新读文件。
class McapReviewIndex {
  McapReviewIndex({
    required this.path,
    required this.startTime,
    required this.endTime,
    required this.width,
    required this.height,
    required this.leftCamera,
    required this.rightCamera,
    required this.leftFrames,
    required this.rightFrames,
    required this.leftArm,
    required this.rightArm,
  });

  final String path;
  final int startTime;
  final int endTime;
  final int width;
  final int height;
  final String? leftCamera;
  final String? rightCamera;
  final List<McapFrameRef> leftFrames;
  final List<McapFrameRef> rightFrames;
  final McapJointTrack? leftArm;
  final McapJointTrack? rightArm;

  Duration get duration =>
      Duration(microseconds: ((endTime - startTime) / 1000).round());
}

class McapFrameRef {
  const McapFrameRef({
    required this.time,
    required this.offset,
    required this.length,
  });

  final int time;
  final int offset;
  final int length;
}

class McapJointTrack {
  McapJointTrack({required this.topic, required this.frameId});

  final String topic;
  final String frameId;
  final List<int> times = [];
  final List<List<double>> positions = [];

  /// 转成“每根关节一条曲线”，给 JointChart 用。
  List<List<double>> get series {
    if (positions.isEmpty) return const [];
    final count = positions.first.length;
    final result = List<List<double>>.generate(count, (_) => <double>[]);
    for (final sample in positions) {
      for (var i = 0; i < count; i++) {
        result[i].add(i < sample.length ? sample[i] : 0);
      }
    }
    return result;
  }
}

/// 一遍扫描里不断喂记录，随时能拿出当前索引快照。
class McapReviewIndexBuilder {
  final _schemas = <int, McapSchema>{};
  final _channels = <int, McapChannel>{};
  final _frames = <int, List<McapFrameRef>>{};
  final _joints = <String, McapJointTrack>{};
  final _imageMeta = <int, ({int width, int height})>{};
  var _startTime = 0x7fffffffffffffff;
  var _endTime = 0;
  var _messageCount = 0;

  int get messageCount => _messageCount;

  void add(McapRecord record) {
    if (record is McapChannel) {
      _channels[record.id] = record;
      return;
    }
    if (record is McapSchema) {
      _schemas[record.id] = record;
      return;
    }
    if (record is! McapMessage) return;

    _messageCount++;
    if (record.logTime < _startTime) _startTime = record.logTime;
    if (record.logTime > _endTime) _endTime = record.logTime;

    final channel = _channels[record.channelId];
    final schema = channel == null ? null : _schemas[channel.schemaId];
    if (channel == null || schema == null) return;

    if (schema.name == 'sensor_msgs/msg/Image') {
      final offset = record.dataOffset;
      if (offset == null) return;
      final refs = _frames.putIfAbsent(channel.id, () => []);
      refs.add(
        McapFrameRef(
          time: record.logTime,
          offset: offset,
          length: record.data.length,
        ),
      );
      if (!_imageMeta.containsKey(channel.id)) {
        final image = decodeRos2Message(schema.name, record.data) as RosImage;
        _imageMeta[channel.id] = (width: image.width, height: image.height);
      }
    } else if (schema.name == 'sensor_msgs/msg/JointState') {
      final state =
          decodeRos2Message(schema.name, record.data) as RosJointState;
      final track = _joints.putIfAbsent(
        channel.topic,
        () =>
            McapJointTrack(topic: channel.topic, frameId: state.header.frameId),
      );
      track.times.add(record.logTime);
      track.positions.add(state.position);
    }
  }

  McapReviewIndex snapshot(String path) {
    if (_endTime == 0 || _startTime > _endTime) {
      throw const FormatException('MCAP 里没有消息');
    }

    final cameras =
        _frames.keys.map((id) => (id, _channels[id]!.topic)).toList()
          ..sort((a, b) => a.$2.compareTo(b.$2));
    final leftCamera =
        _pick(cameras, const ['fisheye_l', 'left']) ??
        (cameras.isEmpty ? null : cameras.first);
    var rightCamera = _pick(cameras, const ['fisheye_r', 'right']);
    if (rightCamera == leftCamera) {
      rightCamera = null;
      for (final camera in cameras) {
        if (camera.$2 != leftCamera?.$2) {
          rightCamera = camera;
          break;
        }
      }
    }

    final jointTopics = _joints.keys.toList()..sort();
    final leftJoint =
        _pickTopic(jointTopics, const ['arm_L', 'left']) ??
        (jointTopics.isEmpty ? null : jointTopics.first);
    var rightJoint = _pickTopic(jointTopics, const ['arm_R', 'right']);
    if (rightJoint == null || rightJoint == leftJoint) {
      rightJoint = null;
      for (final topic in jointTopics) {
        if (topic != leftJoint) {
          rightJoint = topic;
          break;
        }
      }
    }

    final meta = _imageMeta[leftCamera?.$1] ?? _imageMeta[rightCamera?.$1];
    return McapReviewIndex(
      path: path,
      startTime: _startTime,
      endTime: _endTime,
      width: meta?.width ?? 0,
      height: meta?.height ?? 0,
      leftCamera: leftCamera?.$2,
      rightCamera: rightCamera?.$2,
      leftFrames: _sortedFrames(
        leftCamera == null ? null : _frames[leftCamera.$1],
      ),
      rightFrames: _sortedFrames(
        rightCamera == null ? null : _frames[rightCamera.$1],
      ),
      leftArm: leftJoint == null ? null : _joints[leftJoint],
      rightArm: rightJoint == null ? null : _joints[rightJoint],
    );
  }
}

(int, String)? _pick(List<(int, String)> options, List<String> needles) {
  for (final option in options) {
    final topic = option.$2.toLowerCase();
    if (needles.any(topic.contains)) return option;
  }
  return null;
}

String? _pickTopic(List<String> topics, List<String> needles) {
  final wanted = needles.map((needle) => needle.toLowerCase()).toList();
  for (final topic in topics) {
    final lower = topic.toLowerCase();
    if (wanted.any(lower.contains)) return topic;
  }
  return null;
}

List<McapFrameRef> _sortedFrames(List<McapFrameRef>? input) {
  if (input == null) return const [];
  return [...input]..sort((a, b) => a.time.compareTo(b.time));
}
