import 'dart:convert';
import 'dart:io';

/// 记住上次连接的机器人 IP。
///
/// 不引第三方插件：桌面用 `$HOME/.tavi_capture/ip.json`，移动端 HOME
/// 不可写时退回系统临时目录（最坏情况是下次启动回到默认 IP）。
class IpStore {
  IpStore({String? path}) : path = path ?? _defaultPath();

  final String path;

  static String _defaultPath() {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null && home.isNotEmpty && home != '/') {
      return '$home/.tavi_capture/ip.json';
    }
    return '${Directory.systemTemp.path}/tavi_capture/ip.json';
  }

  Future<String?> load() async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map && decoded['ip'] is String) {
        return decoded['ip'] as String;
      }
    } catch (_) {
      // 文件损坏/没权限就当没存过。
    }
    return null;
  }

  Future<void> save(String ip) async {
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({'ip': ip}));
    } catch (_) {
      // 写不了就算了，不影响本次连接。
    }
  }
}
