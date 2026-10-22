import 'dart:convert';
import 'dart:typed_data';

import '../telemetry/sample.dart';

class LcmMessage {
  const LcmMessage(this.channel, this.data);
  final String channel;
  final Uint8List data;
}

/// LCM transport fragments and application preview fragments are separate.
/// Both pools are bounded; malformed packets never allocate unbounded memory.
class LcmDecoder {
  final _transport = <String, _Assembly>{};
  final _preview = <String, Map<int, _Assembly>>{};
  final _completed = <String, int>{};
  int malformed = 0;
  int dropped = 0;

  LcmMessage? datagram(Uint8List bytes, String sender) {
    try {
      final r = _BigReader(bytes);
      final magic = r.i32();
      final sequence = r.i32();
      if (magic == 0x4c433032) {
        final channel = r.channel();
        return LcmMessage(channel, r.rest());
      }
      if (magic != 0x4c433033) throw const FormatException('LCM magic');
      final total = r.i32();
      final offset = r.i32();
      final number = r.u16();
      final count = r.u16();
      final channel = number == 0 ? r.channel() : null;
      final payload = r.rest();
      if (total <= 0 ||
          total > 512 * 1024 ||
          count < 1 ||
          count > 1024 ||
          number >= count ||
          offset < 0 ||
          offset + payload.length > total) {
        throw const FormatException('LCM fragment bounds');
      }
      final key = '$sender/$sequence';
      if (!_transport.containsKey(key) && _transport.length >= 32) {
        _transport.remove(_transport.keys.first);
        dropped++;
      }
      final a = _transport.putIfAbsent(key, () => _Assembly(total, count));
      if (a.bytes.length != total ||
          a.parts.length != count ||
          (channel != null && a.channel != null && channel != a.channel)) {
        throw const FormatException('LCM fragment shape changed');
      }
      a.channel ??= channel;
      a.add(number, offset, payload);
      if (!a.complete || a.channel == null) return null;
      _transport.remove(key);
      // Check coverage as well as fragment numbers (overlapping fragments
      // must not make zero-filled holes look like a complete message).
      if (!a.covered) throw const FormatException('LCM fragment coverage');
      return LcmMessage(a.channel!, a.bytes);
    } on FormatException {
      malformed++;
      return null;
    }
  }

  /// A complete JPEG/PNG or serialized joint_batch_t, from 1200-byte pieces.
  Uint8List? preview(String stream, Uint8List bytes) {
    try {
      final r = _BigReader(bytes)..skip(8); // type fingerprint
      final id = r.i64();
      final streamId = r.i32();
      final index = r.i32();
      final count = r.i32();
      final total = r.i32();
      final length = r.i32();
      final offset = index * 1200;
      if (total <= 0 ||
          total > 512 * 1024 ||
          count != (total + 1199) ~/ 1200 ||
          index < 0 ||
          index >= count ||
          length != (total - offset).clamp(0, 1200) ||
          r.remaining != length) {
        throw const FormatException('Preview fragment bounds');
      }
      final key = '$stream/$streamId';
      if (id <= (_completed[key] ?? -1)) return null;
      final frames = _preview.putIfAbsent(key, () => {});
      if (!frames.containsKey(id) && frames.length >= 3) {
        final oldest = frames.keys.reduce((a, b) => a < b ? a : b);
        if (id < oldest) return null;
        frames.remove(oldest);
        dropped++;
      }
      final a = frames.putIfAbsent(id, () => _Assembly(total, count));
      if (a.bytes.length != total || a.parts.length != count) {
        throw const FormatException('Preview shape changed');
      }
      a.add(index, offset, r.rest());
      if (!a.complete) return null;
      frames.remove(id);
      _completed[key] = id;
      // Once a newer frame is complete, older frames are no longer useful.
      frames.removeWhere((old, _) => old < id);
      return a.bytes;
    } on FormatException {
      malformed++;
      return null;
    }
  }

  void expire() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 2));
    _transport.removeWhere((_, a) {
      if (a.updated.isAfter(cutoff)) return false;
      dropped++;
      return true;
    });
    for (final frames in _preview.values) {
      frames.removeWhere((_, a) {
        if (a.updated.isAfter(cutoff)) return false;
        dropped++;
        return true;
      });
    }
    // Publisher restart may reset its sequence IDs.
    if (_preview.values.every((frames) => frames.isEmpty)) {
      _completed.clear();
    }
  }
}

List<JointSample> decodeLcmJoints(Uint8List bytes) {
  final r = _BigReader(bytes)..skip(8);
  final count = r.i32();
  if (count < 0 || count > 10) throw const FormatException('Joint frame count');
  final times = List.generate(10, (_) => r.i64());
  final states = List.generate(10, (_) => r.string().split('\n'));
  final commands = List.generate(10, (_) => r.string().split('\n'));
  final stateCounts = List.generate(10, (_) => r.i32());
  final commandCounts = List.generate(10, (_) => r.i32());
  final stateValues = List.generate(
    10,
    (_) => List.generate(128, (_) => r.f64()),
  );
  final commandValues = List.generate(
    10,
    (_) => List.generate(128, (_) => r.f64()),
  );
  Map<String, double> values(List<String> names, List<double> data, int n) {
    if (n < 0 || n > 128 || names.length < n) {
      throw const FormatException('Joint names/count mismatch');
    }
    return {
      for (var i = 0; i < n; i++)
        if (names[i].endsWith('/position') && data[i].isFinite)
          names[i].replaceFirst('/position', ''): data[i],
    };
  }

  return [
    for (var i = 0; i < count; i++)
      JointSample(
        times[i],
        values(states[i], stateValues[i], stateCounts[i]),
        values(commands[i], commandValues[i], commandCounts[i]),
      ),
  ];
}

class _Assembly {
  _Assembly(int total, int count)
    : bytes = Uint8List(total),
      parts = List.filled(count, false);
  final Uint8List bytes;
  final List<bool> parts;
  final spans = <(int, int)>[];
  int received = 0;
  String? channel;
  DateTime updated = DateTime.now();
  bool get complete => received == parts.length;
  bool get covered {
    spans.sort((a, b) => a.$1.compareTo(b.$1));
    var end = 0;
    for (final span in spans) {
      if (span.$1 != end) return false;
      end = span.$2;
    }
    return end == bytes.length;
  }

  void add(int index, int offset, Uint8List payload) {
    if (parts[index]) return;
    bytes.setRange(offset, offset + payload.length, payload);
    parts[index] = true;
    spans.add((offset, offset + payload.length));
    received++;
    updated = DateTime.now();
  }
}

class _BigReader {
  _BigReader(this.bytes) : data = ByteData.sublistView(bytes);
  final Uint8List bytes;
  final ByteData data;
  int offset = 0;
  int get remaining => bytes.length - offset;
  void skip(int n) {
    if (n < 0 || n > remaining) throw const FormatException('Truncated LCM');
    offset += n;
  }

  int i32() {
    skip(4);
    return data.getInt32(offset - 4);
  }

  int i64() {
    skip(8);
    return data.getInt64(offset - 8);
  }

  int u16() {
    skip(2);
    return data.getUint16(offset - 2);
  }

  double f64() {
    skip(8);
    return data.getFloat64(offset - 8);
  }

  String channel() {
    final end = bytes.indexOf(0, offset);
    if (end <= offset || end - offset > 256) {
      throw const FormatException('LCM channel');
    }
    final result = utf8.decode(bytes.sublist(offset, end));
    offset = end + 1;
    return result;
  }

  String string() {
    final n = i32();
    if (n < 1 || n > 65536) throw const FormatException('LCM string');
    skip(n);
    return utf8.decode(bytes.sublist(offset - n, offset - 1));
  }

  Uint8List rest() => Uint8List.sublistView(bytes, offset);
}
