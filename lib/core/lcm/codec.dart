import 'dart:convert';
import 'dart:typed_data';

/// One complete camera frame (reassembled JPEG/PNG bytes).
class PreviewImage {
  const PreviewImage({
    required this.camera,
    required this.width,
    required this.height,
    required this.bytes,
  });

  final String camera;
  final int width;
  final int height;

  /// Image payload (JPEG from the robot; PNG works too, e.g. the mock).
  final Uint8List bytes;
}

/// One controller-manager introspection frame inside a `joint_batch_t`.
class JointFrame {
  const JointFrame({
    required this.timestampNs,
    required this.stateNames,
    required this.commandNames,
    required this.stateValues,
    required this.commandValues,
  });

  final int timestampNs;
  final List<String> stateNames;
  final List<String> commandNames;
  final List<double> stateValues;
  final List<double> commandValues;
}

// ---------------------------------------------------------------------------
// joint_batch_t
// ---------------------------------------------------------------------------

/// Decode the LCM `joint_batch_t` wire format (all fields big-endian):
///
///   int32 num_frames, int64 timestamp_ns[10], string state_names[10],
///   string command_names[10], int32 state_value_count[10],
///   int32 command_value_count[10], double state_values[10][128],
///   double command_values[10][128].
///
/// Fixed-size arrays have no length prefix; the counts say how much of each
/// 128-wide row is real. Mirrors `JointBatchDecode.kt`.
List<JointFrame>? decodeJointBatch(Uint8List bytes) {
  if (bytes.length < 16) return null;
  try {
    final d = ByteData.sublistView(bytes);
    var p = 8; // 8-byte fingerprint

    final numFrames = d.getInt32(p, Endian.big);
    p += 4;
    if (numFrames < 0 || numFrames > 10) return null;

    final timestamps = List<int>.generate(10, (_) {
      final v = d.getInt64(p, Endian.big);
      p += 8;
      return v;
    }, growable: false);

    final stateNames = <String>[];
    for (var i = 0; i < 10; i++) {
      final r = _readString(bytes, p);
      if (r == null) return null;
      stateNames.add(r.$1);
      p = r.$2;
    }

    final commandNames = <String>[];
    for (var i = 0; i < 10; i++) {
      final r = _readString(bytes, p);
      if (r == null) return null;
      commandNames.add(r.$1);
      p = r.$2;
    }

    final stateCounts = List<int>.generate(10, (_) {
      final v = d.getInt32(p, Endian.big);
      p += 4;
      return v;
    }, growable: false);

    final commandCounts = List<int>.generate(10, (_) {
      final v = d.getInt32(p, Endian.big);
      p += 4;
      return v;
    }, growable: false);

    final stateValues = List<List<double>>.generate(10, (_) {
      return List<double>.generate(128, (_) {
        final v = d.getFloat64(p, Endian.big);
        p += 8;
        return v;
      }, growable: false);
    }, growable: false);

    final commandValues = List<List<double>>.generate(10, (_) {
      return List<double>.generate(128, (_) {
        final v = d.getFloat64(p, Endian.big);
        p += 8;
        return v;
      }, growable: false);
    }, growable: false);

    final frames = <JointFrame>[];
    for (var i = 0; i < numFrames; i++) {
      final stateCount = _clampCount(stateCounts[i]);
      final commandCount = _clampCount(commandCounts[i]);
      frames.add(
        JointFrame(
          timestampNs: timestamps[i],
          stateNames: _splitNames(stateNames[i]),
          commandNames: _splitNames(commandNames[i]),
          stateValues: stateValues[i].take(stateCount).toList(growable: false),
          commandValues: commandValues[i]
              .take(commandCount)
              .toList(growable: false),
        ),
      );
    }
    return frames;
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Reads one LCM string; returns (value, offset just past the string).
(String, int)? _readString(Uint8List bytes, int offset) {
  if (offset < 0 || offset + 4 > bytes.length) return null;
  final len = ByteData.sublistView(bytes).getInt32(offset, Endian.big);
  if (len < 1 || offset + 4 + len > bytes.length) return null;
  final value = utf8.decode(
    bytes.sublist(offset + 4, offset + 4 + len - 1),
    allowMalformed: true,
  );
  return (value, offset + 4 + len);
}

List<String> _splitNames(String value) =>
    value.split('\n').where((s) => s.isNotEmpty).toList(growable: false);

int _clampCount(int value) {
  if (value < 0) return 0;
  if (value > 128) return 128;
  return value;
}
