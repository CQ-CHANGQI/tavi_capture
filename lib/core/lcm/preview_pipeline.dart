import 'dart:typed_data';

import 'chunked_preview.dart';
import 'codec.dart';
import 'types.dart';

/// Channel routing + chunk reassembly + payload decoding.
///
/// This runs inside the receiver isolate, so the UI isolate never sees LCM
/// datagrams: it only receives complete frames (`PreviewImage`) and decoded
/// joint batches. That is the same split as the Compose client, where the
/// lcm-java reader thread does receive → validate → reassemble → decode and
/// the UI thread only paints.
///
/// Camera channels carry `preview_package_t` fragments (JPEG/PNG slices);
/// `/preview/joint_batch` carries a serialised `joint_batch_t`, also in
/// `preview_package_t` fragments on the real robot. Raw `joint_batch_t`
/// messages (the mock publisher) still decode directly.
class PreviewPipeline {
  PreviewPipeline({
    required this.onFrame,
    required this.onJoints,
    LcmStats? stats,
  }) : stats = stats ?? LcmStats();

  final void Function(PreviewImage image) onFrame;
  final void Function(List<JointFrame> frames) onJoints;
  final LcmStats stats;

  late final ChunkedPreviewAssembler _chunks = ChunkedPreviewAssembler(
    stats: stats,
  );
  late final JointBatchAssembler _jointChunks = JointBatchAssembler(onJoints);

  /// Incomplete chunk sets currently buffered (diagnostics).
  int get pendingFrames => _chunks.pendingFrames;

  void handle(LcmMessage message) {
    final channel = message.channel;
    final payload = message.payload;

    if (channel.startsWith('/preview/cameras/')) {
      _camera(channel, payload);
      return;
    }
    if (channel.contains('joint')) {
      _joint(payload);
      return;
    }

    // `LCM_ALL`/unknown channel: try each decoder once.
    if (_camera(channel, payload)) return;
    _joint(payload);
  }

  /// Returns true when [payload] is a camera fragment (complete or not).
  bool _camera(String channel, Uint8List payload) {
    final package = decodePreviewPackage(payload);
    if (package == null) return false;
    final image = _chunks.addPackage(channel, package);
    if (image != null) onFrame(image);
    return true;
  }

  void _joint(Uint8List payload) {
    final package = decodePreviewPackage(payload);
    if (package != null) {
      // The robot's joint bridge: preview_package_t fragments wrapping a
      // serialised joint_batch_t.
      _jointChunks.add(package);
      return;
    }
    final frames = decodeJointBatch(payload);
    if (frames == null || frames.isEmpty) return;
    onJoints(frames);
  }
}
