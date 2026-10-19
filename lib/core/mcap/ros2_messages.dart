import 'dart:typed_data';

import 'cdr.dart';

/// 这个仓库用到的 ROS2 消息的精简 Dart 模型。

class RosHeader {
  const RosHeader({
    required this.sec,
    required this.nanosec,
    required this.frameId,
  });

  final int sec;
  final int nanosec;
  final String frameId;

  int get stampNanos => sec * 1000000000 + nanosec;
}

class RosJointState {
  const RosJointState({
    required this.header,
    required this.name,
    required this.position,
    required this.velocity,
    required this.effort,
  });

  final RosHeader header;
  final List<String> name;
  final List<double> position;
  final List<double> velocity;
  final List<double> effort;
}

class RosPoint {
  const RosPoint(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;
}

class RosQuaternion {
  const RosQuaternion(this.x, this.y, this.z, this.w);

  final double x;
  final double y;
  final double z;
  final double w;
}

class RosPoseStamped {
  const RosPoseStamped({
    required this.header,
    required this.position,
    required this.orientation,
  });

  final RosHeader header;
  final RosPoint position;
  final RosQuaternion orientation;
}

class RosImage {
  const RosImage({
    required this.header,
    required this.height,
    required this.width,
    required this.encoding,
    required this.step,
    required this.isBigEndian,
    required this.data,
  });

  final RosHeader header;
  final int height;
  final int width;
  final String encoding;
  final int step;
  final bool isBigEndian;
  final Uint8List data;

  /// 只处理本项目相机用的 bgr8/rgb8。
  Uint8List toRgba() {
    final pixels = Uint8List(width * height * 4);
    final bgr = encoding == 'bgr8';
    if (!bgr && encoding != 'rgb8') {
      throw UnsupportedError('Image encoding: $encoding');
    }
    for (var y = 0; y < height; y++) {
      final srcRow = y * step;
      final dstRow = y * width * 4;
      for (var x = 0; x < width; x++) {
        final src = srcRow + x * 3;
        final dst = dstRow + x * 4;
        final c0 = data[src];
        final c1 = data[src + 1];
        final c2 = data[src + 2];
        pixels[dst] = bgr ? c2 : c0;
        pixels[dst + 1] = c1;
        pixels[dst + 2] = bgr ? c0 : c2;
        pixels[dst + 3] = 255;
      }
    }
    return pixels;
  }
}

class RosGripper {
  const RosGripper({
    required this.header,
    required this.angle,
    required this.distance,
    required this.effort,
    required this.velocity,
    required this.enable,
    required this.setZero,
    required this.error,
    required this.voltage,
    required this.driverTemp,
    required this.motorTemp,
    required this.busCurrent,
    required this.status,
  });

  final RosHeader header;
  final double angle;
  final double distance;
  final double effort;
  final double velocity;
  final bool enable;
  final bool setZero;
  final bool error;
  final double voltage;
  final double driverTemp;
  final double motorTemp;
  final double busCurrent;
  final String status;
}

class RosString {
  const RosString(this.data);

  final String data;
}

class RosTeleopStatus {
  const RosTeleopStatus({
    required this.topics,
    required this.fail,
    required this.quit,
  });

  final List<String> topics;
  final bool fail;
  final bool quit;
}

/// 按 schema 名解码。未覆盖的类型直接报错，避免悄悄读出垃圾数据。
Object decodeRos2Message(String schemaName, Uint8List data) {
  final reader = CdrReader(data);
  switch (schemaName) {
    case 'sensor_msgs/msg/JointState':
      return _readJointState(reader);
    case 'geometry_msgs/msg/PoseStamped':
      return _readPoseStamped(reader);
    case 'sensor_msgs/msg/Image':
      return _readImage(reader);
    case 'data_msgs/msg/Gripper':
      return _readGripper(reader);
    case 'data_msgs/msg/TeleopStatus':
      return _readTeleopStatus(reader);
    case 'std_msgs/msg/String':
      return RosString(reader.string());
    default:
      throw UnsupportedError('ROS2 message: $schemaName');
  }
}

RosHeader _readHeader(CdrReader reader) {
  return RosHeader(
    sec: reader.i32(),
    nanosec: reader.u32(),
    frameId: reader.string(),
  );
}

RosJointState _readJointState(CdrReader reader) {
  final header = _readHeader(reader);
  final names = _readStrings(reader);
  final position = _readDoubles(reader);
  final velocity = _readDoubles(reader);
  final effort = _readDoubles(reader);
  return RosJointState(
    header: header,
    name: names,
    position: position,
    velocity: velocity,
    effort: effort,
  );
}

RosPoseStamped _readPoseStamped(CdrReader reader) {
  final header = _readHeader(reader);
  final position = RosPoint(reader.f64(), reader.f64(), reader.f64());
  final orientation = RosQuaternion(
    reader.f64(),
    reader.f64(),
    reader.f64(),
    reader.f64(),
  );
  return RosPoseStamped(
    header: header,
    position: position,
    orientation: orientation,
  );
}

RosImage _readImage(CdrReader reader) {
  final header = _readHeader(reader);
  final height = reader.u32();
  final width = reader.u32();
  final encoding = reader.string();
  final isBigEndian = reader.boolean();
  final step = reader.u32();
  final size = reader.u32();
  final data = reader.bytes(size);
  if (data.length < step * height) {
    throw const FormatException('Image data is shorter than step * height');
  }
  return RosImage(
    header: header,
    height: height,
    width: width,
    encoding: encoding,
    step: step,
    isBigEndian: isBigEndian,
    data: data,
  );
}

RosGripper _readGripper(CdrReader reader) {
  final header = _readHeader(reader);
  final angle = reader.f64();
  final distance = reader.f64();
  final effort = reader.f64();
  final velocity = reader.f64();
  final enable = reader.boolean();
  final setZero = reader.boolean();
  final error = reader.boolean();
  final voltage = reader.f64();
  final driverTemp = reader.f64();
  final motorTemp = reader.f64();
  final busCurrent = reader.f64();
  final status = reader.string();
  return RosGripper(
    header: header,
    angle: angle,
    distance: distance,
    effort: effort,
    velocity: velocity,
    enable: enable,
    setZero: setZero,
    error: error,
    voltage: voltage,
    driverTemp: driverTemp,
    motorTemp: motorTemp,
    busCurrent: busCurrent,
    status: status,
  );
}

RosTeleopStatus _readTeleopStatus(CdrReader reader) {
  final topics = _readStrings(reader);
  return RosTeleopStatus(
    topics: topics,
    fail: reader.boolean(),
    quit: reader.boolean(),
  );
}

List<String> _readStrings(CdrReader reader) {
  final count = reader.u32();
  return List<String>.generate(count, (_) => reader.string(), growable: false);
}

List<double> _readDoubles(CdrReader reader) {
  final count = reader.u32();
  return List<double>.generate(count, (_) => reader.f64(), growable: false);
}
