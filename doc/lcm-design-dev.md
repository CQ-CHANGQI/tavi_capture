# LCM 实时链路设计（开发版）

LCM 这块是这轮重写得最彻底的一块。老的实现是从参考仓库搬的，前后叠了好几版，光看调用链就得半天；这次索性按协议拆开重写。

下面把整条链路讲一遍，包括当时为什么这么选、哪些方案试过又扔了，免得后面接手的人再踩一遍。代码主要在 `lib/core/lcm/` 下，四个文件，UI 侧在 `lib/core/live_preview.dart`。

## 整体是怎么跑的

```text
UDP 组播
   │
   ▼
┌──────────────── 接收 isolate ────────────────┐
│ socket → LCM 分帧/长包重组 → preview 分片重组 │
│        → 关节解码 → outbox                    │
└───────────────────┬──────────────────────────┘
                    │ SendPort（只传完整帧）
                    ▼
┌──────────────── UI isolate ──────────────────┐
│ 每路 latest 槽 → JPEG 解码 → ui.Image → 上屏  │
└──────────────────────────────────────────────┘
```

接收 isolate 把 UDP 包变成完整的相机帧和关节批次，UI isolate 只负责解码和上屏。两边不共享内存，字节靠 `SendPort` 传。

## 背景和约束

机器人侧相机走 `239.255.76.67:7667`，关节走 `239.255.76.68:7668`。现场 60Hz，四路 640×360 JPEG，正常一帧几十 KB，我拿 150KB 的图压过。

几个硬约束：

- 平板和机器人必须在同一二层网络，LCM 是 TTL=1 的组播，跨网段/跨 VLAN 收不到。
- 只订阅，不发布。
- 目标不是“每帧都显示”，是“显示最新的一帧，别越播越慢”。解码跟不上就丢帧，这个后面单独说。
- 客户端跑 Android / iOS / macOS / Windows / Linux，不支持 Web，浏览器开不了裸 UDP 组播。

## 线格式

所有整数都是大端。payload 前面有 8 字节 LCM 类型指纹，业务解码直接跳过，不校验。

### LCM udpm

短包（一条消息一个 UDP 包）：

```text
magic(LC02) | seq(4) | channel\0 | payload
```

长包（大消息被 LCM 拆片）：

```text
magic(LC03) | seq(4) | total(4) | offset(4) | index(2) | count(2) | channel\0? | chunk
```

**通道名只在第 0 片。** 这是 lcm_udpm 的行为，不是我们省了。按“每片都带通道”去解，真实的多片消息会全部丢掉。这个坑当时返工过一次。

### preview_package_t

相机帧和关节包都会被机器人切成最多 1200 字节的片：

```text
hash(8) | messageId(8) | streamId(4) | index(4) | count(4) | total(4) | length(4) | payload
```

头部固定 36 字节。发送端契约是：

- `count == ceil(total / 1200)`
- 每片 `length == min(1200, total - index * 1200)`

不满足就直接丢，缓冲区都不进。现场见过发布端改切片大小，如果不校验，拼出来的图是断的。

### joint_batch_t

```text
int32   num_frames
int64   timestamp_ns[10]
string  state_names[10]        // 里面是 '\n' 连起来的关节名
string  command_names[10]
int32   state_value_count[10]
int32   command_value_count[10]
double  state_values[10][128]
double  command_values[10][128]
```

固定 10 个槽位、每个 128 宽，实际多少看 count。我们只读 count 个 double，剩下 128-count 个直接跳，只保留 `/position` 后缀的项，去掉后缀按关节名对齐。velocity、effort 这些不进 UI 曲线，混进去图就没法看了。

### 通道约定

相机是 `/preview/cameras/<name>`，关节是 `/preview/joint_batch`。正常模式按固定名字订阅。

现场通道名经常不统一，有叫 `camera_fisheye_l` 的，有叫 `cam_left` 的。`LCM_ALL=true` 时不按名字过滤，全收；相机名从通道里按关键字归一（`left/fisheye_l` → `cam_left` 等），认不出来的保留原名，`live_check` 能看到，UI 四宫格不显示。

## 组播接收

相机和关节各一条 socket，绑 `0.0.0.0`，`reuseAddress` 打开。相机链路会顺手把关节通道也加进订阅列表，因为有些发布端（包括我们的 mock）把关节和相机发在同一组；机器人关节如果是单独的组和端口，就再开一条。

**join 要挨个网卡加。** 组播成员关系是按网卡的，不是按机器。之前只 join 默认路由那块，现场就是“Wi-Fi 能看，插上网线黑屏”。现在每 2 秒扫一遍 `NetworkInterface.list()`，新插的网卡、新起来的 VPN 都会补 join；排查时可以用 `LCM_IFACE=en6` 固定一块。

收包循环一次最多连收 512 个，然后主动让出去。不让的话，数据一密，定时器和停止命令都排不上。

平台权限这块：

- Android 要 `CHANGE_WIFI_MULTICAST_STATE`，并在采集期间持有 `MulticastLock`（MethodChannel `tavi/multicast`），不然息屏/后台就被系统过滤。
- iOS 要 Apple 的 `com.apple.developer.networking.multicast` entitlement。我们现在没放，所以 **iOS 目前收不到组播**，这个不是代码问题，是权限没申请。
- macOS 沙箱里 `network.client/server` 都有，实测能收。
- Windows 放行 UDP 7667/7668 入站，专用网络。
- Linux 没特殊配置，多网卡时用 `LCM_IFACE`。

收不到数据，先看 `datagrams` 和 `interfaces`：`datagrams` 是 0 就是包没到本机；`interfaces` 是空就是一块网卡都没 join 上。这两个数能排掉八成“没数据”的问题。

## 两层组包

这里有两层分片，别混。

### 第一层：LCM 长包

按 `发送方:端口 + seq` 分组。每个分片写进固定缓冲区，同时记录字节区间。

判完整不是数片数，是看**字节有没有从 0 连续覆盖到 total**。片数是够的、但中间有洞或者有重叠，照样丢。这个是当时 review 时补的，之前只数片数，理论上能拼出一条中间带零的消息。

上限：同时最多 64 个半包，单条消息 512KB，2 秒收不齐就过期。重复片忽略；同一 seq 的 total/count 变了，整组丢掉，不试图救。

### 第二层：preview_package_t

每路相机最多留 3 个半成品。丢了一片的那帧直接废掉，不能卡着后面的帧——实时预览里，卡一帧比丢一帧难受。

`message_id` 比已经完成的帧旧的直接丢。发布端的 message_id 基本是时间戳，迟到的旧片能再拼一张旧图出来，不挡的话画面会往回跳。

相机按 `相机名/streamId` 分组，发布端重启后 streamId 变了不会串帧。拼完校验 JPEG/PNG 头，不是图就记 `corrupt`，不交给 UI。

### 关节包

`joint_batch_t` 有两种到法：裸包直接发，或者用 `preview_package_t` 包一层（机器人 joint bridge 是后者）。两条路都支持，先试分片，解不出来再按裸包解。

### 坏包原则

就两条：**坏片不进缓冲，坏帧不交 UI**。其他都交给计数，不在热路径上打日志。

`parseErrors`、`dropped`、`incomplete`、`corrupt` 是分开的，现场一看就知道是包坏了、片丢了，还是发布端格式变了。

## isolate 和 UI

接收全在后台 isolate：socket、LCM 分帧、两层重组、关节解码、统计。UI isolate 只拿完整帧，负责解码和上屏。

分的原因不复杂：收包和重组是纯 CPU/IO，放后台 UI 不卡；单个坏包影响不到 UI 事件循环；接收端能独立统计；UI 只处理完整画面，逻辑简单。

跨 isolate 传的是 `CameraFrame`（相机名 + JPEG/PNG 字节）和 `JointBatch`（时间戳 + 状态/指令 map）。同一轮 socket 事件里完成的几帧，用 microtask 合成一条 port 消息再发，减少消息数。

UI 侧每路相机只有**一个 latest 槽**，不是队列：

```text
latest[相机] = 最新一帧
解码线程取走 latest 去解
解码期间来的新帧直接覆盖 latest
```

每路最多一张在解、一张在等。解码慢就丢中间帧，延迟不越积越大。旧 `ui.Image` 在新图替换后、下一帧结束时再 dispose，避免还在绘制的时候被释放。

角标上的 fps 统计的是**解码并显示**的帧，不是收到的帧。源 60Hz、解码跟得上就是 60fps；跟不上显示实际能力，不骗人。

解码前会读一下 JPEG/PNG 头拿尺寸，源宽超过 1280 才按 1280 解，640×360 不缩放。UI 只重建相机面板（`ListenableBuilder`），`AppState` 的状态栏刷新节流到 500ms，不会每帧重建整页。

生命周期就 ready/stop 两个消息。接收 isolate 建好 socket、join 完网卡发 ready；UI 发 stop 就关 socket、停定时器。统计每 500ms 推一次。

## 当时试过、后来扔掉的方案

这部分我觉得比结果有用，写下来免得再走一遍。

**33ms 合并定时器**：老实现里有个 33ms 的 flush 定时器，60Hz 进来也只能出 30fps。删掉，改成按帧到达发。

**排队逐帧解码**：一开始 UI 侧是队列，想“一帧都不丢”。60Hz 跑几分钟延迟就上来了，画面越看越旧，直接废掉，改成 latest-wins。

**ack 背压**：UI 收一批回一个 ack，接收端最多 N 批在途。实测 26KB/60Hz 下带 ack 只有 57fps 左右，不带能到 59.6；150KB 大帧抖得更厉害。ack 往返的抖动比它省下的发送更亏，最后改成接收端直接发、UI 端丢帧。

**TransferableTypedData**：拿 292MB 做了 isolate 往返基准，94ms 对 80ms，只快 15%。摊到每帧大概 1%，不想为这点收益加一层所有权管理，没上。

**buffer pool**：参考实现里有个池子，但发送时 VM 还是要复制一份消息，UI 端瓶颈是 JPEG 解码不是分配，收益有限。等真出现 GC 卡顿再按 size class 做。

**整页重建**：之前每来一帧就 `notifyListeners` 刷整个页面，4 路 60Hz 就是 240 次/秒，顶栏、列表全跟着重画。现在只有相机面板监听实时数据，顶栏 500ms 刷一次。

## 统计和排查

每 500ms 推一次快照，字段不多，但现场够用：

| 字段 | 看什么 |
|---|---|
| `datagrams` | 包到没到本机 |
| `messages` | 完整 LCM 消息数；远小于 datagrams 说明丢片或通道没匹配 |
| `parseErrors` | 坏包、端口混入别的流量 |
| `dropped` | 半包过期，基本等于丢片 |
| `incomplete` | 半成品被淘汰，弱网或发布端重启 |
| `corrupt` | 拼好了但不是图/关节，发布端格式可能变了 |
| `pending` | 当前半成品数，持续涨就是重组异常 |
| `interfaces` | join 上的网卡，空就是没 join 上 |

工具就两个：

```bash
dart run tool/live_check.dart 5          # 现场组播探针
LCM_ALL=true dart run tool/live_check.dart 5   # 通道名不确定时
dart run tool/e2e_check.dart             # Python 发布端 → Dart 接收，端到端
```

## 测试

- `test/lcm_protocol_test.dart`：短包、长包乱序、缺片过期、preview 重组、同尺寸不串帧、旧帧忽略、每流 3 个半成品、坏分片、joint 解码、通道路由、LCM_ALL、图片尺寸解析、坏图过滤。
- `test/app_smoke_test.dart`：页面链路和手机宽度；另外有一条 mock 不按 IP 过滤。
- e2e：真起 Python 发布端，收到 12 帧（4 相机 ×3 轮）、3 批关节、20 个位置值，`corrupt=0`。

现场验收我一般按这个顺序：先 `live_check` 看四路 fps 和 interfaces，再开采集页看角标，然后拔插网线看 2 秒内能不能自己 join 回来，最后限速/丢包看 `incomplete` 和画面是不是只丢帧、不冻结。

## 平台和配置

平台差异前面提过，配置再列一下：

| 变量 | 默认 | 说明 |
|---|---|---|
| `LCM_GROUP` / `LCM_PORT` | `239.255.76.67:7667` | 相机组播 |
| `LCM_JOINT_GROUP` / `LCM_JOINT_PORT` | `239.255.76.68:7668` | 关节组播 |
| `LCM_IFACE` | 空 | 固定网卡 |
| `LCM_ALL` | `false` | 全通道收，排查用 |
| `ROBOT_IP` | `192.168.13.4` | 首屏默认 IP，也拼 MCAP 地址 |
| `MCAP_URL` | `http://<ROBOT_IP>:8090/rosbag_0.mcap` | MCAP 回放，和 LCM 是两条链路 |

IP 不做持久化，每次启动用默认值或者 `--dart-define`。业务任务/采集条是 mock，不按 IP 过滤；LCM 画面和 MCAP 回放是真实数据，这两块别混。

## 还没搞定的

- iOS multicast entitlement 得向 Apple 申请，不解决 iOS 端 LCM 就是不可用。
- 150KB/60Hz 在 debug 构建下只有 50 出头，release 还没正经测。如果现场就是大帧，是降到 960 宽解，还是上原生解码，得定个方向。
- 无 ack 的代价：UI 线程如果被系统卡住，SendPort 里可能短时堆一点消息。UI 处理每帧是 O(1)，实际没出过问题，但要求硬上限就得把 ack 捡回来。
- 通道名长期靠映射不是办法，最好让机器人侧统一，或者把映射配置化。
- 局域网没有认证/加密，同网段能监听。现在靠网络隔离，真要有安全要求得加网关或 TLS。
- UDP 没有重传，丢片就是丢帧。实时预览能接受，录制/回放不走这条链路。

## 文件

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

先写这些。评审的时候主要想听几件事：iOS 权限怎么推进、大帧要不要降分辨率、无 ack 的瞬态堆消息能不能接受。
