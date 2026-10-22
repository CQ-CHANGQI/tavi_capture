import 'package:flutter/material.dart';

import '../../app_routes.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_page.dart';

/// 登录后选择模式：数据采集 / 查看数据。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    // 原型是“先进首页，再弹登录”。没登录时在首帧后打开登录弹窗。
    if (appState.userName == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pushNamed(context, Routes.login);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Wrap(
              spacing: 24,
              runSpacing: 24,
              alignment: WrapAlignment.center,
              children: [
                SizedBox(
                  width: 420,
                  child: _ModeCard(
                    title: '数据采集',
                    description: '进入我的任务。本机任务都可以采集。',
                    button: '进入采集',
                    onTap: () => Navigator.pushNamed(
                      context,
                      appState.tasks.isEmpty ? Routes.tasks : Routes.capture,
                      arguments: appState.tasks.firstOrNull,
                    ),
                  ),
                ),
                SizedBox(
                  width: 420,
                  child: _ModeCard(
                    title: '查看数据',
                    description: (appState.isEngineer || appState.localSession)
                        ? '工程师可查看并删除当前这台机器人工控上所有人的采集条，不采集。'
                        : '采集员只能进数据采集。',
                    button: (appState.isEngineer || appState.localSession)
                        ? '进入查看'
                        : '采集员不可用',
                    onTap: (appState.isEngineer || appState.localSession)
                        ? () => Navigator.pushNamed(context, Routes.library)
                        : null,
                  ),
                ),
              ],
            ),
          ),
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Opacity(
          opacity: disabled ? 0.45 : 1,
          child: Container(
            height: 220,
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
            decoration: BoxDecoration(
              color: AppColors.panel,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.ink,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Text(
                    description,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.6,
                      color: AppColors.muted,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: AppButton(
                    button,
                    onPressed: onTap,
                    height: 48,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
