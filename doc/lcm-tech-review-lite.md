# LCM 实时链路技术评审（重点版）

| 项目 | 内容 |
|---|---|
| 模块 | LCM 组播接收 / 分片组包 / isolate 线程模型 |
| 客户端 | Flutter（Android / iOS / macOS / Windows / Linux） |
| 关联提交 | `60ad932`、`ac052ba`、`603712c` |
| 日期 | 2026-10-22 |

本文只讲三个重点：**组播怎么收、分片怎么组、线程怎么分**。协议字段、平台权限、测试细节不展开。

## 0. 一张图

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

## 1. 组播数据接收

### 1.1 地址

| 数据 | 组播地址 | 端口 | 通道 |
|---|---|---|---|
| 相机 | `239.255.76.67` | `7667` | `/preview/cameras/<name>` |
| 关节 | `239.255.76.68` | `7668` | `/preview/joint_batch` |

- 只订阅，不发布。
- 相机链路会自动追加关节通道，兼容“相机和关节发在同一组”的发布端。
- 关节组/端口与相机不同时，额外开一条关节 socket；相同则复用一条。

### 1.2 接收流程

1. `RawDatagramSocket.bind(0.0.0.0, port, reuseAddress: true)`。
2. 遍历所有 IPv4 网卡，逐块 `joinMulticast(group, nic)`。
3. 每 2 秒重扫网卡：新插的网线、新建的 VPN 会自动补 join。
4. socket 可读时一次最多连收 512 个数据报，然后让出事件循环。
5. 每个数据报交给 `LcmMessageReader` 解析，按通道过滤后交给重组/解码。

### 1.3 为什么按网卡 join

组播成员关系是**按网卡**的，不是按主机：

- 只 join 默认路由那块网卡 → 插网线、双网卡、VPN 场景下另一块网卡收不到。
- 现场典型现象：“Wi-Fi 能看，插网线看不到”，通常不是解码问题，是没 join 对网卡。

排查时可以看统计里的 `interfaces`：

- 空 → 一块都没 join 上（权限/防火墙/VPN）。
- 只有 `en0` → 有线网卡没加入，检查 `LCM_IFACE` 或网卡状态。

### 1.4 平台差异

| 平台 | 关键点 |
|---|---|
| Android | `CHANGE_WIFI_MULTICAST_STATE` + `MulticastLock`（`tavi/multicast`），否则息屏/后台会被过滤 |
| iOS | 需要 Apple 的 `com.apple.developer.networking.multicast` entitlement，未申请就收不到 |
| macOS | App Sandbox 需要 `network.client` / `network.server`，本地网络说明已配置 |
| Windows | 防火墙放行 UDP 7667/7668 入站（专用网络） |
| Linux | 无特殊配置，多网卡时用 `LCM_IFACE` 指定 |

### 1.5 收不到数据时的判断顺序

1. `datagrams` 是否为 0：0 说明包没到本机（网段/端口/组播 join/防火墙）。
2. `interfaces` 是否为空：空说明 join 失败（VPN、权限、`LCM_IFACE` 写错）。
3. `messages` 是否远小于 `datagrams`：说明分片丢失或通道名不匹配。
4. 通道名不确定时，用 `LCM_ALL=true` 收全部通道，先确认有没有包。

## 2. 分片组包

这里其实有**两层分片**，分别解决不同层的问题：

| 层 | 解决什么 | 谁分的片 | 关键标识 |
|---|---|---|---|
| LCM 长包 | UDP 单包放不下的大消息 | LCM 发送端 | `发送方 + seq` |
| preview_package_t | 相机帧/关节包切成 1200 字节 | 机器人 preview 发布端 | `message_id + streamId + index` |

### 2.1 第一层：LCM 长包重组

LCM 短包直接是 `magic + seq + channel + payload`；大消息会被拆成长包：

```text
magic(LC03,4) | seq(4) | total(4) | offset(4) | index(2) | count(2) | channel\0? | chunk
```

- **通道名只在第 0 片**，后续片没有通道名，这是最容易实现错的地方。
- 按 `发送方:端口 + seq` 分组，避免不同发布端串包。
- 每片写入固定缓冲区，记录字节区间。
- 判完整不是看“片数够了”，而是看**字节是否连续覆盖**；重叠片/空洞片会被丢弃。
- 最多同时保留 64 个半包；单条消息最大 512KB；2 秒收不齐过期。
- 重复片忽略；同一 seq 的 total/count 发生变化则丢弃整组。

### 2.2 第二层：preview_package_t 重组

相机帧和关节包都会切成最多 1200 字节的片：

```text
hash(8) | messageId(8) | streamId(4) | index(4) | count(4) | total(4) | length(4) | payload
```

发送端契约（不满足直接丢弃，不进缓冲区）：

- `count == ceil(total / 1200)`
- `length == min(1200, total - index * 1200)`
- `index < count`，`total <= 512KB`

接收端策略：

- 每条流最多 3 个半成品，丢了片的帧立刻淘汰，不阻塞后面的帧。
- `message_id` 比已完成帧旧的直接丢弃，防止迟到旧片拼出重复画面。
- 相机按 `相机名/streamId` 分组，发布端重启后不会串帧。
- 拼完后校验 JPEG/PNG 文件头，坏图计 `corrupt`，不交给 UI。

### 2.3 关节包

`joint_batch_t` 有两种到达方式：

- 裸包：直接发 `joint_batch_t`；
- 包一层：用 `preview_package_t` 分片，重组后再解码（机器人 joint bridge 的方式）。

解码要点：

- 固定 10 个槽位、128 宽数组，实际数量由 count 决定。
- 只读 count 个 double，其余跳过，避免无意义分配。
- 只保留 `/position` 后缀，去掉后缀后按关节名对齐。

### 2.4 异常处理

| 异常 | 处理 |
|---|---|
| 片序号/偏移越界 | 丢该片 |
| 重复片 | 忽略 |
| 缺片 | 2 秒后过期，计 `dropped` |
| 重叠/空洞 | 覆盖检查失败，丢弃 |
| 同 id 形状变化 | 丢半成品，计 `corrupt` |
| 旧帧迟到 | 直接丢 |
| 拼出的不是图片 | 计 `corrupt`，不交 UI |

## 3. isolate 线程模型

### 3.1 边界

- **接收 isolate**：socket、LCM 分帧、长包重组、preview 分片重组、关节解码、统计。
- **UI isolate**：只收完整相机字节和关节批次，负责 JPEG/PNG 解码、`ui.Image`、上屏。
- 两个 isolate 不共享内存，字节通过 `SendPort` 传递；业务页面不接触 socket。

### 3.2 为什么这么分

- 收包和分片重组是纯 CPU/IO 工作，放到后台 isolate，UI 线程不卡。
- 单个坏包/异常只影响接收 isolate，不会拖垮 UI 事件循环。
- 接收端可以独立做统计、限流、排查。
- UI 侧只处理“完整画面”，逻辑简单。

### 3.3 UI 侧怎么消费

每路相机只有一个 latest 槽，不是队列：

```text
latest[相机] = 最新一帧
解码线程取走 latest 解码
解码期间来的新帧覆盖 latest → 中间帧自然丢弃
```

效果：

- 每路最多 1 张正在解码 + 1 张等待；
- 解码慢时丢中间帧，**延迟不随运行时间增长**；
- 显示帧率 = 实际解码能力，源 60Hz、解码跟得上就是 60fps；
- 不做 ack 往返：实测 ack 会让 60Hz 下的帧率下降 2–10%，所以把丢帧放在 UI 侧。

### 3.4 跨 isolate 的代价

- 每帧字节要复制一份到 UI isolate：26KB × 4 × 60 ≈ 6.2MB/s，150KB × 4 × 60 ≈ 36MB/s。
- 实测 `TransferableTypedData` 只比普通拷贝快约 15%，占总耗时约 1%，暂不引入。
- 真正的瓶颈在 UI 侧 JPEG 解码，所以策略是“控制解码量”，不是“优化拷贝”。

### 3.5 生命周期与统计

- 启动：接收 isolate 建好 socket、join 网卡后发 `ready`。
- 停止：UI 发 `stop`，关闭 socket、取消定时器。
- 统计：每 500ms 推送一次快照（datagrams、messages、parseErrors、dropped、incomplete、corrupt、pending、interfaces），供页面和 `tool/live_check.dart` 使用。

## 4. 关键参数

| 参数 | 值 |
|---|---|
| 相机组播 / 端口 | `239.255.76.67:7667` |
| 关节组播 / 端口 | `239.255.76.68:7668` |
| 单次 socket drain | 512 包 |
| 网卡重扫 | 2 秒 |
| LCM 半包上限 | 64 组 / 512KB / 2 秒过期 |
| preview 分片 | 1200 字节，单帧最大 512KB |
| 每流半成品 | 3 |
| 关节槽位 | 10 × 128 |
| 统计推送 | 500ms |
| 解码降采样 | 宽度 > 1280 时按 1280 解码 |

## 5. 评审关注点

- 组播是否 join 到所有实际网卡（现场双网卡/VPN）。
- 长包“通道只在第 0 片”是否覆盖所有发布端。
- 分片覆盖检查、过期、重复片是否满足弱网。
- latest-wins 的丢帧策略是否接受（实时优先，不排队）。
- iOS multicast entitlement 是否在上线前解决。
- `LCM_ALL` 只作为排查手段，生产默认关闭。

## 6. 一句话总结

接收和组包全部在独立 isolate 完成，UI 只拿完整帧；LCM 长包按发送方+seq 重组、preview 分片按 message_id 重组，两层都做字节覆盖校验；实时性靠“每路只留最新帧”保证，丢帧但不累积延迟。
