import 'dart:async';
import 'dart:io';

import 'types.dart';
import 'udpm.dart';

/// Subscribes to LCM `udpm://` channels over UDP multicast.
///
/// Unlike lcm-java (which joins one, kernel-selected interface), this client
/// joins the group on **every** IPv4 interface by default. That is what makes
/// a wired connection work when Wi-Fi is also up: multicast membership is per
/// interface, so a socket joined only on `en0` never sees packets arriving on
/// `en6`. Pass [interfaceName] to pin one interface instead.
class LcmUdpClient {
  LcmUdpClient({
    this.group = '239.255.76.67',
    this.port = 7667,
    this.interfaceName,
  });

  /// Multicast group. LCM's default is 239.255.76.67.
  final String group;

  /// UDP port. LCM's default is 7667.
  final int port;

  /// Optional interface to join on (e.g. `en11` for USB Ethernet). When null
  /// the group is joined on every IPv4 interface, and newly appearing
  /// interfaces (a cable plugged in later) are joined while running.
  final String? interfaceName;

  final LcmPacketDecoder _decoder = LcmPacketDecoder();
  final StreamController<LcmMessage> _messages =
      StreamController<LcmMessage>.broadcast();
  final LcmStats _stats = LcmStats();
  final Set<String> _channels = <String>{};
  bool _allChannels = false;

  RawDatagramSocket? _socket;
  Timer? _sweep;
  Timer? _watch;
  String? _watchSignature;

  /// Decoded messages whose channel matches the subscription list.
  Stream<LcmMessage> get messages => _messages.stream;

  LcmStats get stats => _stats;

  bool get _pinned => interfaceName != null && interfaceName!.isNotEmpty;

  /// Binds the socket and joins [group]. Channel names are literal; pass
  /// [all] to receive every channel on the group.
  Future<void> start(Iterable<String> channels, {bool all = false}) async {
    await _stop();

    _allChannels = all;
    _channels.clear();
    if (!all) {
      for (final channel in channels) {
        final value = channel.trim();
        if (value.isNotEmpty) _channels.add(value);
      }
      if (_channels.isEmpty) {
        throw ArgumentError('No channels to subscribe to');
      }
    }

    _stats.reset();

    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      port,
      reuseAddress: true,
    );
    try {
      socket.multicastLoopback = false;
      final joined = await _joinAll(socket);
      _stats.joinedInterfaces = joined;
      _watchSignature = _signature(await _listInterfaces());
    } catch (_) {
      socket.close();
      rethrow;
    }

    socket.listen(
      _onEvent,
      onError: (Object error, StackTrace stack) {
        _stats.parseErrors++;
        _messages.addError(error, stack);
      },
    );
    _socket = socket;
    _sweep = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _decoder.expire(_stats),
    );
    if (!_pinned) {
      _watch = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _watchInterfaces(),
      );
    }
  }

  Future<void> _stop() async {
    _sweep?.cancel();
    _sweep = null;
    _watch?.cancel();
    _watch = null;
    _watchSignature = null;
    _socket?.close();
    _socket = null;
    _stats.joinedInterfaces = const <String>[];
    _decoder.clear();
  }

  Future<void> dispose() async {
    await _stop();
    await _messages.close();
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final socket = _socket;
    if (socket == null) return;

    // Drain what the kernel has queued, but yield after a bounded batch so
    // timers and the UI keep running.
    for (var i = 0; i < 1024; i++) {
      final datagram = socket.receive();
      if (datagram == null) return;

      _stats.datagrams++;

      final sender = '${datagram.address.address}:${datagram.port}';
      final message = _decoder.decode(datagram.data, sender, _stats);
      if (message == null || !_matches(message.channel)) continue;
      _stats.messages++;
      if (!_messages.isClosed) _messages.add(message);
    }
  }

  bool _matches(String channel) => _allChannels || _channels.contains(channel);

  Future<List<NetworkInterface>> _listInterfaces() => NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
  );

  Future<List<String>> _joinAll(RawDatagramSocket socket) async {
    final interfaces = await _resolveInterfaces();
    final joined = <String>[];
    Object? lastError;
    for (final interface in interfaces) {
      try {
        socket.joinMulticast(InternetAddress(group), interface);
        joined.add(interface.name);
      } catch (error) {
        // Point-to-point/VPN interfaces reject IP_ADD_MEMBERSHIP; keep going.
        lastError = error;
      }
    }
    if (joined.isEmpty) {
      throw StateError(
        'Could not join $group on any interface'
        '${lastError == null ? '' : ': $lastError'}',
      );
    }
    return joined;
  }

  Future<List<NetworkInterface>> _resolveInterfaces() async {
    final interfaces = await _listInterfaces();
    if (!_pinned) return interfaces;

    final name = interfaceName!;
    for (final interface in interfaces) {
      if (interface.name == name) return <NetworkInterface>[interface];
    }
    throw ArgumentError(
      'LCM_IFACE "$name" not found; available: '
      '${interfaces.map((i) => i.name).join(', ')}',
    );
  }

  /// Joins interfaces that appeared after [start] (e.g. a USB Ethernet cable
  /// plugged in while the app is running). Interfaces that disappeared are
  /// dropped from the reported list; the kernel removes their membership.
  Future<void> _watchInterfaces() async {
    if (_socket == null) return;
    List<NetworkInterface> interfaces;
    try {
      interfaces = await _listInterfaces();
    } catch (_) {
      return;
    }

    final signature = _signature(interfaces);
    if (signature == _watchSignature) return;
    _watchSignature = signature;

    final socket = _socket;
    if (socket == null) return;

    final joined = <String>{..._stats.joinedInterfaces};
    final present = interfaces.map((i) => i.name).toSet();
    joined.removeWhere((name) => !present.contains(name));

    for (final interface in interfaces) {
      if (joined.contains(interface.name)) continue;
      try {
        socket.joinMulticast(InternetAddress(group), interface);
        joined.add(interface.name);
      } catch (_) {
        // Not multicast-capable; ignore.
      }
    }
    _stats.joinedInterfaces = joined.toList(growable: false);
  }

  static String _signature(List<NetworkInterface> interfaces) {
    final parts = <String>[];
    for (final interface in interfaces) {
      final addresses = interface.addresses.map((a) => a.address).toList()
        ..sort();
      parts.add('${interface.name}:${addresses.join(',')}');
    }
    parts.sort();
    return parts.join(';');
  }
}
