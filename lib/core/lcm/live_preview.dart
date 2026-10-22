import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../telemetry/sample.dart';
import 'lcm_client.dart';

/// Page-scoped ownership keeps hidden pages from retaining UDP subscriptions.
class LivePreview extends ChangeNotifier {
  final cameras = <String, CameraFrame>{};
  final _arrivals = <String, List<DateTime>>{};
  JointSample? joints;
  LcmUpdate? diagnostics;
  String? error;
  LcmClient? _client;
  StreamSubscription<LcmUpdate>? _subscription;
  Timer? _ticker;
  bool _disposed = false;
  static const _lock = MethodChannel('tavi/multicast');

  double fps(String camera) {
    final arrivals = _arrivals[camera];
    if (arrivals == null || arrivals.length < 2) return 0;
    final span = arrivals.last.difference(arrivals.first).inMicroseconds;
    return span > 0 ? (arrivals.length - 1) * 1e6 / span : 0;
  }

  bool get online => cameraLabels.keys.every((c) => fps(c) > 0);

  Future<void> start() async {
    if (_disposed || _client != null) return;
    final client = _client = LcmClient();
    _subscription = client.updates.listen(
      (update) {
        if (_disposed) return;
        diagnostics = update;
        error = update.error;
        for (final entry in update.cameras.entries) {
          cameras[entry.key] = entry.value;
          (_arrivals[entry.key] ??= []).add(DateTime.now());
        }
        joints = update.joints ?? joints;
        notifyListeners();
      },
      onError: (Object e) {
        if (!_disposed) {
          error = '$e';
          notifyListeners();
        }
      },
    );
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final cutoff = DateTime.now().subtract(const Duration(seconds: 2));
      for (final arrivals in _arrivals.values) {
        arrivals.removeWhere((t) => t.isBefore(cutoff));
      }
      notifyListeners();
    });
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _lock.invokeMethod<void>('acquire');
      }
      if (_disposed) return;
      await client.start();
    } catch (e) {
      if (!_disposed) {
        error = '$e';
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _subscription?.cancel();
    _client?.dispose();
    if (defaultTargetPlatform == TargetPlatform.android) {
      unawaited(_lock.invokeMethod<void>('release').catchError((Object _) {}));
    }
    super.dispose();
  }
}
