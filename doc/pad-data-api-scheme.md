# 端侧采集平板：数据与接口方案（定稿）

这版不再留“待确认”。下面每个决定我都按最稳妥的方案定了，理由写在旁边；后面接后端按这个来，pad 上不再留任何业务 mock。

先说三条底线：

1. **pad 不存业务数据**。任务、采集条、人员、状态、进程、日志全部有接口。pad 本地只存“上次连接的 IP”和内存里的登录 token。
2. **机器人本地 API 是主数据源**。云端只负责任务目录，pad 在线时可以用机器人发的临时凭据去拉，离线就退回机器人缓存。
3. **LCM 只负责实时画面/关节，Caddy 只负责文件**。业务数据不走这两条。

## 1. 四条数据通道

| 通道 | 地址 | 负责什么 |
|---|---|---|
| 本地 HTTP | `http://{robotIp}:8080/api/v1` | 登录、状态、任务、采集、采集条、进程、控制、回放地址 |
| 本地 WebSocket | `ws://{robotIp}:8080/api/v1/ws` | 采集/任务/状态/设备/模式事件 |
| 日志 WebSocket | `ws://{robotIp}:8080/api/v1/ws/logs` | 进程/系统日志实时流 |
| LCM 组播 | `239.255.76.67:7667` / `...68:7668` | 实时相机、关节 |
| Caddy | `http://{robotIp}:8090` | MCAP 文件，HTTP Range 按需读 |
| 云端 | `https://{cloudBaseUrl}/api/v1` | 任务目录（pad 在线时） |

健康检查单独：`GET http://{robotIp}:8080/healthz`，不带 `/api/v1`，不鉴权，2 秒超时。

所有接口统一：

```text
Authorization: Bearer <pad token>
X-Robot-Code: <robotCode>
X-Device-Id: <deviceId>
Content-Type: application/json
```

错误统一：

```json
{ "code": "COLLECT_BUSY", "message": "正在采集中，不能切换任务", "detail": "collectId=..." }
```

pad 只展示客户端映射后的中文，`detail` 写本地日志。

## 2. 状态机（决定页面行为）

### 连接

```text
idle → probing → connected → (登录) → ready
              ↘ failed（留在连接页）
```

- 启动读本地 `last_robot_ip`，有就自动探测。
- 探测成功才写缓存、才允许下一步；失败不覆盖旧 IP。
- 采集中（`collecting=true`）IP 只读。

### 会话

```text
loggedOut → loggedIn(role, token, permissions) → expired(401) → 重新登录
```

- token 只放内存，重启重新登录；不落盘。
- 角色/权限以登录响应为准，pad 不自己判断“工程师能看全部”。

### 模式

```text
idle → review（默认） → collect（进采集页） → review/idle（退出）
```

- pad 只通过 `POST /mode` 请求切换，实际服务启停由机器人做。
- 采集中禁止切模式；`GET /mode` 和 `GET /collect/current` 用于重连后对齐。
- 工程师登录后默认 `review` 并进查看数据；操作员默认进任务/采集。

### 采集

```text
idle → starting → recording → saving → idle
                        ↘ aborted（设备异常/机器人重启）
```

- 以机器人事件为准：`collect.started` / `collect.stopped` / `collect.aborted`。
- `GET /collect/current` 是唯一恢复入口；pad 不自己猜是否在录。
- 计时用 `startedAt` + 服务器时间偏移；断线重连后重新算，不累加本地时间。

## 3. 接口总表

### 健康 / 登录 / 设备

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/healthz` | 存活、robotCode、model、version、serverTime、bootId |
| POST | `/api/v1/auth/login` | 云端/本地登录，返回 token、user、permissions |
| POST | `/api/v1/auth/logout` | 注销 token |
| POST | `/api/v1/device/register` | pad 注册，返回 deviceId |
| POST | `/api/v1/device/heartbeat` | 5 秒一次，带 mode/collect/task/user |
| GET | `/api/v1/device/credentials` | 返回 robotCode、cloudBaseUrl、短期 cloudToken |
| GET | `/api/v1/bootstrap` | 首屏/重连聚合：robot、mode、status、collect |

登录请求：

```json
{ "mode": "cloud", "username": "zhangsan", "password": "..." }
{ "mode": "local", "role": "operator", "password": "..." }
```

登录响应：

```json
{
  "token": "...",
  "expiresAt": 1768896697000,
  "user": { "id": "u1", "name": "张三", "role": "engineer" },
  "permissions": ["collect", "viewAllTakes", "manageProcess", "control"]
}
```

`GET /device/credentials`：

```json
{
  "robotCode": "TAVI-001",
  "cloudBaseUrl": "https://cloud.example.com",
  "cloudToken": "short-lived...",
  "expiresAt": 1768893697000
}
```

pad 只在拉任务目录时用它直连云端；拉不到就用 `GET /tasks` 的机器人缓存。

### 状态 / 模式 / 任务

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/v1/status` | 硬件状态、FSM、网络、存储 |
| GET | `/api/v1/mode` | 当前模式 |
| POST | `/api/v1/mode` | `{mode: collect|review|idle}` |
| GET | `/api/v1/tasks` | 机器人缓存的任务列表 |
| GET | `/api/v1/tasks/{id}` | 单个任务详情（brief、persons、进度） |
| POST | `/api/v1/tasks/refresh` | 机器人去云端同步一次 |
| POST | `/api/v1/tasks/{id}/ensure` | 确保机器人有该任务配置，没有再下载 |
| POST | `/api/v1/tasks/config` | 云端→机器人下发配置，pad 不调 |
| GET | `https://{cloudBaseUrl}/api/v1/tasks` | pad 在线拉任务目录，带 cloudToken |

任务模型：

```json
{
  "id": "t1",
  "name": "compact_shoes",
  "done": 60,
  "total": 100,
  "size": "18.6 GB",
  "state": "采集中",
  "robotId": "r1",
  "robotName": "1号工位",
  "model": "Tavi-W2",
  "brief": ["从满箱中逐件取出鞋盒...", "..."],
  "persons": [
    { "id": "u1", "name": "张三" },
    { "id": "u2", "name": "李四" }
  ],
  "updatedAt": 1768893097000
}
```

pad 在线拉任务：`GET https://{cloudBaseUrl}/api/v1/tasks?robotCode=TAVI-001`，`Authorization: Bearer <cloudToken>`。失败/离线 → `GET /tasks`，任务页标“当前离线”。

### 采集

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/api/v1/collect/select` | 切任务/人员，`{taskId, personId}` |
| GET | `/api/v1/collect/current` | 当前会话或 `{collecting:false}` |
| POST | `/api/v1/collect/start` | `{taskId, personId}`，返回 collectId/startedAt |
| POST | `/api/v1/collect/stop` | `{collectId}`，返回 take 和 task 进度 |
| POST | `/api/v1/collect/{id}/drop` | 作废，不保存不计数 |

当前会话：

```json
{
  "collecting": true,
  "collectId": "c-1001",
  "taskId": "t1",
  "personId": "u1",
  "startedAt": 1768893097000,
  "lastTake": { "id": "take-1000", "valid": true }
}
```

### 采集条

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/v1/takes` | 分页/过滤，服务端分页 |
| GET | `/api/v1/takes/{id}` | 单条详情 |
| PATCH | `/api/v1/takes/{id}` | `{valid:false}` 标记无效 |
| GET | `/api/v1/takes/{id}/source` | 返回 Caddy 回放 URL |

查询参数：

```text
taskId, personId, valid, status, page, pageSize, sort=capturedAt:desc
```

响应：

```json
{
  "items": [
    {
      "id": "take-1001",
      "taskId": "t1",
      "taskName": "compact_shoes",
      "personId": "u1",
      "personName": "张三",
      "robotName": "1号工位",
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

`status` 只取 `saved` / `recording` / `dropped`；有效/无效看 `valid`。默认有效。

回放地址：

```json
{
  "url": "http://192.168.13.4:8090/data/takes/2026-10-22/take-1001.mcap",
  "sizeBytes": 1288490188,
  "durationMs": 33480
}
```

pad 用这个 URL 走 Range，不整包下载。

### 进程 / 日志

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/v1/processes` | `{name,pid,running,startedAt,version}` |
| POST | `/api/v1/processes/{name}/start` | 启动 |
| POST | `/api/v1/processes/{name}/stop` | 停止 |
| POST | `/api/v1/processes/{name}/restart` | 重启 |
| GET | `/api/v1/logs` | `type/range/limit/cursor` 历史日志 |
| GET | `/api/v1/logs/download` | 下载日志文件 |
| WS | `/api/v1/ws/logs` | 实时日志，订阅 `{name,type,range}` |

日志类型固定：`system` / `collect` / `device` / `error`。日志条目：

```json
{ "ts": 1768893097000, "level": "WARN", "source": "camRight", "message": "帧率偏低 28fps" }
```

### 手动控制

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/v1/control/state` | 底盘/双臂连接状态、当前点位 |
| POST | `/api/v1/control/connect` | 一键连接 |
| POST | `/api/v1/control/arm/home` | `{pose:"home|pack|standby", seq}` |
| POST | `/api/v1/control/chassis/move` | `{direction,speed,seq}`，按住时 10Hz |
| POST | `/api/v1/control/chassis/stop` | `{seq}` |

- 方向：`forward/back/left/right/rotate_left/rotate_right`。
- 后端按 `seq` 去重，300ms 没新命令自动停；不能只靠 pointerup。
- 采集中返回 `409 COLLECT_BUSY`。

### WebSocket 事件

`/api/v1/ws?lastSeq=123`，重连带最后序号；服务端保留 5 分钟事件，超了让 pad 调 `/bootstrap` 全量对齐。

```json
{ "type": "collect.started", "seq": 124, "ts": 1768893097000, "data": { } }
```

事件类型：

`hello`、`mode.changed`、`status.updated`、`fsm.changed`、`collect.started`、`collect.stopped`、`collect.aborted`、`take.created`、`take.updated`、`task.updated`、`device.changed`、`process.changed`、`control.state`、`error`。

## 4. 每个页面的数据映射

### 连接页

| 页面元素/交互 | 数据来源 |
|---|---|
| 默认 IP | 本地 `last_robot_ip`（唯一允许的本地业务缓存） |
| 连接结果 | `GET /healthz` |
| 机器人型号/版本 | `/healthz` |
| 错误提示 | health 失败类型 + 客户端映射 |
| 保存 IP | 健康检查成功后才写本地 |

### 登录

| 元素 | 来源 |
|---|---|
| 云端/本地 tab | 本地 UI 状态 |
| 账号/密码 | 用户输入 |
| 角色/权限 | `POST /auth/login` |
| 默认落地页 | 登录响应 role/permissions + 本地规则 |
| 当前账号 | 登录响应 |

### 首页

| 元素 | 来源 |
|---|---|
| 两张模式卡 | 静态 UI |
| 查看数据是否可用 | `permissions` 含 `viewAllTakes` |
| 当前模式 | `GET /mode` / `mode.changed` |
| 是否采集中 | `GET /collect/current` / events |
| 切换 loading/失败 | `POST /mode` 响应 |

### 我的任务

| 元素 | 来源 |
|---|---|
| 任务列表 | 云端 `GET /tasks`（在线）或机器人 `GET /tasks` |
| 当前机器人/型号 | `/healthz` + `/status` |
| 网络状态 | `/status.network` |
| 已采/总数/进度 | task.done/total |
| 任务状态 | task.state |
| 采集说明 | task.brief |
| 人员下拉 | task.persons |
| 拉取新任务 | `POST /tasks/refresh` + 事件 `task.updated` |
| 下载任务 | `POST /tasks/{id}/ensure` |
| 进入任务 | `POST /collect/select` 后跳采集页 |

### 采集页

| 元素 | 来源 |
|---|---|
| 任务下拉 | `GET /tasks` |
| 人员下拉 | 当前 task.persons |
| 采集说明 | task.brief |
| 已采 N 条 | `GET /takes?taskId&personId&pageSize=1` 的 total |
| 本次 N 条 | 本次会话内 `take.created` 计数 |
| 进度 done/total | task.done/total（stop 后刷新） |
| 采集条列表 | `GET /takes` 当前页，2s + `take.created` |
| 开始/停止按钮 | `POST /collect/start` / `stop` |
| 当前会话/计时 | `GET /collect/current` + `collect.started` |
| 录制状态/上一条 | `current` + `collect.stopped` / `take.created` |
| FSM | `/status.fsm` / `fsm.changed`，只读 |
| 顶栏设备芯片 | `/status` |
| 存储 | `/status.storage` |
| 四路画面 | LCM；主视角大格 + 下排左腕/右腕/全景 |
| 关节状态 | LCM（采集页不画曲线） |
| 设备异常 | `collect.aborted` / `device.changed` |

### 已采页

| 元素 | 来源 |
|---|---|
| 任务/进度 | `GET /tasks/{id}` 或本地选中的 task |
| 全部/有效/无效 | `GET /takes?taskId&valid=` |
| 列表字段 | take 模型 |
| 回看 | `GET /takes/{id}/source` 后进回看页 |
| 标记有效/无效 | `PATCH /takes/{id}` |
| 继续采集 | `POST /collect/select` 后回采集页 |

### 查看数据 / 回放

| 元素 | 来源 |
|---|---|
| 任务/人员筛选 | `GET /tasks`、`task.persons` |
| 有效/无效 tab | `GET /takes?valid=` |
| 列表字段 | take 模型 |
| 分页 | `GET /takes?page&pageSize` |
| 当前条目 | 列表选中 |
| 四路画面 | `GET /takes/{id}/source` + Caddy Range |
| 关节曲线 | MCAP 里的 JointState/Statistics |
| 播放/倍速/循环/seek | 本地播放器，数据源同上 |
| 标记无效 | `PATCH /takes/{id}` |
| 最大化 | 本地 UI 状态 |

### 回放交互细节（定死）

- 相机布局：主视角占大格，左腕/右腕/全景在下排；包里缺哪路就显示“无画面”，不硬凑。
- 最大化：**整个回放面板全屏**（相机 + 关节 + 播放条），不是单路相机。单路相机全屏是双击相机，另一套交互。
- 关节：左臂/右臂/身体分开画，默认“状态”，可切“指令/全部”；没有 command 数据时“指令”置灰。
- 播放条：播放/暂停、后退 5 秒、逐帧后退、逐帧前进、前进 5 秒、进度拖拽、倍速 0.5/1/2/4、循环。
- 逐帧按图像通道的真实 `log_time` 找下一帧，不是固定 33ms（当前代码是 33ms，要改）。
- 查看数据默认 tab 是“有效”，切“全部”才看无效；采集条新建默认有效。

存储阈值：`< 50GB` 黄色提示，`< 20GB` 红色并禁止开始采集；判断在 pad，数据来自 `/status.storage`。

### 设置

| 元素 | 来源 |
|---|---|
| 机器人 IP | 本地缓存 + 用户输入 |
| 当前账号/角色 | 登录响应 |
| 进程列表 | `GET /processes` |
| 进程操作 | `POST /processes/{name}/...` |
| 日志 | `GET /logs` / `WS /ws/logs` / 下载 |
| 设备状态 | `/status` |
| 存储/网络 | `/status.storage`、`/status.network` |
| 只读规则 | 客户端根据 `mode=collect` 和当前页面推导 |

### 手动控制

| 元素 | 来源 |
|---|---|
| 底盘/双臂状态 | `GET /control/state` |
| 一键连接 | `POST /control/connect` |
| 回 home | `POST /control/arm/home` + 确认框 |
| 方向键 | `POST /control/chassis/move` 持续发 |
| 松开停止 | `POST /control/chassis/stop` |
| 速度档位 | 本地 UI，值随 move 发 |

### 异常/Toast

| 元素 | 来源 |
|---|---|
| 设备掉线 | `device.changed` / `collect.aborted` |
| 服务启动失败 | `POST /mode` / `control/connect` 响应 |
| 回 home 确认 | 本地弹层 + `/control/state` 位姿 |
| 作废确认 | 本地弹层 + `POST /collect/{id}/drop` |
| 保存/标记成功 | 接口响应 + `take.created/updated` |
| 错误文案 | 服务端 code → 客户端映射 |

## 5. 刷新与降级

| 数据 | 首选 | 兜底 | 频率 |
|---|---|---|---|
| 健康 | `GET /healthz` | — | 连接时 + 10s |
| 状态/FSM | WS `status.updated` | `GET /status` | 1s |
| 心跳 | `POST /device/heartbeat` | 本地排队一条 | 5s |
| 任务 | 云端 `GET /tasks` | 机器人 `GET /tasks` | 登录/上线/30s |
| 当前采集 | WS 事件 | `GET /collect/current` | 重连时 |
| 采集条 | WS `take.*` | `GET /takes` | 2s（页面可见时） |
| 进程 | WS `process.changed` | `GET /processes` | 2s（设置页） |
| 日志 | `WS /ws/logs` | `GET /logs` | 实时 / 打开时 200 条 |
| 回放 | Caddy Range | — | 本地播放 |
| 实时画面 | LCM | — | 持续 |

离线：

- 没公网：任务用机器人缓存；采集/回放/状态/控制都在局域网，不受影响。
- 连不上机器人：回连接页，所有业务页清空，不展示旧数据。
- WS 断开：按 1s、2s、5s 退避重连；重连先 `/bootstrap` 对齐，再补事件。
- 机器人重启（`bootId` 变化）：重新 bootstrap，当前采集以 `/collect/current` 为准。

## 6. 权限和只读

| 能力 | 工程师 | 采集员 | 本地登录 |
|---|---|---|---|
| 采集 | 是 | 是 | 是 |
| 查看全部采集条 | 是 | 否（只看自己的任务） | 是 |
| 标记有效/无效 | 是 | 否 | 是 |
| 进程/日志/设备状态 | 是 | 否 | 是 |
| 手动控制 | 是 | 否 | 是 |

服务端按 token 再校验一遍，pad 的隐藏只是体验。

只读规则（客户端推导，不单独接口）：

- `mode=collect` 或 `collecting=true`：IP、任务、人员、返回、切换账号、模式切换禁用。
- 查看数据/回看页：设置里的 IP 只读。

## 7. 错误码

| code | HTTP | 场景 | pad 行为 |
|---|---|---|---|
| `UNAUTHORIZED` | 401 | token 过期 | 重新登录 |
| `FORBIDDEN` | 403 | 权限不足 | 提示并返回 |
| `NOT_FOUND` | 404 | 任务/采集条不存在 | 刷新列表 |
| `COLLECT_BUSY` | 409 | 采集中切任务/模式 | 提示 |
| `DEVICE_NOT_READY` | 409 | 设备未连接 | 弹恢复框 |
| `STORAGE_LOW` | 409 | 存储 < 20GB | 禁止开始采集 |
| `MODE_INVALID` | 409 | 当前模式不允许 | 刷新 mode |
| `OFFLINE` | 503 | 云端不可达 | 用本地缓存 |
| `TIMEOUT` | 504 | 控制/模式超时 | 提示重试 |
| `INTERNAL` | 500 | 机器人内部错误 | 提示 + detail 日志 |

## 8. 安全

- 局域网 HTTP 可用；公网必须 HTTPS。
- pad token 短有效期（8 小时），只放内存；401 重新登录。
- `cloudToken` 只用于任务目录，10 分钟过期，不给文件/控制权限。
- Caddy 文件地址默认只在内网；如果暴露公网，`/takes/{id}/source` 返回 5 分钟签名 URL，Caddy 用 forward_auth 回调机器人校验。
- 文件路径只允许机器人返回的 `filePath`，pad 不做字符串拼接。
- 控制命令带 `seq` 和超时停车，防重复/丢包。
- 心跳只上报必要字段，不带画面和个人敏感信息；机器人汇总后转发云端。

## 9. 要删掉的 mock

| 现在 mock 的东西 | 换成 |
|---|---|
| 任务列表、brief、人员 | `/tasks` / 云端 |
| 采集条、有效状态 | `/takes` |
| 登录账号/密码 | `/auth/login` |
| 设备状态、存储 | `/status` |
| 进程、日志 | `/processes`、`/logs`、`/ws/logs` |
| 采集计时、录制状态 | `/collect/*` + 事件 |
| FSM | `/status.fsm` |
| 手动控制 | `/control/*` |
| 回放 URL | `/takes/{id}/source` |
| 健康检查探端口 | `/healthz` |
| 顶栏/首页的在线状态 | `/status.network` |

保留的本地数据只有一个：`last_robot_ip`。token 只在内存。

## 10. 实施顺序

1. 机器人侧先出 `/healthz`、`/auth/login`、`/bootstrap`、`/status`、`/tasks`、`/takes` 六个接口，够把页面点亮。
2. 接 `/collect/*` 和事件 WS，替换采集页 mock 计时/状态。
3. 接 `/takes/{id}/source` + Caddy Range，替换统一 `MCAP_URL`。
4. 接进程/日志、控制、心跳、凭据。
5. 删 mock，补 `last_robot_ip` 缓存和 WS 重连对齐。

先按这个做，接口字段有异议在评审时改字段名就行，数据来源不再动。
