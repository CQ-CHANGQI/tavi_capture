import 'package:go_router/go_router.dart';

import '../core/app_state.dart';
import '../screens/collect.dart';
import '../screens/control.dart';
import '../screens/review.dart';
import '../screens/setup.dart';
import '../ui/shell.dart';
import 'app_routes.dart';

/// 四个页面：连接、采集、查看数据、手动模式。设置是弹层。
GoRouter createRouter(AppState app) {
  return GoRouter(
    initialLocation: app.robotOk
        ? AppRoutes.forMode(app.mode)
        : AppRoutes.setup,
    redirect: (context, state) {
      if (!app.robotOk && state.matchedLocation != AppRoutes.setup) {
        return AppRoutes.setup;
      }
      return null;
    },
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: AppRoutes.setup,
            builder: (context, state) => const SetupScreen(),
          ),
          GoRoute(
            path: AppRoutes.collect,
            builder: (context, state) => const CollectScreen(),
            onExit: (context, state) {
              if (app.recording) {
                app.toast('采集中不能切换模式');
                return false;
              }
              app.closePlayback();
              return true;
            },
          ),
          GoRoute(
            path: AppRoutes.review,
            builder: (context, state) => const ReviewScreen(),
            onExit: (context, state) {
              app.closePlayback();
              return true;
            },
          ),
          GoRoute(
            path: AppRoutes.control,
            builder: (context, state) => const ControlScreen(),
          ),
        ],
      ),
    ],
  );
}
