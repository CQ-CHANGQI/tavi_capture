import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'connect_page.dart';
import 'services/ping_service.dart';

void main() {
  runApp(const TaviApp());
}

/// App 根组件：只负责全局主题和首屏。
class TaviApp extends StatelessWidget {
  const TaviApp({super.key, this.ping = PingService.ping});

  /// 默认用真的 ping；测试时可以换成假函数。
  final PingCheck ping;

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
      home: ConnectPage(ping: ping),
    );
  }
}
