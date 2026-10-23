# AGENTS.md

开发平台是 macOS。这个仓库需要在移动端和桌面端跑起来，不需要兼容 Web
（浏览器打不开裸 UDP 组播，实时预览只用 LCM 组播）。

## 平台

- 目标：Android、iOS、macOS、Windows、Linux。
- 不要加 `kIsWeb` 分支、web stub、`dart:html` 回退，也不要恢复 `web/` runner。
- `lib/` 下可以直接用 `dart:io`。

## 代码地图

- `lib/core/lcm/`：
  - `lcm_message.dart`：UDP 数据报 → LCM 消息，长包按发送方+seq 重组；
  - `preview_protocol.dart`：`preview_package_t` 分片重组、`joint_batch_t`
    解码、通道路由；
  - `lcm_receiver.dart`：组播、网卡、接收 isolate、统计；
  - `multicast_lock.dart`：Android MulticastLock。
  纯 Dart，不依赖 widget。
- `lib/core/mcap/`：MCAP over HTTP Range、CDR 解码（Image / CompressedImage /
  JointState / Statistics）。纯 Dart。
- `lib/core/app_state.dart`：全部页面的业务状态和动作，页面不自己存业务状态。
- `lib/core/live_preview.dart` / `playback.dart`：实时与回放两个控制器，
  负责解码 `ui.Image` 和给图表喂数据。
- `lib/router/`：`go_router` 路由表；`app_routes.dart` 是路径常量，
  `app_router.dart` 负责 `ShellRoute`、redirect 和离开采集页的 `onExit`。
- `lib/screens/`、`lib/ui/`：按 `端侧采集平板 2.html` 实现的界面，颜色和尺寸
  以 `lib/core/theme.dart` 为准。

## 约定

- 业务数据（任务、采集条、进程、日志）仍是原型模拟数据；接接口时改
  `AppState`，不要往 widget 里塞数据。
- 机器人 IP 来自 `ROBOT_IP` 或 `configuredIp`，目前只在内存，不跨启动保存；
  没有登录、角色、权限；模式只有 `collect / review / control`，默认 `review`，
  没有 `idle`。不要恢复已删除的首页、任务页、已采页、独立回看页和登录弹层。
- 实时链路只订阅、不发布；相机通道 `/preview/cameras/<name>`，关节
  `/preview/joint_batch`。
- 页面跳转走 go_router（`context.go/push/pushReplacement/pop`），不要再用
  `Navigator.push(MaterialPageRoute(...))` 或自己维护页面栈。
- UI 不直接开 socket / HTTP，走 `LivePreview` 和 `PlaybackController`。
- 新增页面先看原型里有没有，不自己发明交互。新增页面同时加 `AppRoutes`
  常量和 `app_router.dart` 里的 `GoRoute`。

## 检查

```bash
flutter analyze
flutter test
dart run tool/e2e_check.dart
```
