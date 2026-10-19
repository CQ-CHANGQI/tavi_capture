/// Web 端没有 ICMP，无法真 ping。
/// 这里返回提示，保证 Web 平台仍能编译和运行。
class PingService {
  static Future<String?> ping(String ip) async {
    return 'Web 端不支持 ICMP ping，请用桌面或平板端运行。';
  }
}
