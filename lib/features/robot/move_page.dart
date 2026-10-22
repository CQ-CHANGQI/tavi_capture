import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/modal_panel.dart';

/// Control layout only: telemetry access does not imply a robot command API.
class MovePage extends StatefulWidget {
  const MovePage({super.key});
  @override
  State<MovePage> createState() => _MovePageState();
}

class _MovePageState extends State<MovePage> {
  int _speed = 50;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: ModalPanel(
      title: '手动控制',
      width: 1000,
      onClose: () => Navigator.maybePop(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text('控制服务尚未接入', style: TextStyle(color: AppColors.muted)),
              AppButton('一键连接'),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 24,
            runSpacing: 18,
            alignment: WrapAlignment.center,
            children: [
              const SizedBox(
                width: 180,
                child: Column(
                  children: [
                    Text('双臂服务'),
                    SizedBox(height: 12),
                    AppButton('回 home 点', kind: AppButtonKind.secondary),
                  ],
                ),
              ),
              SizedBox(
                width: 350,
                child: Column(
                  children: [
                    const Text('底盘控制'),
                    const SizedBox(height: 12),
                    for (final row in [
                      ['↺', '↑', '↻'],
                      ['←', '', '→'],
                      ['', '↓', ''],
                    ])
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (final label in row)
                            Padding(
                              padding: const EdgeInsets.all(4),
                              child: SizedBox(
                                width: 82,
                                height: 72,
                                child: label.isEmpty
                                    ? null
                                    : AppButton(label, fontSize: 28),
                              ),
                            ),
                        ],
                      ),
                    Row(
                      children: [
                        const Text('移动速度'),
                        const SizedBox(width: 20),
                        Expanded(
                          child: DropdownButton<int>(
                            isExpanded: true,
                            value: _speed,
                            items: [
                              for (final (v, label) in [
                                (25, '慢 25%'),
                                (50, '中 50%'),
                                (75, '快 75%'),
                                (100, '最快 100%'),
                              ])
                                DropdownMenuItem(value: v, child: Text(label)),
                            ],
                            onChanged: (v) {
                              if (v != null) setState(() => _speed = v);
                            },
                          ),
                        ),
                      ],
                    ),
                    const Text(
                      '按住方向按钮移动，松开停止。',
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
