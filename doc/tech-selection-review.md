# 技术选型评审（分点版）

上一版把 Flutter、LCM、isolate、MCAP 混在一起讲，看着累。这版一个技术点一节，每节只讲这一件事：它解决什么问题、为什么用它、不用什么、代价是什么。

> **实现状态（以代码为准）**：Flutter、dart:io、go_router、LCM、MCAP、自绘 UI、
> Go 联调服务已经落地；`shared_preferences`、JSON REST + WebSocket、token 登录
> 尚未接入。当前业务数据仍是 `AppState` 里的 mock，冷启动默认张三/工程师，
> 机器人 IP 不持久化。

先把地图放这：

- UI 和跨平台：Flutter
- 语言和底层 IO：Dart + dart:io
- 实时总线：LCM
- 实时传输方式：UDP 组播
- 实时线程：长驻接收 isolate
- LCM 协议解析：自己写
- 离线容器：MCAP
- 远程读文件：HTTP Range
- 文件服务：Caddy
- 消息编码：CDR，自己写
- 图像解码：Flutter engine
- 状态管理：ChangeNotifier + InheritedNotifier
- 路由：go_router + ShellRoute
- UI 组件：自绘
- 图表：CustomPainter
- 网络客户端：dart:io
- 业务接口：JSON REST + WebSocket（计划，尚未接入）
- 本地存储：shared_preferences（计划，尚未接入）
- 联调服务：Go 标准库
- 平台适配：Android/iOS/macOS/Windows 原生配置
- 测试、日志、依赖策略

下面一个一个说。

## 1. Flutter：管 UI 和跨平台

Flutter 解决的是“一套 UI 跑五个平台”。平板上的固定布局、四宫格相机、自绘图表、弹层，用 Flutter 写一遍就行；Android、iOS、macOS、Windows、Linux 共用同一套页面和主题。

也评估过 React Native。UDP/LCM 这种底层能力最后还是要写原生模块，60Hz 图像过 JS 桥我不放心；桌面端支持也不如 Flutter 稳。纯原生更不考虑，五套代码，UI 对齐原型要重做五遍，团队扛不住。

代价是包体比原生大，Dart 生态比 JS 小，iOS 的组播权限还是得走原生配置。这些是一次性成本，比维护五套 UI 划算。

代码在 `lib/screens/` 和 `lib/ui/`，跨平台没有分支。

## 2. Dart + dart:io：语言和底层 IO

Dart 不是单独选的，是 Flutter 带出来的；但 `dart:io` 值得单独说。它提供 RawDatagramSocket、HttpClient、WebSocket，正好覆盖 UDP 组播、HTTP Range 和事件推送，不需要为了网络能力再写原生插件。

不用原生 socket/HTTP 栈，是因为五个平台各写一套成本太高；也不用第三方网络库，dart:io 已经够底层，Range 和原始流都能控制。

代价是 Dart 的事件循环是单线程的，CPU 重的活儿（分片重组、像素转换）必须挪到 isolate，不然会卡 UI。这个约束后面在 isolate 那节展开。

代码在 `lib/core/lcm/lcm_receiver.dart` 和 `lib/core/mcap/mcap_reader.dart`。

## 3. 不做 Web：不是漏了，是主动砍的

浏览器开不了裸 UDP 组播，LCM 实时预览在 Web 上根本走不通；用 WebRTC 或 WebSocket 网关转发，等于把整条链路重做一遍。

所以项目不设 web runner，也不写 `kIsWeb` 分支。代价是没有“打开浏览器就能看”的能力，分享、SEO 这些也都没有；这个产品本来就不需要。

## 4. LCM：机器人侧的发布订阅总线

LCM 是机器人圈子里的消息总线：发布端往通道发二进制消息，订阅端按通道收，底层默认 UDP 组播。消息前面有 8 字节类型指纹，通道名是字面匹配。

选它不是因为时髦，是因为机器人本来就发 LCM。相机走 `/preview/cameras/<name>`，关节走 `/preview/joint_batch`，pad 顺着协议收就行，不需要机器人再加一层网关。

评估过让机器人加 WebSocket 网关、或者上 MQTT。前者多一跳转发，TCP 一丢包全排后面；后者要布 broker，消息模型也不适合大帧视频。HTTP 轮询更不用考虑。

代价是 LCM 本身不可靠、没鉴权、TTL=1 只能同二层网络。这些是协议属性，不是实现能补的，只能靠丢帧策略和网络隔离兜。

代码在 `lib/core/lcm/`。

## 5. UDP 组播：LCM 的传输方式

LCM 默认用 udpm，也就是 UDP 组播。相机组是 239.255.76.67:7667，关节是 239.255.76.68:7668，TTL=1。

组播的好处是一个发布端可以同时喂多台平板，不用为每台设备维护连接；UDP 没有重传和队头阻塞，60Hz 下延迟低。坏处是丢包就丢包，网络设备不转发就一个包都收不到。

实现上最重要的不是 `bind`，是 **join 要按网卡加**。组播成员关系是按网卡的，只 join 默认路由那块，现场就是“Wi-Fi 能看、插网线黑屏”。现在每 2 秒扫一遍网卡，新插的网线、新起的 VPN 都会补 join。

其他细节：绑 `0.0.0.0`、`reuseAddress`、一次最多连收 512 个包就让出事件循环。Android 还要 MulticastLock，iOS 要 entitlement，这些在平台适配那节说。

代码在 `lcm_receiver.dart` 的 `_UdpLink`。

## 6. 接收 isolate：实时线程模型

Dart 的 isolate 是独立事件循环 + 独立内存堆，两个 isolate 不能直接读对方对象，只能通过 SendPort 发消息，发过去的数据会复制。

接收全放一个长驻 isolate：socket、LCM 分帧、两层重组、关节解码、统计。UI isolate 只拿完整帧和关节批次，负责解码、上屏。

原因是 60Hz 四路相机，分片重组是纯 CPU/IO，放 UI 会挤掉渲染和触摸；一个坏包也不该把页面带崩。之前那版 60Hz 只出 30fps，是 33ms 合并定时器干的，和 isolate 无关，但同样说明实时链路不能堵 UI。

不选 UI 里 async：async 不解决 CPU 占用，socket 回调和重组照样跑在 UI 事件循环。不选每个包 compute：isolate 启停比解析还贵。

代价是跨 isolate 要复制字节，26KB×4×60 约 6.2MB/s，150KB 时 36MB/s；UI 卡住时 SendPort 会短暂堆积。缓解是 UI 每路只留最新帧、解码慢就丢、不做 ack、解码前按 1280 宽降采样。

代码在 `lcm_receiver.dart` 和 `live_preview.dart`。

## 7. LCM 协议解析：自己写

这一层解决的是“把 UDP 数据报变成一帧画面/一批关节”。LCM 有短包和长包：短包一条消息一个 UDP 包；长包会拆片，通道名只在第 0 片，按发送方+seq 重组。

相机帧外面还有一层 `preview_package_t`：36 字节头、每片最多 1200 字节、按 message_id/streamId/index 重组。关节是 `joint_batch_t`：10 个固定槽位、每个 128 宽、名字用换行分隔、只保留 `/position`。

自己写的原因是找过 Dart 的 LCM/MCAP 包，基本只覆盖本地文件和基础 pub/sub；长包通道只在第 0 片、preview 分片、ROS2 CDR 这些都得自己补。索性按协议重写，四个文件一千多行，边界和测试都在自己手里。

代价是维护：发布端一改格式，pad 就可能解出脏数据。所以协议单测、e2e、corrupt 计数不能省。这是整个选型里最需要长期盯的一块。

代码在 `lcm_message.dart` 和 `preview_protocol.dart`。

## 8. MCAP：离线容器

MCAP 是 ROS2 的录制容器，不是编码格式。一个文件里有 Header、Chunk、ChunkIndex、Summary、Footer；每个 Chunk 装一批消息，可以压缩；Summary 在文件尾部，记录 schema、channel、chunk 索引和统计。

选它是因为机器人本来就录 MCAP，自带多话题、时间戳、索引，seek 方便。转 MP4 会丢关节、多相机同步和多话题；自己定义格式又要重新做索引和工具链。

代价是依赖 summary：没有 summary 的文件现在不支持；chunk 压缩只支持 none/zlib，zstd/lz4 会直接报错。

代码在 `mcap_reader.dart`。

## 9. HTTP Range：远程读 MCAP

Range 是 HTTP 的字节范围请求，服务器返回 206 和 Content-Range。pad 只读 footer、summary 和当前 chunk，不整包下载。

第一版是整包下载到临时文件再建索引，几 GB 的包打开要等很久，还占磁盘，后来整个删了。现在 1.7GB 的包能直接打开播，首帧不用等下载。

代价是服务器必须支持 Range/206、不能 gzip；文件在播放期间不要被替换（当前代码只缓存打开时的长度，没有一致性校验）；当前没有 chunk 缓存，拖回去会重新请求。

代码在 `McapRemoteFile`。

## 10. Caddy：文件服务

生产用 Caddy 把机器人的 MCAP 目录暴露成 HTTP；本地联调用 Go 单文件服务。

Caddy 一个二进制搞定静态文件、Range、TLS、反代，配置短；Go 的 `http.ServeContent` 自带 Range/HEAD，写联调服务几十行。Nginx 也能做，但对“机器人上放个文件”这个场景配置偏重；自己写生产文件服务要补 TLS、缓存、限速，没必要。

代价是 Caddy 配错 gzip 会破坏 Range；公网暴露要加签名/鉴权。这部分不是 pad 代码能兜的，得运维一起定。

## 11. CDR：ROS2 消息编码

CDR 是 ROS2 消息的二进制编码：4 字节封装头、按字节对齐、字符串带长度和 NUL、数组先长度再元素。

只实现 Image、CompressedImage、JointState、Statistics 四种。回放只用这四类；通用 CDR/ROS 包带一堆 schema 和代码生成，真正要改的边界还是得自己看。

代价是机器人换消息类型要补代码；字段顺序错了不会报错，只会解出脏数据。所以每种消息都有单测。

代码在 `mcap_codecs.dart`。

## 12. 图像解码：Flutter engine

JPEG/PNG 用 `instantiateImageCodec`；raw 图（bgr8/rgb8 等）先转 RGBA，再用 `decodeImageFromPixels` 生成 `ui.Image`。

不引 OpenCV：包体、构建、NDK 都是成本，当前也不需要做视觉算法。不写原生解码：每个平台一遍，收益只在超大帧。

代价是 raw bgr8 的像素转换是纯 Dart 循环，640×480 还行，4K 会重。现在源宽超过 1280 才降采样，真遇到大帧再考虑原生或后台解码。

代码在 `live_preview.dart` 和 `playback.dart`。

## 13. 状态管理：ChangeNotifier + InheritedNotifier

一个 AppState（ChangeNotifier）管全局业务状态，AppScope（InheritedNotifier）往下传；页面栈归 go_router，实时和回放各自有 Controller。

不选 Riverpod：团队没人用过，这个 app 就一个状态机，引一套 provider/scope 规则不划算。不选 Bloc：事件/状态样板代码多，页面交互没那么复杂。

代价是 AppState 会胖。早期每来一帧就 notify 整页，四路 60Hz 就是 240 次/秒，顶栏、列表全重画；后来才拆成相机面板只听 LivePreview，顶栏 500ms 刷一次。新模块必须独立 Controller，不能再往里塞。

代码在 `app_state.dart`、`scope.dart`、`live_preview.dart`、`playback.dart`。

## 14. 路由：go_router + ShellRoute

七个固定页面用 `GoRoute` 注册，`ShellRoute` 把顶栏、弹层和 toast 包在外面，子路由只替换页面内容。跳转用 `go` / `push` / `pushReplacement` / `pop`，录制中离开采集页由 collect 路由的 `onExit` 拦截。

不用裸 Navigator：`push/pop` 本身够用，但 redirect、`onExit` 和嵌套 shell 都要自己拼。代价是多一个 `go_router` 依赖，路径字符串要靠 `AppRoutes` 常量收口。

代码在 `lib/router/`、`lib/ui/shell.dart`。

## 15. UI 组件：自绘

Material 基础上自己封按钮、输入、弹层、相机网格、播放条，主题集中在 `theme.dart`。

不选组件库：原型里的间距、圆角、颜色、平板断点都定死了，组件库默认样式反而要一个个覆盖。代价是组件自己维护，无障碍和键盘焦点容易漏。

## 16. 图表：CustomPainter

关节曲线用 CustomPainter 自己画：折线、坐标、图例，三组，每组最多 240 个点。

不选 fl_chart：功能多，但样式对不上，依赖也用不完。代价是坐标轴、tooltip、缩放要自己写；复杂图表不要硬扛。

代码在 `joints.dart`。

## 17. 网络客户端：dart:io，不引 dio

HTTP 和 WebSocket 直接用 dart:io：HttpClient 控 Range、流式读、超时、连接复用；WebSocket 收事件。当前代码只用了 HttpClient（MCAP）和 `Socket.connect`（连接探测），业务 WebSocket 还没接。

dio 不是不好，是它的拦截器、取消、重试在这个场景用不上；Range 和原始流最后还是要落到 HttpClient，多一层封装反而难排查。代价是重试、超时、鉴权头要自己封一个薄 client。

## 18. 业务接口：JSON REST + WebSocket

普通查询/命令走 HTTP JSON；状态、采集、任务变化走一条 WebSocket。调试直观，Flutter 自带客户端，LAN 延迟足够低。这是目标方案，当前业务数据仍由 `AppState` mock，没有 REST/WS client。

不选 gRPC：要 proto/codegen/HTTP2，这点接口用不上。不选 MQTT：要 broker，消息语义也不适合请求/响应。代价是没有 schema 强约束，字段靠文档和手写模型。

## 19. 本地存储：shared_preferences

计划只存上次连接的 IP；token 只放内存，重启重新登录。

就一个字符串，不值得上 sqlite/Hive；用文件的话 Android/iOS 目录和权限又要 path_provider。之前联调时把持久化去掉了，现在需求要缓存，又得加回来，绕了一圈。

**当前代码还没有这一步**：`pubspec` 里没有 shared_preferences，启动用的是 `ROBOT_IP` 默认值，`savedIp` 只存在内存。这是目前唯一计划新增的运行时依赖。

## 20. 联调服务：Go 标准库

`server/main.go` 用 net/http + http.ServeContent，提供 Range/HEAD/限速/healthz。

选 Go 是因为单文件、无依赖、跨平台编译；ServeContent 的 Range 行为标准，适合验证 pad。不选 Python/Node：起服务和依赖管理麻烦。代价是没有目录列表、鉴权、TLS，这些交给 Caddy。

## 21. 平台适配：原生配置

- Android：声明组播权限；实时预览启动后持有 MulticastLock（MethodChannel `tavi/multicast`），不然息屏/后台会被过滤。当前连接成功就启动实时预览，离开采集页不会停，锁会一直持有到 App 退出。
- iOS：需要 `com.apple.developer.networking.multicast` entitlement，现在没申请，所以 iOS 收不到组播；这不是代码问题。
- macOS：App Sandbox 开 network.client/server，本地网络说明已配置。
- Windows：防火墙放行 UDP 7667/7668 入站。
- Linux：多网卡时用 LCM_IFACE 指定。

这块没有替代方案，是平台规则。上线前 iOS 权限必须解决。

## 22. 测试：三层

flutter_test 覆盖协议和页面；Python 发布端 + Dart 接收做 e2e；Go 服务做回放联调。

LCM 的缺片、乱序、过期只能靠单测，真组播只能靠 e2e。只靠手测会漏协议回归。代价是 Python 环境和端口占用要管，CI 还没串起来。

## 23. 日志和监控：本地 counters

接收端统计 + live_check + 进程日志，不接 Sentry/埋点。局域网、隐私、数据不出机器人；现场排查看 datagrams、incomplete、corrupt 比看云端面板快。

代价是没有崩溃聚合，线上问题只能靠用户描述和本地日志。先把 counters 做扎实，真有需要再加。

## 24. 依赖和版本

现在 pubspec 里是 Flutter 本体 + `go_router`，计划加 shared_preferences。

明确不引：dio、http、provider、riverpod、bloc、fl_chart、第三方 LCM/MCAP 包。

版本：Flutter 3.47.7、Dart 3.13.5、Go 1.26。CI 里要锁，不然过两个月构建又对不上。

## 25. 风险清单

- iOS 组播 entitlement 没申请，iOS 现在不可用，得走 Apple 流程。
- Caddy Range 配错（gzip/200）会让回放整包下载，启动自检 206。
- 自研 LCM/MCAP 的长期维护，发布端改协议、加压缩格式都要跟。
- 4K raw 解码会卡，当前只有 1280 降采样。
- AppState 膨胀，新模块必须独立 Controller。
- 无 CI/CD，先锁版本，再串 analyze/test/e2e。
- token 只在内存，重启要重新登录，安全优先（目标方案；当前登录仍是本地 mock，没有 token）。

## 评审想听什么

1. iOS 组播权限谁去推、什么时候能下来。
2. Caddy 的 Range 配置和公网鉴权谁负责。
3. 自研 LCM/MCAP 长期谁接，代码量和测试能不能撑住。

别的我觉得没什么可纠结的。这套东西说白了就是：Flutter 一套 UI，LCM 走 UDP，MCAP 走 Range，业务走 REST+WS，依赖能少则少。
