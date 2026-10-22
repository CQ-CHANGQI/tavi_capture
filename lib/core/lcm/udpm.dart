import 'dart:convert';
import 'dart:typed_data';

import 'types.dart';

/// Parses LCM's `udpm://` datagrams and reassembles fragmented messages.
///
/// Kept free of `dart:io` so it can be unit-tested without sockets.
///
/// Wire format (all integers big-endian, from lcm-java 1.5 / `udpm.c`):
///
///   short: magic(4) seq(4) channel\0 payload
///   long:  magic(4) seq(4) total(4) offset(4) num(2) count(2) channel\0 chunk
///          (the channel name appears only in fragment 0; later fragments
///           start their chunk at byte 20)
///
/// `payload` starts with the 8-byte type fingerprint. Messages larger than
/// 64 KiB are split by the publisher; this class buffers them by sender and
/// sequence number and drops incomplete sets after [expire]'s deadline.
class LcmPacketDecoder {
  static const int magicShort = 0x4C433032; // "LC02"
  static const int magicLong = 0x4C433033; // "LC03"

  /// Sanity cap; real preview frames are far smaller.
  static const int _maxMessageBytes = 16 << 20;

  final Map<String, _Fragment> _fragments = <String, _Fragment>{};

  /// Decodes one UDP datagram. Returns a message only when it is complete.
  LcmMessage? decode(Uint8List datagram, String sender, LcmStats stats) {
    if (datagram.length < 9) {
      stats.parseErrors++;
      return null;
    }

    final data = ByteData.sublistView(datagram);
    switch (data.getUint32(0, Endian.big)) {
      case magicShort:
        return _decodeShort(datagram, stats);
      case magicLong:
        return _decodeLong(datagram, sender, data, stats);
      default:
        stats.parseErrors++;
        return null;
    }
  }

  LcmMessage? _decodeShort(Uint8List datagram, LcmStats stats) {
    final nul = datagram.indexOf(0, 8);
    if (nul <= 8) {
      stats.parseErrors++;
      return null;
    }
    return LcmMessage(
      channel: utf8.decode(datagram.sublist(8, nul), allowMalformed: true),
      payload: Uint8List.sublistView(datagram, nul + 1),
    );
  }

  LcmMessage? _decodeLong(
    Uint8List datagram,
    String sender,
    ByteData data,
    LcmStats stats,
  ) {
    if (datagram.length < 20) {
      stats.parseErrors++;
      return null;
    }

    final seq = data.getInt32(4, Endian.big);
    final total = data.getInt32(8, Endian.big);
    final offset = data.getInt32(12, Endian.big);
    final number = data.getInt16(16, Endian.big);
    final count = data.getInt16(18, Endian.big);

    if (total < 0 ||
        total > _maxMessageBytes ||
        count <= 0 ||
        count > 4096 ||
        number < 0 ||
        number >= count ||
        offset < 0) {
      stats.parseErrors++;
      return null;
    }

    // lcm-java / lcm_udpm.c put the channel name only in fragment 0. Later
    // fragments start their data right after the 20-byte header.
    final String? channel;
    final Uint8List chunk;
    if (number == 0) {
      final nul = datagram.indexOf(0, 20);
      if (nul < 0) {
        stats.parseErrors++;
        return null;
      }
      channel = utf8.decode(datagram.sublist(20, nul), allowMalformed: true);
      chunk = Uint8List.sublistView(datagram, nul + 1);
    } else {
      channel = null;
      chunk = Uint8List.sublistView(datagram, 20);
    }

    if (offset + chunk.length > total) {
      stats.parseErrors++;
      return null;
    }

    final key = '$sender|$seq';
    var fragment = _fragments[key];
    if (fragment == null ||
        fragment.total != total ||
        fragment.count != count ||
        (channel != null &&
            fragment.channel != null &&
            fragment.channel != channel)) {
      fragment = _Fragment(total, count, channel);
      _fragments[key] = fragment;
    } else if (channel != null && fragment.channel == null) {
      // Fragment 0 arrived after some later fragments; adopt its channel.
      fragment.channel = channel;
    }

    fragment.data.setRange(offset, offset + chunk.length, chunk);
    fragment.received.add(number);
    fragment.last = DateTime.now();

    if (fragment.received.length < count || fragment.channel == null) {
      return null;
    }
    _fragments.remove(key);
    return LcmMessage(channel: fragment.channel!, payload: fragment.data);
  }

  /// Drops incomplete fragment sets older than [maxAge].
  void expire(LcmStats stats, {Duration maxAge = const Duration(seconds: 2)}) {
    final now = DateTime.now();
    final stale = <String>[];
    _fragments.forEach((key, fragment) {
      if (now.difference(fragment.last) > maxAge) stale.add(key);
    });
    for (final key in stale) {
      _fragments.remove(key);
      stats.droppedFragments++;
    }
  }

  void clear() => _fragments.clear();
}

class _Fragment {
  _Fragment(this.total, this.count, this.channel) : data = Uint8List(total);

  final int total;
  final int count;

  /// Known once fragment 0 has been seen; later fragments may arrive first.
  String? channel;
  final Uint8List data;
  final Set<int> received = <int>{};
  DateTime last = DateTime.now();
}
