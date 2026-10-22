import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../telemetry/sample.dart';
import 'lcm_protocol.dart';

class LcmUpdate {
  const LcmUpdate(
    this.cameras,
    this.joints,
    this.datagrams,
    this.dropped,
    this.malformed,
    this.interfaces, {
    this.error,
  });
  final Map<String, CameraFrame> cameras;
  final JointSample? joints;
  final int datagrams, dropped, malformed;
  final List<String> interfaces;
  final String? error;
}

/// Owns one receiver isolate. Only bounded snapshots cross to the UI.
class LcmClient {
  LcmClient({
    this.cameraGroup = const String.fromEnvironment(
      'LCM_GROUP',
      defaultValue: '239.255.76.67',
    ),
    this.cameraPort = const int.fromEnvironment('LCM_PORT', defaultValue: 7667),
    this.jointGroup = const String.fromEnvironment(
      'LCM_JOINT_GROUP',
      defaultValue: '239.255.76.68',
    ),
    this.jointPort = const int.fromEnvironment(
      'LCM_JOINT_PORT',
      defaultValue: 7668,
    ),
    this.interfaceName = const String.fromEnvironment('LCM_IFACE'),
  });
  final String cameraGroup, jointGroup, interfaceName;
  final int cameraPort, jointPort;
  final _updates = StreamController<LcmUpdate>.broadcast();
  Stream<LcmUpdate> get updates => _updates.stream;
  Isolate? _worker;
  ReceivePort? _port;
  bool _closed = false;
  bool _started = false;

  Future<void> start() async {
    if (_closed || _started) return;
    _started = true;
    final port = _port = ReceivePort();
    SendPort? commands;
    port.listen((event) {
      if (_closed) return;
      if (event is SendPort) {
        commands = event;
      } else if (event is LcmUpdate) {
        _updates.add(event);
        commands?.send('ack');
      } else if (event is List) {
        _updates.addError(StateError('LCM 接收失败：${event.first}'));
      }
    });
    final worker = await Isolate.spawn(
      _receive,
      (
        port.sendPort,
        cameraGroup,
        cameraPort,
        jointGroup,
        jointPort,
        interfaceName,
      ),
      onError: port.sendPort,
      errorsAreFatal: true,
    );
    if (_closed) {
      worker.kill(priority: Isolate.immediate);
      return;
    }
    _worker = worker;
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    _worker?.kill(priority: Isolate.immediate);
    _port?.close();
    unawaited(_updates.close());
  }
}

Future<void> _receive(
  (SendPort, String, int, String, int, String) config,
) async {
  final (out, cameraGroup, cameraPort, jointGroup, jointPort, iface) = config;
  final commands = ReceivePort();
  out.send(commands.sendPort);
  final decoder = LcmDecoder();
  final latest = <String, CameraFrame>{};
  JointSample? joints;
  var datagrams = 0;
  var inFlight = false;
  String? error;
  final links = <(RawDatagramSocket, String, Set<String>)>[];
  final started = Stopwatch()..start();
  var lastSent = -1000;

  void flush() {
    // At most 30 UI updates/s; UDP continues draining independently.
    if (inFlight || started.elapsedMilliseconds - lastSent < 32) return;
    lastSent = started.elapsedMilliseconds;
    inFlight = true;
    out.send(
      LcmUpdate(
        Map.of(latest),
        joints,
        datagrams,
        decoder.dropped,
        decoder.malformed,
        links.expand((l) => l.$3).toSet().toList(),
        error: error,
      ),
    );
    latest.clear();
    joints = null;
  }

  commands.listen((_) {
    inFlight = false;
  });

  Future<void> joinInterfaces() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    for (final (socket, group, joined) in links) {
      final present = <String>{};
      for (final nic in interfaces) {
        if (iface.isNotEmpty && nic.name != iface) continue;
        final key =
            '${nic.name}:${nic.index}:${nic.addresses.map((a) => a.address).join(',')}';
        present.add(key);
        if (joined.contains(key)) continue;
        try {
          socket.joinMulticast(InternetAddress(group), nic);
          joined.add(key);
        } on SocketException {
          /* VPN interfaces may not support multicast. */
        }
      }
      joined.removeWhere((key) => !present.contains(key));
    }
  }

  for (final (group, port) in {
    (cameraGroup, cameraPort),
    (jointGroup, jointPort),
  }) {
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
      );
      links.add((socket, group, <String>{}));
      socket.listen(
        (event) {
          if (event != RawSocketEvent.read) return;
          for (var i = 0; i < 512; i++) {
            final packet = socket.receive();
            if (packet == null) break;
            datagrams++;
            final sender = '${packet.address.address}:${packet.port}';
            final message = decoder.datagram(packet.data, sender);
            if (message == null) continue;
            final camera = cameraOf(message.channel);
            final isJoint = message.channel == '/preview/joint_batch';
            if (camera == null && !isJoint) continue;
            if (isJoint) {
              // Older bridges publish a raw batch inside LCM transport frames.
              try {
                final batch = decodeLcmJoints(message.data);
                if (batch.isNotEmpty) joints = batch.last;
                continue;
              } on FormatException {
                // Current bridges wrap the batch in preview_package_t.
              }
            }
            // Preview streams are keyed by sender too: independent publishers
            // cannot accidentally assemble each other's fragments.
            final data = decoder.preview(
              '$sender/${message.channel}',
              message.data,
            );
            if (data == null) continue;
            if (camera != null) {
              latest[camera] = CameraFrame(
                DateTime.now().microsecondsSinceEpoch * 1000,
                data,
              );
            } else {
              try {
                final batch = decodeLcmJoints(data);
                if (batch.isNotEmpty) joints = batch.last;
              } on FormatException {
                decoder.malformed++;
              }
            }
          }
        },
        onError: (Object e) {
          error = '$e';
        },
      );
    } on SocketException catch (e) {
      error = '$group:$port $e';
    }
  }
  await joinInterfaces();
  Timer.periodic(const Duration(milliseconds: 33), (_) => flush());
  var joining = false;
  Timer.periodic(const Duration(seconds: 2), (_) async {
    decoder.expire();
    if (joining) return;
    joining = true;
    try {
      await joinInterfaces();
    } catch (e) {
      error = '$e';
    } finally {
      joining = false;
    }
  });
}
