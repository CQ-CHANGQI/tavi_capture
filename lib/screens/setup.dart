import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/scope.dart';
import '../core/theme.dart';

/// 首屏：填机器人 IP，用户点连接。已保存 IP 时由 AppState 自动连接。
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  String? _ip;
  bool _edited = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_edited) _ip = AppScope.of(context).configuredIp;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ip = _ip ?? app.configuredIp;
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
              : app.connectError.isEmpty
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
              ? '正在按填写的 IP 连接机器人。'
              : app.connectError.isEmpty
              ? '已从配置读取上次的 IP。确认机器人上电、和平板同一网段后，点击“保存并连接”。'
              : '机器人没有响应。确认上电和网段后，再保存连接。',
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
            onChanged: (value) {
              _edited = true;
              setState(() => _ip = value);
            },
          ),
          const SizedBox(height: 16),
          AppButton(
            app.connecting
                ? '正在连接…'
                : app.connectError.isEmpty
                ? '保存并连接'
                : '重新连接',
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
    if (app.connectError.isEmpty) {
      return const SizedBox.shrink();
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
            app.connectError,
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
