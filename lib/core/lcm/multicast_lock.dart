import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Acquires Android's `WifiManager.MulticastLock` while the preview is live.
///
/// Many Android devices silently filter multicast packets when the screen is
/// off or the app is in the background. The native side lives in
/// `MainActivity.kt`; this is a no-op on every other platform.
class MulticastLock {
  static const MethodChannel _channel = MethodChannel('tavi/multicast');
  static bool _held = false;

  static Future<void> acquire() async {
    if (defaultTargetPlatform != TargetPlatform.android || _held) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('acquire');
      _held = true;
    } on MissingPluginException {
      // Running without the Android host (e.g. desktop): nothing to do.
    } catch (error) {
      debugPrint('MulticastLock.acquire failed: $error');
    }
  }

  static Future<void> release() async {
    if (!_held) return;
    _held = false;
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('release');
    } on MissingPluginException {
      // Ignore.
    } catch (error) {
      debugPrint('MulticastLock.release failed: $error');
    }
  }
}
