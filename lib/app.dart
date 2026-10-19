import 'package:flutter/material.dart';

import 'app_router.dart';
import 'app_routes.dart';
import 'core/network/ping_service.dart';
import 'core/theme/app_colors.dart';

/// App 根组件：主题 + 命名路由。
class TaviApp extends StatelessWidget {
  const TaviApp({
    super.key,
    this.ping = PingService.ping,
    this.enableVideo = true,
  });

  /// 默认用真的 ping；测试时可以换成假函数。
  final PingCheck ping;

  /// 测试时关掉实时视频，避免启动真实网络连接和帧率定时器。
  final bool enableVideo;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tavi Capture',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.brand,
          brightness: Brightness.dark,
        ),
      ),
      initialRoute: Routes.connect,
      onGenerateRoute: (settings) => generateRoute(settings, ping, enableVideo),
    );
  }
}
