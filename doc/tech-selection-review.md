# 技术选型评审（草稿）

这份我没按模板写。技术选型真到评审的时候，没人关心“原则一、原则二”，大家只想知道当时为什么选它、踩过什么、后面会不会被坑。下面按这个思路来。

## 先把约束说清楚

平板要同时跑 Android、iOS、macOS、Windows、Linux，不是只做一个安卓 pad。

机器人 60Hz 发四路相机和关节，走局域网 UDP 组播；离线回放要读几 GB 的 MCAP，不能整包下载。

团队不大，没有前端、后端、客户端三套人马。页面是固定原型，不面向公网，不需要 SEO、分享链接、浏览器兼容。也不做 Web：浏览器开不了裸 UDP 组播，实时预览这条链路在 Web 上根本走不通。

后端还没完全好，pad 这边得先把接口契约定下来，不能等。

## 客户端为什么是 Flutter

这个没什么好纠结的。五个平台一套代码，平板上那种固定布局、四宫格相机、自绘图表都好做；dart:io 能直接开 UDP socket，组播不用再写一套原生插件。

也评估过 React Native。UDP/LCM 这种底层能力最后还是要落原生模块，60Hz 图像过 JS 桥我也不放心；桌面端支持不如 Flutter 稳。纯原生更不考虑，五套代码，UI 对齐原型要重做五遍，团队扛不住。

代价也有：包体比原生大，Dart 生态比 JS 小，iOS 的组播 entitlement 还是得走原生配置。但这些是一次性成本，比维护五套 UI 划算。

UI 没上组件库。原型里的间距、圆角、颜色、平板断点都定死了，组件库的默认样式反而要一个个覆盖，最后还是要抽自己的按钮、输入框、弹层。现在 `theme.dart` 加一组 widget，够用。

状态管理也没上 Riverpod/Bloc。一开始考虑过 Riverpod，但团队没人用过，这个 app 说到底就一个状态机：连接、登录、任务、采集、回放。最后用 ChangeNotifier + InheritedNotifier，页面通过 AppScope 取。

代价是 AppState 会胖，什么都想往里塞。早期每来一帧就 notify 整页，四路 60Hz 就是 240 次/秒，顶栏、列表全跟着重画；后来才拆成相机面板只听 LivePreview，顶栏 500ms 刷一次。新模块别再往 AppState 里堆，这个约束得靠 review 守，不然半年后又是一个几千行的 god object。

路由就是 ScreenId 枚举加一个 Shell 做 switch。就七八个固定页面，没有 URL、没有深链、没有浏览器历史，go_router 那套路径参数用不上；采集中还要拦一道“不能乱跳”，自己写反而直接。

图表用 CustomPainter。关节曲线就是折线、坐标、图例，三组、每组最多 240 个点，fl_chart 不是不好，是样式对不上，功能也用不完。

## 实时链路

LCM 不是我们选的，机器人本来就发这个。我们能选的是怎么收。

评估过让机器人加一个 WebSocket 网关，pad 连网关。多一层转发就多一层延迟和故障点，而且 TCP 一丢包全排后面，60Hz 视频等不起。MQTT 更不合适，要布 broker，消息模型也不是给大帧准备的。HTTP 轮询就不用说了。

所以实时只走 LCM UDP 组播，业务数据不走它。

接收放一个长驻 isolate，socket、分帧、两层重组、关节解码都在里面，UI 只拿完整帧。原因很实际：60Hz 四路，分片重组是纯 CPU/IO，放 UI 会挤掉渲染和触摸；一个坏包也不该把页面带崩。之前那版 60Hz 只出 30fps，就是 33ms 合并定时器干的，删掉就正常了。

也想过在 UI 里 async 收。async 不解决 CPU 占用，socket 回调和重组照样跑在 UI 事件循环，帧一大就露馅。每个包 compute 更不现实，isolate 启停比解析还贵。

代价是跨 isolate 要复制字节，26KB×4×60 大概 6.2MB/s，150KB 时 36MB/s。UI 侧每路只留最新帧，解码慢就丢；不做 ack；解码前按 1280 宽降采样。这套组合目前够用，没有再折腾 Transferable 或 buffer pool。

协议解析是自己写的。找过 Dart 的 LCM/MCAP 包，基本只覆盖本地文件和基础 pub/sub；lcm_udpm 长包“通道只在第 0 片”、preview 分片、ROS2 CDR 这些都得自己补。索性按协议重写，四个文件一千多行，边界和测试都在自己手里。

这块的代价是维护。发布端一改格式，pad 就可能解出脏数据；所以协议单测、e2e、corrupt 计数不能省。说实话，这是整个选型里最需要长期盯的一块。

## 回放

第一版是整包下载到临时文件再建索引。几 GB 的包打开要等很久，还占磁盘，后来整个删了。

现在走 MCAP + HTTP Range：只读 footer、summary 和当前 chunk，按需拉。1.7GB 的包能直接打开播，首帧不用等下载。转 MP4 不考虑，关节、多相机同步、多话题都会丢，转码还吃机器人 CPU。

文件服务生产用 Caddy，本地联调用 Go 单文件服务。Caddy 一个二进制搞定 Range、TLS、反代，Go 的 ServeContent 写联调服务几十行。Nginx 也能做，但对“机器人上放个文件”这个场景配置偏重。自己写生产文件服务没必要，TLS、缓存、限速都要补。

CDR 只实现 Image、CompressedImage、JointState、Statistics 四种。回放只用这四类，通用 CDR 包带一堆 schema 和代码生成，真正要改的边界还是得自己看。

图像解码用 Flutter engine：JPEG/PNG 走 instantiateImageCodec，raw 图走 decodeImageFromPixels。不引 OpenCV，包体、构建、NDK 都是成本；640×360 现在够用。代价是 raw bgr8 的像素转换是纯 Dart 循环，4K 会重，只能靠降采样或压缩录制。

## 网络、接口、存储

网络库直接用 dart:io 的 HttpClient 和 WebSocket。dio 不是不好，是它的拦截器、取消、重试在这个场景用不上；Range 和原始流最后还是要落到 HttpClient，多一层封装反而难排查。自己封一个薄 client，统一 header、超时、错误码。

业务接口是 JSON REST + 一条 WebSocket。普通查询/命令走 HTTP，状态、采集、任务变化走 WS。gRPC 要 proto/codegen/HTTP2，这点接口用不上；MQTT 要 broker。代价是没有 schema 强约束，字段靠文档和手写模型，版本兼容要自觉。

本地存储只加 shared_preferences，存上次连接的 IP；token 只放内存。就一个字符串，不值得上 sqlite/Hive；用文件的话 Android/iOS 目录和权限又要 path_provider。之前联调时把持久化去掉了，现在需求要缓存，又得加回来，绕了一圈。

这是目前唯一计划新增的运行时依赖。

## 联调、测试、日志

联调服务用 Go 标准库，server/main.go 一个文件，Range/HEAD/限速/healthz 都有。生产 Caddy，两边行为要一致，不然本地能播、现场不能播。

测试三层：flutter_test 覆盖协议和页面；Python 发布端 + Dart 接收做 e2e；Go 服务做回放联调。LCM 的缺片、乱序、过期只能靠单测，真组播只能靠 e2e。CI 还没串起来，这是个欠账。

日志和监控先用本地 counters + live_check + 进程日志，不接 Sentry/埋点。局域网、隐私、数据不出机器人；现场排查看 datagrams、incomplete、corrupt 比看云端面板快。代价是没有崩溃聚合，线上问题只能靠用户描述和本地日志。

## 依赖和版本

现在 pubspec 里只有 Flutter 本体，计划加 shared_preferences。

明确不引：dio、http、provider、riverpod、bloc、go_router、fl_chart、第三方 LCM/MCAP 包。

服务端 Go 标准库，生产 Caddy。

版本：Flutter 3.47.7、Dart 3.13.5、Go 1.26。CI 里要锁，不然过两个月构建又对不上。

## 风险

- iOS 组播 entitlement 没申请，iOS 现在就是不可用。这个不是代码能解决的，得走 Apple 流程。
- Caddy Range 配错（gzip、返回 200）会让回放整包下载。启动自检 206，错误文案写清楚。
- 自研 LCM/MCAP 的长期维护。发布端改协议、加压缩格式，pad 都要跟。
- 4K raw 解码会卡。现在只有 1280 降采样，真遇到大帧再考虑原生解码。
- AppState 膨胀。新模块必须独立 Controller，不能再往里塞。
- 无 CI/CD。先锁版本，再把 analyze/test/e2e 串起来。
- token 只在内存，重启要重新登录。安全优先，这个可以接受。

这些不是选型错误，是选型的代价。评审时别只看“为什么选”，也看这些代价能不能接受。

## 评审想听什么

1. iOS 组播权限能不能按期解决，谁去推。
2. Caddy 的 Range 配置和公网鉴权谁负责，别到最后没人管。
3. 自研 LCM/MCAP 长期谁接，代码量和测试能不能撑住。

别的我觉得没什么可纠结的。这套东西的核心就是：Flutter 一套 UI，LCM 走 UDP，MCAP 走 Range，业务走 REST+WS，依赖能少则少。
