import 'package:flutter/material.dart';

import '../../app_routes.dart';
import '../models/connect_state.dart';
import '../state/app_state.dart';
import 'top_bar.dart';

/// 所有内页的统一外壳：顶栏 + 内容区。
class AppPage extends StatelessWidget {
  const AppPage({super.key, required this.child, this.showDevices = false});

  final Widget child;
  final bool showDevices;

  @override
  Widget build(BuildContext context) {
    final connected = appState.connection == ConnectState.connected;
    final route = ModalRoute.of(context)?.settings.name;
    final readOnly = [
      Routes.capture,
      Routes.library,
      Routes.review,
    ].contains(route);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TopBar(
              state: appState.connection,
              userName: appState.userName,
              onStatusTap: () => Navigator.pushNamed(
                context,
                Routes.settings,
                arguments: readOnly,
              ),
              onSettings: () => Navigator.pushNamed(
                context,
                Routes.settings,
                arguments: readOnly,
              ),
              onDevices: connected
                  ? () => Navigator.pushNamed(context, Routes.devices)
                  : null,
              onMove: connected && !readOnly
                  ? () => Navigator.pushNamed(context, Routes.move)
                  : null,
              onLogin: () => Navigator.pushNamed(context, Routes.login),
              showDevices: showDevices,
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
