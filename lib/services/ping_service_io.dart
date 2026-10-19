import 'package:dart_ping/dart_ping.dart';

/// 真正的 ICMP ping。
///
/// macOS / Windows / Linux / Android 调系统 ping 命令；
/// iOS 用 dart_ping 自带的原生 ICMP 实现。
class PingService {
  /// 返回 null 表示 ping 通；返回一段文字表示失败原因。
  static Future<String?> ping(String ip) async {
    try {
      // count: 1 只发一个包；timeout: 1 最多等 1 秒。
      final event = await Ping(ip, count: 1, timeout: 1).stream.first;

      if (event is PingResponse) {
        return null;
      }

      return 'ping 不通 $ip。检查机器人是否上电、和平板在同一网段。';
    } catch (error) {
      return 'ping $ip 失败：$error';
    }
  }
}
