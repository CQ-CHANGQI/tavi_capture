# 端侧采集平板 · 机器人接口清单

> 本文只列要实现的接口和必要说明；未实现、未定功能统一放在 TODO，不写成正式接口。
>
> 机器人本地 API、云端任务接口、WebSocket、文件服务四方对接。

## 1. 通用约定

### 1.1 地址

```text
机器人 API：http://{robotIp}:{apiPort}/api/v1
WebSocket： ws://{robotIp}:{apiPort}/api/v1/ws
文件服务：  http://{robotIp}:{filePort}{filePath}
云端：      {cloudBaseUrl}/tasks
```

- `apiPort` 默认 8080。
- `filePort` 默认 8090。
- `cloudBaseUrl` 已经到 `/api/v1`，pad 只追加 `/tasks`。

### 1.2 响应包

机器人 API 和云端 API 的 HTTP 状态码统一返回 200，业务结果看 `code`。文件服务除外，按 Range 正常返回 200/206。

成功：

```json
{
  "code": 200,
  "msg": "success",
  "data": {}
}
```

失败：

```json
{
  "code": 500,
  "msg": "具体错误内容",
  "data": null
}
```

约定：

- 成功 `code = 200`，`msg = "success"`。
- 失败 `code = 500`，`msg` 给 pad 展示。
- 失败时 `data = null`。
- `data` 可以是对象、数组、`null` 或 `true`。
- 动作成功统一 `data: true`。
- 所有响应 `Content-Type: application/json`。
- 不允许返回非 JSON。
- 不用 HTTP 4xx/5xx 表达业务错误。

### 1.3 时间、单位、命名

- 时间戳统一毫秒，例如 `1768893097000`。
- 文件大小统一字节，例如 `1288490188`。
- 时长统一毫秒，例如 `34000`。
- 任务名称 `taskName` 是任务唯一标识，没有 `taskId`。
- 采集条名称 `takeName` 是采集条唯一标识，没有 `takeId`。
- 人员用 `personName`，没有 `personId`。
- 采集条状态：

```text
recording / valid / invalid
```

列表接口只返回已保存的 `valid / invalid`，不返回 `recording`。

### 1.4 超时和重试

- HTTP 超时 5 秒。
- HTTP 失败不自动重试。
- WebSocket 连接超时 5 秒。
- WebSocket 断开后重连间隔 1、2、3、4、5 秒，共 5 次。
- 重连成功不额外立即刷新 mode/current/status；status/storage 按原 2 秒周期恢复。
- 重连 5 次失败，pad 回连接页。

### 1.5 鉴权

机器人本地接口无鉴权，不校验 token 和设备号。

---

## 2. 配置文件

### 2.1 文件

- `assets/config.json`：出厂默认，只读。
- App 私有目录 `config.json`：运行时配置，pad 自己读写。
- 用户不手动编辑。

### 2.2 字段

```json
{
  "robotIp": "192.168.13.4",
  "cloudBaseUrl": "https://cloud.example.com/api/v1",
  "apiPort": 8080,
  "filePort": 8090,
  "lcm": {
    "cameraGroup": "239.255.76.67",
    "cameraPort": 7667,
    "jointGroup": "239.255.76.68",
    "jointPort": 7668
  }
}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `robotIp` | string | 机器人 IP，不能为空 |
| `cloudBaseUrl` | string | 云端 API 根地址，包含 `/api/v1` |
| `apiPort` | int | 机器人 HTTP/WS 端口，默认 8080 |
| `filePort` | int | 文件服务端口，默认 8090 |
| `lcm.cameraGroup` | string | 相机组播地址 |
| `lcm.cameraPort` | int | 相机组播端口 |
| `lcm.jointGroup` | string | 关节组播地址 |
| `lcm.jointPort` | int | 关节组播端口 |

- 启动先读 App 私有配置；不存在或损坏时读 `assets/config.json`。
- 连接成功后 pad 把 `robotIp` 写回私有配置。
- 连接失败不覆盖旧 IP。
- 设置页改 IP 只写配置文件，下次启动生效；当前连接不变。

LCM 通道固定，直接使用：

```text
/preview/cameras/cam_head
/preview/cameras/cam_left
/preview/cameras/cam_right
/preview/cameras/cam_chest
/preview/joint_batch
```

---

## 3. 页面、模式和启动

### 3.1 页面和模式

| 页面 | 说明 |
|---|---|
| 连接页 | 填 IP、连接机器人、完成启动流程 |
| 采集页 | 选择任务/人员、看实时画面、开始/停止采集、查看当前任务采集条 |
| 查看数据页 | 查看全部采集条、详情、内嵌回放、修改有效/无效 |
| 手动模式页 | 双臂回位、底盘方向控制 |

设置是弹层。只有三个模式，没有 `idle`。

- 顶部三个模式按钮：数据采集 / 查看数据 / 手动模式。
- 未连接时点击模式按钮只提示“请先连接机器人”。
- 采集中模式按钮置灰，不能切换。
- 三个模式页不响应系统返回键。

| mode | 页面 |
|---|---|
| `collect` | 采集页 |
| `review` | 查看数据页 |
| `control` | 手动模式页 |

机器人启动后的默认模式是 `review`。

### 3.2 启动顺序

```text
WS 连接
  → POST /api/v1/cloud/token
      ├─ 失败：停在连接页
      └─ 成功：
          → GET {cloudBaseUrl}/tasks
              ├─ 成功：POST /api/v1/tasks/sync
              │        ├─ 失败：停在连接页
              │        └─ 成功：继续
              └─ 失败：跳过同步
          → GET /api/v1/tasks
              ├─ 失败：停在连接页
              └─ 成功：
                  → GET /api/v1/mode
                      ├─ 失败：停在连接页
                      └─ 成功：进入对应模式
```

- 云端任务失败不阻断连接，继续用机器人任务。
- 不管云端任务成功还是失败，最后都必须调用 `GET /tasks`。
- token 失败阻断连接。
- 同步失败阻断连接。
- 机器人任务失败阻断连接。
- 模式失败阻断连接。
- 任务同步在每次从连接页成功连接时执行一次；同一连接的 WS 自动重连不再同步。
- 模式为 `collect` 时，进入采集页后再请求 `GET /collect/current`。
- App 启动不自动连接；用户点“保存并连接”才走上面的流程。
- 连接页从配置读取 IP；连接过程中依次显示：正在连接 WS、获取 token、同步任务、获取任务、获取模式。
- 连接成功后才写回 `robotIp`；连接失败不覆盖旧 IP。
- 各阶段失败文案：连接机器人失败、获取云端 token 失败、给机器人同步任务失败、获取任务失败、获取模式失败。

### 3.3 异常恢复

设备异常恢复弹层点“确定”后：

1. `GET /api/v1/mode`
2. 按模式进入对应页面
3. 如果是 `collect`，再 `GET /api/v1/collect/current`

模式查询失败时留在当前页，不清空本地数据。

### 3.4 录制中 WS 断开

- 保持本地“录制中”状态，计时继续。
- 不自动停止、不作废。
- 重连成功后继续计时。
- 重连 5 次失败回连接页，下一次连接后通过 `GET /collect/current` 恢复。

---

## 4. 接口总表

机器人本地：

| 方法 | 路径 | 用途 |
|---|---|---|
| `POST` | `/api/v1/cloud/token` | 获取云端任务 token |
| `GET` | `/api/v1/tasks` | 获取机器人任务 |
| `POST` | `/api/v1/tasks/sync` | 全量同步任务 |
| `GET` | `/api/v1/mode` | 查询模式 |
| `POST` | `/api/v1/mode` | 切换模式 |
| `GET` | `/api/v1/status` | 硬件状态 + FSM |
| `GET` | `/api/v1/storage` | 剩余存储 |
| `GET` | `/api/v1/collect/current` | 当前采集 |
| `POST` | `/api/v1/collect/start` | 开始采集 |
| `POST` | `/api/v1/collect/stop` | 结束采集 |
| `GET` | `/api/v1/takes` | 采集条列表 |
| `POST` | `/api/v1/takes/status` | 修改采集条状态 |
| `GET` | `/api/v1/processes` | 进程列表 |
| `POST` | `/api/v1/processes/action` | 启动/停止/重启进程 |

云端：

| 方法 | 路径 | 用途 |
|---|---|---|
| `GET` | `{cloudBaseUrl}/tasks` | 云端任务 |

其他：

| 协议 | 地址 | 用途 |
|---|---|---|
| WS | `/api/v1/ws` | 连接判断 |
| HTTP | `{filePort}{filePath}` | MCAP Range 回放 |

### 4.1 页面调用

| 页面 | 请求 |
|---|---|
| 连接页 | WS、`POST /cloud/token`、云端 `GET /tasks`、`POST /tasks/sync`、`GET /tasks`、`GET /mode` |
| 采集页 | 进入时 `GET /tasks`、`GET /takes`、`GET /collect/current`；操作时 `POST /collect/start`、`POST /collect/stop`、`POST /takes/status`；`GET /status`、`GET /storage` 2 秒轮询 |
| 查看数据页 | 进入时 `GET /tasks`、`GET /takes`；`POST /takes/status`；按 `filePath` 请求 MCAP；`GET /status`、`GET /storage` 2 秒轮询 |
| 手动模式页 | `GET /status`、`GET /storage` 2 秒轮询；`GET /processes` 2 秒轮询判断服务 |
| 设置弹层 | `GET /status`、`GET /storage`、`GET /processes` 2 秒轮询；`POST /processes/action`；IP 保存只写本地配置 |

采集页进入时如果 `collect/current` 非空，恢复当前采集，不再调用 start。

### 4.2 采集页行为

- 进入默认“全部任务 + 人员空”，开始按钮禁用。
- 任务列表为空时显示空任务，不跳任务页，开始按钮禁用。
- 选中任务后，人员下拉才出现，人员来自任务 `persons`，没有默认值。
- 有 `collect/current` 时，任务/人员锁定为当前值，任务/人员下拉禁用。
- 采集条列表默认显示全部任务；选中任务后只显示该任务；按开始时间降序，最新一条高亮。
- 列表显示时间、大小、状态；不显示时长。
- 已采集 `N` 按当前任务采集条数量计算，`valid/invalid` 都算，不包含 `recording`。
- `total` 来自任务。
- FSM 从 `/status` 的 `fsm` 项读取，只显示，不可点击；存储只显示，不拦截采集。
- 开始成功后显示“停止并保存”；停止成功后重新拉取采集条。
- 作废按 `stop + takes/status(invalid) + takes` 三步执行。
- 进入页面、stop 后、状态修改后刷新采集条；刷新失败保留当前数据。
- 采集中任务/人员下拉禁用；结束采集后恢复。

| 状态 | 开始按钮 | 作废 |
|---|---|---|
| 空闲，没有任务/人员 | 禁用 | 禁用 |
| 空闲，任务/人员已选 | “开始采集”可用 | 禁用 |
| 录制中 | “停止并保存”可用 | 可用 |
| 停止中 | 禁用 | 禁用 |

### 4.3 查看数据页行为

- 进入默认“全部任务 + 全部人员 + 全部状态”。
- 进入不默认选中采集条；未选中时播放、上一条/下一条、详情、最大化、标记有效/无效都禁用。
- 任务未选时，人员候选为所有任务 `persons` 的合集。
- 选中任务后，人员候选只来自该任务，没有“全部人员”，人员不默认。
- 切换任务/人员/状态时清空选中，重新显示空状态。
- 列表为空时显示“还没有采集数据”。
- 列表每页 10 条，pad 本地分页；列表显示任务名、大小、状态；头部显示总条数和页码。
- 详情字段来自采集条：任务名、文件名、采集时间、人员、机器人、存储地址、大小、时长、任务说明。
- 标记有效/无效后重新拉取 `takes`；原选中条还在当前筛选结果里就保留，否则清空。
- 回放使用 `filePath` 拼文件服务 URL，不单独请求回放地址。

### 4.4 手动模式页行为

- 没有“一键连接”。
- 切到 `control` 时由 `POST /mode` 后台启动双臂/底盘服务。
- 页面轮询 `/processes`，判断双臂/底盘服务是否运行；未运行时方向键和机械臂按钮禁用。
- 硬件是否上电看 `/status`，服务是否运行看 `/processes`。
- 手动模式页没有返回按钮，只能通过顶部模式按钮离开；采集中不能进入。
- 机械臂、底盘控制接口还没实现，见 TODO。

### 4.5 设置弹层行为

- 基本设置修改 IP 只写配置，下次启动生效，当前连接不变；采集中 IP 只读。
- 设置页不自动连接，不读本地任务；IP 按钮只保存。
- 进程管理每 2 秒轮询 `/processes`，动作走 `/processes/action`。
- 操作日志是 pad 本地文件，按时间范围筛选、下载也读本地文件，不走机器人接口。
- 设备状态显示双臂、夹爪、底盘、四路相机、机载存储；不显示机器人（工控）和 VR。硬件状态来自 `/status`，存储来自 `/storage`。

---

## 5. 云端接口

### 5.1 POST /api/v1/cloud/token

从机器人获取云端访问 token。

请求：无。

成功：

```json
{
  "code": 200,
  "msg": "success",
  "data": {
    "token": "eyJ...",
    "expiresAt": 1768896697000
  }
}
```

- 每次从连接页成功连接时调用；同一连接的 WS 自动重连不再调用。
- pad 只保存在内存，不落盘。
- token 只用于云端任务请求。
- token 过期后 pad 提示用户手动重试/重连，不自动刷新。

### 5.2 GET {cloudBaseUrl}/tasks

请求头：

```http
Authorization: Bearer {token}
```

成功：

```json
{
  "code": 200,
  "msg": "success",
  "data": {
    "tasks": []
  }
}
```

- 云端失败不阻断连接，跳过同步，继续用机器人任务。

---

## 6. 任务接口

### 6.1 任务模型

```json
{
  "taskName": "compact_shoes",
  "brief": [
    "站到工位前，双手自然下垂",
    "听到提示后开始动作"
  ],
  "persons": ["张三", "李四"],
  "total": 100,
  "updatedAt": 1768893097000
}
```

字段：

| 字段 | 类型 | 说明 |
|---|---|---|
| `taskName` | string | 任务唯一名称 |
| `brief` | string[] | 采集说明 |
| `persons` | string[] | 可选人员 |
| `total` | int | 目标采集条数 |
| `updatedAt` | int | 毫秒时间戳 |

pad 侧“已采集 N 条”由 `/takes` 按 `taskName` 统计，任务接口不返回进度字段。

### 6.2 GET /api/v1/tasks

请求：无。

成功：

```json
{
  "code": 200,
  "msg": "success",
  "data": {
    "tasks": []
  }
}
```

- 返回机器人当前保存的全部任务。
- 字段与云端任务一致。
- 连接阶段失败停在连接页。
- 已进入 App 后，采集页/查看数据页刷新失败保留当前数据，只提示。
- pad 不缓存任务；采集页、查看数据页每次进入都重新请求。

### 6.3 POST /api/v1/tasks/sync

请求体就是云端 `data` 原样：

```json
{
  "tasks": [
    {
      "taskName": "compact_shoes",
      "brief": ["..."],
      "persons": ["张三", "李四"],
      "total": 100,
      "updatedAt": 1768893097000
    }
  ]
}
```

成功：

```json
{
  "code": 200,
  "msg": "success",
  "data": true
}
```

- 全量覆盖，原子替换。
- 校验通过后一次性替换；失败不改旧任务。
- 空数组表示清空机器人任务。
- 只有云端任务成功时才调用同步；云端失败不调用。
- 同步失败，pad 停在连接页。

---

## 7. 模式接口

### 7.1 GET /api/v1/mode

请求：无。

成功：

```json
{
  "code": 200,
  "msg": "success",
  "data": {
    "mode": "review"
  }
}
```

`mode` 取值：

```text
collect / review / control
```

机器人启动后的默认模式是 `review`。

调用时机：每次从连接页成功连接、异常恢复点“确定”后查询；不轮询。

### 7.2 POST /api/v1/mode

请求：

```json
{
  "mode": "control"
}
```

成功：

```json
{
  "code": 200,
  "msg": "success",
  "data": true
}
```

失败：

```json
{
  "code": 500,
  "msg": "切换模式失败的具体原因",
  "data": null
}
```

- 返回 `true` 立即返回，服务在后台启停。
- pad 收到 `true` 后跳对应页面。
- 失败时页面不变。
- 采集中 pad 不允许切模式，顶部模式按钮置灰；结束采集后恢复。后端是否再校验见 TODO。
- 不做多 pad 同步；其他 pad 改了模式，本 pad 不跟随。

模式对应的服务：

| 模式 | 双臂 | 底盘 | VR | 相机 |
|---|---|---|---|---|
| `collect` | 启动 | 启动 | 启动 | 启动 |
| `control` | 启动 | 启动 | 不要求 | 不要求 |
| `review` | 停止 | 停止 | 停止 | 停止 |

服务启停是后台异步的，pad 通过 `/status` 和 `/processes` 轮询状态。

---

## 8. 状态、FSM、存储

### 8.1 GET /api/v1/status

请求：无。

成功：

```json
{
  "code": 200,
  "msg": "success",
  "data": [
    { "name": "arm", "online": true },
    { "name": "gripper", "online": true },
    { "name": "chassis", "online": true },
    { "name": "vr", "online": true },
    { "name": "cam_head", "online": true },
    { "name": "cam_left", "online": true },
    { "name": "cam_right", "online": true },
    { "name": "cam_chest", "online": true },
    { "name": "fsm", "state": "HOME" }
  ]
}
```

设备项：

| name | 说明 |
|---|---|
| `arm` | 双臂 |
| `gripper` | 夹爪 |
| `chassis` | 底盘 |
| `vr` | VR |
| `cam_head` | 主视角相机 |
| `cam_left` | 左腕相机 |
| `cam_right` | 右腕相机 |
| `cam_chest` | 全景相机 |

`online` 表示硬件已上电，不表示服务已启动；服务是否运行看 `/processes`。

FSM 项：

```json
{ "name": "fsm", "state": "HOME" }
```

`state` 取值：

```text
HOME / HOLD / WAITING
```

FSM 项不带 `online`，只返回 `state`。

前端映射：`HOME → HOME点`，`HOLD → HOLD`，`WAITING → 待确认`。

调用时机：连接成功后每 2 秒轮询一次，所有页面共用；WS 断开或回连接页时停止，重连后恢复。

### 8.2 GET /api/v1/storage

请求：无。

成功：

```json
{
  "code": 200,
  "msg": "success",
  "data": {
    "freeBytes": 864000000000
  }
}
```

调用时机：连接成功后每 2 秒轮询一次，所有页面共用。

pad 只显示剩余空间，不按阈值拦截采集；能否录制由机器人校验。

### 8.3 轮询汇总

| 接口 | 频率 | 范围 |
|---|---|---|
| `/status` | 2 秒 | 连接后所有页面 |
| `/storage` | 2 秒 | 连接后所有页面 |
| `/processes` | 2 秒 | 设置页、手动模式页 |
| `/tasks` | 页面进入 | 采集页、查看数据页 |
| `/takes` | 页面进入 / stop 后 / 状态修改后 | 采集页、查看数据页 |

---

## 9. 采集会话接口

### 9.1 GET /api/v1/collect/current

请求：无。

没有当前采集：

```json
{
  "code": 200,
  "msg": "success",
  "data": null
}
```

有当前采集：

```json
{
  "code": 200,
  "msg": "success",
  "data": {
    "startedAt": 1768893097000,
    "taskName": "compact_shoes",
    "personName": "张三",
    "takeName": "compact_shoes_20261023_1421"
  }
}
```

- 没有 `status` 字段。
- `data: null` 表示空闲。
- 有数据表示正在录制；pad 恢复 `taskName/personName/takeName`，计时从 `startedAt` 继续。

### 9.2 POST /api/v1/collect/start

请求：

```json
{
  "taskName": "compact_shoes",
  "personName": "张三"
}
```

成功：

```json
{
  "code": 200,
  "msg": "success",
  "data": {
    "takeName": "compact_shoes_20261023_1421",
    "startedAt": 1768893097000
  }
}
```

- `takeName` 由机器人生成；pad 保存它用于作废。
- 只有任务和人员都选中、且当前没有进行中的采集时，pad 才调用。
- 失败返回 `code: 500`。

### 9.3 POST /api/v1/collect/stop

请求：

```json
{
  "taskName": "compact_shoes"
}
```

成功：

```json
{
  "code": 200,
  "msg": "success",
  "data": true
}
```

- 正常结束，采集条默认状态 `valid`。
- 成功后 pad 重新 `GET /takes`。
- 失败保持录制中。

作废采集条没有单独接口，pad 按顺序调用：

1. `POST /collect/stop`
2. `POST /takes/status`，`status: "invalid"`
3. `GET /takes`

- stop 失败，不调用 `takes/status`，保持录制中。
- `takes/status` 失败，采集条仍是 `valid`，pad 提示失败。
- 作废条仍计入 `N`，`valid/invalid` 都算。

---

## 10. 采集条接口

### 10.1 采集条模型

```json
{
  "takeName": "compact_shoes_20261023_1421",
  "taskName": "compact_shoes",
  "personName": "张三",
  "robotName": "1号工位",
  "startedAt": 1768893097000,
  "endedAt": 1768893131000,
  "durationMs": 34000,
  "sizeBytes": 1288490188,
  "status": "valid",
  "filePath": "/takes/compact_shoes_20261023_1421.mcap",
  "fileName": "compact_shoes_10-10_1421.mcap",
  "storagePath": "/data/episodes/compact_shoes/10-10_1421/"
}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `takeName` | string | 采集条唯一名称 |
| `taskName` | string | 所属任务 |
| `personName` | string | 采集人员 |
| `robotName` | string | 机器人名称 |
| `startedAt` | int | 开始时间，毫秒 |
| `endedAt` | int | 结束时间，毫秒 |
| `durationMs` | int | 时长，毫秒 |
| `sizeBytes` | int | 文件大小，字节 |
| `status` | string | `valid` / `invalid` |
| `filePath` | string | MCAP 相对路径，用于回放 URL |
| `fileName` | string | 文件名，展示用 |
| `storagePath` | string | 存储目录，展示用 |

实际文件是 MCAP，不是 MP4。

### 10.2 GET /api/v1/takes

请求：无。

成功：

```json
{
  "code": 200,
  "msg": "success",
  "data": {
    "takes": [
      {
        "takeName": "compact_shoes_20261023_1421",
        "taskName": "compact_shoes",
        "personName": "张三",
        "robotName": "1号工位",
        "startedAt": 1768893097000,
        "endedAt": 1768893131000,
        "durationMs": 34000,
        "sizeBytes": 1288490188,
        "status": "valid",
        "filePath": "/takes/compact_shoes_20261023_1421.mcap",
        "fileName": "compact_shoes_10-10_1421.mcap",
        "storagePath": "/data/episodes/compact_shoes/10-10_1421/"
      }
    ]
  }
}
```

- 返回全部采集条，不按任务过滤。
- 按 `startedAt` 降序。
- 不服务端分页。
- 不返回正在录制的采集条。
- 调用时机：采集页/查看数据页进入、采集 stop 后、`takes/status` 后。
- 回放 URL：`http://{robotIp}:{filePort}{filePath}`。

### 10.3 POST /api/v1/takes/status

请求：

```json
{
  "takeName": "compact_shoes_20261023_1421",
  "status": "invalid"
}
```

成功：

```json
{
  "code": 200,
  "msg": "success",
  "data": true
}
```

- 只允许 `valid` / `invalid`。
- 不允许改成 `recording`。
- 成功后 pad 重新 `GET /takes`。

---

## 11. 进程接口

### 11.1 GET /api/v1/processes

请求：无。

成功：

```json
{
  "code": 200,
  "msg": "success",
  "data": [
    { "name": "采集服务", "running": true, "pid": 1284 },
    { "name": "设备连接服务", "running": true, "pid": 1290 },
    { "name": "网络同步服务", "running": true, "pid": 1291 },
    { "name": "数据存储服务", "running": true, "pid": 1292 },
    { "name": "日志服务", "running": true, "pid": 1293 }
  ]
}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `name` | string | 进程显示名 |
| `running` | bool | 是否运行 |
| `pid` | int | 进程 ID |

- 设置页和手动模式页每 2 秒轮询这个接口；手动模式页用它判断双臂/底盘服务是否运行。
- 服务名和 `pid` 由机器人返回。

### 11.2 POST /api/v1/processes/action

请求：

```json
{
  "pid": 1284,
  "action": "restart"
}
```

`action`：

```text
start / stop / restart
```

成功：

```json
{
  "code": 200,
  "msg": "success",
  "data": true
}
```

- 按 `pid` 操作。
- 操作后不返回最新状态，由 `/processes` 轮询刷新。

---

## 12. WebSocket

地址：

```text
ws://{robotIp}:{apiPort}/api/v1/ws
```

- 用户点连接时建立，5 秒超时。
- 握手成功即连接成功；不要求服务端先发 `hello`，也不调用 `/healthz`。
- 当前只用于判断在线/断线，不承载业务消息。
- 断开后重连 5 次，间隔 1、2、3、4、5 秒。
- 重连成功继续当前页面，不额外立即刷新 mode/current/status，不重新同步任务；status/storage 按原 2 秒周期恢复。
- 重连失败，pad 回连接页。
- 回连接页后再次点连接，重新走第 3.2 节完整流程。

---

## 13. 文件服务

文件服务由 Caddy 提供，不在机器人业务 API 内。

pad 拼接：

```text
http://{robotIp}:{filePort}{filePath}
```

要求：

- 支持 `HEAD`。
- 支持 `Range`，返回 `206 Partial Content`。
- 返回 `Content-Range`、`Content-Length`、`Accept-Ranges: bytes`。
- 不压缩 MCAP。
- 文件路径和 `filePath` 一致。

---

## 14. 失败处理

- 云端任务失败：跳过同步，继续获取机器人任务。
- token 失败：停在连接页。
- 任务同步失败：停在连接页。
- 机器人任务失败：连接阶段停在连接页；已进入 App 后刷新失败保留当前数据。
- 模式查询失败：停在连接页。
- `POST /mode` 失败：页面不变。
- `POST /collect/start` 失败：保持空闲，任务/人员选择不变。
- `POST /collect/stop` 失败：保持录制中，计时不变。
- `GET /takes` 失败：保留当前数据。
- `POST /takes/status` 失败：不修改本地状态。


---

## 15. TODO

以下功能还没实现，先不要按接口开发；确定后再补接口和字段。

1. **进程日志**
   - HTTP 还是 WebSocket
   - 日志接口路径、字段
   - 进程日志下载
2. **双臂/底盘服务进程名**
   - 手动模式页用 `/processes` 的哪个 `name` 或 `pid` 判断服务已运行
3. **机械臂三个位姿**
   - 接口路径、pose 取值、请求/响应
   - UI 是一个按钮循环还是三个按钮
4. **底盘控制**
   - 移动/旋转/停止
   - 速度、seq、超时停车、急停
5. **WebSocket 业务消息**
   - 当前只用于连接判断
   - 是否传日志/事件、ping/pong、连接后是否发消息
6. **操作日志本地格式**
   - pad 自己写文件，不走机器人接口
7. **重复 start / 采集中切模式的后端校验**
   - pad 已经禁用，但机器人侧是否还要校验

---

## 16. 联调顺序

建议按这个顺序实现和联调：

1. WS 握手
2. `POST /cloud/token`
3. `GET /tasks` + `POST /tasks/sync`
4. `GET /mode` + `POST /mode`
5. `GET /status` + `GET /storage`
6. `GET /collect/current` + `POST /collect/start` + `POST /collect/stop`
7. `GET /takes` + `POST /takes/status`
8. Caddy Range 回放
9. `GET /processes` + `POST /processes/action`
10. 进程日志、机械臂、底盘
