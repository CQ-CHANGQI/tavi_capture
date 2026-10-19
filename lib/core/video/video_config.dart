/// MJPEG 视频地址配置。
///
/// 默认用“连接页保存的机器人 IP + 8080 端口”：
///   `http://ROBOT_IP:8080/stream?topic=/cam1/image&type=mjpeg&width=...`
///
/// 视频服务和机器人不是同一台机器、或端口不同时，可以用 dart-define 覆盖：
///   flutter run -d macos --dart-define=ROBOT_IP=192.168.13.4
///   flutter run -d macos --dart-define=VIDEO_BASE=http://192.168.13.4:8080
///   flutter run -d macos --dart-define=VIDEO_PORT=8080
///
/// 摄像头 topic 也可以覆盖：
///   --dart-define=CAM_MAIN=/cam1/image
///   --dart-define=CAM_LEFT=/cam3/image
///   --dart-define=CAM_RIGHT=/cam4/image
const videoBaseOverride = String.fromEnvironment('VIDEO_BASE');
const videoPort = int.fromEnvironment('VIDEO_PORT', defaultValue: 8080);

/// 主视角：头戴相机（对应 lesson 的 cam_head）。
const camMainTopic = String.fromEnvironment(
  'CAM_MAIN',
  defaultValue: '/cam1/image',
);

/// 左腕相机。
const camLeftTopic = String.fromEnvironment(
  'CAM_LEFT',
  defaultValue: '/cam3/image',
);

/// 右腕相机。
const camRightTopic = String.fromEnvironment(
  'CAM_RIGHT',
  defaultValue: '/cam4/image',
);

String videoBaseUrl(String robotIp) {
  if (videoBaseOverride.isNotEmpty) {
    return videoBaseOverride.endsWith('/')
        ? videoBaseOverride.substring(0, videoBaseOverride.length - 1)
        : videoBaseOverride;
  }
  return 'http://$robotIp:$videoPort';
}

String cameraStreamUrl({
  required String robotIp,
  required String topic,
  int width = 640,
  int quality = 70,
}) {
  return '${videoBaseUrl(robotIp)}/stream'
      '?topic=$topic&type=mjpeg&width=$width&quality=$quality';
}
