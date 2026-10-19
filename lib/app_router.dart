import 'package:flutter/material.dart';

import 'app_routes.dart';
import 'core/models/take.dart';
import 'core/models/task.dart';
import 'core/network/ping_service.dart';
import 'core/state/app_state.dart';
import 'core/theme/app_colors.dart';
import 'features/auth/login_page.dart';
import 'features/capture/capture_page.dart';
import 'features/connect/connect_page.dart';
import 'features/home/home_page.dart';
import 'features/robot/devices_page.dart';
import 'features/robot/move_page.dart';
import 'features/robot/recovery_page.dart';
import 'features/settings/settings_page.dart';
import 'features/takes/review_page.dart';
import 'features/takes/takes_page.dart';
import 'features/tasks/brief_page.dart';
import 'features/tasks/swap_page.dart';
import 'features/tasks/tasks_page.dart';

/// 命名路由表。页面跳转统一走这里。
Route<dynamic>? generateRoute(
  RouteSettings settings,
  PingCheck ping,
  bool enableVideo,
) {
  switch (settings.name) {
    case Routes.connect:
      return _route(settings, ConnectPage(ping: ping));
    case Routes.login:
      return _modalRoute(settings, const LoginPage());
    case Routes.home:
      return _route(settings, const HomePage());
    case Routes.tasks:
      return _route(settings, const TasksPage());
    case Routes.capture:
      final task = settings.arguments is Task
          ? settings.arguments as Task
          : (appState.tasks.isEmpty ? null : appState.tasks.first);
      if (task == null) {
        return _route(settings, const _NotFoundPage(message: '任务不存在'));
      }
      return _route(
        settings,
        CapturePage(task: task, enableVideo: enableVideo),
      );
    case Routes.takes:
      return _route(settings, const TakesPage(allPeople: false));
    case Routes.library:
      return _route(settings, const TakesPage(allPeople: true));
    case Routes.review:
      final take = settings.arguments is Take
          ? settings.arguments as Take
          : (appState.takes.isEmpty ? null : appState.takes.first);
      if (take == null) {
        return _route(settings, const _NotFoundPage(message: '采集条不存在'));
      }
      return _route(settings, ReviewPage(take: take));
    case Routes.brief:
      final task = settings.arguments is Task
          ? settings.arguments as Task
          : (appState.tasks.isEmpty ? null : appState.tasks.first);
      if (task == null) {
        return _route(settings, const _NotFoundPage(message: '任务不存在'));
      }
      return _modalRoute(settings, BriefPage(task: task));
    case Routes.swap:
      return _modalRoute(settings, const SwapPage());
    case Routes.settings:
      return _modalRoute(settings, const SettingsPage());
    case Routes.devices:
      return _modalRoute(settings, const DevicesPage());
    case Routes.move:
      return _modalRoute(settings, const MovePage());
    case Routes.recovery:
      return _modalRoute(settings, const RecoveryPage());
  }

  return _route(
    settings,
    _NotFoundPage(message: '页面不存在：${settings.name ?? '未知'}'),
  );
}

MaterialPageRoute<dynamic> _route(RouteSettings settings, Widget page) {
  return MaterialPageRoute<dynamic>(settings: settings, builder: (_) => page);
}

/// 透明弹窗路由：底层页面保留，外面盖一层暗色遮罩。
PageRouteBuilder<dynamic> _modalRoute(RouteSettings settings, Widget page) {
  return PageRouteBuilder<dynamic>(
    settings: settings,
    opaque: false,
    barrierDismissible: true,
    barrierColor: const Color(0xB8070D15),
    barrierLabel: '关闭',
    transitionDuration: const Duration(milliseconds: 150),
    reverseTransitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (_, animation, _, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

class _NotFoundPage extends StatelessWidget {
  const _NotFoundPage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(message, style: const TextStyle(color: AppColors.muted)),
      ),
    );
  }
}
