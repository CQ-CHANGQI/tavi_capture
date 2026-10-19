import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/modal_panel.dart';

/// 底盘移动弹窗。
class MovePage extends StatefulWidget {
  const MovePage({super.key});

  @override
  State<MovePage> createState() => _MovePageState();
}

class _MovePageState extends State<MovePage> {
  final _speed = TextEditingController(text: '0.20');
  double _x = 0;
  double _y = 0;
  int _angle = 0;

  @override
  void dispose() {
    _speed.dispose();
    super.dispose();
  }

  double? get _currentSpeed {
    final value = double.tryParse(_speed.text);
    if (value == null || value < 0.05 || value > 0.5) {
      return null;
    }
    return value;
  }

  void _move(int dx, int dy) {
    final speed = _currentSpeed;
    if (speed == null) {
      showToast(context, '速度需在 0.05–0.50 米/秒');
      return;
    }

    final distance = speed * 0.5;
    final radians = _angle * pi / 180;

    setState(() {
      _x += dx * distance * cos(radians) - dy * distance * sin(radians);
      _y += dx * distance * sin(radians) + dy * distance * cos(radians);
    });
  }

  void _turn() {
    setState(() => _angle = (_angle + 15) % 360);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ModalPanel(
        title: '底盘移动',
        width: 760,
        onClose: () => Navigator.maybePop(context),
        child: Wrap(
          spacing: 28,
          runSpacing: 20,
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _pad(),
            SizedBox(width: 250, child: _info()),
          ],
        ),
      ),
    );
  }

  Widget _pad() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 76, height: 52),
            const SizedBox(width: 8),
            _padButton('↑', () => _move(0, -1)),
            const SizedBox(width: 8),
            const SizedBox(width: 76, height: 52),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _padButton('←', () => _move(-1, 0)),
            const SizedBox(width: 8),
            _padButton('↻', _turn, secondary: true),
            const SizedBox(width: 8),
            _padButton('→', () => _move(1, 0)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 76, height: 52),
            const SizedBox(width: 8),
            _padButton('↓', () => _move(0, 1)),
            const SizedBox(width: 8),
            const SizedBox(width: 76, height: 52),
          ],
        ),
      ],
    );
  }

  Widget _padButton(
    String label,
    VoidCallback onPressed, {
    bool secondary = false,
  }) {
    return SizedBox(
      width: 76,
      child: AppButton(
        label,
        kind: secondary ? AppButtonKind.secondary : AppButtonKind.primary,
        onPressed: onPressed,
        height: 52,
        fontSize: 22,
      ),
    );
  }

  Widget _info() {
    final speed = double.tryParse(_speed.text);
    final distance = speed == null || speed < 0.05 || speed > 0.5
        ? null
        : speed * 0.5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'X ${_x.toStringAsFixed(2)} m　Y ${_y.toStringAsFixed(2)} m　朝向 $_angle°',
          style: const TextStyle(fontSize: 13, color: Color(0xFFD5E2EF)),
        ),
        const SizedBox(height: 14),
        const Text(
          '移动速度（米/秒）',
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _speed,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(color: AppColors.ink),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.input,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 11,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.brand),
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          '允许 0.05–0.50。速度越高，每次移动距离越远。',
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        const SizedBox(height: 8),
        Text(
          distance == null
              ? '速度需在 0.05–0.50 米/秒。'
              : '当前每次移动 ${distance.toStringAsFixed(2)} 米。',
          style: const TextStyle(fontSize: 12, color: Color(0xFFD5E2EF)),
        ),
        const SizedBox(height: 12),
        AppButton(
          '底盘停止',
          kind: AppButtonKind.danger,
          onPressed: () => showToast(context, '底盘已停止（模拟）'),
        ),
      ],
    );
  }
}
