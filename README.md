# Tavi Capture · 端侧采集平板

按端侧采集平板原型重做的 Flutter 客户端：连接机器人 → 默认进入查看数据 → 顶部三个模式切换。业务数据仍是模拟数据，**画面和关节是真数据**：

- 实时预览：LCM UDP 组播（相机 4 路 + 关节 `joint_batch_t`）。接收 isolate
  负责组帧、分片重组和关节解码；相机 JPEG/PNG 在 UI isolate 解码上屏，UI
  只拿完整帧。
- 回放：MCAP over HTTP Range，只读 footer/summary 和需要的 chunk，几 GB 的
  包也能按需打开。

平台：Android、iOS、macOS、Windows、Linux。**不支持 Web**（浏览器无法打开
裸 UDP 组播 socket）。

## 页面

| 页面 | 说明 |
|---|---|
| 连接 | 从本地配置读 IP，启动自动连接；失败留在 P0 |
| 采集 | 默认第一个任务/人员、二次确认切换、实时四路画面（2×2）、进度、计时、录制、FSM、作废 |
| 查看数据 | 全部任务/人员/状态筛选、分页、本条信息 / 回放三态、最大化、内嵌回放 |
| 手动模式 | 双臂回位、底盘方向键、速度；双臂/底盘独立可用；没有一键连接 |
| 设置 | 基本设置（保存并连接）、进程管理、操作日志、设备状态 |
| 异常恢复 | 回位确认 / 作废确认 / 启动服务失败 |

不再有首页、登录页、我的任务页、已采页、独立回看页、`idle` 模式。

## 结构

```
lib/
  core/
    lcm/
      lcm_message.dart      UDP 数据报 → LCM 消息（长包按发送方+seq 重组）
      preview_protocol.dart preview_package_t 重组、joint_batch_t 解码、通道路由
      lcm_receiver.dart     组播/网卡/接收 isolate/统计，向上暴露帧和关节流
      multicast_lock.dart   Android MulticastLock
    mcap/        MCAP Range 读取、CDR 解码（Image / CompressedImage / JointState / Statistics）
    app_state.dart   全部业务状态与动作（页面跳转归 go_router）
    config_store.dart 本地 config.json（机器人 IP）
    telemetry.dart     埋点事件队列（上报未接）
    live_preview.dart  实时预览控制器：帧解码 + fps + 在线状态
    playback.dart      回放控制器：时间轴、seek、四路画面、三组关节曲线
    models.dart、theme.dart、scope.dart
  router/       app_routes（路径常量）、app_router（go_router 路由表 + ShellRoute）
  screens/      setup / collect / review / control / modals
  ui/           shell（AppShell：顶栏 + 弹层 + toast）、相机网格、关节图、播放条、回放面板
tool/           mock_publisher.py、e2e_check、live_check、mcap_check
server/         单文件 MCAP Range 服务器（联调用）
```

## 当前实现边界

- 真实链路：LCM 实时画面/关节、MCAP 回放，以及 Android/iOS/macOS/Windows/Linux
  的网络配置。
- 配置：新增 `path_provider`，启动时读 App 私有目录的 `config.json`；有已保存
  IP 就自动连接，连接成功写回配置。设置页「保存并连接」立即重连。
- 页面栈：go_router，4 个页面通过 `AppRoutes` 路径切换；顶栏/弹层/toast 由
  `ShellRoute` 保持，`AppState` 不再保存当前页面。
- mock：任务、采集条、进程、日志、设备状态、采集计时/FSM、手动控制回位、
  服务启停；采集条只写内存，录制服务未接。没有登录和权限。
- 埋点：只写内存事件队列，上报 SDK/接口未接。
- `doc/robot-api.md` 是接后端的目标方案，不是当前实现；
  `doc/lcm-design-dev-full.md`、`doc/mcap-playback-design.md` 描述的是当前实现。

## 运行

```bash
flutter pub get

# 没有机器人时只看 UI：跳过 IP 探测
flutter run -d macos --dart-define=DEMO=true

# 真机
flutter run -d macos --dart-define=ROBOT_IP=192.168.13.4
flutter run -d android --dart-define=ROBOT_IP=192.168.13.4
```

常用 `--dart-define`：

| 变量 | 默认 | 说明 |
|---|---|---|
| `ROBOT_IP` | `192.168.13.4` | 首次启动默认 IP；有 `config.json` 时以配置为准 |
| `MCAP_URL` | `http://<ROBOT_IP>:8090/rosbag_0.mcap` | 回放地址 |
| `DEMO` | `false` | 跳过机器人探测，方便看 UI |
| `LCM_GROUP` / `LCM_PORT` | `239.255.76.67:7667` | 相机组播 |
| `LCM_JOINT_GROUP` / `LCM_JOINT_PORT` | `239.255.76.68:7668` | 关节组播 |
| `LCM_IFACE` | 空 | 只加入指定网卡 |
| `LCM_ALL` | `false` | 收组播里的所有通道，排查通道名时用 |

## 本地联调

```bash
# 1) 假相机 + 假关节（同一台机器）
python3 tool/mock_publisher.py --host 127.0.0.1

# 2) 假 MCAP 服务器（任意 .mcap 都行；server 是独立 Go module）
go -C server run . -file /path/to/data.mcap -addr 127.0.0.1:8090

# 3) App（DEMO 只是为了跳过 ping，实时画面照样收）
flutter run -d macos --dart-define=DEMO=true \
  --dart-define=MCAP_URL=http://127.0.0.1:8090/data.mcap
```

`tool/mock_publisher.py --help` 可以调相机名、帧率、关节数量；默认发
`cam_head/cam_chest/cam_left/cam_right` 四路 640×360 JPEG。

## 检查

```bash
flutter analyze
flutter test
dart run tool/e2e_check.dart    # Python 发布端 → Dart 接收端，端到端
dart run tool/live_check.dart 5 # 现场组播探针
dart run tool/mcap_check.dart http://<host>:8090/<file>.mcap  # MCAP 话题/解码
```

## 已知限制

- 任务、采集条、进程、日志仍是原型里的模拟数据；录制服务未接，
  「停止并保存」只写内存，不会真的上传。
- 没有登录、角色、权限；页面只有连接、采集、查看数据、手动模式，设置是弹层。
- 机器人 IP 已落盘到 App 私有目录 `config.json`；启动自动连接，设置页保存后
  立即重连。首次启动没有配置时停在 P0。
- 模式和机器人/云端接口的当前约定以 [`doc/robot-api.md`](doc/robot-api.md) 为准；
  代码里的业务数据还没接真实接口。
- 每一条采集条都指向同一个 `MCAP_URL` 或默认地址，这是原型行为；接后端后按
  记录存地址。
- MCAP 只支持未压缩 / `zlib` chunk，且文件必须带 summary。
- 实时关节流在接收端解码，但当前没有实时关节面板；关节曲线只在 MCAP 回放里。
- 设备掉线弹窗、60s 延迟杀服务、回位点循环、日志下载、任务按型号×工位筛选、
  埋点上报都还是 TODO，等机器人/云端接口或产品确认。
- 采集说明目前只有文字；PRD 里的图片等云端任务接口有字段后再补。
- iOS 14+ 接收组播需要 Apple 的 `com.apple.developer.networking.multicast`
  entitlement（需申请，仓库里不放，避免签名失败）；`Info.plist` 已有本地网络说明。
- Android 已声明 `CHANGE_WIFI_MULTICAST_STATE`；实时预览从连接成功起持有
  `MulticastLock`，直到 App 退出（离开采集页不会停实时链路）。
- Windows 需要放行 UDP 7667/7668（专用网络）。
