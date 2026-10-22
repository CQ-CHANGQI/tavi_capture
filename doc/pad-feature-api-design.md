# 端侧采集平板：页面交互与接口设计

这份不是纯需求列表，也不是纯接口文档。按用户实际走一遍：每个页面显示什么、点什么、数据从哪来、调哪个接口。当前代码里还是 mock 的地方我会标出来，免得看着像已经通了。

机器人侧统一约定：

- 控制/状态服务：`http://{robotIp}:8080/api/v1`
- 文件服务（Caddy）：`http://{robotIp}:8090`
- 鉴权：`Authorization: Bearer <token>`，设备注册后拿；云端任务另带 `X-Robot-Code`。
- 错误统一 `{code, message, detail}`，pad 只展示 `message`，`detail` 进日志。

## 0. 页面怎么走

```text
启动
 └─ 连接页（健康检查）──失败──> 停在连接页，显示原因
        │ 成功
        ▼
     登录（云端/本地）
        │
        ├─ 工程师 ──> 首页 ──> 查看数据（默认）
        │                 └─> 数据采集
        └─ 操作员 ──> 我的任务 ──> 采集页 ──> 已采页
                                          └─> 回看页
     顶栏/弹层：设置、手动控制、设备状态、异常恢复
```

“默认回看模式”我建议这样落：工程师登录后直接进查看数据；操作员没有查看权限，直接进任务/采集。首页保留，作为模式切换入口。采集页是唯一的“采集模式”，进出时通知机器人切模式。

## 1. 连接页（健康检查）

### 页面

- 机器人 IP 四段输入，默认填上次成功的 IP。
- “保存并连接”按钮；连接中禁用输入。
- 成功：进入登录。
- 失败：红框显示“连不上 {ip}”，下面给原因（超时/拒绝/HTTP 错误码）。

### 交互

1. 启动时读本地缓存 IP。有缓存就自动探测，没有就显示空/默认 IP。
2. 用户改 IP 后点连接：先校验四段 0–255，再发健康检查。
3. 健康检查通过才把 IP 写缓存、置 `connected=true`；失败不覆盖上次成功的 IP。
4. 采集中不能改 IP：设置页的 IP 输入和保存按钮禁用，提示“采集中不能修改连接”。
5. 自动连接失败不弹登录，停在连接页，允许改 IP 重试。

### 接口

`GET /healthz`（不带 `/api/v1`，超时 2s）

```json
{ "ok": true, "robotCode": "TAVI-001", "model": "Tavi-W2", "version": "1.4.2", "serverTime": 1768893097000 }
```

- 只要 `ok=true` 就算连接成功；`robotCode`、`model` 后面展示和任务请求要用。
- 失败：超时、连接拒绝、非 2xx 都算失败。
- 当前代码是探 TCP 8080/8090，没有 `/healthz`。这条要改成真接口。

### 本地缓存

- Key 建议 `last_robot_ip`，存 IP + 上次成功时间。
- 当前实现为了联调把持久化去掉了，按这份需求要加回来。
- 缓存损坏/为空就回默认 IP，不阻塞启动。

## 2. 登录

### 页面

- 云端登录：账号、密码。
- 本地登录：角色（工程师/采集员）+ 本地密码。
- 失败显示错误，成功关闭弹层。

### 交互 / 接口

- 云端：`POST /api/v1/auth/login`，body `{username,password,mode:"cloud"}`，返回：

```json
{ "token": "...", "user": { "id": "u1", "name": "张三", "role": "engineer" }, "expiresAt": 1768896697000 }
```

- 本地：`POST /api/v1/auth/login`，body `{mode:"local", role:"operator", password:"..."}`。本地密码校验在机器人侧，pad 不写死。
- token 只放内存（或安全存储），重启要重新登录；不落普通文件。
- 角色：
  - 工程师：可看本机全部采集条、可改有效/无效、可进设置/手动控制。
  - 采集员：只看自己的任务，不能进查看数据。
- 登录成功后按角色决定落地页：工程师进查看数据，采集员进任务页。
- 顶栏人员按钮可以切换账号；采集中禁止切换。

> 当前代码的账号/密码是 mock（张三/1234 等），要换成上面的接口。

## 3. 首页 / 模式切换

### 页面

- 两张卡：数据采集、查看数据。
- 采集员只看得到数据采集；查看数据置灰。
- 采集中不能切模式。

### 交互

- 点“数据采集”：调 `POST /mode` 切采集模式，启服务，进任务页/采集页。
- 点“查看数据”：调 `POST /mode` 切回看模式，进查看数据。
- 离开采集页：停止采集（如果还在录）→ 调 `POST /mode {mode:"review"}` 或 `idle` → 回首页。
- 切模式期间显示 loading，失败回原页面并提示。

### 接口

`POST /api/v1/mode`

```json
{ "mode": "collect" }   // collect | review | idle
```

返回 `{ok, mode, services:[...]}`。机器人负责启动/停止采集服务，pad 不直接拉进程。

`GET /api/v1/mode` 用来在页面刷新/重连后确认当前模式，避免 pad 以为在采集、机器人已经停了。

“默认回看模式”就是登录后先 `GET /mode`，如果不是 collect 就按回看处理；只有用户主动进采集才切 collect。

## 4. 任务下发与我的任务

### 数据从哪来

- pad 不直接连云端，先向机器人要凭据：

`GET /api/v1/device/credentials` →

```json
{ "robotCode": "TAVI-001", "deviceToken": "...", "cloudBaseUrl": "https://cloud.example.com" }
```

- 机器人拿 `robotCode + deviceToken` 去云端拉本机任务，pad 调机器人：

`GET /api/v1/tasks?robotCode=TAVI-001` →

```json
{
  "items": [
    {
      "id": "t1",
      "name": "compact_shoes",
      "done": 60,
      "total": 100,
      "size": "18.6 GB",
      "state": "采集中",
      "robot": "1号工位",
      "model": "Tavi-W2",
      "brief": ["从满箱中逐件取出鞋盒...", "..."],
      "persons": [{"id":"u1","name":"张三"},{"id":"u2","name":"李四"}]
    }
  ],
  "updatedAt": 1768893097000
}
```

- 有公网时自动更新：pad 在登录后、网络恢复时、以及每 30 秒调一次 `POST /api/v1/tasks/refresh`（机器人去云端拉），成功后 `GET /tasks`。没网就用机器人本地缓存，不报错，只在任务页提示“当前离线，显示本地任务”。
- 任务配置下发：云端 → 机器人用 `POST /api/v1/tasks/config`（机器人侧接口，pad 不直接调）；机器人更新后通过事件 `task.updated` 推给 pad，pad 刷新列表。pad 侧只需要消费事件 + 兜底轮询。

### 页面

- 标题“我的任务”，显示当前机器人、型号、网络状态。
- 操作：切换模式、拉取新任务、下载到本地。
- 任务卡：名称、已采/总数、进度条、机器人、型号、大小、状态、进入任务。
- 空态：本机没有任务 / 当前离线。

### 交互

- 进入任务：调 `POST /collect/select {taskId, personId?}`，成功后进采集页。
- 拉取新任务：`POST /tasks/refresh` + 刷新列表；没网禁用并提示。
- 下载到本地：pad 本地缓存任务配置（brief、persons、total），供离线使用。
- 任务进度以机器人返回的 `done/total` 为准，pad 不自己累加。

## 5. 设备注册、心跳、硬件状态

### 注册

连接成功后：

`POST /api/v1/device/register`

```json
{ "robotCode": "TAVI-001", "padId": "pad-7f3a", "appVersion": "1.0.0" }
```

返回 `{deviceId, token}`，后续请求带 token。

### 心跳

每 5 秒：

`POST /api/v1/device/heartbeat`

```json
{
  "deviceId": "pad-7f3a",
  "mode": "collect",
  "collecting": true,
  "taskId": "t1",
  "userId": "u1",
  "status": "ok",
  "appTime": 1768893097000
}
```

- 断网时本地排队，恢复后补最近一条即可，不补历史。
- 心跳带 `mode/collecting/taskId`，云端和机器人侧都能看到 pad 当前状态。

### 硬件状态

`GET /api/v1/status` →

```json
{
  "robot":  { "ok": true,  "detail": "工控在线" },
  "gripper":{ "ok": true,  "detail": "就绪" },
  "upperArm":{ "ok": true, "detail": "双臂服务运行中" },
  "chassis":{ "ok": false, "detail": "未启动" },
  "vr":     { "ok": true,  "detail": "头显/手柄在线" },
  "camHead":{ "ok": true,  "detail": "30 fps" },
  "camPanorama":{ "ok": true, "detail": "30 fps" },
  "camLeft":{ "ok": true,  "detail": "30 fps" },
  "camRight":{ "ok": true, "detail": "30 fps" },
  "storage":{ "ok": true,  "detail": "剩余 805 GB", "remainGb": 805 }
}
```

- 采集页顶栏和设置-设备状态用同一份数据，1 秒轮询；也可以由机器人通过 `/events` 推。
- 存储阈值：< 50GB 黄色提示，< 20GB 红色并禁止开始采集（和现有逻辑一致）。

## 6. 进程管理

### 接口

- `GET /api/v1/processes` → `[{name,pid,running,startedAt,version}]`
- `POST /api/v1/processes/{name}/start`
- `POST /api/v1/processes/{name}/stop`
- `POST /api/v1/processes/{name}/restart`
- 日志：推荐 WebSocket `ws://.../api/v1/processes/{name}/logs?type=system&range=1h` 流式推送；HTTP 兜底 `GET /api/v1/processes/{name}/logs?type=&range=&limit=200`。
- 日志下载：`GET /api/v1/logs/download?type=&from=&to=` 返回文件流。

日志传输方式我的建议是 WebSocket：进程日志是持续输出，轮询会有延迟和空请求；WebSocket 断线重连后从最后一条序号续传。HTTP 只做“打开设置页先拉最近 200 条”。

### 页面

设置-进程管理：

- 左侧进程列表：名称、运行中/已停止、PID。
- 右侧日志区，操作：启用/停止/重启。
- 采集中/查看数据页只读，按钮禁用。
- 日志页：类型（系统/采集/设备/错误）、时间范围、下载。

## 7. 手动控制

### 接口

- `POST /api/v1/control/connect`：一键连接底盘、双臂，返回各服务状态。
- `POST /api/v1/control/arm/home {pose:"home|pack|standby"}`：回位，执行前 pad 弹确认。
- `POST /api/v1/control/chassis/move`：按住方向键时持续发。

```json
{ "direction": "forward|back|left|right|rotate_left|rotate_right", "speed": 50, "seq": 1024 }
```

- 松开/离开按钮：`POST /api/v1/control/chassis/stop {seq}`。
- 后端要按 `seq` 去重和超时停车（比如 300ms 没新命令自动停），不能只靠 pad 的 pointerup。
- 采集中禁止手动控制；非采集模式才显示。

### 页面

- 手动控制弹层：一键连接、双臂回 home 点、底盘方向键（按住移动、松开停止）、速度 25/50/75/100。
- 回 home 弹确认框，展示目标点位姿，确认后调接口。
- 状态：底盘/双臂未连接时按钮禁用，提示先一键连接。

## 8. 采集页

### 顶部

- 任务下拉：来自任务配置的 `items`。
- 人员下拉：来自当前任务的 `persons`。
- 采集说明：打开 brief 弹层。
- 已采 N 条：进已采页。
- 返回选择模式：停止采集 → 切模式 → 回首页。

### 任务/人员切换

`POST /api/v1/collect/select {taskId, personId}`。机器人确认后返回当前会话；切换成功才更新下拉。采集中禁止切换，按钮禁用并提示。

### 采集数据列表

这是问得最多的分页问题，我的建议：**服务端分页 + 过滤**。

`GET /api/v1/takes?taskId=t1&personId=u1&valid=&page=1&pageSize=20&sort=capturedAt,desc`

返回：

```json
{
  "items": [
    {
      "id": "take-1001",
      "taskId": "t1",
      "taskName": "compact_shoes",
      "personId": "u1",
      "personName": "张三",
      "robot": "1号工位",
      "capturedAt": 1768893097000,
      "durationMs": 34000,
      "sizeBytes": 1288490188,
      "valid": true,
      "status": "saved",
      "filePath": "/data/takes/2026-10-22/take-1001.mcap"
    }
  ],
  "total": 128,
  "page": 1,
  "pageSize": 20
}
```

- 不建议 pad 拉全量再自己分页：采集条会越来越多，内存和首屏时间都扛不住。
- 采集页列表只显示当前任务/人员，2 秒轮询当前页 + `total`；有 `/events` 时用 `take.created` 触发刷新，轮询做兜底。
- 删除/作废后刷新当前页；如果当前页空了且不是第一页，自动回上一页。

### 开始采集按钮

- 空闲：按钮“开始采集”，`POST /api/v1/collect/start {taskId, personId}`，返回 `{collectId, startedAt}`。
- 录制中：按钮“停止并保存”，`POST /api/v1/collect/stop {collectId}`，返回新采集条。
- 作废：`POST /api/v1/collect/{collectId}/drop`，弹确认，不保存、不计数。
- 机器人侧重启/断连后，pad 用 `GET /api/v1/collect/current` 恢复状态：返回 `{collecting:true, collectId, startedAt, taskId, personId}` 或 `null`。
- 采集中禁用来宾切换、任务切换、返回、改 IP。

### 计时和状态

- pad 不自己“开始计时”就完事。以机器人事件为准：
  - `collect.started {collectId, startedAt}`
  - `collect.stopped {collectId, take}`
  - `take.created {take}`
- 收到 `collect.started` 才开始走秒；收到 `collect.stopped` 停表并刷新列表。没有事件时用 `GET /collect/current` 的 `startedAt` 算差值。
- 空闲状态显示“空闲”；录制中显示“录制中”；异常断连显示“连接断开”。

### 条数怎么显示

建议分两个数，别混：

- **机器人计数**：`task.done / task.total`，机器人每保存一条 +1，pad 只展示，不累加。
- **本次会话计数**：pad 从 `collect.started` 开始数 `take.created` 的条数，显示“本次 N 条”，仅用于操作员参考，刷新/重连归零。

这样不会出现 pad 本地加一条、机器人那边失败、两边对不上。

### 实时数据

- 沿用现有 LCM，不走 HTTP。四路相机 + 关节批次，latest-wins，丢帧不排队。
- 相机布局保持：主视角占大格，下面左腕/右腕/全景；缺画显示占位，不拉伸。
- FSM：机器人给状态，pad 只读展示；不要像现在 mock 那样点击切换。
- 关节曲线：采集页当前没有，只有状态判断。我的建议是保留现状，采集时别加曲线，减少 UI 干扰；如果操作员需要看力矩/角度，做一个可折叠的“关节”小面板，默认收起。
- 顶栏芯片：VR、夹爪、双臂、相机、底盘、存储，来自 `/status`。

## 9. 已采页

- 入口：采集页“已采 N 条”。
- 顶部：任务名、已采/总数、还差多少、采集说明。
- Tabs：全部/有效/无效。
- 列表字段：任务名、时间、人员、机器人、时长、大小、有效/无效。
- 操作：回看、标记有效/无效。
- 底部：返回选择模式、继续采集一条。
- 数据：`GET /takes?taskId=&valid=&page=&pageSize=`，过滤和分页同采集页；标记调 `PATCH /takes/{id} {valid:false}`。
- 默认有效：新建的采集条 `valid=true`；只有明确“标记无效”才变 false。
- 继续采集：切回采集页并 `POST /collect/select` 恢复当前任务/人员。

## 10. 查看数据 / 回放

### 列表

- 过滤：任务、人员、有效/无效。
- 分页：服务端分页，`pageSize=20`。
- 字段：任务名、状态、采集时刻、时长、大小、人员、机器人、文件路径。
- 接口：

`GET /api/v1/takes?taskId=&personId=&valid=&page=&pageSize=`

响应同上。`filePath` 是机器人上的相对路径，pad 用它拼 Caddy 地址。

- 默认只显示“有效”；切“全部”才带无效。这个和现有 UI 的 tabs 一致。
- 标记无效：`PATCH /api/v1/takes/{id} {valid:false}`，成功后刷新列表和当前回放状态。

### 回放入口

选中一条 → `GET /api/v1/takes/{id}/source` 返回：

```json
{ "url": "http://192.168.13.4:8090/data/takes/2026-10-22/take-1001.mcap", "sizeBytes": 1288490188 }
```

pad 用这个 URL 走 HTTP Range，不整包下载。Caddy 负责 Range/HEAD/206；文件路径由机器人给，pad 不要自己拼目录规则。

### 回放面板

- 四路相机：主视角大格 + 左/右/全景小格；包里只有两路时，其余显示“无画面”，不硬凑。
- 关节：左臂、右臂、身体三块，分开画；默认“状态”，可切“指令/全部”；没有 command 数据时“指令”禁用或退回状态。
- 最大化：整个回放面板全屏（相机 + 关节 + 播放条），不是单路相机最大化。相机单路全屏是双击相机，另一套交互。
- 播放条：播放/暂停、后退 5 秒、逐帧后退、逐帧前进、前进 5 秒、进度拖拽、时间、倍速 0.5/1/2/4、循环。
- 逐帧按真实帧时间戳走（当前是固定 33ms，待改）。
- seek：按 chunk index 定位，不整包下载；当前没有 chunk 缓存，回退会重新请求。

### 回看页

- 复用同一个回放面板，底部“标记无效/返回列表”。
- 默认有效，标记后立即刷新状态。

## 11. 设置页

- 基本设置：机器人 IP、保存并连接、当前账号/角色、切换账号。
  - 采集中/查看数据页：IP 只读，保存禁用。
  - 修改 IP 重新走健康检查，成功才保存。
- 进程管理：列表、状态、启用/停止/重启、日志。
- 日志查看：类型、时间范围、下载；WebSocket 优先。
- 设备状态：10 个组件，字段同 `/status`。
- 权限：采集员看不到进程/日志/设备状态，或只读。

## 12. 异常和提示

- 设备掉线：弹恢复框，说明哪个设备（VR/相机/机器人），本条采集作废，回首页。
- 服务启动失败：提示“去连接/取消”。
- 回 home 确认：展示目标点位姿，确认后才调接口。
- 作废确认：确认后丢当前采集，不保存不计数。
- 全局 Toast：保存成功、标记成功、网络恢复等，2 秒消失。
- 错误码到文案的映射放在 pad 侧，别把后端 `detail` 直接抛给操作员。

## 13. 接口清单

| 方法 | 路径 | 用途 |
|---|---|---|
| GET | `/healthz` | 健康检查 |
| POST | `/api/v1/auth/login` | 云端/本地登录 |
| GET | `/api/v1/device/credentials` | 机器 token/编码 |
| POST | `/api/v1/device/register` | 设备注册 |
| POST | `/api/v1/device/heartbeat` | 心跳 |
| GET | `/api/v1/status` | 硬件状态 |
| GET | `/api/v1/tasks` | 任务列表/配置 |
| POST | `/api/v1/tasks/refresh` | 触发云端拉取 |
| POST | `/api/v1/tasks/config` | 云端下发配置（机器人侧） |
| GET | `/api/v1/mode` | 当前模式 |
| POST | `/api/v1/mode` | 切模式 |
| GET | `/api/v1/processes` | 进程列表 |
| POST | `/api/v1/processes/{name}/start` | 启动 |
| POST | `/api/v1/processes/{name}/stop` | 停止 |
| POST | `/api/v1/processes/{name}/restart` | 重启 |
| WS | `/api/v1/processes/{name}/logs` | 进程日志流 |
| GET | `/api/v1/logs/download` | 日志下载 |
| POST | `/api/v1/control/connect` | 一键连接 |
| POST | `/api/v1/control/arm/home` | 回位 |
| POST | `/api/v1/control/chassis/move` | 底盘移动 |
| POST | `/api/v1/control/chassis/stop` | 底盘停止 |
| POST | `/api/v1/collect/select` | 切换任务/人员 |
| GET | `/api/v1/collect/current` | 当前采集会话 |
| POST | `/api/v1/collect/start` | 开始采集 |
| POST | `/api/v1/collect/stop` | 停止并保存 |
| POST | `/api/v1/collect/{id}/drop` | 作废 |
| GET | `/api/v1/takes` | 采集条分页/过滤 |
| PATCH | `/api/v1/takes/{id}` | 标记有效/无效 |
| GET | `/api/v1/takes/{id}/source` | 回放地址 |
| WS | `/api/v1/events` | 采集/任务/设备事件 |

事件建议：

```json
{ "type": "collect.started", "collectId": "...", "startedAt": 1768893097000 }
{ "type": "collect.stopped", "collectId": "...", "take": { } }
{ "type": "take.created", "take": { } }
{ "type": "task.updated", "taskId": "t1" }
{ "type": "device.changed", "device": "camRight", "ok": false }
```

WebSocket 断线重连后先 `GET /collect/current` 和 `GET /tasks` 对齐，不能只靠事件。

## 14. 刷新频率建议

| 数据 | 方式 | 频率 |
|---|---|---|
| 健康检查 | HTTP | 连接时一次，之后 10s |
| 硬件状态 | HTTP/事件 | 1s 或事件 |
| 心跳 | HTTP | 5s |
| 任务列表 | HTTP/事件 | 登录、网络恢复、30s |
| 采集条列表 | HTTP | 采集/查看页 2s |
| 进程列表 | HTTP | 设置页 2s |
| 进程日志 | WS | 实时 |
| LCM 画面 | UDP | 60Hz |
| 回放 | HTTP Range | 按播放 |

## 15. 当前实现和这份需求的差距

- 业务数据（任务、采集条、人员、进程、日志、设备状态）还是 mock，没有后端。
- 健康检查现在是探 TCP 端口，不是 `/healthz`。
- IP 持久化之前去掉了，按这份需求要加回来。
- 开始/停止采集、任务/人员切换、标记无效、控制指令都还没接接口，按钮目前是本地状态。
- 回放所有采集条共用一个 `MCAP_URL`，还没有按 `filePath` 取源。
- 默认落地页现在是首页，需求里的“默认回看模式”要按角色改。
- 关节曲线、FSM 现在是 mock/本地状态。
- 日志传输还没定，我建议 WebSocket。

## 16. 几个需要拍板的

1. **分页**：服务端分页（我建议）还是 pad 全量拉取？
2. **条数**：机器人计数 + 本次会话计数，还是只显示一个数？
3. **任务下发**：pad 只拉机器人缓存，还是 pad 也直连云端？
4. **采集页关节曲线**：不加（我建议）还是加可折叠面板？
5. **默认模式**：工程师默认查看数据、操作员默认任务，是否接受？
6. **日志传输**：WebSocket（我建议）还是 HTTP 轮询？
7. **最大化**：整个回放面板全屏（我理解）还是单路相机全屏？
8. **Caddy 鉴权**：裸 URL 还是有签名/过期时间？
9. **健康检查地址**：`/healthz` 在 8080 还是 8090？

先这样，评审的时候对着页面过一遍，把接口字段和状态机定死，后面就好写了。
