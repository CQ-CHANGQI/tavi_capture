import 'package:flutter/widgets.dart';

import 'app_state.dart';

/// 把 [AppState] 放进 widget 树；notifyListeners 时依赖它的页面自动重建。
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope 不在 widget 树里');
    return scope!.notifier!;
  }
}
