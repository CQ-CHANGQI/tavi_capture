import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android 的 `WifiManager.MulticastLock`：很多设备在息屏或后台会过滤组播，
/// 实时预览启动后持有它（当前连接成功即启动，离开采集页不停止）。原生实现见
/// `MainActivity.kt`，其他平台是空操作。
class AndroidMulticastLock {
  static const MethodChannel _channel = MethodChannel('tavi/multicast');
  static bool _held = false;

  static Future<void> acquire() async {
    if (_held || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('acquire');
      _held = true;
    } on MissingPluginException {
      // 桌面 / 测试环境没有原生实现。
    } catch (error) {
      debugPrint('MulticastLock.acquire 失败：$error');
    }
  }

  static Future<void> release() async {
    if (!_held) return;
    _held = false;
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('release');
    } on MissingPluginException {
      // 忽略。
    } catch (error) {
      debugPrint('MulticastLock.release 失败：$error');
    }
  }
}
