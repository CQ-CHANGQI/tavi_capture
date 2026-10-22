# 离线视频（MCAP 回放）设计与实现

离线视频就是“查看数据 / 回看”这块，播的是机器人工控上录的 `.mcap` 包，不是本地文件，也不是 LCM 实时流。

这条链路和 LCM 是**完全独立**的：LCM 走 UDP 组播、只保留最新帧；离线回放走 HTTP Range、有时间轴、能暂停/快进/拖进度条/看关节曲线。两边的代码唯一的交集是 `CameraGrid` 和关节图组件。

我们组之前也没怎么用过 MCAP，所以前面先补一下格式，后面再讲实现和坑。

## 0. 和实时预览的区别

| | LCM 实时 | MCAP 离线 |
|---|---|---|
| 数据源 | 机器人组播 | 工控上的 `.mcap` 文件 |
| 传输 | UDP 组播 | HTTP Range |
| 时间 | 只有“现在” | 有完整时间轴 |
| 丢帧 | 常态，保最新 | 按时间播放，seek 时重新读 |
| 交互 | 无 | 播放/暂停/倍速/循环/拖拽/逐帧 |

实时链路不会等 MCAP，MCAP 也不依赖实时链路。

## 1. MCAP 是什么

先说人话：MCAP 是一个**录制容器**，不是编码格式。它把 ROS2 的话题、消息、时间戳、schema 打包进一个文件，支持分块、压缩和索引。

它长这样：

```text
magic(8) | Header | Chunk... | Chunk... | Summary | Footer | magic(8)
```

- **Chunk**：一批消息打包在一起，可以压缩（我们支持未压缩和 zlib）。
- **ChunkIndex**：记录每个 chunk 在文件里的 offset/length、起止时间、每个 channel 的消息数。
- **Summary**：schema、channel、chunk index、statistics，放在文件尾部。
- **Footer**：最后 37 字节，指向 Summary 的起始位置。

每条记录是：

```text
opcode(1) | length(8, little-endian) | body[length]
```

我们用到的 opcode：

| opcode | 记录 |
|---|---|
| 0x01 | Header |
| 0x02 | Footer |
| 0x03 | Schema |
| 0x04 | Channel |
| 0x05 | Message |
| 0x06 | Chunk |
| 0x08 | ChunkIndex |
| 0x0B | Statistics |

消息本身是 `Message`：

```text
channel_id(2) | sequence(4) | log_time(8) | publish_time(8) | data
```

`log_time` 是纳秒时间戳，回放的时间轴就是它。

**为什么用 MCAP**：ROS2 生态默认录制格式，自带 schema 和索引；一个几 GB 的包，能只读 footer + summary + 需要的 chunk 就开始播，不用整包下载。

## 2. HTTP Range 读取

机器人工控上一般用 Caddy 或者一个静态文件服务把 `.mcap` 暴露成 HTTP。我们只要求它支持 **Range**。

打开一个包的过程：

1. `HEAD` 拿文件长度；服务器不支持 HEAD 就发 `Range: bytes=0-0`，从 `Content-Range` 里拿总长度。
2. 读最后 37 字节，校验 magic 和 Footer，拿到 Summary 的 offset。
3. 读 Summary，拿到 schema、channel、chunk index、statistics。
4. 播放时按 chunk 发 `Range: bytes=start-end`，只下当前需要的块。

几个硬要求：

- 必须返回 **206**，不能是 200。返回 200 说明服务器忽略了 Range，整个文件会被拉下来。
- `Content-Range` 要准确，`start-end/total` 对得上；我们对返回长度也做了校验。
- 要 `Accept-Encoding: identity`。中间层如果 gzip 了，`Content-Length` 和 Range 的语义都会乱，我们直接按字节数校验，错了就报。
- 文件在播放期间不能变。读到一半总长度变了，直接报“回放文件在读取期间发生变化”。

第一版不是这么做的：整包下载到临时文件，边下边建索引。几 GB 的包光打开就要等半天，还占磁盘，后来整个删了。现在首帧只依赖 footer + summary + 第一个 chunk。

### Seek 怎么找位置

Summary 里有 ChunkIndex。给定目标时间，在 chunk 列表里找到覆盖这个时间的块，从那个 offset 开始读；不需要从头扫消息。

目前**没有 chunk 缓存**：拖进度条回到刚才播过的地方，会重新发 Range 请求。局域网问题不大，Wi-Fi 弱的时候会顿一下。这个后面可以加个小的 LRU。

## 3. CDR 解码

MCAP 里 ROS2 消息的 data 是 CDR。

CDR 有几个坑：

- 前面 4 字节是封装头，第 2 个字节表示大小端。
- 对齐是**相对于第 4 字节之后**算的，不是文件绝对偏移。
- string 是 `uint32 长度（含结尾 NUL）+ 内容`。
- 数组是 `uint32 长度`，然后按元素类型对齐。

我们支持的消息：

### Image

```text
header: stamp(sec, nanosec) + frame_id
height, width, encoding, is_bigendian, step, data
```

支持 `bgr8 / rgb8 / bgra8 / rgba8 / mono8`。bgr8 要自己转 RGBA，然后 `decodeImageFromPixels` 生成 `ui.Image`。

### CompressedImage

```text
header + format + data
```

format 里含 jpeg/jpg/png 就交给 `instantiateImageCodec`，其他格式直接丢。

### JointState

```text
header + name[] + position[] + velocity[] + effort[]
```

按话题名分左臂/右臂/身体，位置进曲线，velocity/effort 不用。

### Statistics

```text
header + count + (name, value)[]
```

`pal_statistics_msgs` 的格式。名字带 `state_interface.` / `command_interface.` 前缀，我们按前缀分状态/指令，只留 `/position`，再去掉前缀和后缀，按关节名对齐。

为什么要同时支持 JointState 和 Statistics：不同批次的录制不一样。现有样例 `train_data_1_0.mcap` 里是 JointState；更早的机器人包里有 Statistics。两条路都保留，按 schema 分派。

## 4. 一条回放的完整流程

1. 用户在“查看数据”里选一条记录，拿到 `sourceUrl`。
2. `PlaybackController.open()`：
   - `McapRemoteFile.open()`：HEAD/Range、footer、summary。
   - `McapSummary.load()`：schema、channel、chunk index、statistics。
   - 给每个 channel 建 schema 名和 topic 的映射。
3. `_mapChannels()`：
   - 图像 channel 按 topic 分到 `cam_head / cam_left / cam_right / cam_chest`；
   - JointState/Statistics channel 放进选中集合。
4. 建 `McapChunkCursor`，从 `startTime` 开始。
5. `_prime()`：先读 400ms（最多 240 条消息），把首帧和关节曲线填出来。播放器一打开就有画面，不是黑屏。
6. `play()` 跑 `_run()`：读下一条消息，按 `log_time` 和墙钟等到该显示的时刻，`_apply()`。
7. 图像走 latest-wins 解码；关节追加到 `JointTrack`。
8. UI 的 `PlayBar` 负责播放/暂停、±5 秒、逐帧、倍速、循环、拖拽。
9. 画面和关节图在 `ReplayPanel` 里，库和回看页共用。

### 通道怎么对到四个画面

MCAP 里的 topic 名字不固定，我们按关键字归一：

- `head` / `main` / `cam1` → `cam_head`
- `chest` / `pan` / `overview` / `cam4` → `cam_chest`
- `left` / `fisheye_l` / `cam3` / 结尾 `_l` → `cam_left`
- `right` / `fisheye_r` / `cam2` / 结尾 `_r` → `cam_right`

认不出来的图像 channel 按 topic 排序后，依次补到还没占用的槽位。比如包里只有两路鱼眼，会先按 `fisheye_l/r` 分到左右，主视角和全景保持空白。

关节按话题名分左臂/右臂/身体，Statistics 还会按 `state_interface.` / `command_interface.` 分状态和指令。头部关节不进 UI（我们只画三组），名字里没有 `/position` 的也丢掉。

## 5. 播放时钟和 seek

播放器不是“读一条显示一条”，是按时钟走：

- `log_time` 是纳秒，播放开始记 `mediaStart` 和 `wallStart`。
- 每条消息算 `dueMs = (logTime - mediaStart) / 1e6 / speed`，和墙钟比，不够就等。
- 等待按 80ms 一片切，避免一次长 sleep 导致暂停/seek 不响应。
- 播到末尾：循环就 seek 回开头，不循环就停。

Seek：

1. 暂停，`generation++` 让旧的播放循环退出。
2. 清空当前画面和关节历史。
3. 用目标时间新建 `McapChunkCursor`。
4. `_prime()` 读 400ms，把目标附近的画面/关节填出来。
5. 原来在播就继续播。

逐帧现在是 `±33ms`，不是按真实帧时间戳找下一帧。源是 30fps 时基本对，60fps 会跳一帧。这个后面要改成读图像通道的下一个 `log_time`。

## 6. 解码和渲染

图像解码和实时那条链路一样，是 latest-wins：

- 每路相机一个“最新待解码”槽，解码期间来的新帧覆盖旧的；
- 解码慢就丢中间帧，拖动/倍速时不会积压；
- 旧 `ui.Image` 在新图替换后、下一帧结束时 dispose。

区别是数据来源：

- `CompressedImage`：直接 `instantiateImageCodec`，成本低。
- `Image`（raw）：`decodeRosImage` 先把 bgr8/rgb8 等转成 RGBA，再 `decodeImageFromPixels`。640×480 的 raw 一帧 900KB，转像素是纯 Dart 循环，CPU 比 JPEG 重不少。

关节数据：

- 每帧按名字追加到 `JointTrack` 的 `state` / `command`；
- 每条曲线最多留 600 个点，图上只画最近 240 个；
- 左臂/右臂/身体三组，图例按位置映射成“肩俯仰/肩滚转/…”这类中文名；
- 模式有“指令 / 状态 / 全部”，没有 command 数据时退回 state，避免空图。

通知节流到 33ms，解码/关节更新不会把 UI 刷爆。

## 7. UI 这块

- “查看数据”左侧是采集条列表，支持任务/人员/有效性筛选、分页；右侧是回放面板。
- 回放面板：四路相机 + 三组关节图 + 播放条；可以最大化，相机可以双击全屏。
- “回看”页复用同一个 `ReplayPanel`，底下是标记无效/返回列表。
- `PlayBar`：后退 5 秒、逐帧后退、播放/暂停、逐帧前进、前进 5 秒、进度条、时间、倍速、循环。

一个现状：所有 mock 采集条都指向同一个 `recordingUrl`，所以点哪条播的都是同一个包。接后端后要按记录存 `sourceUrl`，这是已知的临时行为。

## 8. 服务器和配置

本地联调：

```bash
go run ./server -file /path/to/data.mcap -addr 127.0.0.1:8090
```

`server/main.go` 是一个单文件 Range 服务：`/data.mcap`、`/healthz`，用 `http.ServeContent` 处理 Range/HEAD，可选限速。生产上就是 Caddy 或者机器人自带的文件服务。

配置：

| 变量 | 默认 | 说明 |
|---|---|---|
| `MCAP_URL` | 空 | 直接指定回放地址，优先级最高 |
| 默认地址 | `http://<ROBOT_IP>:8090/rosbag_0.mcap` | 没配 `MCAP_URL` 时用 |

注意回放地址和 LCM 无关，LCM 是组播，不需要 IP；`ROBOT_IP` 只影响这个默认 URL。

## 9. 实测和性能

拿 `train_data_1_0.mcap`（1.7GB）跑过：

- 25 个 channel，2007 个 chunk，时长 33.48 秒，48133 条消息。
- 两路 640×480 bgr8 鱼眼相机，各 1000 帧左右；左右臂 JointState 各 175/182 条。
- 打开只读 footer + summary；播放时按 chunk 拉，不整包下载。
- 打开和播放验证过，左右相机画面和 6 轴关节都能出来；seek 走同一套 cursor，没做长时间压测。

raw 图像很吃带宽：一帧 900KB，两路 30fps 就是 50MB/s 量级。局域网千兆没问题，Wi-Fi 会卡；压缩图像（JPEG）的包轻很多。

当前没有 chunk 缓存、没有预读。顺序播没问题，来回拖会重复请求。

## 10. 出问题怎么查

UI 上回放失败会显示“回放加载失败”+ 重试，具体原因在错误文本里。常见几种：

| 现象 | 原因 |
|---|---|
| 404 / 连接失败 | URL 错、文件不在、服务没起 |
| 200 而不是 206 | 服务器不支持 Range，或者被中间层转成了整包 |
| 返回长度不对 | 中间层 gzip / 改写了 Content-Length |
| 没有 summary | 录制工具没写索引，当前不支持 |
| 不支持的压缩 | chunk 是 zstd/lz4，目前只支持 none/zlib |
| 没有图像或关节话题 | 包不对，或者 topic 名不匹配 |
| 有画面没关节 | schema 不是 JointState/Statistics，或名字里没有 `/position` |
| 拖动后卡一下 | 没缓存，重新拉 chunk |

命令行先看包：

```bash
dart run tool/mcap_check.dart http://<host>:8090/<file>.mcap
```

会打印文件大小、profile、消息数、channel、时长、每个 topic 的 schema 和消息数，以及前几条消息的采样。

## 11. 测试

- `test/mcap_codecs_test.dart`：Statistics、JointState、bgr8 Image 的 CDR 解码。
- 真包手测：1.7GB 的 `train_data_1_0.mcap`，打开、播放、seek、关节曲线。
- UI 冒烟：回放失败时显示错误和“重试”，不崩。
- `tool/mcap_check.dart`：命令行验包。

缺口也说一下：MCAP reader/chunk cursor 目前没有合成文件的单测，都是靠真包和 codec 测试；后面可以造一个小的 MCAP 跑 CI。

## 12. 还没搞定的

- 每条采集条独立 `sourceUrl`：现在全是同一个 mock URL。
- chunk LRU 缓存：seek 回退会重复下载。
- zstd/lz4：机器人如果换压缩方式，现在会直接报错。
- 逐帧按真实帧时间戳走，不是固定 33ms。
- 4K/高分辨率包的降采样：实时链路有 1280 宽限制，回放这边还没做。
- raw Image 的像素转换在 UI isolate，4K 包会很重；考虑降采样或原生解码。
- CRC 字段目前只读不校验。
- 鉴权/TLS：Range 服务和回放都没有认证，靠网络隔离。

## 13. 文件

```text
lib/core/mcap/mcap_reader.dart      HTTP Range / Footer / Summary / ChunkCursor
lib/core/mcap/mcap_codecs.dart      CDR：Image / CompressedImage / JointState / Statistics
lib/core/playback.dart              播放时钟、seek、四路画面、三组关节
lib/ui/replay_panel.dart            回放面板
lib/ui/playbar.dart                 播放条
lib/ui/camera.dart                  相机网格/全屏
lib/ui/joints.dart                  关节图表
lib/screens/library.dart            查看数据
lib/screens/review.dart             回看
server/main.go                      本地 Range 服务
tool/mcap_check.dart                命令行验包
```

（`mcap_format.dart` 之前有，后来没人用删了。）

先写这些。离线这块后面主要想解决三件事：每条记录独立地址、chunk 缓存、以及大分辨率包的解码性能。

