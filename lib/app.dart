import 'package:flutter/material.dart';

import 'core/app_state.dart';
import 'core/scope.dart';
import 'core/theme.dart';
import 'ui/shell.dart';

class TaviApp extends StatefulWidget {
  const TaviApp({super.key, this.state});

  /// 测试可以注入一个自己的 AppState。
  final AppState? state;

  @override
  State<TaviApp> createState() => _TaviAppState();
}

class _TaviAppState extends State<TaviApp> {
  late final AppState _state;
  late final bool _ownsState;

  @override
  void initState() {
    super.initState();
    _ownsState = widget.state == null;
    _state = widget.state ?? AppState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _state.boot();
    });
  }

  @override
  void dispose() {
    if (_ownsState) _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppScope(
    state: _state,
    child: MaterialApp(
      title: 'Tavi Capture',
      debugShowCheckedModeBanner: false,
      theme: taviTheme(),
      home: const Shell(),
    ),
  );
}
