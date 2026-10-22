# LCM 实时链路设计与实现（开发版）

先把话说明白：我们部门之前没人正经用过 LCM，我第一次看 udpm 协议也懵。所以这份文档除了写我们怎么做，也把 LCM 本身、以及为什么把线程拆成这样讲清楚。已经熟的可以直接跳到第 6 节。

代码主要在 `lib/core/lcm/` 下，四个文件；UI 侧在 `lib/core/live_preview.dart`。

## 1. LCM 到底是什么

先说人话：LCM 就是机器人圈子里的一个**发布/订阅消息总线**。发布端往一个“通道”上发二进制消息，订阅端按通道收。底层默认走 UDP 组播，一条消息可以被同一网段里所有订阅者同时收到。

它解决的问题很朴素：机器人上相机、关节、底盘这些进程各跑各的，需要一个足够快、足够简单的进程间/机器间通信方式。LCM 就是其中一种，NASA 和一堆机器人公司都在用。

它有几个特点，决定了我们后面的实现：

- **消息是二进制的**，格式由 `.lcm` 文件定义，没有 JSON/Protobuf 那些自描述字段。收发两端必须按同一份定义解。
- **默认 UDP 组播**，没有连接、没有握手、没有重传。丢包就是丢包。
- **一个通道一个名字**，比如 `/preview/cameras/cam_head`，订阅是字面匹配。
- **消息前面有 8 字节类型指纹**，是一个类型哈希，不是长度。我们直接跳过，不校验。
- **大消息会被 LCM 自己拆成长包**（后面讲），但相机预览这条链路是机器人应用层先切好 1200 字节的片，所以两条链路的分片逻辑都要懂。

为什么不用 HTTP/WebSocket：60Hz 四路视频，走 TCP 一丢包就队头阻塞，重传完画面已经过期了；组播又是一对多，机器人发一份，几台平板都能收，不用维护连接。代价是 UDP 不可靠、没有鉴权、必须同一二层网络（TTL=1）。

我们只订阅，不发布。

## 2. 一条相机帧的完整旅程

先不看代码，跟着一帧画面走一遍，后面所有概念都能对上：

1. 机器人相机进程拿到一张 JPEG，切成 1200 字节一片。
2. 每片套一个 `preview_package_t` 头（36 字节），带上 `message_id`、`stream_id`、片序号/总数、总长度。
3. 每一片作为一个独立的 LCM 消息，发到组播组 `239.255.76.67:7667`，通道 `/preview/cameras/cam_head`。
4. 平板网卡收到 UDP 包，内核按组播组投递给已经 join 的 socket。
5. 接收 isolate 里的 `LcmMessageReader` 解出 LCM 短包：通道名 + payload。
6. 按通道名过滤，只看 `/preview/cameras/` 开头的。
7. `PreviewRouter` 把 payload 按 `preview_package_t` 解出片，按 `相机名 + streamId + message_id` 找半成品，写进缓冲区。
8. 最后一片到齐、字节连续覆盖、JPEG 头正确，拼成一帧完整 JPEG。
9. 帧被放进 outbox，microtask 合并后通过 `SendPort` 发到 UI isolate。
10. UI 侧取最新一帧，`instantiateImageCodec` 解成 `ui.Image`，`RawImage` 上屏。

关节包也是类似的路，只是最后一步不是解码图片，而是解 `joint_batch_t` 的固定结构。

## 3. LCM udpm 线格式

所有整数都是大端。协议不大，但有几个反直觉的点。

### 短包

```text
magic(4) | seq(4) | channel\0 | payload
```

- `magic = 0x4C433032`，ASCII 是 `LC02`。
- `channel` 以 NUL 结尾，不是长度前缀。
- `payload` 前面 8 字节是类型指纹，业务解码跳过。

相机链路基本都是短包：一片 1200 字节，加上通道名和头，远小于 UDP 单包上限。

### 长包

```text
magic(4) | seq(4) | total(4) | offset(4) | index(2) | count(2) | channel\0? | chunk
```

- `magic = 0x4C433033`，`LC03`。
- **通道名只在第 0 片。** 第 1 片开始，chunk 直接从第 20 字节开始。按“每片都带通道”去解，真实的多片消息会全部丢掉。这个不是实现选择，是 lcm_udpm 本身的行为。
- 分片按 `发送方:端口 + seq` 分组。不同发布端可能用相同的 seq，不区分发送方会串包。
- 缺片 2 秒后过期，重复片忽略。

什么时候会走长包：一条消息超过 UDP 单包能承载的大小时，LCM 发送端自己拆。关节 `joint_batch_t` 大概 21KB，Linux 上一次发完可能没问题；macOS 的 UDP 单包上限小，我们的 mock 会按 8000 字节拆成长包；真实机器人上也可能因为配置或网络 MTU 走长包。所以长包重组不能省。

### 类型指纹

payload 前 8 字节是类型哈希。我们**不校验**，只跳过。原因是：校验需要维护所有消息类型的哈希，收益不大；格式对不对，最终会在后面的字段边界和长度校验里暴露出来。这一点和参考实现一致。

## 4. preview_package_t：应用层分片

相机帧和关节包都会套这一层：

```text
hash(8) | messageId(8) | streamId(4) | index(4) | count(4) | total(4) | length(4) | payload
```

头部固定 36 字节，`payload` 最多 1200 字节。

为什么是 1200：机器人相机进程就是这么切的，主要是让每个 UDP 包留在 MTU 以内（1200 + 36 字节 preview 头 + LCM 头 ≈ 1250），避免 IP 分片。IP 分片一丢就是整包重传/整帧报废，不如应用层自己切小。

发送端契约（不满足直接丢，缓冲区都不进）：

- `count == ceil(total / 1200)`
- 每片 `length == min(1200, total - index * 1200)`
- `index < count`，`total <= 512KB`

这层为什么要校验得这么死：现场见过发布端改切片大小，也见过半路混进别的东西。按 1200 写死 offset 的话，片长不对会把后面的数据错位，拼出来的图是断的，而且很难查。

接收端策略：

- 每个流最多 3 个半成品。丢了一片的那帧直接淘汰，不能卡着后面的帧。实时预览里，卡一帧比丢一帧难受。
- `message_id` 比已完成帧旧的直接丢。发布端的 message_id 基本是时间戳，迟到的旧片能再拼一张旧图，不挡的话画面会往回跳。
- 相机按 `相机名/streamId` 分组。发布端重启后 streamId 变化，不会和旧帧串。
- 拼完校验 JPEG/PNG 头，不是图就记 `corrupt`，不交给 UI。

关节包也走这层，只是最后解的是 `joint_batch_t`。

## 5. joint_batch_t

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

这是控制器管理器 introspection 的固定结构，反直觉的地方：

- 固定 10 个槽位，每个 128 宽，**没有长度前缀**。实际多少看 `*_value_count`。
- 名字是一个字符串，里面用 `\n` 连多个关节名，不是字符串数组。
- 每个名字带 `/position` 后缀，我们只保留这一种，去掉后缀按名字对齐。velocity、effort 不进 UI 曲线，混进去图就没法看。
- 只读 count 个 double，剩下 128-count 个直接跳过。全读会多分配一堆没用的 double。

一包可能有多帧（num_frames > 1），全部解出来按顺序发给 UI。

关节包有两种到法：裸的 `joint_batch_t` 直接发，或者用 `preview_package_t` 包一层（机器人 joint bridge 是后者）。两条路都支持：先试 preview 分片，解不出来再按裸包解。

## 6. 组播接收

相机和关节各一条 socket，绑 `0.0.0.0`，`reuseAddress` 打开。相机链路会顺手把关节通道也加进订阅列表，因为有些发布端（包括我们的 mock）把关节和相机发在同一组；机器人关节如果是单独的组和端口，就再开一条。

### join 要按网卡加

组播成员关系是**按网卡**的，不是按机器。`joinMulticast(group, nic)` 每块 IPv4 网卡都要加一次。

之前只 join 默认路由那块，现场就是“Wi-Fi 能看，插上网线黑屏”。现在每 2 秒扫一遍 `NetworkInterface.list()`，新插的网卡、新起来的 VPN 都会补 join；排查时可以用 `LCM_IFACE=en6` 固定一块。

TTL=1 意味着组播包不跨路由器，平板和机器人必须在同一个 VLAN/AP 下。 guest Wi-Fi、AP 隔离、IGMP snooping 配置不对，都会表现成“一个包都没有”。

### 收包循环

socket 可读时一次最多连收 512 个数据报，然后主动让出去。不让的话，数据一密，定时器和停止命令都排不上。

### 平台权限

- Android 要 `CHANGE_WIFI_MULTICAST_STATE`，并在采集期间持有 `MulticastLock`（MethodChannel `tavi/multicast`），不然息屏/后台就被系统过滤。
- iOS 要 Apple 的 `com.apple.developer.networking.multicast` entitlement。我们现在没放，所以 **iOS 目前收不到组播**，这个不是代码问题，是权限没申请。
- macOS 沙箱里 `network.client/server` 都有，实测能收。
- Windows 放行 UDP 7667/7668 入站，专用网络。
- Linux 没特殊配置，多网卡时用 `LCM_IFACE`。

收不到数据，先看 `datagrams` 和 `interfaces`：`datagrams` 是 0 就是包没到本机；`interfaces` 是空就是一块网卡都没 join 上。这两个数能排掉八成“没数据”的问题。

通道名不确定就 `LCM_ALL=true` 先全收，确认有没有包、通道叫什么，再回来改配置。

## 7. 线程模型

这是我们这次改得最狠的地方，也是之前 30fps 的根源。

### 先说 Dart 的 isolate

Dart 的 isolate 不是一个普通线程，它是**独立事件循环 + 独立内存堆**。两个 isolate 之间不能直接读对方对象，只能 `SendPort.send` 发消息。发过去的对象会被复制（除了 `SendPort`、`TransferableTypedData` 这种特殊类型）。

Flutter 启动时有一个 root isolate（UI isolate），`dart:ui`、`ui.Image`、`instantiateImageCodec` 只能在这个 isolate 用。后台 isolate 里调 `dart:ui` 会直接报错。

### 我们怎么分

- **接收 isolate**：socket、LCM 分帧、两层重组、关节解码、统计。
- **UI isolate**：只拿完整帧和关节批次，负责 JPEG/PNG 解码、`ui.Image`、上屏。
- 业务页面（`AppState`）不接触 socket，也不碰数据报。

为什么不直接在 UI 里 `async` 收包：socket 回调、分片重组是纯 CPU/IO，60Hz 四路相机一密集，UI 事件循环会被这些工作占满，掉帧、触摸卡顿都来了；而且一个坏包抛出异常，可能把 UI 逻辑带崩。丢进独立 isolate，最坏情况只是预览卡，页面还能动。

### 跨 isolate 传什么

只传两样：

- `CameraFrame`：相机名 + 一帧 JPEG/PNG 字节。
- `JointBatch`：时间戳 + 状态/指令的 `Map<String,double>`。

同一轮 socket 事件里完成的几帧，用 microtask 合成一条 port 消息再发，减少消息数。

### UI 侧怎么消费

每路相机只有**一个 latest 槽**，不是队列：

```text
latest[相机] = 最新一帧
解码线程取走 latest 去解
解码期间来的新帧直接覆盖 latest
```

时间线大概是这样（解码 8ms，源 16.7ms 一帧）：

```text
0ms     帧 1 到，开始解
8ms     帧 1 上屏
16.7ms  帧 2 到
24ms    帧 2 上屏
...
```

解码 25ms、源 16.7ms 一帧：

```text
0ms     帧 1 开始解
16.7ms  帧 2 到，覆盖 latest
25ms    帧 1 上屏（已经落后 8ms）
25ms    取帧 2 开始解
41ms    帧 3 到，覆盖
50ms    帧 2 上屏
...
```

显示帧率会降到 40fps 左右，但延迟稳定在“一次解码时间 + 最多一帧间隔”，不会越看越旧。这个是我们想要的。

### 为什么不做 ack 背压

UI 收一批回一个 ack，接收端最多 N 批在途——这是参考实现的做法。我们试过，实测 26KB/60Hz 下带 ack 只有 57fps 左右，不带能到 59.6；150KB 大帧抖得更厉害。ack 往返的抖动比它省下的发送更亏，最后改成接收端直接发、UI 端丢帧。

### 跨 isolate 的代价

每帧字节要复制一份到 UI isolate：26KB × 4 × 60 大概 6.2MB/s，150KB 的话 36MB/s。

我拿 292MB 数据量过 `TransferableTypedData`，94ms 对 80ms，只快 15%。摊到每帧大概 1%，不想为这点收益加一层所有权管理，没上。

真正的瓶颈在 UI 解码，不在拷贝。所以源宽超过 1280 才按 1280 解，正常 640×360 不缩放。

### 生命周期和统计

接收 isolate 建好 socket、join 完网卡发 `ready`；UI 发 `stop` 就关 socket、停定时器。

统计每 500ms 推一次快照：`datagrams / messages / parseErrors / dropped / incomplete / corrupt / pending / interfaces`。页面和 `tool/live_check.dart` 用的是同一套。

## 8. 当时试过、后来扔掉的方案

这部分我觉得比结果有用。

**33ms 合并定时器**：老实现里有个 33ms 的 flush 定时器，60Hz 进来也只能出 30fps。删掉，改成按帧到达发。

**排队逐帧解码**：一开始 UI 侧是队列，想“一帧都不丢”。60Hz 跑几分钟延迟就上来了，画面越看越旧，直接废掉，改成 latest-wins。

**ack 背压**：上面说了，57 vs 59.6，大帧更差，不划算。

**TransferableTypedData**：只快 15%，占每帧 1%，没上。

**buffer pool**：参考实现里有个池子，但发送时 VM 还是要复制一份消息，UI 端瓶颈是 JPEG 解码不是分配，收益有限。等真出现 GC 卡顿再按 size class 做。

**整页重建**：之前每来一帧就 `notifyListeners` 刷整个页面，4 路 60Hz 就是 240 次/秒，顶栏、列表全跟着重画。现在只有相机面板监听实时数据，顶栏 500ms 刷一次。

## 9. 统计和排查

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

工具：

```bash
dart run tool/live_check.dart 5          # 现场组播探针
LCM_ALL=true dart run tool/live_check.dart 5   # 通道名不确定时
dart run tool/e2e_check.dart             # Python 发布端 → Dart 接收，端到端
```

## 10. 新手容易踩的坑

给后面第一次碰 LCM 的同学，这几条都是真踩过的：

1. **大端**。Dart 的 `ByteData` 默认就是大端，但用 `Uint8List` 手拼的时候容易忘。
2. **长包通道名只在第 0 片**。不要每片都去找通道名。
3. **LCM 字符串长度包含结尾 NUL**，不是纯内容长度；空字符串长度是 1。
4. **`joint_batch_t` 的固定数组没有长度前缀**，10×128 是写死的，实际数量看 count。
5. **preview 片长必须刚好 1200 或最后一片的剩余长度**，不能按“差不多”解。
6. **组播要按网卡 join**，只 join 默认路由会漏网卡。
7. **TTL=1**，跨网段收不到，别怀疑代码，先看网络。
8. Android 没 `MulticastLock`、iOS 没 entitlement，代码再对也收不到。
9. `socket.receive()` 要循环读到 null，别一次只读一个包。

## 11. 平台和配置

| 变量 | 默认 | 说明 |
|---|---|---|
| `LCM_GROUP` / `LCM_PORT` | `239.255.76.67:7667` | 相机组播 |
| `LCM_JOINT_GROUP` / `LCM_JOINT_PORT` | `239.255.76.68:7668` | 关节组播 |
| `LCM_IFACE` | 空 | 固定网卡 |
| `LCM_ALL` | `false` | 全通道收，排查用 |
| `ROBOT_IP` | `192.168.13.4` | 首屏默认 IP，也拼 MCAP 地址 |
| `MCAP_URL` | `http://<ROBOT_IP>:8090/rosbag_0.mcap` | MCAP 回放，和 LCM 是两条链路 |

IP 不做持久化，每次启动用默认值或者 `--dart-define`。业务任务/采集条是 mock，不按 IP 过滤；LCM 画面和 MCAP 回放是真实数据，这两块别混。

## 12. 测试

- `test/lcm_protocol_test.dart`：短包、长包乱序、缺片过期、preview 重组、同尺寸不串帧、旧帧忽略、每流 3 个半成品、坏分片、joint 解码、通道路由、LCM_ALL、图片尺寸解析、坏图过滤。
- `test/app_smoke_test.dart`：页面链路和手机宽度；另外有一条 mock 不按 IP 过滤。
- e2e：真起 Python 发布端，收到 12 帧（4 相机 ×3 轮）、3 批关节、20 个位置值，`corrupt=0`。

现场验收顺序：先 `live_check` 看四路 fps 和 interfaces，再开采集页看角标，然后拔插网线看 2 秒内能不能自己 join 回来，最后限速/丢包看 `incomplete` 和画面是不是只丢帧、不冻结。

## 13. 还没搞定的

- iOS multicast entitlement 得向 Apple 申请，不解决 iOS 端 LCM 就是不可用。
- 150KB/60Hz 在 debug 构建下只有 50 出头，release 还没正经测。如果现场就是大帧，是降到 960 宽解，还是上原生解码，得定个方向。
- 无 ack 的代价：UI 线程如果被系统卡住，SendPort 里可能短时堆一点消息。UI 处理每帧是 O(1)，实际没出过问题，但要求硬上限就得把 ack 捡回来。
- 通道名长期靠映射不是办法，最好让机器人侧统一，或者把映射配置化。
- 局域网没有认证/加密，同网段能监听。现在靠网络隔离，真要有安全要求得加网关或 TLS。
- UDP 没有重传，丢片就是丢帧。实时预览能接受，录制/回放不走这条链路。

## 14. 文件

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
