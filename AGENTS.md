# AGENTS.md

开发平台是 macOS。这个仓库需要在移动端和桌面端跑起来，不需要兼容 Web
（浏览器打不开裸 UDP 组播，实时预览只用 LCM 组播）。

## 平台

- 目标：Android、iOS、macOS、Windows、Linux。
- 不要加 `kIsWeb` 分支、web stub、`dart:html` 回退，也不要恢复 `web/` runner。
- `lib/` 下可以直接用 `dart:io`。

## 代码地图

- `lib/core/lcm/`：LCM 分帧、`preview_package_t` 分片重组、`joint_batch_t`
  解码、组播组管理、Android MulticastLock。纯 Dart，不依赖 widget。
- `lib/core/mcap/`：MCAP over HTTP Range、CDR 解码（Image / CompressedImage /
  JointState / Statistics）。纯 Dart。
- `lib/core/app_state.dart`：全部页面的状态和动作，页面不自己存业务状态。
- `lib/core/live_preview.dart` / `playback.dart`：实时与回放两个控制器，
  负责解码 `ui.Image` 和给图表喂数据。
- `lib/screens/`、`lib/ui/`：按 `端侧采集平板.html` 实现的界面，颜色和尺寸
  以 `lib/core/theme.dart` 为准。

## 约定

- 业务数据（任务、采集条、用户、进程、日志）仍是原型模拟数据；接接口时改
  `AppState`，不要往 widget 里塞数据。
- 实时链路只订阅、不发布；相机通道 `/preview/cameras/<name>`，关节
  `/preview/joint_batch`。
- UI 不直接开 socket / HTTP，走 `LivePreview` 和 `PlaybackController`。
- 新增页面先看原型里有没有，不自己发明交互；原型没有入口的页面可以补一个
  不改变布局的入口（当前补了「登录」和「已采 N 条」）。

## 检查

```bash
flutter analyze
flutter test
dart run tool/selftest.dart
dart run tool/e2e_check.dart
```
