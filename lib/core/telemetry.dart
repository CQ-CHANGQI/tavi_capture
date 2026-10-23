/// 端侧操作埋点。当前只记录事件，不接上报 SDK；上报留给后续接口。
class TelemetryEvent {
  const TelemetryEvent(this.name, this.params);

  final String name;
  final Map<String, Object?> params;
}

class Telemetry {
  static const _maxEvents = 500;
  final List<TelemetryEvent> events = [];

  void track(String name, [Map<String, Object?> params = const {}]) {
    if (events.length >= _maxEvents) events.removeAt(0);
    events.add(TelemetryEvent(name, Map.unmodifiable(params)));
  }
}
