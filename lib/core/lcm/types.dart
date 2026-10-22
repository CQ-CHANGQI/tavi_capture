import 'dart:typed_data';

/// One LCM message received on [channel].
class LcmMessage {
  const LcmMessage({required this.channel, required this.payload});

  /// LCM channel name (e.g. `/preview/joint_batch`).
  final String channel;

  /// Raw LCM message body. Starts with the 8-byte type fingerprint.
  final Uint8List payload;
}

/// Counters owned by the receiver. The UI reads them on its refresh ticker.
///
/// The frame counters are filled by `ChunkedPreviewAssembler` and tell packet
/// loss apart from render lag:
///
///   datagrams  → [messages] : LCM framing / channel filter
///   messages   → frames     : chunked frames that never completed
///   frames     → pixels     : decode/render on the UI side
class LcmStats {
  int datagrams = 0;
  int messages = 0;
  int droppedFragments = 0;
  int parseErrors = 0;

  /// Chunk sets abandoned because a chunk never arrived.
  int incompleteFrames = 0;

  /// Chunk sets that completed but did not form a valid image.
  int corruptFrames = 0;

  /// Incomplete chunk sets currently buffered by the assembler.
  int pendingFrames = 0;

  /// Interfaces this client successfully joined the multicast group on.
  List<String> joinedInterfaces = const <String>[];

  void reset() {
    datagrams = 0;
    messages = 0;
    droppedFragments = 0;
    parseErrors = 0;
    incompleteFrames = 0;
    corruptFrames = 0;
    pendingFrames = 0;
  }

  /// Applies a snapshot without replacing the object, so widgets holding
  /// `stats` keep seeing live values.
  void applySnapshot(Map<String, Object?> snapshot) {
    datagrams = _int(snapshot['datagrams']) ?? datagrams;
    messages = _int(snapshot['messages']) ?? messages;
    droppedFragments = _int(snapshot['droppedFragments']) ?? droppedFragments;
    parseErrors = _int(snapshot['parseErrors']) ?? parseErrors;
    incompleteFrames = _int(snapshot['incompleteFrames']) ?? incompleteFrames;
    corruptFrames = _int(snapshot['corruptFrames']) ?? corruptFrames;
    pendingFrames = _int(snapshot['pendingFrames']) ?? pendingFrames;
    final interfaces = snapshot['joinedInterfaces'];
    if (interfaces is List) {
      joinedInterfaces = interfaces.whereType<String>().toList(growable: false);
    }
  }

  static int? _int(Object? value) => value is int ? value : null;
}
