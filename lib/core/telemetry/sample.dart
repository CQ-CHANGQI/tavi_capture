import 'dart:typed_data';

const cameraLabels = {
  'cam_head': '主视角',
  'cam_left': '左腕',
  'cam_right': '右腕',
  'cam_chest': '全景',
};

String? cameraOf(String topic) {
  for (final name in cameraLabels.keys) {
    if (topic.split('/').contains(name)) return name;
  }
  return null;
}

/// Names, rather than array positions, identify joints across every source.
class JointSample {
  const JointSample(this.timeNs, this.state, this.command);
  final int timeNs;
  final Map<String, double> state;
  final Map<String, double> command;
}

class CameraFrame {
  const CameraFrame(this.timeNs, this.bytes);
  final int timeNs;
  final Uint8List bytes;
}

String clockText(Duration duration) {
  final seconds = duration.inSeconds.clamp(0, 999999);
  return '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
      '${(seconds % 60).toString().padLeft(2, '0')}';
}
