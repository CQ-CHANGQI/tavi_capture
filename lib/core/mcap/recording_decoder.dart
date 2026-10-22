import '../telemetry/sample.dart';
import 'cdr.dart';
import 'remote_mcap.dart';

/// The supplied recording stores arm telemetry in Statistics, not JointState.
/// Keep only position interfaces; velocity/effort/diagnostic counters are not angles.
JointSample decodeStatistics(McapMessage message) {
  final r = CdrReader(message.data);
  r.i32();
  r.u32();
  r.string();
  final count = r.u32();
  if (count > 10000) throw const FormatException('Statistics count too large');
  final state = <String, double>{}, command = <String, double>{};
  for (var i = 0; i < count; i++) {
    final name = r.string();
    final value = r.f64();
    if (!name.endsWith('/position') || !value.isFinite) continue;
    if (name.startsWith('state_interface.')) {
      state[name.substring(16, name.length - 9)] = value;
    } else if (name.startsWith('command_interface.')) {
      command[name.substring(18, name.length - 9)] = value;
    }
  }
  return JointSample(message.logTime, state, command);
}

CameraFrame decodeCompressedFrame(McapMessage message) {
  final r = CdrReader(message.data);
  r.i32();
  r.u32();
  r.string();
  final format = r.string().toLowerCase();
  if (!format.contains('jpeg') &&
      !format.contains('jpg') &&
      !format.contains('png')) {
    throw UnsupportedError('图像格式：$format');
  }
  return CameraFrame(message.logTime, r.bytes(r.u32()));
}
