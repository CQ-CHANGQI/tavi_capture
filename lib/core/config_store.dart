import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 端侧本地配置。目前只存机器人 IP，后续可扩展。
class ConfigStore {
  static const _fileName = 'config.json';

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<String?> loadRobotIp() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final data = jsonDecode(await file.readAsString());
      if (data is Map && data['robotIp'] is String) {
        final ip = (data['robotIp'] as String).trim();
        return ip.isEmpty ? null : ip;
      }
    } catch (error) {
      debugPrint('读取配置失败：$error');
    }
    return null;
  }

  Future<void> saveRobotIp(String ip) async {
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({'robotIp': ip}), flush: true);
    } catch (error) {
      debugPrint('保存配置失败：$error');
    }
  }
}
