import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/scope.dart';
import '../core/theme.dart';

/// 手动模式：机械臂回位 + 底盘方向控制。没有一键连接。
class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  String _message = '按住方向按钮移动，松开停止。';
  int _speed = 50;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ready = app.armServiceOk && app.baseServiceOk;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final title = Row(
                children: [
                  const Text(
                    '手动模式',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 16),
                  Hint(ready ? '双臂/底盘服务已就绪' : '等待双臂/底盘服务启动'),
                ],
              );
              return constraints.maxWidth < 720
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        title,
                        const SizedBox(height: 8),
                        const Hint('连接底盘和双臂后才能控制'),
                      ],
                    )
                  : title;
            },
          ),
          const SizedBox(height: 16),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 800;
                final arm = _zone(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '双臂服务',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: C.legendInk,
                        ),
                      ),
                      const SizedBox(height: 10),
                      AppButton(
                        '回 home 点',
                        kind: BtnKind.ghost,
                        height: 46,
                        onPressed: ready ? app.cycleHome : null,
                      ),
                    ],
                  ),
                );
                final chassis = _zone(_chassis(app, ready, narrow));
                if (narrow) {
                  return ListView(
                    children: [
                      arm,
                      const SizedBox(height: 12),
                      SizedBox(height: 440, child: chassis),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 65, child: arm),
                    const SizedBox(width: 16),
                    Expanded(flex: 135, child: chassis),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _zone(Widget child) =>
      Panel(color: C.input, padding: const EdgeInsets.all(12), child: child);

  Widget _chassis(AppState app, bool ready, bool narrow) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '底盘控制',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: C.legendInk,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const gap = 10.0;
                final size = ((constraints.maxWidth - 2 * gap - 16) / 5).clamp(
                  40.0,
                  104.0,
                );
                final radius = (size * 0.19).clamp(10.0, 20.0);
                Widget pad(String label) => SquareButton(
                  label,
                  size: size,
                  radius: radius,
                  fontSize: size * 0.44,
                  onPressed: ready ? () {} : null,
                );
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _turn('↺', size, ready, () => _hold('左转中…')),
                    const SizedBox(width: gap),
                    _dpad(size, pad),
                    const SizedBox(width: gap),
                    _turn('↻', size, ready, () => _hold('右转中…')),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text('移动速度', style: TextStyle(fontSize: 14, color: C.muted)),
            const SizedBox(width: 12),
            Expanded(
              child: AppSelect<int>(
                value: _speed,
                items: const [
                  (25, '慢 25%'),
                  (50, '中 50%'),
                  (75, '快 75%'),
                  (100, '最快 100%'),
                ],
                onChanged: ready
                    ? (value) => setState(() => _speed = value ?? _speed)
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          _message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: C.muted),
        ),
      ],
    );
  }

  Widget _turn(String label, double size, bool ready, VoidCallback hold) =>
      Listener(
        onPointerDown: (_) {
          if (ready) hold();
        },
        onPointerUp: (_) => ready ? _release() : null,
        onPointerCancel: (_) => ready ? _release() : null,
        child: SquareButton(
          label,
          size: size,
          radius: size / 2,
          fontSize: size * 0.42,
          color: C.warn,
          onPressed: ready ? () {} : null,
        ),
      );

  Widget _dpad(double size, Widget Function(String) pad) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: size, height: size),
          const SizedBox(width: 8),
          _holdButton(pad('↑'), '前进'),
          const SizedBox(width: 8),
          SizedBox(width: size, height: size),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _holdButton(pad('←'), '左移'),
          const SizedBox(width: 8),
          SizedBox(width: size, height: size),
          const SizedBox(width: 8),
          _holdButton(pad('→'), '右移'),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: size, height: size),
          const SizedBox(width: 8),
          _holdButton(pad('↓'), '后退'),
          const SizedBox(width: 8),
          SizedBox(width: size, height: size),
        ],
      ),
    ],
  );

  Widget _holdButton(Widget child, String action) => Listener(
    onPointerDown: (_) {
      final app = AppScope.of(context);
      if (app.armServiceOk && app.baseServiceOk) _hold('$action中…');
    },
    onPointerUp: (_) => _release(),
    onPointerCancel: (_) => _release(),
    child: child,
  );

  void _hold(String message) => setState(() => _message = message);

  void _release() => setState(() => _message = '已停止。');
}
