/// 机器人上的设备状态。
class DeviceStatus {
  DeviceStatus({required this.name, required this.detail, required this.ok});

  final String name;
  String detail;
  bool ok;
}
