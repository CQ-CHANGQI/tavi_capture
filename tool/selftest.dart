// Self-test for the pure-Dart LCM layer. Run with:
//
//   dart run tool/selftest.dart
//
// It builds synthetic `preview_package_t` / `joint_batch_t` payloads, wraps them
// in LCM short and fragmented datagrams, and finally exercises the real UDP
// socket over loopback (no robot required).
//
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:tavi_capture/core/lcm/chunked_preview.dart';
import 'package:tavi_capture/core/lcm/codec.dart';
import 'package:tavi_capture/core/lcm/lcm_udp_client.dart';
import 'package:tavi_capture/core/lcm/preview_pipeline.dart';
import 'package:tavi_capture/core/lcm/types.dart';
import 'package:tavi_capture/core/lcm/udpm.dart';

void main() async {
  final stats = LcmStats();
  final decoder = LcmPacketDecoder();

  // --- LCM framing ---------------------------------------------------------
  final payload = Uint8List.fromList(
    List<int>.generate(3000, (i) => (i * 31) & 0xff),
  );
  final shortPayload = payload.sublist(0, 100);

  final shortMessage = decoder.decode(
    _shortPacket('/test', shortPayload),
    'test:1',
    stats,
  );
  _check(
    shortMessage != null &&
        shortMessage.channel == '/test' &&
        _sameBytes(shortMessage.payload, shortPayload),
    'short packet decodes',
  );

  // --- fragmented long packet ---------------------------------------------
  final fragments = _longPackets('/test', payload, chunkSize: 100);
  _check(fragments.length > 2, 'payload is fragmented');

  LcmMessage? assembled;
  for (final fragment in fragments.reversed) {
    final message = decoder.decode(fragment, 'test:1', stats);
    if (message != null) assembled = message;
  }
  _check(assembled != null, 'fragments reassemble out of order');
  _check(
    _sameBytes(assembled!.payload, payload),
    'reassembled payload matches the original',
  );

  // --- joint_batch_t ------------------------------------------------------
  final joint = decodeJointBatch(_jointPayload());
  _check(joint != null, 'joint_batch_t decodes');
  _check(joint!.length == 2, 'num_frames honoured');
  _check(joint.first.stateValues.length == 20, '20 state values honoured');
  _check(joint.first.commandValues.length == 20, '20 command values honoured');

  // --- chunked preview: message_id-keyed, bounded reassembly -------------
  {
    final chunkStats = LcmStats();
    final assembler = ChunkedPreviewAssembler(stats: chunkStats);
    final frameA = _chunkedJpeg(3000, 0x11);
    final frameB = _chunkedJpeg(3000, 0x22);

    // Frame A loses chunk 1.
    assembler.add(
      '/preview/cameras/front',
      _chunkPacket(1, 0, 3, 3000, frameA.sublist(0, 1200)),
    );
    assembler.add(
      '/preview/cameras/front',
      _chunkPacket(1, 2, 3, 3000, frameA.sublist(2400)),
    );

    // Frame B has the same JPEG size; it must stay a separate frame and be
    // emitted immediately even though A is still incomplete.
    assembler.add(
      '/preview/cameras/front',
      _chunkPacket(2, 0, 3, 3000, frameB.sublist(0, 1200)),
    );
    assembler.add(
      '/preview/cameras/front',
      _chunkPacket(2, 1, 3, 3000, frameB.sublist(1200, 2400)),
    );
    final chunked = assembler.add(
      '/preview/cameras/front',
      _chunkPacket(2, 2, 3, 3000, frameB.sublist(2400)),
    );
    _check(
      chunked != null && chunked.bytes[1200] == 0x22,
      'same-size frames stay separate',
    );

    // Three incomplete frames per camera may be in flight; the next one
    // evicts the oldest instead of blocking or leaking.
    for (final id in <int>[3, 4]) {
      assembler.add(
        '/preview/cameras/front',
        _chunkPacket(id, 0, 3, 3000, frameA.sublist(0, 1200)),
      );
    }
    _check(assembler.pendingFrames == 3, 'three in-flight frames allowed');
    assembler.add(
      '/preview/cameras/front',
      _chunkPacket(5, 0, 3, 3000, frameA.sublist(0, 1200)),
    );
    _check(
      chunkStats.incompleteFrames == 1 && assembler.pendingFrames == 3,
      'oldest incomplete frame is evicted',
    );

    // The type fingerprint is skipped, like the Compose client.
    final noHash = ChunkedPreviewAssembler();
    final hashJpeg = _chunkedJpeg(1300, 0x33);
    noHash.add(
      '/preview/cameras/front',
      _chunkPacket(9, 0, 2, 1300, hashJpeg.sublist(0, 1200))
        ..fillRange(0, 8, 0),
    );
    final noHashImage = noHash.add(
      '/preview/cameras/front',
      _chunkPacket(9, 1, 2, 1300, hashJpeg.sublist(1200))..fillRange(0, 8, 0),
    );
    _check(
      noHashImage != null && noHashImage.bytes.length == 1300,
      'chunked preview does not require a known type fingerprint',
    );
  }

  // --- joint chunks: preview_package_t -> joint_batch_t -------------------
  {
    final raw = _jointPayload();
    final count =
        (raw.length + previewFragmentPayload - 1) ~/ previewFragmentPayload;
    final batches = <List<JointFrame>>[];
    final pipeline = PreviewPipeline(onFrame: (_) {}, onJoints: batches.add);

    // Out of order: the joint bridge publishes 1200-byte fragments.
    for (var i = count - 1; i >= 0; i--) {
      final begin = i * previewFragmentPayload;
      final end = min(begin + previewFragmentPayload, raw.length);
      pipeline.handle(
        LcmMessage(
          channel: '/preview/joint_batch',
          payload: _chunkPacket(
            77,
            i,
            count,
            raw.length,
            raw.sublist(begin, end),
          ),
        ),
      );
    }
    _check(batches.length == 1, 'joint fragments reassemble in the pipeline');
    _check(batches.single.length == 2, 'joint batch frames survive');
    _check(
      batches.single.first.stateValues.length == 20,
      'joint state values survive reassembly',
    );

    // The mock publisher sends a raw joint_batch_t (no fragment wrapper).
    final rawJoints = <List<JointFrame>>[];
    PreviewPipeline(onFrame: (_) {}, onJoints: rawJoints.add).handle(
      LcmMessage(channel: '/preview/joint_batch', payload: _jointPayload()),
    );
    _check(rawJoints.length == 1, 'raw joint_batch_t still decodes');
  }

  // --- real UDP socket over loopback --------------------------------------
  final port = 42000 + Random().nextInt(2000);
  final client = LcmUdpClient(port: port);
  final received = <LcmMessage>[];
  final subscription = client.messages.listen(received.add);
  await client.start(<String>['/test']);

  final sender = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  sender.send(
    _shortPacket('/test', shortPayload),
    InternetAddress.loopbackIPv4,
    port,
  );
  await Future<void>.delayed(const Duration(milliseconds: 300));
  _check(
    received.length == 1 && received.single.channel == '/test',
    'loopback UDP delivery',
  );

  // --- incomplete fragment expires ---------------------------------------
  final dropStats = LcmStats();
  final dropDecoder = LcmPacketDecoder();
  dropDecoder.decode(fragments.first, 'test:2', dropStats);
  dropDecoder.expire(dropStats, maxAge: Duration.zero);
  _check(dropStats.droppedFragments == 1, 'incomplete fragment expires');

  sender.close();
  await subscription.cancel();
  await client.dispose();

  print('\nAll LCM self-tests passed.');
}

void _check(bool condition, String message) {
  if (!condition) throw StateError('FAIL: $message');
  print('ok  $message');
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// --- synthetic wire builders ----------------------------------------------

Uint8List _jointPayload() {
  const frames = 2;
  const stateCount = 20;
  const commandCount = 20;

  final out = BytesBuilder(copy: false);
  out.add(Uint8List(8)); // fingerprint
  out.add(_i32(frames));

  for (var i = 0; i < 10; i++) {
    out.add(_i64(1000 + i));
  }

  final names = List<String>.generate(
    20,
    (i) => 'joint_${i + 1}/position',
  ).join('\n');
  final stateNames = List<String>.generate(10, (i) => i == 0 ? names : '');
  final commandNames = stateNames;
  for (final name in stateNames) {
    out.add(_string(name));
  }
  for (final name in commandNames) {
    out.add(_string(name));
  }
  for (var i = 0; i < 10; i++) {
    out.add(_i32(i == 0 ? stateCount : 0));
  }
  for (var i = 0; i < 10; i++) {
    out.add(_i32(i == 0 ? commandCount : 0));
  }
  for (var i = 0; i < 10; i++) {
    for (var j = 0; j < 128; j++) {
      out.add(_f64(i == 0 && j < stateCount ? j * 0.5 : 0));
    }
  }
  for (var i = 0; i < 10; i++) {
    for (var j = 0; j < 128; j++) {
      out.add(_f64(i == 0 && j < commandCount ? j * 2.0 : 0));
    }
  }
  return out.toBytes();
}

Uint8List _shortPacket(String channel, Uint8List payload, {int seq = 1}) {
  final out = BytesBuilder(copy: false);
  final header = ByteData(8)
    ..setUint32(0, LcmPacketDecoder.magicShort, Endian.big)
    ..setInt32(4, seq, Endian.big);
  out.add(header.buffer.asUint8List());
  out.add(ascii.encode(channel));
  out.addByte(0);
  out.add(payload);
  return out.toBytes();
}

List<Uint8List> _longPackets(
  String channel,
  Uint8List payload, {
  int seq = 7,
  int chunkSize = 20,
}) {
  final chunks = <Uint8List>[];
  for (var offset = 0; offset < payload.length; offset += chunkSize) {
    chunks.add(
      Uint8List.sublistView(
        payload,
        offset,
        min(offset + chunkSize, payload.length),
      ),
    );
  }

  final packets = <Uint8List>[];
  for (var i = 0; i < chunks.length; i++) {
    final out = BytesBuilder(copy: false);
    final header = ByteData(20)
      ..setUint32(0, LcmPacketDecoder.magicLong, Endian.big)
      ..setInt32(4, seq, Endian.big)
      ..setInt32(8, payload.length, Endian.big)
      ..setInt32(12, i * chunkSize, Endian.big)
      ..setInt16(16, i, Endian.big)
      ..setInt16(18, chunks.length, Endian.big);
    out.add(header.buffer.asUint8List());
    // Real LCM writers (lcm_udpm.c / lcm-java) carry the channel only in the
    // first fragment. Fragments 1..n-1 start their data at byte 20.
    if (i == 0) {
      out.add(ascii.encode(channel));
      out.addByte(0);
    }
    out.add(chunks[i]);
    packets.add(out.toBytes());
  }
  return packets;
}

Uint8List _chunkPacket(
  int timestamp,
  int index,
  int count,
  int total,
  Uint8List data,
) {
  final bytes = ByteData(36 + data.length);
  const fingerprint = <int>[0x6a, 0x92, 0xf4, 0x94, 0x7c, 0xbc, 0x31, 0x90];
  for (var i = 0; i < fingerprint.length; i++) {
    bytes.setUint8(i, fingerprint[i]);
  }
  bytes.setInt64(8, timestamp, Endian.big);
  bytes.setUint32(16, 42, Endian.big);
  bytes.setUint32(20, index, Endian.big);
  bytes.setUint32(24, count, Endian.big);
  bytes.setUint32(28, total, Endian.big);
  bytes.setUint32(32, data.length, Endian.big);

  final out = bytes.buffer.asUint8List();
  out.setRange(36, 36 + data.length, data);
  return out;
}

Uint8List _chunkedJpeg(int length, int fill) {
  final jpeg = Uint8List(length)..fillRange(0, length, fill);
  jpeg[0] = 0xFF;
  jpeg[1] = 0xD8;
  jpeg[2] = 0xFF;
  jpeg[3] = 0xC0;
  jpeg[4] = 0;
  jpeg[5] = 17;
  jpeg[6] = 8;
  jpeg[7] = 0x01;
  jpeg[8] = 0x68;
  jpeg[9] = 0x02;
  jpeg[10] = 0x80;
  jpeg[length - 2] = 0xFF;
  jpeg[length - 1] = 0xD9;
  return jpeg;
}

Uint8List _i32(int value) {
  final data = ByteData(4)..setInt32(0, value, Endian.big);
  return data.buffer.asUint8List();
}

Uint8List _i64(int value) {
  final data = ByteData(8)..setInt64(0, value, Endian.big);
  return data.buffer.asUint8List();
}

Uint8List _f64(double value) {
  final data = ByteData(8)..setFloat64(0, value, Endian.big);
  return data.buffer.asUint8List();
}

Uint8List _string(String value) {
  final encoded = utf8.encode(value);
  final out = BytesBuilder(copy: false);
  out.add(_i32(encoded.length + 1));
  out.add(encoded);
  out.addByte(0);
  return out.toBytes();
}
