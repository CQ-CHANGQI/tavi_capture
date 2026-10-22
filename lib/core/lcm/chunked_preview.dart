import 'dart:math' as math;
import 'dart:typed_data';

import 'codec.dart';
import 'types.dart';

/// Bytes in one `preview_package_t` header, fingerprint included.
const int previewHeaderBytes = 36;

/// Payload bytes the robot packs into each `preview_package_t` fragment.
const int previewFragmentPayload = 1200;

/// Max in-flight (incomplete) frames retained per camera.
const int previewMaxFramesPerStream = 3;

/// Upper bound on pooled assembly buffers.
const int previewBufferPoolCapacity = 24;

/// Safety bound on one preview image (a 360P frame is far smaller).
const int previewMaxFrameBytes = 512 * 1024;

/// Safety bound on one fragmented `joint_batch_t` (~21 KB on the wire).
const int previewMaxJointBytes = 512 * 1024;

/// One decoded LCM `preview_package_t` message (a fragment of a preview JPEG
/// or of a serialised `joint_batch_t`).
class PreviewPackage {
  const PreviewPackage({
    required this.messageId,
    required this.streamId,
    required this.fragmentIndex,
    required this.fragmentCount,
    required this.totalSize,
    required this.payload,
  });

  final int messageId;
  final int streamId;
  final int fragmentIndex;
  final int fragmentCount;
  final int totalSize;
  final Uint8List payload;
}

/// Decode the LCM `preview_package_t` wire format (all fields big-endian):
///
///   int64 hash, int64 message_id, int32 stream_id, int32 fragment_index,
///   int32 fragment_count, int32 total_size, int32 payload_size,
///   then `payload_size` bytes of payload (no extra length prefix).
///
/// Mirrors `decodePreviewPackage` in `PreviewReassemble.kt`: the type
/// fingerprint is skipped, not checked. Callers validate the fragment
/// metadata before using it.
PreviewPackage? decodePreviewPackage(Uint8List bytes) {
  if (bytes.length < previewHeaderBytes) return null;
  final data = ByteData.sublistView(bytes);
  final messageId = data.getInt64(8, Endian.big);
  final streamId = data.getInt32(16, Endian.big);
  final fragmentIndex = data.getInt32(20, Endian.big);
  final fragmentCount = data.getInt32(24, Endian.big);
  final totalSize = data.getInt32(28, Endian.big);
  final payloadSize = data.getInt32(32, Endian.big);

  if (fragmentCount <= 0 ||
      fragmentIndex < 0 ||
      fragmentIndex >= fragmentCount ||
      totalSize <= 0 ||
      payloadSize < 0 ||
      payloadSize > bytes.length - previewHeaderBytes) {
    return null;
  }

  return PreviewPackage(
    messageId: messageId,
    streamId: streamId,
    fragmentIndex: fragmentIndex,
    fragmentCount: fragmentCount,
    totalSize: totalSize,
    payload: Uint8List.sublistView(
      bytes,
      previewHeaderBytes,
      previewHeaderBytes + payloadSize,
    ),
  );
}

/// Reassembles the robot's fragmented preview frames.
///
/// Wire format (the robot's `preview_package_t`, 1200-byte fragments):
///
/// ```
/// 8B  fingerprint
/// 8B  message_id          (unique per frame; timestamp_ns or a counter)
/// 4B  stream_id
/// 4B  fragment_index
/// 4B  fragment_count
/// 4B  total_size
/// 4B  fragment data length (1200, the last fragment shorter)
/// NB  JPEG/PNG slice
/// ```
///
/// The policy mirrors the Compose client (`PreviewReassemble.kt`), which is
/// what makes four 360p streams at 30 fps cheap to receive:
///
/// * **Strict contract** — `fragment_count == ceil(total / 1200)` and every
///   payload is exactly `min(1200, total - offset)`. A fragment that breaks the
///   contract is dropped before it can poison a frame.
/// * **Bounded, loss-tolerant** — up to [previewMaxFramesPerStream] in-flight
///   frames per camera, keyed by `message_id`. A frame that lost a fragment never
///   blocks later frames; when the slots are full the oldest incomplete frame
///   is evicted immediately (no expiry window, no head-of-line blocking).
/// * **Pooled buffers** — assembly buffers are reused, so steady state does not
///   allocate a frame buffer per frame; the completed image is copied out once.
class ChunkedPreviewAssembler {
  ChunkedPreviewAssembler({this.stats});

  /// Optional counters; abandoned/corrupt frames are recorded here.
  final LcmStats? stats;

  final Map<String, List<_Frame>> _streams = <String, List<_Frame>>{};
  final List<Uint8List> _pool = <Uint8List>[];

  /// Incomplete frames currently buffered (diagnostics).
  int get pendingFrames {
    var count = 0;
    for (final frames in _streams.values) {
      count += frames.length;
    }
    return count;
  }

  /// Feeds one LCM payload; returns a full image when this fragment completes
  /// it. Returns null for incomplete frames and non-chunked payloads.
  PreviewImage? add(String channel, Uint8List payload) {
    final package = decodePreviewPackage(payload);
    return package == null ? null : addPackage(channel, package);
  }

  /// Feeds one decoded fragment; returns a full image when it completes one.
  PreviewImage? addPackage(String channel, PreviewPackage package) {
    final offset = _validate(package);
    if (offset == null) {
      stats?.parseErrors++;
      return null;
    }

    final frames = _streams.putIfAbsent(channel, () => <_Frame>[]);
    var frame = _frameById(frames, package.messageId);
    if (frame == null) {
      if (frames.length >= previewMaxFramesPerStream) {
        // No head-of-line blocking: recycle the oldest incomplete frame and
        // reuse its slot for the fragment that just arrived.
        final victim = _oldest(frames);
        frames.remove(victim);
        _recycle(victim.buffer);
        stats?.incompleteFrames++;
      }
      frame = _Frame(
        package.messageId,
        package.streamId,
        package.totalSize,
        package.fragmentCount,
        _obtain(package.totalSize),
      );
      frames.add(frame);
    } else if (frame.streamId != package.streamId ||
        frame.total != package.totalSize ||
        frame.count != package.fragmentCount) {
      // Same message_id, different shape: ignore instead of corrupting.
      stats?.parseErrors++;
      return null;
    }

    if (frame.received[package.fragmentIndex]) {
      return null; // duplicate fragment
    }
    frame.received[package.fragmentIndex] = true;
    frame.receivedCount++;
    frame.buffer.setRange(
      offset,
      offset + package.payload.length,
      package.payload,
    );
    if (frame.receivedCount < package.fragmentCount) return null;

    // Complete: copy out before recycling, then hand the image to the caller.
    frames.remove(frame);
    final image = Uint8List(package.totalSize);
    image.setRange(0, package.totalSize, frame.buffer);
    _recycle(frame.buffer);

    // The Compose client hands the assembled bytes straight to its image
    // decoder; Flutter rejects non-images here so a corrupt frame never
    // reaches `ui.decodeImage`.
    if (!_looksLikeImage(image)) {
      stats?.corruptFrames++;
      return null;
    }
    final size = _imageSize(image);
    return PreviewImage(
      camera: channel.split('/').last,
      width: size?.$1 ?? 0,
      height: size?.$2 ?? 0,
      bytes: image,
    );
  }

  /// Validates one fragment's metadata and returns its destination offset, or
  /// null if the fragment is illegal and must be dropped without touching any
  /// frame. Enforces the sender contract: `fragment_count == ceil(total / 1200)`
  /// and each fragment's payload is exactly `min(1200, total - offset)`.
  int? _validate(PreviewPackage package) {
    if (package.totalSize <= 0 || package.totalSize > previewMaxFrameBytes) {
      return null;
    }
    final expectedCount =
        (package.totalSize + previewFragmentPayload - 1) ~/
        previewFragmentPayload;
    if (package.fragmentCount != expectedCount) return null;
    if (package.fragmentIndex < 0 ||
        package.fragmentIndex >= package.fragmentCount) {
      return null;
    }
    final offset = package.fragmentIndex * previewFragmentPayload;
    if (offset >= package.totalSize) return null;
    final expectedPayload = math.min(
      previewFragmentPayload,
      package.totalSize - offset,
    );
    if (package.payload.length != expectedPayload) return null;
    return offset;
  }

  /// The oldest unfinished frame: the Compose client sorts by `message_id`
  /// (a timestamp_ns for the robot's preview stream).
  static _Frame _oldest(List<_Frame> frames) {
    var oldest = frames.first;
    for (final frame in frames.skip(1)) {
      if (frame.messageId < oldest.messageId) oldest = frame;
    }
    return oldest;
  }

  static _Frame? _frameById(List<_Frame> frames, int messageId) {
    for (final frame in frames) {
      if (frame.messageId == messageId) return frame;
    }
    return null;
  }

  Uint8List _obtain(int size) {
    var bestIndex = -1;
    var bestSize = 1 << 62;
    for (var i = 0; i < _pool.length; i++) {
      final pooled = _pool[i].length;
      if (pooled >= size && pooled < bestSize) {
        bestSize = pooled;
        bestIndex = i;
      }
    }
    if (bestIndex >= 0) return _pool.removeAt(bestIndex);
    return Uint8List(size);
  }

  void _recycle(Uint8List buffer) {
    if (_pool.length < previewBufferPoolCapacity) _pool.add(buffer);
  }
}

/// Reassembles the fragmented `joint_batch_t` stream.
///
/// The robot's joint bridge (`joint_preview_bridge.cpp`) serialises each
/// `joint_batch_t` and publishes it as 1200-byte `preview_package_t`
/// fragments on `/preview/joint_batch`, so the receiver must reassemble the
/// fragments before [decodeJointBatch] can run. Mirrors `JointBatchAssembler`
/// in `JointBatchDecode.kt`: one batch in flight, keyed by `message_id`;
/// duplicate and late fragments are ignored.
class JointBatchAssembler {
  JointBatchAssembler(this.onBatch);

  final void Function(List<JointFrame> frames) onBatch;

  int _messageId = 0;
  int _fragmentCount = 0;
  int _totalSize = 0;
  int _received = 0;
  Uint8List _buffer = Uint8List(0);
  List<bool> _got = const <bool>[];

  void add(PreviewPackage package) {
    if (_buffer.isEmpty || package.messageId != _messageId) {
      if (package.totalSize > previewMaxJointBytes) return;
      _messageId = package.messageId;
      _fragmentCount = package.fragmentCount;
      _totalSize = package.totalSize;
      _received = 0;
      _buffer = Uint8List(package.totalSize);
      _got = List<bool>.filled(package.fragmentCount, false);
    } else if (_received >= _fragmentCount) {
      return; // batch already emitted; ignore stray late fragments
    }

    if (package.fragmentIndex >= _got.length) return; // inconsistent metadata
    if (_got[package.fragmentIndex]) return; // duplicate fragment
    final offset = package.fragmentIndex * previewFragmentPayload;
    if (offset >= _totalSize) return;
    final end = math.min(offset + package.payload.length, _totalSize);
    _buffer.setRange(offset, end, package.payload);
    _got[package.fragmentIndex] = true;
    _received++;

    if (_received < _fragmentCount) return;
    final frames = decodeJointBatch(_buffer);
    if (frames != null && frames.isNotEmpty) onBatch(frames);
  }
}

class _Frame {
  _Frame(this.messageId, this.streamId, this.total, this.count, this.buffer)
    : received = List<bool>.filled(count, false);

  final int messageId;
  final int streamId;
  final int total;
  final int count;
  final Uint8List buffer;
  final List<bool> received;
  int receivedCount = 0;
}

bool _looksLikeImage(Uint8List bytes) {
  if (bytes.length < 4) return false;
  if (bytes[0] == 0xFF && bytes[1] == 0xD8) return true; // JPEG SOI
  return bytes[0] == 0x89 && // PNG signature
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47;
}

/// Reads width/height from a PNG IHDR chunk or a JPEG SOF marker.
(int, int)? _imageSize(Uint8List bytes) {
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
    return (data.getUint32(16, Endian.big), data.getUint32(20, Endian.big));
  }
  var i = 2;
  while (i + 9 < bytes.length) {
    if (bytes[i] != 0xFF) {
      i++;
      continue;
    }
    final marker = bytes[i + 1];
    i += 2;
    if (marker == 0xD8 ||
        marker == 0xD9 ||
        (marker >= 0xD0 && marker <= 0xD7)) {
      continue;
    }
    if (i + 2 > bytes.length) return null;
    final length = (bytes[i] << 8) | bytes[i + 1];
    if (length < 2 || i + length > bytes.length) return null;
    if ((marker >= 0xC0 && marker <= 0xC3) ||
        (marker >= 0xC5 && marker <= 0xC7) ||
        (marker >= 0xC9 && marker <= 0xCB) ||
        (marker >= 0xCD && marker <= 0xCF)) {
      if (i + 7 >= bytes.length) return null;
      final height = (bytes[i + 3] << 8) | bytes[i + 4];
      final width = (bytes[i + 5] << 8) | bytes[i + 6];
      return (width, height);
    }
    i += length;
  }
  return null;
}
