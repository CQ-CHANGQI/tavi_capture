import '../core/models.dart';

/// 页面路径。业务状态在 [AppState]，这里只负责页面栈。
abstract final class AppRoutes {
  static const setup = '/setup';
  static const collect = '/collect';
  static const review = '/review';
  static const control = '/control';

  static String forMode(PageMode mode) => switch (mode) {
    PageMode.collect => collect,
    PageMode.review => review,
    PageMode.control => control,
  };
}
