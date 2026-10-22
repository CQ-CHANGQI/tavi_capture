# 端侧采集平板 LCM 实时数据链路技术评审

| 项目 | 内容 |
|---|---|
| 文档类型 | 技术方案评审 |
| 模块 | LCM 实时数据接收与渲染 |
| 客户端 | Flutter（Android / iOS / macOS / Windows / Linux） |
| 关联提交 | `60ad932` 重写接收层、`ac052ba` 实时优先策略、`603712c` LCM_ALL 与解码降采样、`6e09f20` 相机名归一 |
| 文档日期 | 2026-10-22 |
| 评审状态 | 待评审 |

## 1. 背景与目标

端侧采集平板需要实时显示机器人四路相机画面，并把关节状态/指令用于状态判断和曲线展示。机器人侧通过 LCM UDP 组播持续发布：

- 相机：`239.255.76.67:7667`，通道 `/preview/cameras/<name>`
- 关节：`239.255.76.68:7668`，通道 `/preview/joint_batch`

现场源端频率为 **60Hz**，单帧 JPEG 大小随分辨率和场景变化（常见几十 KB，压测到 150KB）。

本次技术评审的目标：

1. 说明 LCM 接收、分片重组、关节解码的完整实现。
2. 说明实时性策略：为什么采用“最新帧优先、允许丢帧”，延迟如何保证不累积。
3. 明确协议边界、异常处理、平台权限和测试结论。
4. 列出仍需评审确认的风险和待决项。

## 2. 范围与非目标

**范围**

- LCM UDP 组播接收
- LCM `udpm` 分帧与长包重组
- `preview_package_t` 分片重组
- 相机 JPEG/PNG 解码与上屏
- `joint_batch_t` 解码
- 接收端统计、排查工具、平台适配

**非目标**

- 不涉及录制、上传、任务下发等业务后端
- 不涉及 MCAP 回放链路（回放走独立 HTTP Range 通道，单独评审）
- 不发布 LCM 消息，只订阅
- 不处理跨网段/跨 VLAN（LCM TTL=1，要求同一二层网络）

## 3. 术语

| 术语 | 说明 |
|---|---|
| LCM | Lightweight Communications and Marshalling，机器人常用的 UDP 组播消息库 |
| udpm | LCM 的 UDP 组播传输格式，分短包和长包（分片） |
| preview_package_t | 相机/关节预览数据的分片容器，每片最多 1200 字节 |
| joint_batch_t | 控制器管理器打包的多帧关节状态/指令 |
| isolate | Dart 的独立事件循环和内存堆，可理解为轻量线程 |
| latest-wins | 只保留最新一帧，解码跟不上时覆盖旧帧，不排队 |
| backbone | 本次接收架构：接收 isolate 组装，UI 只消费完整帧 |

## 4. 总体架构

### 4.1 数据流

```text
┌────────────────────── 接收 isolate（lcm-receiver）──────────────────────┐
│ RawDatagramSocket 239.255.76.67:7667（相机）                            │
│ RawDatagramSocket 239.255.76.68:7668（关节，同组同端口时合并成一条）      │
│        │ 每个 UDP 数据报                                                 │
│        ▼                                                                │
│ LcmMessageReader：短包/长包 → 完整 LcmMessage（channel + payload）        │
│        │ 按订阅通道过滤                                                  │
│        ▼                                                                │
│ PreviewRouter                                                           │
│   ├─ /preview/cameras/<name> → preview 分片重组 → JPEG/PNG 字节          │
│   └─ /preview/joint_batch    → preview 分片重组 → joint_batch_t 解码     │
│        │ 组装好一帧就放进 outbox                                          │
│        ▼                                                                │
│ microtask 合并 → SendPort（只跨完整帧/关节）                              │
└──────────────────────────────────┬──────────────────────────────────────┘
                                   │
┌──────────────────────────────────▼──────────────────────────────────────┐
│ UI isolate                                                              │
│ LcmReceiver.frames / joints                                             │
│        ▼                                                                │
│ LivePreview：每路相机一个 latest 槽（不是队列）                            │
│        ▼ ui.instantiateImageCodec（>1280 宽按 1280 解码）                 │
│        ▼ ui.Image                                                       │
│ CameraGrid（ListenableBuilder）→ 每解出一帧 notify                       │
└─────────────────────────────────────────────────────────────────────────┘
```

### 4.2 线程模型

- **接收 isolate**：socket、LCM 分帧、长包重组、preview 分片重组、关节解码、统计。
- **UI isolate**：只接收完整相机字节和关节批次，负责 JPEG/PNG 解码、`ui.Image`、上屏。
- 两个 isolate 之间不共享内存，字节通过 `SendPort` 传递。
- 业务页面（`AppState`）不直接接触 socket 或数据报。

关键收益：

- UI 线程不被 UDP 收包、分片重组阻塞。
- 单帧解析失败不会影响 UI 事件循环。
- 接收端可以独立限流、统计和排查。

## 5. 协议与数据格式

> 所有整数均为**大端**。payload 前 8 字节是 LCM 类型指纹，业务解码时跳过。

### 5.1 LCM udpm

**短包（单报文）**

```text
magic(4) | seq(4) | channel\0 | payload
```

- `magic = 0x4C433032`（“LC02”）
- `channel` 以 NUL 结尾
- `payload` 前 8 字节为类型指纹

**长包（分片）**

```text
magic(4) | seq(4) | total(4) | offset(4) | index(2) | count(2) | channel\0? | chunk
```

- `magic = 0x4C433033`（“LC03”）
- **只有第 0 片带通道名**，第 1..n-1 片从字节 20 开始就是 chunk
- 按 `发送方:端口 + seq` 分组重组
- 缺片 2 秒后过期；重复片忽略

### 5.2 preview_package_t

```text
hash(8) | messageId(8) | streamId(4) | index(4) | count(4) | total(4) | length(4) | payload[length]
```

- 头部固定 36 字节（含 8 字节指纹）
- 每片 payload 最多 1200 字节，最后一片更短
- 发送端契约：`count == ceil(total / 1200)`，每片长度必须是 `min(1200, total - index*1200)`
- 相机通道 payload 是 JPEG/PNG 切片
- 关节通道 payload 是序列化后的 `joint_batch_t`

### 5.3 joint_batch_t

```text
int32   num_frames
int64   timestamp_ns[10]
string  state_names[10]        // 每个字符串是 '\n' 连接的关节名
string  command_names[10]
int32   state_value_count[10]
int32   command_value_count[10]
double  state_values[10][128]
double  command_values[10][128]
```

- 固定 10 个槽位、每个 128 宽，实际有效数量由 `*_value_count` 决定
- 只保留 `/position` 后缀的项，去掉后缀后按关节名对齐
- 非 position（velocity/effort 等）不进入 UI 曲线
- `num_frames`、count 越界直接拒绝整包

## 6. 关键设计与实现

### 6.1 文件与职责

| 文件 | 职责 |
|---|---|
| `lib/core/lcm/lcm_message.dart` | UDP 数据报解析、长包重组、字节游标、通用分片缓冲、统计计数 |
| `lib/core/lcm/preview_protocol.dart` | preview 分片校验与重组、通道路由、joint_batch_t 解码、图片尺寸解析 |
| `lib/core/lcm/lcm_receiver.dart` | 组播 socket、网卡 join、接收 isolate、跨 isolate 发送、统计快照 |
| `lib/core/lcm/multicast_lock.dart` | Android MulticastLock |

### 6.2 接收 isolate

- 绑定 `0.0.0.0:port`，`reuseAddress: true`
- 每块 IPv4 网卡都 `joinMulticast`，不是只加默认路由那块
- 每 2 秒重扫网卡，插网线/新建 VPN 后自动补 join
- 每次 socket 事件最多连续收 512 个数据报，避免饿死定时器和控制消息
- 相机链路自动追加 `/preview/joint_batch`，兼容“相机和关节发在同一组”的发布端
- 关节组/端口与相机不同时，额外开一条关节链路

### 6.3 LCM 长包重组

- 按 `发送方:端口 + seq` 分组，避免不同发布端串包
- 通道名只从第 0 片读取；先收到后续片也能缓存
- 用 `FragmentBuffer` 记录每一片和字节区间：
  - **判完整靠字节覆盖**，不只是“片数够了”
  - 重叠片/空洞片拼出的消息会被丢弃
- 上限：
  - 同时最多 64 个半包
  - 单条消息最大 512KB
  - 2 秒收不齐过期
- 重复片直接忽略；分片形状（total/count）变化则丢弃该组

### 6.4 preview 分片重组

- 严格校验 1200 字节契约，不满足直接丢，不进入缓冲
- 每条流最多 3 个半成品，丢片的帧立刻淘汰，不阻塞后续帧
- `message_id` 比已完成帧旧的直接丢弃，防止迟到旧片拼出重复画面
- 完成后再校验 JPEG/PNG 头，坏图计 `corrupt`，不交给 UI
- 相机按 `相机名/streamId` 分组，发布端重启后 streamId 变化不会串帧

### 6.5 关节解码

- 只读实际 count 个 double，其余 128-count 个直接跳过，避免无意义分配
- 名字与值按位置对齐；名字来自 `\n` 连接的字符串
- 一包可能含多帧，全部解码后按顺序发给 UI
- 支持两种发送方式：
  - 直接发裸 `joint_batch_t`（mock/部分发布端）
  - 用 `preview_package_t` 包一层（机器人 joint bridge）

### 6.6 实时性策略：latest-wins

现场 60Hz，UI 解码能力受设备、帧大小、调试模式影响，不能保证永远 60fps。策略是**保最新、不排队**：

```text
每路相机：
  latest[相机] = 最新一帧字节
  如果该路没有在解码：开始解码
  解码循环：
    取走 latest（取到的是当下最新）
    解码、上屏、notify
    解码期间来的新帧覆盖 latest，中间帧自然丢弃
```

效果：

- 每路最多 1 张正在解码 + 1 张等待
- 解码慢时丢中间帧，延迟不会随运行时间增长
- 显示帧率 = 实际解码能力；源 60Hz、解码跟得上就显示 60fps
- 不会出现“越看越延迟”的积压

### 6.7 为什么不做 ack 背压

曾实现过“UI 收一批回 ack、接收端最多 N 批在途”的方案，实测：

- 26KB 帧、60Hz：有 ack 约 57fps，无 ack 约 59.6fps
- 150KB 帧、60Hz：ack 在 isolate 调度下抖动更明显，帧率下降更多

结论：ack 往返带来的收益（减少发送）小于它带来的抖动；当前改为接收端直接发、UI 端 latest-wins 丢帧。丢帧发生在 UI 侧，接收链路保持简单。

### 6.8 相机名归一（LCM_ALL）

正常模式按固定通道名 `/preview/cameras/cam_head` 等订阅。开启 `LCM_ALL=true` 时：

- 不按通道名过滤，接收组播内所有通道
- 名字含 `joint` 的走关节
- 其余尝试按 preview 分片解相机
- 相机名按关键字归一：
  - `head` / `main` → `cam_head`
  - `left` / `fisheye_l` → `cam_left`
  - `right` / `fisheye_r` → `cam_right`
  - `chest` / `pan` → `cam_chest`
- 认不出的名字保留原名（`live_check` 可见，UI 四宫格不显示）

## 7. 异常与边界

| 场景 | 处理 |
|---|---|
| 非法 magic / 长度不够 | 计 `parseErrors`，丢包 |
| 分片序号/偏移越界 | 丢该分片 |
| 同 seq 分片形状变化 | 丢弃整组半包 |
| 分片缺失 | 2 秒后过期，计 `dropped` |
| 分片重叠/空洞 | 覆盖检查失败，丢弃 |
| 重复分片 | 忽略，不重复写入 |
| 同一 message_id 形状不一致 | 丢半成品，计 `corrupt` |
| 旧帧迟到 | `message_id <= lastCompleted` 时丢弃 |
| 拼出的不是 JPEG/PNG | 计 `corrupt`，不交 UI |
| joint 包截断/越界 | 计 `corrupt`，丢整包 |
| 解码坏帧 | UI 保留上一张，不崩溃 |
| socket 绑定失败 | 启动失败，向 UI 抛错 |
| 关节链路失败 | 相机链路继续工作，关节可选 |
| 网卡变化 | 2 秒重扫自动补 join |

## 8. 性能

### 8.1 实测数据

60Hz mock 源，四路相机：

| 场景 | 接收端 | 应用显示 |
|---|---|---|
| 26KB/帧 | 59.6 fps ×4 | 60 fps ×4 |
| 150KB/帧（36MB/s） | 58.8–59 fps ×4，UDP 丢片 1 帧/5s | 约 51–55 fps（debug 构建，解码瓶颈），丢中间帧但延迟不增长 |

### 8.2 为什么不做 TransferableTypedData

对 292MB 数据做 isolate 往返基准：

| 方式 | 耗时 |
|---|---|
| Uint8List | 94ms |
| TransferableTypedData | 80ms |

只快约 15%，而 36MB/s 的拷贝在每帧耗时里约占 1%；`fromList` 本身仍要复制到外部内存，复杂度与收益不匹配。暂不引入。

### 8.3 为什么不做 buffer pool

参考实现的池子主要复用“拼装缓冲”，但发送时 VM 仍会复制一份消息；UI 端瓶颈是 JPEG 解码，不是 buffer 分配。当前优先用 latest-wins 控制解码量，池子收益有限。若后续出现 GC 卡顿，再按 size class 池化。

### 8.4 解码降采样

- 解码前解析 PNG IHDR / JPEG SOF 获取宽高
- 宽度 > 1280 时用 `instantiateImageCodec(targetWidth: 1280)`
- 640×360 / 640×480 源不缩放
- 目的：1080p/4K 源减少解码像素、内存和纹理上传开销

## 9. 可观测性

接收端每 500ms 向 UI 推送统计快照：

| 字段 | 含义 | 异常时说明 |
|---|---|---|
| `datagrams` | 收到的 UDP 数据报数 | 一直是 0 → 组播没到/网卡没 join/端口错 |
| `messages` | 完整 LCM 消息数 | 远小于 datagrams → 分片丢失或通道过滤 |
| `parseErrors` | 解析失败数 | 涨 → 坏包/端口混入其他流量 |
| `dropped` | 过期的半包数 | 涨 → 网络丢片 |
| `incomplete` | 淘汰/覆盖的半成品数 | 涨 → 丢片或流重启 |
| `corrupt` | 拼好但不是有效图像/关节 | 涨 → 发布端格式变化 |
| `pending` | 当前半成品数 | 持续增长 → 重组异常 |
| `interfaces` | 成功 join 的网卡 | 空 → 组播 join 失败（VPN/权限） |

排查工具：

```bash
# 现场组播探针，不启动 UI
dart run tool/live_check.dart 5

# 不按通道名过滤
LCM_ALL=true dart run tool/live_check.dart 5

# Python 发布端 → Dart 接收端，端到端
dart run tool/e2e_check.dart
```

## 10. 平台适配

| 平台 | 处理 |
|---|---|
| Android | 声明 `INTERNET`、`ACCESS_NETWORK_STATE`、`CHANGE_WIFI_MULTICAST_STATE`；`MainActivity` 持有 `MulticastLock`，MethodChannel `tavi/multicast` |
| iOS | `Info.plist` 已有 `NSLocalNetworkUsageDescription`；组播需要 Apple 的 `com.apple.developer.networking.multicast` entitlement，**当前未随仓库提供**（避免无权限签名失败），上线前必须申请 |
| macOS | App Sandbox 已开 `network.client` / `network.server`；本地网络说明已配置 |
| Windows | 需放行 UDP 7667/7668 入站（专用网络） |
| Linux | 无特殊配置，多网卡时用 `LCM_IFACE` 指定 |

## 11. 配置项

| 变量 | 默认 | 说明 |
|---|---|---|
| `ROBOT_IP` | `192.168.13.4` | 首屏默认 IP，也用于拼 MCAP 地址 |
| `MCAP_URL` | `http://<ROBOT_IP>:8090/rosbag_0.mcap` | MCAP 回放地址 |
| `DEMO` | `false` | 跳过机器人探测，方便看 UI |
| `LCM_GROUP` / `LCM_PORT` | `239.255.76.67:7667` | 相机组播 |
| `LCM_JOINT_GROUP` / `LCM_JOINT_PORT` | `239.255.76.68:7668` | 关节组播 |
| `LCM_IFACE` | 空 | 只加入指定网卡 |
| `LCM_ALL` | `false` | 收所有通道，排查通道名时用 |

说明：

- IP 不做持久化，每次启动使用默认值或 `--dart-define=ROBOT_IP`。
- 业务任务/采集条是 mock，不按机器人 IP 过滤；LCM 画面和 MCAP 回放是真实数据。

## 12. 测试与验收

### 12.1 自动化测试

| 范围 | 内容 |
|---|---|
| `test/lcm_protocol_test.dart` | 短包、长包乱序/缺片过期、preview 重组、同尺寸不串帧、旧帧忽略、半成品上限、坏分片、joint 解码、通道路由、LCM_ALL、图片尺寸解析、坏图过滤 |
| `test/app_smoke_test.dart` | 首页 → 采集 → 已采 → 回看、设置/手动控制/登录弹层、手机宽度不溢出、mock 不按 IP 过滤 |
| `test/mcap_codecs_test.dart` | Statistics / JointState / bgr8 Image 解码 |

命令：

```bash
flutter analyze
flutter test
dart run tool/e2e_check.dart
```

当前结果：`flutter analyze` 0 issues；`flutter test` 全部通过；e2e 收到 12 帧（4 相机 ×3 轮）、3 批关节、20 个位置值，`corrupt=0`。

### 12.2 现场验收建议

1. 平板与机器人同一二层网络，关闭 AP 隔离/访客网络。
2. `dart run tool/live_check.dart 5` 确认四路 fps 和 `interfaces`。
3. 打开采集页，四路画面正常、角标 fps 接近源频率。
4. 拔插网线/VPN 切换，2 秒内自动重新 join。
5. 弱网（限速/丢包）下观察 `incomplete`，画面应丢帧但不冻结、不越积越慢。

## 13. 风险与待决项

| # | 问题 | 影响 | 建议 |
|---|---|---|---|
| 1 | UI isolate 被系统阻塞时，SendPort 消息可能短暂堆积 | 内存短时上涨，恢复后只显示最新帧 | UI 处理每帧是 O(1)，实际可接受；若需硬上限，再加 ack/速率限制 |
| 2 | 150KB/帧、60Hz 时 debug 构建解码只有约 51–55fps | 画面流畅度略低，但延迟不增长 | 用 release 构建复测；必要时降到 960 宽解码或原生解码 |
| 3 | iOS 组播 entitlement 未申请 | iOS 上收不到组播 | 上线前走 Apple 申请流程，补 entitlements |
| 4 | 通道名不统一（`cam_left` vs `camera_fisheye_l`） | 固定订阅模式收不到 | 现场先用 `LCM_ALL=true` 确认，再固化映射 |
| 5 | 无重传/纠错 | 丢片即丢帧 | 实时预览可接受；录制/回放不依赖 LCM |
| 6 | 局域网无认证/加密 | 同网段可被监听/伪造 | 机器人网络隔离；如需安全，后续加 TLS/网关 |
| 7 | `LCM_ALL` 常开可能收到无关流量 | 解析开销增加 | 仅用于排查，生产默认关闭 |

## 14. 评审清单

- [ ] 协议字段、大小端、长度边界是否与机器人发布端一致
- [ ] 长包“通道只在第 0 片”是否覆盖所有发布端
- [ ] 分片覆盖检查、过期、重复片处理是否满足现场弱网
- [ ] 60Hz 下的丢帧/延迟策略是否接受（latest-wins，不排队）
- [ ] 相机/关节通道命名和 `LCM_ALL` 兜底方案是否确认
- [ ] Android MulticastLock、iOS entitlement、macOS 沙箱权限是否满足交付
- [ ] 统计字段是否足够定位“没数据/丢片/坏包/解码慢”
- [ ] 自动化测试和现场验收步骤是否通过

## 15. 附录

### 15.1 关键代码位置

```text
lib/core/lcm/lcm_message.dart       UDP 数据报 → LCM 消息
lib/core/lcm/preview_protocol.dart  preview 重组 / joint 解码 / 通道路由
lib/core/lcm/lcm_receiver.dart      组播 socket / isolate / 统计
lib/core/lcm/multicast_lock.dart    Android MulticastLock
lib/core/live_preview.dart          UI 侧 latest-wins 解码与上屏
lib/screens/collect.dart            采集页相机面板
tool/live_check.dart                现场探针
tool/e2e_check.dart                 端到端检查
```

### 15.2 一句话总结

接收和重组全部在独立 isolate 完成，UI 只拿完整帧；实时性靠“每路只留最新帧、解码慢就丢中间帧”保证，延迟不随运行时间增长；协议层对分片契约、覆盖范围、越界和坏图都有硬校验。
