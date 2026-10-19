// 编译时按平台选实现：
// - 有 dart:io 的桌面/移动端用真正的 ICMP ping
// - Web 没有 ICMP，返回一条明确提示，保证 Web 还能编译运行
export 'ping_service_web.dart' if (dart.library.io) 'ping_service_io.dart';
