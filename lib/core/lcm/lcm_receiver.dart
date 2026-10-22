import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'lcm_message.dart';
import 'preview_protocol.dart';

/// 相机 / 关节的组播地址，和 `preview.get` 通告的一致。
const String lcmCameraGroup = String.fromEnvironment(
  'LCM_GROUP',
  defaultValue: '239.255.76.67',
);
const int lcmCameraPort = int.fromEnvironment('LCM_PORT', defaultValue: 7667);
const String lcmJointGroup = String.fromEnvironment(
  'LCM_JOINT_GROUP',
  defaultValue: '239.255.76.68',
);
const int lcmJointPort = int.fromEnvironment(
  'LCM_JOINT_PORT',
  defaultValue: 7668,
);
const String lcmInterface = String.fromEnvironment('LCM_IFACE');

/// 接收端给 UI 看的计数快照。
class LcmStats {
  int datagrams = 0;
  int messages = 0;
  int parseErrors = 0;
  int dropped = 0;
  int incomplete = 0;
  int corrupt = 0;
  int pending = 0;
  List<String> interfaces = const [];

  void reset() {
    datagrams = 0;
    messages = 0;
    parseErrors = 0;
    dropped = 0;
    incomplete = 0;
    corrupt = 0;
    pending = 0;
    interfaces = const [];
  }

  void apply(Map<String, Object?> data) {
    int read(String key) => data[key] is int ? data[key]! as int : 0;
    datagrams = read('datagrams');
    messages = read('messages');
    parseErrors = read('parseErrors');
    dropped = read('dropped');
    incomplete = read('incomplete');
    corrupt = read('corrupt');
    pending = read('pending');
    final list = data['interfaces'];
    interfaces = list is List
        ? list.whereType<String>().toList(growable: false)
        : const [];
  }
}

/// 相机和关节的接收端：socket、组播、分片重组、解码都在一个独立 isolate 里，
/// UI 只拿完整画面和关节批次。
class LcmReceiver {
  LcmReceiver({
    this.cameraGroup = lcmCameraGroup,
    this.cameraPort = lcmCameraPort,
    this.jointGroup = lcmJointGroup,
    this.jointPort = lcmJointPort,
    this.interfaceName = lcmInterface,
  });

  final String cameraGroup;
  final int cameraPort;
  final String jointGroup;
  final int jointPort;
  final String interfaceName;

  final StreamController<CameraFrame> _frames =
      StreamController<CameraFrame>.broadcast();
  final StreamController<List<JointBatch>> _joints =
      StreamController<List<JointBatch>>.broadcast();
  final LcmStats stats = LcmStats();

  Isolate? _isolate;
  ReceivePort? _responses;
  ReceivePort? _errors;
  SendPort? _commands;
  Completer<void>? _ready;
  bool _disposed = false;

  Stream<CameraFrame> get frames => _frames.stream;
  Stream<List<JointBatch>> get joints => _joints.stream;

  Future<void> start(Iterable<String> cameraChannels) async {
    if (_disposed) throw StateError('LcmReceiver 已释放');
    await stop();
    stats.reset();

    final responses = _responses = ReceivePort();
    final errors = _errors = ReceivePort();
    final ready = _ready = Completer<void>();
    responses.listen(_onMessage);
    errors.listen((event) => _fail('接收 isolate 失败：$event'));

    try {
      _isolate = await Isolate.spawn(
        _receive,
        <String, Object?>{
          'responses': responses.sendPort,
          'channels': cameraChannels.toList(growable: false),
          'cameraGroup': cameraGroup,
          'cameraPort': cameraPort,
          'jointGroup': jointGroup,
          'jointPort': jointPort,
          'interfaceName': interfaceName,
        },
        onError: errors.sendPort,
        errorsAreFatal: true,
        debugName: 'lcm-receiver',
      );
      await ready.future.timeout(const Duration(seconds: 10));
    } catch (error) {
      await stop();
      rethrow;
    }
  }

  Future<void> stop() async {
    final ready = _ready;
    _ready = null;
    // 正常 complete：start() 里可能已经超时返回，这里再抛错会变成未处理异常。
    if (ready != null && !ready.isCompleted) ready.complete();
    _commands?.send(const <String, Object?>{'type': 'stop'});
    _commands = null;

    final isolate = _isolate;
    _isolate = null;
    if (isolate != null) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      isolate.kill(priority: Isolate.immediate);
    }

    _responses?.close();
    _responses = null;
    _errors?.close();
    _errors = null;
    stats.interfaces = const [];
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    await _frames.close();
    await _joints.close();
  }

  void _onMessage(Object? message) {
    if (message is! Map) return;
    switch (message['type']) {
      case 'ready':
        final commands = message['commands'];
        if (commands is SendPort) _commands = commands;
        final ready = _ready;
        if (ready != null && !ready.isCompleted) ready.complete();

      case 'frames':
        final items = message['items'];
        if (items is List && !_frames.isClosed) {
          for (final item in items) {
            if (item is! Map) continue;
            final camera = item['camera'];
            final image = item['image'];
            if (camera is String && image is Uint8List) {
              _frames.add(CameraFrame(camera, image));
            }
          }
        }
      case 'joints':
        final batches = _decodeJoints(message['items']);
        if (batches.isNotEmpty && !_joints.isClosed) _joints.add(batches);

      case 'stats':
        final data = message['data'];
        if (data is Map) {
          stats.apply(data.cast<String, Object?>());
        }

      case 'error':
        _fail('${message['message'] ?? 'LCM 接收失败'}');
    }
  }

  static List<JointBatch> _decodeJoints(Object? items) {
    if (items is! List) return const [];
    final batches = <JointBatch>[];
    for (final item in items) {
      if (item is! Map) continue;
      final timestamp = item['timestamp'];
      final state = item['state'];
      final command = item['command'];
      if (timestamp is! int || state is! Map || command is! Map) continue;
      batches.add(
        JointBatch(timestamp, _doubleMap(state), _doubleMap(command)),
      );
    }
    return batches;
  }

  static Map<String, double> _doubleMap(Map<Object?, Object?> source) => {
    for (final entry in source.entries)
      if (entry.key is String && entry.value is num)
        entry.key! as String: (entry.value! as num).toDouble(),
  };

  void _fail(String message) {
    final ready = _ready;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(StateError(message));
      return;
    }
    final error = StateError(message);
    if (!_frames.isClosed) _frames.addError(error);
    if (!_joints.isClosed) _joints.addError(error);
  }
}

// ---------------------------------------------------------------------------
// isolate 内部
// ---------------------------------------------------------------------------

Future<void> _receive(Map<String, Object?> args) async {
  final responses = args['responses']! as SendPort;
  final commands = ReceivePort();
  final counters = LcmCounters();
  final reader = LcmMessageReader(counters: counters);
  final channels = <String>{
    ...(args['channels']! as List).cast<String>(),
    jointBatchChannel,
  };

  // 组装好的帧按到达顺序排队；UI 慢就排队，不在接收端丢帧。
  final outbox = <Map<String, Object?>>[];
  var stopped = false;
  var flushQueued = false;

  /// 同一轮 socket 事件里完成的几帧合成一条消息，帧本身一个都不少。
  void queueFlush() {
    if (flushQueued || stopped) return;
    flushQueued = true;
    scheduleMicrotask(() {
      flushQueued = false;
      if (stopped || outbox.isEmpty) return;
      final items = List<Map<String, Object?>>.of(outbox);
      outbox.clear();
      responses.send(<String, Object?>{'type': 'frames', 'items': items});
    });
  }

  final router = PreviewRouter(
    counters: counters,
    onCameraFrame: (frame) {
      outbox.add(<String, Object?>{
        'camera': frame.camera,
        'image': frame.image,
      });
      queueFlush();
    },
    onJointBatches: (batches) {
      if (stopped) return;
      responses.send(<String, Object?>{
        'type': 'joints',
        'items': <Map<String, Object?>>[
          for (final batch in batches)
            <String, Object?>{
              'timestamp': batch.timestampNs,
              'state': batch.state,
              'command': batch.command,
            },
        ],
      });
    },
  );

  void onLinkError(Object error) {
    if (!stopped) {
      responses.send(<String, Object?>{'type': 'error', 'message': '$error'});
    }
  }

  final links = <_UdpLink>[];
  final cameraLink = _UdpLink(
    group: args['cameraGroup']! as String,
    port: args['cameraPort']! as int,
    interfaceName: args['interfaceName']! as String,
    channels: channels,
    reader: reader,
    router: router,
    counters: counters,
    onError: onLinkError,
  );
  try {
    await cameraLink.open();
  } catch (error) {
    responses.send(<String, Object?>{'type': 'error', 'message': '$error'});
    commands.close();
    return;
  }
  links.add(cameraLink);

  // 先 ready，再开关节链路：相机的首帧不会被关节 socket 的启动拖住。
  responses.send(<String, Object?>{
    'type': 'ready',
    'commands': commands.sendPort,
  });

  Timer? statsTimer;
  Timer? housekeeping;

  commands.listen((command) {
    if (command is! Map) return;
    if (command['type'] == 'stop') {
      stopped = true;
      statsTimer?.cancel();
      housekeeping?.cancel();
      for (final link in links) {
        unawaited(link.close());
      }
      commands.close();
    }
  });

  final jointGroup = args['jointGroup']! as String;
  final jointPort = args['jointPort']! as int;
  if (jointGroup != args['cameraGroup'] || jointPort != args['cameraPort']) {
    final jointLink = _UdpLink(
      group: jointGroup,
      port: jointPort,
      interfaceName: args['interfaceName']! as String,
      channels: const {jointBatchChannel},
      reader: reader,
      router: router,
      counters: counters,
      onError: onLinkError,
    );
    try {
      await jointLink.open();
      links.add(jointLink);
    } catch (_) {
      // 关节是可选数据：相机链路照常工作。
    }
  }

  statsTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
    if (stopped) return;
    final interfaces = <String>{for (final link in links) ...link.joinedNames};
    responses.send(<String, Object?>{
      'type': 'stats',
      'data': <String, Object?>{
        'datagrams': counters.datagrams,
        'messages': counters.messages,
        'parseErrors': counters.parseErrors,
        'dropped': counters.dropped,
        'incomplete': counters.incomplete,
        'corrupt': counters.corrupt,
        'pending': router.pendingFrames,
        'interfaces': interfaces.toList(growable: false),
      },
    });
  });
  housekeeping = Timer.periodic(const Duration(seconds: 2), (_) {
    reader.expire();
    for (final link in links) {
      unawaited(link.joinInterfaces());
    }
  });
}

class _UdpLink {
  _UdpLink({
    required this.group,
    required this.port,
    required this.interfaceName,
    required this.channels,
    required this.reader,
    required this.router,
    required this.counters,
    required this.onError,
  });

  final String group;
  final int port;
  final String interfaceName;
  final Set<String> channels;
  final LcmMessageReader reader;
  final PreviewRouter router;
  final LcmCounters counters;
  final void Function(Object error) onError;

  final Set<String> joinedNames = {};
  final Set<String> _joinedKeys = {};

  RawDatagramSocket? _socket;
  Timer? _joinTimer;
  bool _joining = false;

  Future<void> open() async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      port,
      reuseAddress: true,
    );
    _socket = socket;
    socket.listen(_drain, onError: onError);
    await joinInterfaces();
    _joinTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(joinInterfaces()),
    );
  }

  /// 组播成员关系是按网卡的：每块 IPv4 网卡都要 join，否则插网线/多网卡时
  /// 只有默认路由那块能收到。新出现的网卡由两秒一次的定时器补上。
  Future<void> joinInterfaces() async {
    final socket = _socket;
    if (socket == null || _joining) return;
    _joining = true;
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      final present = <String>{};
      for (final nic in interfaces) {
        if (interfaceName.isNotEmpty && nic.name != interfaceName) continue;
        final key =
            '${nic.name}:${nic.index}:${nic.addresses.map((a) => a.address).join(',')}';
        present.add(key);
        if (_joinedKeys.contains(key)) continue;
        try {
          socket.joinMulticast(InternetAddress(group), nic);
          _joinedKeys.add(key);
          joinedNames.add(nic.name);
        } on SocketException {
          // VPN / 虚拟网卡不支持组播，跳过。
        }
      }
      _joinedKeys.removeWhere((key) => !present.contains(key));
    } catch (error) {
      onError(error);
    } finally {
      _joining = false;
    }
  }

  void _drain(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final socket = _socket;
    if (socket == null) return;
    for (var i = 0; i < 512; i++) {
      final datagram = socket.receive();
      if (datagram == null) break;
      counters.datagrams++;
      final message = reader.read(
        datagram.data,
        sender: '${datagram.address.address}:${datagram.port}',
      );
      if (message == null) continue;
      if (!channels.contains(message.channel)) continue;
      router.handle(message);
    }
  }

  Future<void> close() async {
    _joinTimer?.cancel();
    _joinTimer = null;
    _socket?.close();
    _socket = null;
  }
}
