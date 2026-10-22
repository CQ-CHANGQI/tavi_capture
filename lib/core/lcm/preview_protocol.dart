import 'dart:math' as math;
import 'dart:typed_data';

import 'lcm_message.dart';

/// 相机通道前缀，通道最后一段就是相机名。
const String cameraChannelPrefix = '/preview/cameras/';

/// 关节批量数据的通道。
const String jointBatchChannel = '/preview/joint_batch';

/// preview_package_t 头部长度（含 8 字节类型指纹）。
const int previewChunkHeaderBytes = 36;
const int previewChunkPayloadBytes = 1200;
const int previewMaxFrameBytes = 512 * 1024;

/// 一张完整的相机画面（JPEG/PNG 字节）。
class CameraFrame {
  const CameraFrame(this.camera, this.image);

  final String camera;
  final Uint8List image;
}

/// 一帧关节数据：状态和指令按关节名对齐。
class JointBatch {
  const JointBatch(this.timestampNs, this.state, this.command);

  final int timestampNs;
  final Map<String, double> state;
  final Map<String, double> command;
}

/// preview_package_t：大端
///   hash(8) messageId(8) streamId(4) index(4) count(4) total(4) length(4)
///   payload[length]
class PreviewChunk {
  const PreviewChunk({
    required this.messageId,
    required this.streamId,
    required this.index,
    required this.count,
    required this.totalBytes,
    required this.payload,
  });

  final int messageId;
  final int streamId;
  final int index;
  final int count;
  final int totalBytes;
  final Uint8List payload;
}

/// 解析一个 preview 分片。分片契约不成立就返回 null（坏包不进缓冲区）。
PreviewChunk? readPreviewChunk(Uint8List bytes) {
  if (bytes.length < previewChunkHeaderBytes) return null;
  final data = ByteData.sublistView(bytes);
  final messageId = data.getInt64(8);
  final streamId = data.getInt32(16);
  final index = data.getInt32(20);
  final count = data.getInt32(24);
  final totalBytes = data.getInt32(28);
  final length = data.getInt32(32);

  if (totalBytes <= 0 ||
      totalBytes > previewMaxFrameBytes ||
      count <= 0 ||
      index < 0 ||
      index >= count ||
      length < 0 ||
      previewChunkHeaderBytes + length > bytes.length) {
    return null;
  }
  // 机器人固定按 1200 字节切片；片数和每片长度都必须对得上。
  final expectedCount =
      (totalBytes + previewChunkPayloadBytes - 1) ~/ previewChunkPayloadBytes;
  final expectedLength = math.min(
    previewChunkPayloadBytes,
    totalBytes - index * previewChunkPayloadBytes,
  );
  if (count != expectedCount || length != expectedLength) return null;

  return PreviewChunk(
    messageId: messageId,
    streamId: streamId,
    index: index,
    count: count,
    totalBytes: totalBytes,
    payload: Uint8List.sublistView(
      bytes,
      previewChunkHeaderBytes,
      previewChunkHeaderBytes + length,
    ),
  );
}

/// 按流重组 preview_package_t。每条流最多保留 [maxFramesPerStream] 个半成品，
/// 丢了片的帧立刻丢弃，不阻塞后面的帧。
class PreviewAssembler {
  PreviewAssembler({this.maxFramesPerStream = 3, LcmCounters? counters})
    : counters = counters ?? LcmCounters();

  final int maxFramesPerStream;
  final LcmCounters counters;
  final Map<String, _Stream> _streams = {};

  int get pendingFrames =>
      _streams.values.fold(0, (sum, stream) => sum + stream.frames.length);

  Uint8List? add(String streamKey, PreviewChunk chunk) {
    final stream = _streams.putIfAbsent(streamKey, _Stream.new);

    if (chunk.messageId <= stream.lastCompleted) {
      counters.dropped++;
      return null;
    }

    var pending = stream.find(chunk.messageId);
    if (pending == null) {
      while (stream.frames.length >= maxFramesPerStream) {
        stream.frames.removeAt(0);
        counters.incomplete++;
      }
      pending = _PendingFrame(
        chunk.messageId,
        FragmentBuffer(chunk.totalBytes, chunk.count),
      );
      stream.frames.add(pending);
    } else if (pending.buffer.totalBytes != chunk.totalBytes ||
        pending.buffer.partCount != chunk.count) {
      stream.frames.remove(pending);
      counters.corrupt++;
      return null;
    }

    try {
      pending.buffer.write(
        chunk.index,
        chunk.index * previewChunkPayloadBytes,
        chunk.payload,
      );
    } on FormatException {
      stream.frames.remove(pending);
      counters.corrupt++;
      return null;
    }

    if (!pending.buffer.isComplete) return null;

    stream.frames.remove(pending);
    stream.lastCompleted = chunk.messageId;
    stream.frames.removeWhere((other) => other.id < chunk.messageId);
    if (!pending.buffer.isContiguous) {
      counters.incomplete++;
      return null;
    }
    return pending.buffer.bytes;
  }

  void reset() => _streams.clear();
}

class _Stream {
  final List<_PendingFrame> frames = [];
  int lastCompleted = -1;

  _PendingFrame? find(int messageId) {
    for (final frame in frames) {
      if (frame.id == messageId) return frame;
    }
    return null;
  }
}

class _PendingFrame {
  _PendingFrame(this.id, this.buffer);

  final int id;
  final FragmentBuffer buffer;
}

/// 通道 → 画面 / 关节。相机和关节都可能被 preview_package_t 包一层。
class PreviewRouter {
  PreviewRouter({
    required this.onCameraFrame,
    required this.onJointBatches,
    this.allChannels = false,
    LcmCounters? counters,
  }) : counters = counters ?? LcmCounters() {
    assembler = PreviewAssembler(counters: this.counters);
  }

  final void Function(CameraFrame frame) onCameraFrame;
  final void Function(List<JointBatch> batches) onJointBatches;

  /// `LCM_ALL=true` 时接收全部通道，未知通道也尝试按相机/关节解。
  final bool allChannels;
  final LcmCounters counters;
  late final PreviewAssembler assembler;

  int get pendingFrames => assembler.pendingFrames;

  void handle(LcmMessage message) {
    final channel = message.channel;
    if (channel.startsWith(cameraChannelPrefix)) {
      _camera(channel.substring(cameraChannelPrefix.length), message.payload);
      return;
    }
    if (channel == jointBatchChannel) {
      _joint(message.payload);
      return;
    }
    if (!allChannels) return;

    // 未知通道：名字里带 joint 的按关节处理；否则先试 preview 分片，
    // 通道最后一段当相机名（参考实现的 LCM_ALL 行为）。
    if (channel.toLowerCase().contains('joint')) {
      _joint(message.payload);
      return;
    }
    final chunk = readPreviewChunk(message.payload);
    if (chunk == null) return;
    _camera(_cameraNameOf(channel), message.payload);
  }

  /// 从任意通道名里找出相机槽位，例如
  /// `/gripper/camera_fisheye_l/color` → `cam_left`。
  static String _cameraNameOf(String channel) {
    final parts = channel.split('/');
    for (final part in parts) {
      if (part.isEmpty) continue;
      final slot = _cameraSlot(part);
      if (slot != part) return slot;
    }
    return parts.lastWhere((part) => part.isNotEmpty, orElse: () => '');
  }

  static String _cameraSlot(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('head') || lower.contains('main')) return 'cam_head';
    if (lower.contains('left') || lower.contains('fisheye_l')) {
      return 'cam_left';
    }
    if (lower.contains('right') || lower.contains('fisheye_r')) {
      return 'cam_right';
    }
    if (lower.contains('chest') || lower.contains('pan')) return 'cam_chest';
    return name;
  }

  void _camera(String camera, Uint8List payload) {
    final chunk = readPreviewChunk(payload);
    if (chunk == null) {
      counters.corrupt++;
      return;
    }
    if (camera.isEmpty) {
      counters.corrupt++;
      return;
    }
    final image = assembler.add('$camera/${chunk.streamId}', chunk);
    if (image == null) return;
    if (!_isImage(image)) {
      counters.corrupt++;
      return;
    }
    onCameraFrame(CameraFrame(camera, image));
  }

  void _joint(Uint8List payload) {
    var data = payload;
    final chunk = readPreviewChunk(payload);
    if (chunk != null) {
      final assembled = assembler.add('joint/${chunk.streamId}', chunk);
      if (assembled == null) return;
      data = assembled;
    }
    try {
      final batches = decodeJointBatches(data);
      if (batches.isNotEmpty) onJointBatches(batches);
    } on FormatException {
      counters.corrupt++;
    }
  }

  static bool _isImage(Uint8List bytes) {
    if (bytes.length < 4) return false;
    final jpeg = bytes[0] == 0xFF && bytes[1] == 0xD8;
    final png =
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    return jpeg || png;
  }
}

/// 解码 joint_batch_t（大端，前 8 字节是类型指纹）：
///   int32 num_frames
///   int64 timestamp_ns[10]
///   string state_names[10]      // 每个是 '\n' 连接的关节名
///   string command_names[10]
///   int32 state_value_count[10]
///   int32 command_value_count[10]
///   double state_values[10][128]
///   double command_values[10][128]
///
/// 只保留 `/position` 后缀的项，名字去掉后缀后作为键。
List<JointBatch> decodeJointBatches(Uint8List payload) {
  final reader = BigEndianReader(payload);
  reader.skip(8);

  final frameCount = reader.int32;
  if (frameCount < 0 || frameCount > 10) {
    throw const FormatException('joint_batch 帧数越界');
  }

  final timestamps = [for (var i = 0; i < 10; i++) reader.int64];
  final stateNames = [for (var i = 0; i < 10; i++) reader.lcmString()];
  final commandNames = [for (var i = 0; i < 10; i++) reader.lcmString()];
  final stateCounts = [for (var i = 0; i < 10; i++) reader.int32];
  final commandCounts = [for (var i = 0; i < 10; i++) reader.int32];

  for (final count in [...stateCounts, ...commandCounts]) {
    if (count < 0 || count > 128) {
      throw const FormatException('joint_batch 关节数越界');
    }
  }

  final states = [
    for (var i = 0; i < 10; i++)
      _readRow(reader, stateNames[i], stateCounts[i]),
  ];
  final commands = [
    for (var i = 0; i < 10; i++)
      _readRow(reader, commandNames[i], commandCounts[i]),
  ];

  final batches = <JointBatch>[];
  for (var i = 0; i < frameCount; i++) {
    if (states[i].isEmpty && commands[i].isEmpty) continue;
    batches.add(JointBatch(timestamps[i], states[i], commands[i]));
  }
  return batches;
}

Map<String, double> _readRow(
  BigEndianReader reader,
  String joinedNames,
  int count,
) {
  final names = joinedNames.isEmpty
      ? const <String>[]
      : joinedNames.split('\n');
  final values = <String, double>{};
  for (var i = 0; i < 128; i++) {
    if (i >= count) {
      reader.skip(8);
      continue;
    }
    final value = reader.float64;
    if (i >= names.length || !value.isFinite) continue;
    final name = names[i];
    if (!name.endsWith('/position')) continue;
    values[name.substring(0, name.length - 9)] = value;
  }
  return values;
}

/// 从 JPEG/PNG 头部读尺寸；读不出来返回 null。
///
/// UI 解码前用它决定是否需要按显示尺寸降采样（4K/1080p 源解到 1280 宽就够了）。
(int, int)? imageSizeOf(Uint8List bytes) {
  if (bytes.length >= 24 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[12] == 0x49 && // IHDR
      bytes[13] == 0x48 &&
      bytes[14] == 0x44 &&
      bytes[15] == 0x52) {
    final data = ByteData.sublistView(bytes);
    return (data.getUint32(16), data.getUint32(20));
  }

  var offset = 2;
  while (offset + 9 < bytes.length) {
    if (bytes[offset] != 0xFF) {
      offset++;
      continue;
    }
    final marker = bytes[offset + 1];
    offset += 2;
    if (marker == 0xD8 ||
        marker == 0xD9 ||
        (marker >= 0xD0 && marker <= 0xD7)) {
      continue;
    }
    final length = (bytes[offset] << 8) | bytes[offset + 1];
    if (length < 2 || offset + length > bytes.length) return null;
    final isStartOfFrame =
        (marker >= 0xC0 && marker <= 0xC3) ||
        (marker >= 0xC5 && marker <= 0xC7) ||
        (marker >= 0xC9 && marker <= 0xCB) ||
        (marker >= 0xCD && marker <= 0xCF);
    if (isStartOfFrame) {
      if (offset + 7 >= bytes.length) return null;
      final height = (bytes[offset + 3] << 8) | bytes[offset + 4];
      final width = (bytes[offset + 5] << 8) | bytes[offset + 6];
      return (width, height);
    }
    offset += length;
  }
  return null;
}
