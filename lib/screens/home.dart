import 'package:flutter/material.dart';

import '../core/scope.dart';
import '../core/theme.dart';

/// 登录后选择模式：数据采集 / 查看数据。
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final canView = app.canViewLibrary;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
        child: Wrap(
          spacing: 24,
          runSpacing: 24,
          alignment: WrapAlignment.center,
          children: [
            _ModeCard(
              title: '数据采集',
              description: '进入我的任务。本机任务都可以采集。',
              button: '进入采集',
              onTap: app.enterCollectMode,
            ),
            _ModeCard(
              title: '查看数据',
              description: canView
                  ? '工程师可查看并删除当前这台机器人工控上所有人的采集条，不采集。'
                  : '采集员只能进数据采集。',
              button: canView ? '进入查看' : '采集员不可用',
              onTap: canView ? app.enterLibrary : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.description,
    required this.button,
    required this.onTap,
  });

  final String title;
  final String description;
  final String button;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Opacity(
      opacity: disabled ? 0.45 : 1,
      child: SizedBox(
        width: 420,
        height: 240,
        child: Material(
          color: C.panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: C.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Text(
                      description,
                      style: const TextStyle(
                        fontSize: 15,
                        color: C.muted,
                        height: 1.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppButton(button, block: true, height: 48, onPressed: onTap),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
