# AGENTS.md

本文件是开发规范。安装、运行、平台支持、目录结构看 [README.md](README.md)；模式和接口约定看 [doc/robot-api.md](doc/robot-api.md)。

## 动手前

- 先读 README、`doc/robot-api.md` 里相关接口/模式，再看要改的代码。
- 不凭记忆补页面、字段或交互；文档没写的先确认，不要自己发明。
- 先理解完整调用链再改，取能解决问题的最小改动。
- 接口/模式变了，同步改 `doc/robot-api.md`；页面交互看最新原型，不要代码一套、文档一套。

## 架构边界

- Widget 只做渲染和局部 UI 状态；业务状态、动作放 `AppState`。
- 实时流和回放各自用 `LivePreview` / `PlaybackController`，不要把这些状态塞进 `AppState` 每帧 notify。
- Widget 不直接开 socket / HTTP；走 `AppState` 或现有 Controller。
- 页面跳转只走 `go_router`，不要用 `Navigator.push(MaterialPageRoute(...))`，不要自己维护页面栈。
- 优先复用现有 `theme.dart` 组件和已有 Controller，不复制一套相似实现。
- 不新增依赖，除非标准库/现有依赖确实解决不了；加之前说明理由。
- 不支持 Web：不要加 `kIsWeb` 分支、web stub、`dart:html` 或 `web/` runner。
- 平台配置（iOS 组播 entitlement、Android MulticastLock、macOS 沙箱）不要删。

## 代码规范

- 提交前跑 `dart format`；不要留调试 print、注释掉的代码、未使用字段。
- 一个改动只做一件事，不顺手大重构。
- 异步回调检查 `mounted`；Controller、Timer、Listener 在 `dispose` 里释放。
- 高频数据不要每帧 `notifyListeners()` 重建整页，只重建对应面板。
- 接口字段只保留一份定义，不要在 widget 里另造一套模型。

## 测试

- 完成前至少跑：
  - `flutter analyze`
  - `flutter test`
  - `dart run tool/e2e_check.dart`（涉及接收链路时）
- 非 trivial 逻辑补一个最小测试；改行为时同步改已有测试。
- 不要为了过测试删断言或放宽预期。
- 文档改动也要保证不留下失效链接和旧路径。

## 不要做

- 不要恢复已删除的首页、任务页、已采页、登录页/弹层、独立回看页。
- 不要在 widget 里直接写业务数据或网络请求。
- 不要引入 `Navigator` 页面栈、Web 支持、未使用依赖。
- 不要把产品需求、接口字段、设计长文写回 `AGENTS.md`；它们属于 `README.md` 和 `doc/`。
