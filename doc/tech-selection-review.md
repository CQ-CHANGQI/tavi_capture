# 端侧采集平板技术选型评审

这次不聊某个模块，聊整个 app 的技术栈为什么这么选。每个选择我都写了替代方案和代价，评审时主要看有没有明显选错、以及哪些代价现在可以接受。

## 一、约束

- 端侧平板，Android / iOS / macOS / Windows / Linux 都要跑。
- 机器人 60Hz 发四路相机 + 关节，走局域网 UDP 组播。
- 离线回放要读几 GB 的 MCAP，不能整包下载。
- 团队不大，没有专门的前端/后端/客户端三套人马。
- 页面交互是固定原型，不面向公网，不需要 SEO、分享链接、浏览器兼容。
- 后端还没完全就绪，pad 侧要先把接口契约定下来。

## 二、选型原则

1. **能端侧跑，少依赖**。每加一个包，五个平台的构建都要跟着验一遍。
2. **实时链路不用 HTTP**。60Hz 四路视频，TCP 的队头阻塞和重传会把延迟拖死。
3. **大文件不落盘**。几 GB 的包下载完再播，首帧和磁盘都受不了。
4. **业务数据全部接口化**。pad 不藏 mock，也不把业务数据写本地。
5. **不引大框架**。状态管理、路由、图表这些，当前规模用标准库和 Flutter 自带能力就够。

## 三、技术栈总览

- 客户端：Flutter 3.47.7 / Dart 3.13.5。
- UI：Material 基础上自己封主题和组件，尺寸/颜色对齐原型。
- 状态：ChangeNotifier + InheritedNotifier，页面通过 AppScope 取。
- 路由：ScreenId 枚举 + 一个 Shell 做 switch，没有 go_router。
- 网络：dart:io 的 HttpClient 和 WebSocket，没有 dio/http 包。
- 实时：自己实现的 LCM udpm 接收 + isolate 重组。
- 回放：自己实现的 MCAP Reader + HTTP Range + CDR 解码。
- 文件服务：生产 Caddy，本地联调 Go 单文件服务。
- 本地存储：只存上次 IP，计划用 shared_preferences；token 只放内存。
- 测试：flutter_test 单测/组件测试 + Python 组播发布端 + Go Range 服务。
- 后端联调：JSON REST + WebSocket 事件，没有 gRPC/MQTT。

## 四、逐项选型

### 1. 客户端框架：Flutter

- **选择**：Flutter，一套代码跑 Android/iOS/macOS/Windows/Linux。
- **为什么**：五个平台一套 UI；自绘能力强，平板上那种固定布局和相机网格好做；dart:io 能直接开 UDP socket，不需要为了组播再写一套原生插件。
- **不选 React Native**：UDP/LCM 这种底层能力最终还是要写原生模块，60Hz 图像过 JS 桥不合适；桌面端支持也不如 Flutter 稳。
- **不选纯原生**：五套代码，团队扛不住，UI 对齐原型也要重做五遍。
- **代价**：Dart 生态比 JS 小；iOS 的组播 entitlement 还是得走原生配置；包体比纯原生大。
- **结论**：这个项目 Flutter 是合适的，没有换的必要。

### 2. 实时传输：LCM UDP 组播

- **选择**：直接收机器人发的 LCM udpm 组播，不用 WebSocket/MQTT 转发。
- **为什么**：机器人本来就发 LCM；UDP 组播一对多，几台平板可以同时收，不用机器人维护连接；60Hz 下没有 TCP 重传和队头阻塞。
- **不选 WebSocket**：要么机器人加一个 WS 网关，要么 pad 连服务端；多一层转发就多一层延迟和故障点，而且 TCP 一丢包全排后面。
- **不选 MQTT**：要布 broker，消息模型也不适合大帧视频。
- **不选 HTTP 轮询**：60Hz 四路，轮询根本跟不上。
- **代价**：UDP 不可靠、没鉴权、TTL=1 只能同二层网络；丢片就是丢帧。
- **结论**：实时预览只走 LCM，业务数据不走它。

### 3. 线程模型：长驻接收 isolate

- **选择**：socket、LCM 分帧、两层重组、关节解码全放一个长驻 isolate；UI 只收完整帧。
- **为什么**：分片重组是纯 CPU/IO，60Hz 下放 UI 会挤掉渲染和触摸；坏包异常也隔离在后台。
- **不选 UI 里 async**：async 不解决 CPU 占用，socket 回调和重组照样跑在 UI 事件循环。
- **不选每个包 compute**：isolate 启停成本比解析本身还高。
- **代价**：跨 isolate 要复制字节，26KB×4×60 约 6.2MB/s，150KB 时 36MB/s；SendPort 在 UI 卡住时会短暂堆积。
- **缓解**：UI 每路只留最新帧，解码慢就丢；不做 ack；解码前按 1280 宽降采样。
- **结论**：长驻 isolate 是当前最稳的做法，不改成线程池。

### 4. 协议解析：LCM / preview / CDR 自己写

- **选择**：LCM udpm、preview_package_t、joint_batch_t、MCAP、CDR 全部自己实现，纯 Dart。
- **为什么**：Dart 生态里没找到能同时覆盖 lcm_udpm 长包、preview 分片、ROS2 MCAP Range 和 CDR 的现成包；这些协议的核心逻辑不大，自己写能把边界和测试攥在手里。
- **不选第三方 LCM 包**：多数只覆盖基本 pub/sub，长包通道只在第 0 片、preview 类型这些还要自己补。
- **不选第三方 MCAP 包**：本地文件读居多，远程 Range + summary + ROS CDR 要改的地方不少。
- **代价**：协议细节要自己维护，发布端一改格式就可能崩；需要单测和现场抓包。
- **结论**：继续自研，但协议字段、字节边界、错误计数必须有测试兜底。

### 5. 离线视频：MCAP + HTTP Range

- **选择**：机器人用 Caddy 暴露 MCAP，pad 按 chunk 发 Range 请求，边播边读。
- **为什么**：MCAP 是 ROS2 的录制格式，自带 schema、chunk index、时间戳；几 GB 的包只读 footer + summary + 当前 chunk 就能播，首帧快、不占磁盘。
- **不选整包下载**：第一版就是下载到临时文件再建索引，几 GB 的包打开要等很久，还占空间，已经删了。
- **不选转 MP4**：会丢关节、多相机同步和多话题；转码还要吃机器人 CPU。
- **不选本地文件选择器**：当前场景是看机器人上的录制，不是看 U 盘。
- **代价**：服务器必须支持 Range/206、不能 gzip；没有 summary 的包不支持；zstd/lz4 还没接。
- **结论**：MCAP + Range 是唯一能兼顾多话题、seek 和大文件的方案。

### 6. 文件服务：Caddy + Go 联调服务

- **选择**：生产用 Caddy，本地联调用 Go 单文件服务。
- **为什么**：Caddy 一个二进制搞定静态文件、Range、TLS、反代，配置短；Go 的 http.ServeContent 自带 Range/HEAD，写联调服务几十行。
- **不选 Nginx**：能力没问题，但对这个“机器人上放个文件”的场景配置偏重。
- **不选自己写生产文件服务**：TLS、缓存、限速、日志都要自己补，没必要。
- **代价**：Caddy 配错 gzip 会破坏 Range；公网暴露要加签名/鉴权。
- **结论**：Caddy 负责文件，机器人 API 负责鉴权和发 URL。

### 7. 网络库：dart:io，不引 dio/http

- **选择**：HttpClient + WebSocket 直接用 dart:io。
- **为什么**：要控制 Range 头、流式读、超时、连接复用；dart:io 全都有，少一层依赖。
- **不选 dio**：拦截器/取消/重试好用，但 Range 和原始流还是要落到 HttpClient；多一层封装反而难排查。
- **不选 http 包**：同样，流式和 Range 控制不够直接。
- **代价**：重试、超时、鉴权头要自己封一个小 client；错误处理容易写散。
- **结论**：自己封一个薄 API client，统一 header、超时、错误码。

### 8. 状态管理：ChangeNotifier + InheritedNotifier

- **选择**：一个 AppState（ChangeNotifier）+ AppScope（InheritedNotifier），实时/回放各自一个 Controller。
- **为什么**：页面状态集中，原型交互都是“改一个状态、整页跟着变”；不引 provider/riverpod/bloc，少概念、少依赖。
- **不选 Riverpod**：能力强，但这个规模用不上，团队还要学一套 provider/scope 规则。
- **不选 Bloc**：事件/状态样板代码多，页面交互没那么复杂。
- **代价**：AppState 会越写越大，容易出现“什么都往里塞”；全量 notify 会重建过多。
- **缓解**：实时画面用 LivePreview 自己的 Listenable，只重建相机面板；顶栏状态 500ms 节流；回放用 PlaybackController。
- **结论**：当前规模够用，但 AppState 要克制，新模块优先独立 Controller。

### 9. 路由：ScreenId + Shell

- **选择**：ScreenId 枚举 + 一个 Shell 做 switch，页面切换靠 AppState。
- **为什么**：就七八个固定页面，没有 URL、没有深链、没有浏览器历史；模式切换还要拦一道（采集中不能乱跳）。
- **不选 go_router**：路径、参数、重定向这套东西用不上，反而多一层配置。
- **代价**：没有深链、没有系统返回栈；返回逻辑要自己写。
- **结论**：固定页面的平板 app，自建 Shell 更直接。

### 10. UI：自绘组件，不引组件库

- **选择**：Material 基础上自己封按钮、输入、弹层、相机网格、播放条，主题集中在 theme.dart。
- **为什么**：要贴原型，间距、圆角、颜色、平板布局都定死了；组件库的默认样式反而要覆盖。
- **不选 Flutter 默认 Material 直接上**：能做，但每个页面都要写一堆 style，最后还是要抽组件。
- **代价**：组件要自己维护，无障碍/键盘焦点这些容易漏。
- **结论**：当前页面数量可控，自绘更贴设计。

### 11. 图表：CustomPainter，不引 fl_chart

- **选择**：关节曲线用 CustomPainter 自己画。
- **为什么**：只有折线、坐标、图例，三条分组、每組最多 240 个点；需求简单，自己画能完全对齐 UI。
- **不选 fl_chart**：功能多，但样式定制和依赖成本不划算。
- **代价**：坐标轴、缩放、tooltip 要自己写；复杂图表不要硬扛。
- **结论**：当前够用，后面真要交互式图表再换。

### 12. CDR 解码：最小实现

- **选择**：只实现 Image / CompressedImage / JointState / Statistics 四种消息的 CDR 解码。
- **为什么**：回放只用这四类；CDR 的对齐、字符串、数组规则固定，代码量不大。
- **不选通用 CDR/ROS 包**：带一大堆 schema 和代码生成，真正要改的边界还是得自己看。
- **代价**：机器人换消息类型要补代码；字段顺序错了不会报错，只会解出脏数据。
- **结论**：按需实现，给每种消息写单测。

### 13. 本地存储：shared_preferences，只存 IP

- **选择**：加 shared_preferences，只存 last_robot_ip；token 只放内存。
- **为什么**：就一个字符串，五个平台都支持；不值得上 sqlite/Hive。
- **不选文件**：Android/iOS 的目录和权限要自己处理，最后还是要 path_provider。
- **不选 sqlite**：为一行配置引数据库，纯过度设计。
- **代价**：多一个插件；插件初始化和平台构建要验。
- **结论**：这是当前唯一值得加的运行时依赖。

### 14. 联调服务：Go 标准库

- **选择**：server/main.go 用 net/http + http.ServeContent，提供 Range/HEAD/限速/healthz。
- **为什么**：单文件、无依赖、跨平台编译；ServeContent 的 Range 行为标准，适合验证 pad。
- **不选 Python**：起服务和打包依赖麻烦；不选 Node：同样要 node_modules。
- **代价**：没有目录列表、鉴权、TLS；这些交给 Caddy。
- **结论**：联调用 Go，生产用 Caddy，两边行为要一致。

### 15. 业务接口：JSON REST + WebSocket

- **选择**：普通请求走 HTTP JSON，状态/采集/任务变化走一条 WS。
- **为什么**：调试直观，Flutter 自带 HttpClient/WebSocket；LAN 内延迟足够低。
- **不选 gRPC**：要 proto/codegen/HTTP2，平板和机器人这点接口用不上。
- **不选 MQTT**：要 broker，消息语义也不适合请求/响应。
- **代价**：没有 schema 强约束，字段靠文档和手写模型；版本兼容要自觉。
- **结论**：REST 做查询/命令，WS 做事件；所有写操作幂等或带 seq。

### 16. 图像解码：Flutter engine

- **选择**：JPEG/PNG 用 instantiateImageCodec；raw 图用 decodeImageFromPixels。
- **为什么**：不引 OpenCV/原生库，五个平台都能跑；640×360 解码压力可控。
- **不选 OpenCV**：包体、构建、NDK 都是成本，当前不需要做视觉算法。
- **不选原生解码**：每个平台写一遍，收益只在超大帧。
- **代价**：raw bgr8 的像素转换是纯 Dart 循环，4K 会重；只能靠降采样/压缩录制。
- **结论**：当前够用，4K 包再考虑原生或后台解码。

### 17. 测试：单测 + 组件测试 + 脚本 e2e

- **选择**：flutter_test 覆盖协议/页面；Python 发布端 + Dart 接收做 e2e；Go 服务做回放联调。
- **为什么**：LCM 的边界（缺片、乱序、过期）只能靠单测；真组播只能靠 e2e。
- **不选只靠手测**：协议回归很容易漏，现场才发现。
- **代价**：Python 环境和端口占用要管；CI 还没串起来。
- **结论**：保持三层，后面把 e2e 进 CI。

### 18. 日志/监控：本地统计，不接第三方

- **选择**：接收端统计 + live_check + 进程日志，不接 Sentry/埋点。
- **为什么**：局域网、隐私、数据不出机器人；现场排查靠 counters 更快。
- **不选第三方**：要外网、要账号、要脱敏，当前收益低。
- **代价**：没有崩溃聚合；线上问题只能靠用户描述和本地日志。
- **结论**：先把 counters 和日志做扎实，真有需要再加。

## 五、依赖清单

- 运行时：Flutter 本体；**计划新增 shared_preferences**（只存 IP）。
- 开发：flutter_test、flutter_lints。
- 服务端：Go 标准库；生产 Caddy。
- 明确不引：dio、http、provider、riverpod、bloc、go_router、fl_chart、第三方 LCM/MCAP 包。
- 版本：Flutter 3.47.7、Dart 3.13.5、Go 1.26；CI 里要锁版本。

## 六、风险

- **LCM 不可靠**：丢片即丢帧。缓解：允许丢帧、latest-wins、统计 incomplete。
- **iOS 组播 entitlement 未申请**：iOS 目前不可用。缓解：上线前走 Apple 流程，先保证 Android/macOS。
- **自研协议维护**：发布端一改格式就可能崩。缓解：协议单测、e2e、corrupt 计数。
- **Caddy Range 配错**：gzip/200 会让回放整包下载。缓解：启动自检 206，错误文案明确。
- **raw 大帧解码**：4K 会卡。缓解：1280 降采样、优先压缩录制、后续原生解码。
- **AppState 膨胀**：所有页面状态集中，容易互相影响。缓解：实时/回放独立 Controller，新模块不再往 AppState 塞。
- **无 CI/CD**：构建和 e2e 靠本地。缓解：先锁 Flutter/Go 版本，再把 analyze/test/e2e 串到 CI。
- **token 只在内存**：重启要重新登录。可接受，安全优先。

## 七、结论

这套选型的核心是：**Flutter 一套 UI，LCM 走 UDP，MCAP 走 Range，业务走 REST+WS，依赖能少则少**。

我建议按这个方案定，不再引入大框架；唯一要加的运行时依赖是 shared_preferences。评审重点看三件事：

1. iOS 组播权限能不能按期解决。
2. Caddy 的 Range 配置和公网鉴权谁来负责。
3. 自研 LCM/MCAP 的维护成本是否接受（当前代码量和测试是可控的）。

## 八、落地顺序

1. 加 shared_preferences，补 last_robot_ip 缓存。
2. 封 API client（HttpClient + WebSocket），统一 header/超时/错误码。
3. 按接口清单接健康检查、登录、bootstrap、status、tasks、takes。
4. 接采集事件和回放 source，删掉 AppState 里的业务 mock。
5. CI 锁版本，跑 analyze/test/e2e。
