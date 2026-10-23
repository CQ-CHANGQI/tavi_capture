import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/app_state.dart';
import 'core/scope.dart';
import 'core/theme.dart';
import 'router/app_router.dart';

class TaviApp extends StatefulWidget {
  const TaviApp({super.key, this.state});

  /// 测试可以注入一个自己的 AppState。
  final AppState? state;

  @override
  State<TaviApp> createState() => _TaviAppState();
}

class _TaviAppState extends State<TaviApp> {
  late final AppState _state;
  late final GoRouter _router;
  late final bool _ownsState;

  @override
  void initState() {
    super.initState();
    _ownsState = widget.state == null;
    _state = widget.state ?? AppState();
    _router = createRouter(_state);
  }

  @override
  void dispose() {
    _router.dispose();
    if (_ownsState) _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppScope(
    state: _state,
    child: MaterialApp.router(
      title: 'Tavi Capture',
      debugShowCheckedModeBanner: false,
      theme: taviTheme(),
      routerConfig: _router,
    ),
  );
}
