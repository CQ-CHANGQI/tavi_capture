import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'codec.dart';
import 'lcm_udp_client.dart';
import 'preview_pipeline.dart';
import 'types.dart';

/// Preview client with the same split as the Compose app: everything except
/// drawing happens off the UI isolate.
///
/// A dedicated isolate owns one [LcmUdpClient] for the camera group and one for
/// the joint group (the robot publishes them on `239.255.76.67:7667` and
/// `239.255.76.68:7668`), reassembles fragments with [ChunkedPreviewAssembler]
/// and decodes joint batches there. Only complete images cross the isolate
/// boundary, at most one batch in flight (the UI acks after taking it), so a
/// slow frame can never accumulate a packet backlog.
///
/// The UI isolate receives [frames] (about 30/s per camera) and decodes each
/// one once into a `ui.Image`; it never sees LCM datagrams or chunk maps.
class LcmPreviewClient {
  LcmPreviewClient({
    this.group = '239.255.76.67',
    this.port = 7667,
    this.interfaceName,
    this.jointGroup = '239.255.76.68',
    this.jointPort = 7668,
    this.jointInterfaceName,
  });

  /// Camera multicast group/port (LCM `camera_lcm_url`).
  final String group;
  final int port;
  final String? interfaceName;

  /// Joint multicast group/port (LCM `joint_batch.lcm_url`). When identical to
  /// the camera link, a single socket is used and `/preview/joint_batch` is
  /// subscribed on it.
  final String jointGroup;
  final int jointPort;
  final String? jointInterfaceName;

  final StreamController<PreviewImage> _frames =
      StreamController<PreviewImage>.broadcast();
  final StreamController<List<JointFrame>> _joints =
      StreamController<List<JointFrame>>.broadcast();
  final LcmStats _stats = LcmStats();

  Isolate? _isolate;
  ReceivePort? _responses;
  ReceivePort? _isolateErrors;
  SendPort? _commands;
  Completer<void>? _ready;
  bool _disposed = false;

  /// Complete camera frames, already reassembled in the receiver isolate.
  Stream<PreviewImage> get frames => _frames.stream;

  /// Decoded `joint_batch_t` batches.
  Stream<List<JointFrame>> get joints => _joints.stream;

  LcmStats get stats => _stats;

  Future<void> start(Iterable<String> channels, {bool all = false}) async {
    await _stop();
    if (_disposed) throw StateError('LcmPreviewClient has been disposed');
    _stats.reset();

    final responses = ReceivePort();
    final isolateErrors = ReceivePort();
    _responses = responses;
    _isolateErrors = isolateErrors;
    final ready = Completer<void>();
    _ready = ready;

    responses.listen(_onResponse);
    isolateErrors.listen(_onIsolateError);

    try {
      _isolate = await Isolate.spawn(
        _receiverMain,
        <String, Object?>{
          'responses': responses.sendPort,
          'group': group,
          'port': port,
          'interfaceName': interfaceName,
          'jointGroup': jointGroup,
          'jointPort': jointPort,
          'jointInterfaceName': jointInterfaceName,
          'channels': channels.toList(growable: false),
          'all': all,
        },
        onError: isolateErrors.sendPort,
        errorsAreFatal: true,
        debugName: 'lcm-preview',
      );
    } catch (error) {
      await _stop();
      rethrow;
    }

    try {
      await ready.future.timeout(const Duration(seconds: 10));
    } catch (error) {
      await _stop();
      rethrow;
    }
  }

  Future<void> _stop() async {
    final isolate = _isolate;
    _isolate = null;
    _commands?.send(<String, Object?>{'type': 'stop'});
    _commands = null;
    _stats.joinedInterfaces = const <String>[];

    if (isolate != null) {
      // Give the child a moment to close the sockets, then make sure.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      isolate.kill(priority: Isolate.immediate);
    }

    _responses?.close();
    _responses = null;
    _isolateErrors?.close();
    _isolateErrors = null;
  }

  Future<void> dispose() async {
    _disposed = true;
    await _stop();
    await _frames.close();
    await _joints.close();
  }

  void _onResponse(Object? message) {
    if (message is! Map) return;
    switch (message['type']) {
      case 'ready':
        final commands = message['commands'];
        if (commands is SendPort) _commands = commands;
        if (_ready != null && !_ready!.isCompleted) _ready!.complete();

      case 'stats':
        final snapshot = message['stats'];
        if (snapshot is Map) {
          _stats.applySnapshot(snapshot.cast<String, Object?>());
        }

      case 'frames':
        final items = message['items'];
        if (items is List && !_frames.isClosed) {
          for (final item in items) {
            final image = _decodeFrame(item);
            if (image != null) _frames.add(image);
          }
        }
        // Backpressure: the isolate keeps only the latest frame per camera
        // until the UI isolate has taken this batch.
        _commands?.send(const <String, Object?>{'type': 'frameAck'});

      case 'joints':
        final items = message['items'];
        if (items is List && !_joints.isClosed) {
          final batch = _decodeJoints(items);
          if (batch.isNotEmpty) _joints.add(batch);
        }

      case 'error':
        final failure = StateError(
          '${message['message'] ?? 'LCM preview error'}',
        );
        if (_ready != null && !_ready!.isCompleted) {
          _ready!.completeError(failure);
        } else {
          _fail(failure);
        }
    }
  }

  void _onIsolateError(Object? error) {
    final failure = StateError('LCM preview isolate failed: $error');
    if (_ready != null && !_ready!.isCompleted) {
      _ready!.completeError(failure);
    } else {
      _fail(failure);
    }
  }

  void _fail(Object error) {
    if (!_frames.isClosed) _frames.addError(error);
    if (!_joints.isClosed) _joints.addError(error);
  }

  static PreviewImage? _decodeFrame(Object? item) {
    if (item is! Map) return null;
    final camera = item['camera'];
    final width = item['width'];
    final height = item['height'];
    final bytes = item['bytes'];
    if (camera is! String || width is! int || height is! int) return null;
    if (bytes is! Uint8List) return null;
    return PreviewImage(
      camera: camera,
      width: width,
      height: height,
      bytes: bytes,
    );
  }

  static List<JointFrame> _decodeJoints(List items) {
    final batch = <JointFrame>[];
    for (final item in items) {
      if (item is! Map) continue;
      final timestamp = item['ts'];
      final stateNames = item['sn'];
      final commandNames = item['cn'];
      final stateValues = item['sv'];
      final commandValues = item['cv'];
      if (timestamp is! int ||
          stateNames is! List ||
          commandNames is! List ||
          stateValues is! List ||
          commandValues is! List) {
        continue;
      }
      batch.add(
        JointFrame(
          timestampNs: timestamp,
          stateNames: stateNames.whereType<String>().toList(growable: false),
          commandNames: commandNames.whereType<String>().toList(
            growable: false,
          ),
          stateValues: stateValues.whereType<double>().toList(growable: false),
          commandValues: commandValues.whereType<double>().toList(
            growable: false,
          ),
        ),
      );
    }
    return batch;
  }
}

/// Receiver isolate: sockets + LCM framing + reassembly + joint decode.
Future<void> _receiverMain(Map<String, Object?> args) async {
  final responses = args['responses']! as SendPort;
  final commands = ReceivePort();
  final group = args['group']! as String;
  final port = args['port']! as int;
  final jointGroup = args['jointGroup']! as String;
  final jointPort = args['jointPort']! as int;
  final all = args['all']! as bool;
  final requested = (args['channels'] as List).cast<String>();

  const jointChannel = '/preview/joint_batch';

  final stats = LcmStats();
  final camera = LcmUdpClient(
    group: group,
    port: port,
    interfaceName: args['interfaceName'] as String?,
  );
  final sameLink = jointGroup == group && jointPort == port;
  final joint = sameLink
      ? null
      : LcmUdpClient(
          group: jointGroup,
          port: jointPort,
          interfaceName: args['jointInterfaceName'] as String?,
        );

  final cameraChannels = <String>[...requested];
  if (!all && !cameraChannels.contains(jointChannel)) {
    // Same-group publishers (mock, older robot) carry joints on the camera
    // link as well; subscribing here costs nothing when they do not.
    cameraChannels.add(jointChannel);
  }

  final latest = <String, PreviewImage>{};
  var inFlight = false;
  var stopped = false;

  void flushFrames() {
    if (stopped || inFlight || latest.isEmpty) return;
    final batch = <Map<String, Object?>>[
      for (final image in latest.values)
        <String, Object?>{
          'camera': image.camera,
          'width': image.width,
          'height': image.height,
          'bytes': image.bytes,
        },
    ];
    latest.clear();
    inFlight = true;
    responses.send(<String, Object?>{'type': 'frames', 'items': batch});
  }

  final pipeline = PreviewPipeline(
    stats: stats,
    onFrame: (image) {
      latest[image.camera] = image;
      flushFrames();
    },
    onJoints: (frames) {
      if (!stopped) {
        responses.send(<String, Object?>{
          'type': 'joints',
          'items': _encodeJoints(frames),
        });
      }
    },
  );

  final subscriptions = <StreamSubscription<LcmMessage>>[];
  void subscribe(LcmUdpClient client) {
    subscriptions.add(
      client.messages.listen(
        pipeline.handle,
        onError: (Object error) => responses.send(<String, Object?>{
          'type': 'error',
          'message': '$error',
        }),
      ),
    );
  }

  subscribe(camera);
  if (joint != null) subscribe(joint);

  Map<String, Object?> snapshot() {
    var datagrams = 0;
    var messages = 0;
    var dropped = 0;
    var parseErrors = stats.parseErrors;
    final interfaces = <String>{};
    for (final client in <LcmUdpClient>[camera, ?joint]) {
      final link = client.stats;
      datagrams += link.datagrams;
      messages += link.messages;
      dropped += link.droppedFragments;
      parseErrors += link.parseErrors;
      interfaces.addAll(link.joinedInterfaces);
    }
    return <String, Object?>{
      'datagrams': datagrams,
      'messages': messages,
      'droppedFragments': dropped,
      'parseErrors': parseErrors,
      'incompleteFrames': stats.incompleteFrames,
      'corruptFrames': stats.corruptFrames,
      'pendingFrames': pipeline.pendingFrames,
      'joinedInterfaces': interfaces.toList(growable: false),
    };
  }

  try {
    await camera.start(cameraChannels, all: all);
  } catch (error) {
    responses.send(<String, Object?>{'type': 'error', 'message': '$error'});
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await camera.dispose();
    if (joint != null) await joint.dispose();
    commands.close();
    return;
  }

  // Ready goes out before the joint client starts; the command listener is
  // attached immediately so frame acks flow from the very first batch (the
  // joint client's startup must not stall the camera pipeline).
  responses.send(<String, Object?>{
    'type': 'ready',
    'commands': commands.sendPort,
  });

  Timer? statsTimer;
  commands.listen((Object? command) async {
    if (command is! Map) return;
    final type = command['type'];
    if (type == 'frameAck') {
      inFlight = false;
      flushFrames();
      return;
    }
    if (type != 'stop') return;

    stopped = true;
    statsTimer?.cancel();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await camera.dispose();
    if (joint != null) await joint.dispose();
    commands.close();
  });

  if (joint != null) {
    try {
      await joint.start(
        all ? const <String>[] : const <String>[jointChannel],
        all: all,
      );
    } catch (_) {
      // Joint telemetry is optional; the camera preview keeps working.
      await joint.dispose();
    }
  }

  statsTimer = Timer.periodic(
    const Duration(milliseconds: 500),
    (_) =>
        responses.send(<String, Object?>{'type': 'stats', 'stats': snapshot()}),
  );
}

List<Map<String, Object?>> _encodeJoints(List<JointFrame> frames) =>
    <Map<String, Object?>>[
      for (final frame in frames)
        <String, Object?>{
          'ts': frame.timestampNs,
          'sn': frame.stateNames,
          'cn': frame.commandNames,
          'sv': frame.stateValues,
          'cv': frame.commandValues,
        },
    ];
