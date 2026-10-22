import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/scope.dart';
import '../core/theme.dart';

/// 首屏：连接机器人。自动连接失败就停在这里，改 IP 重连。
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  String? _ip;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ip ??= AppScope.of(context).savedIp;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ip = _ip ?? app.savedIp;
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final brand = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          app.connecting
              ? '正在连接'
              : app.robotOk
              ? '连接机器人'
              : '无法连接机器人',
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          app.connecting
              ? '按已保存的 IP 连接机器人。连上之前顶栏不展示设备状态。'
              : app.robotOk
              ? '填写机器人 IP。保存后会记住，下次打开自动连接。'
              : '已按上次保存的 IP 自动连接，但机器人没有响应。确认上电和网段后，再保存连接。',
          style: const TextStyle(fontSize: 16, color: C.muted, height: 1.6),
        ),
      ],
    );

    final card = Panel(
      padding: const EdgeInsets.all(18),
      radius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('机器人 IP', style: TextStyle(fontSize: 12, color: C.muted)),
          const SizedBox(height: 6),
          IpSegments(
            initialIp: ip,
            enabled: !app.connecting,
            onChanged: (value) => setState(() => _ip = value),
          ),
          const SizedBox(height: 16),
          AppButton(
            app.connecting ? '正在连接…' : '保存并连接',
            block: true,
            height: 44,
            onPressed: app.connecting ? null : () => app.connect(ip),
          ),
          const SizedBox(height: 12),
          _status(app, ip),
        ],
      ),
    );

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: wide
            ? Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 360, child: brand),
                  const SizedBox(width: 28),
                  SizedBox(width: 420, child: card),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: brand,
                  ),
                  const SizedBox(height: 24),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: card,
                  ),
                ],
              ),
      ),
    );
  }

  Widget _status(AppState app, String ip) {
    if (app.connecting) {
      return _box(
        C.input,
        C.line,
        Text(
          '正在连接 $ip …',
          style: const TextStyle(fontSize: 15, color: C.softInk),
        ),
      );
    }
    if (app.robotOk) {
      return _box(
        const Color(0xff10291c),
        const Color(0xff246243),
        Text(
          '已连接 ${app.savedIp}',
          style: const TextStyle(fontSize: 15, color: Color(0xffb7ebc9)),
        ),
      );
    }
    return _box(
      const Color(0xff2a1516),
      const Color(0xff6e322d),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '连不上 $ip',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xffffb4ae),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            app.connectError.isEmpty
                ? '机器人无响应。检查已上电、和平板同一网段、IP 是否写对。'
                : app.connectError,
            style: const TextStyle(
              fontSize: 15,
              height: 1.55,
              color: Color(0xffffd0cb),
            ),
          ),
        ],
      ),
    );
  }

  Widget _box(Color color, Color border, Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: color,
      border: Border.all(color: border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: child,
  );
}
