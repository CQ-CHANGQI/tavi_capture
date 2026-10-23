# 端侧采集平板 · 机器人接口清单

> 这是按最新原型和产品讨论整理的接口约定，用于 pad、机器人、云端三方对接。
> 本文件取代旧的 39 条页面接口清单。
>
> 标记 **TODO** 的部分还没有定，不要按本文实现；未标记的按本文实现。
>
> 页面范围只有：连接页、采集页、查看数据页、手动模式页、设置弹层。
> 不再有首页、任务页、已采页、登录页、独立回看页。

## 0. 页面和模式

### 页面

| 页面 | 说明 |
|---|---|
| 连接页 | 填机器人 IP，点连接，完成启动流程 |
| 采集页 | 任务/人员选择、实时画面、开始/停止/作废、采集列表 |
| 查看数据页 | 采集条列表、筛选、详情、内嵌回放 |
| 手动模式页 | 底盘方向控制、机械臂位姿、服务状态 |
| 设置弹层 | 基本设置、进程管理、日志查看、设备状态 |

设置是弹层，不是独立页面。

### 模式

只有三个模式：

```text
collect / review / control
```

没有 `idle`。

| 模式 | 页面 | 顶部按钮 |
|---|---|---|
| `collect` | 采集页 | 数据采集 |
| `review` | 查看数据页 | 查看数据 |
| `control` | 手动模式页 | 手动模式 |

机器人启动后的默认模式是 `review`。

---

## 1. 通用约定

### 1.1 地址

机器人本地 API：

```text
http://{robotIp}:{apiPort}/api/v1
```

默认 `apiPort = 8080`。

WebSocket：

```text
ws://{robotIp}:{apiPort}/api/v1/ws
```

默认 `apiPort = 8080`。

文件服务：

```text
http://{robotIp}:{filePort}{filePath}
```

默认 `filePort = 8090`。

云端：

```text
{cloudBaseUrl}/tasks
```

`cloudBaseUrl` 本身已经到 `/api/v1`，pad 只追加 `/tasks`。

示例：

```text
cloudBaseUrl = https://cloud.example.com/api/v1
GET https://cloud.example.com/api/v1/tasks
```

### 1.2 HTTP 响应格式

机器人业务 API 和云端任务 API 的 HTTP 状态码永远返回 `200`，业务结果看 `code`。文件服务 Caddy 除外，它按 Range 正常返回 `200/206`。

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
- 失败 `code = 500`，`msg` 是给 pad 展示的中文错误。
- 失败时 `data = null`。
- `data` 可以是对象、数组、`null` 或 `true`。
- 只有“动作成功”的接口用 `data: true`：
  - `POST /collect/stop`
  - `POST /tasks/sync`
  - `POST /takes/status`
  - `POST /mode`
  - `POST /processes/action`
- 不使用 HTTP 4xx/5xx 表达业务错误。
- 不允许返回非 JSON。
- 所有响应 `Content-Type: application/json`。

### 1.3 时间、单位、命名

- 所有时间戳统一毫秒，例如 `1768893097000`。
- 文件大小统一字节，例如 `1288490188`。
- 时长统一毫秒，例如 `34000`。
- 任务名称 `taskName` 是任务唯一标识，没有 `taskId`。
- 采集条名称 `takeName` 是采集条唯一标识，没有 `takeId`。
- 人员用 `personName`，没有 `personId`。
- 采集条状态用英文枚举：

```text
recording / valid / invalid
```

- 列表接口不返回 `recording`，只返回已完成保存的 `valid / invalid`。
- 不使用单独的 `valid` 布尔字段，`status` 是唯一权威状态。

### 1.4 超时和重试

- HTTP 请求超时：5 秒。
- HTTP 失败不自动重试。
- WebSocket 连接超时：5 秒。
- WebSocket 断开后自动重连：间隔 1、2、3、4、5 秒，共 5 次。
- 重连成功后不重新请求 mode/current/status，不重新同步任务。
- 重连 5 次失败，回连接页。

### 1.5 登录、权限、健康检查

- 不做登录。
- 不做云端账号、本地账号、角色、权限。
- 不做设备注册、设备心跳。
- 不做 `/healthz`。
- WebSocket 握手成功即代表机器人可达。
- 所有 pad 都可以进入采集、查看数据、手动模式、设置。
- 机器人本地接口不做鉴权。

---

## 2. 配置文件

### 2.1 文件位置

- `assets/config.json`：出厂默认，只读，随 App 打包。
- App 私有目录 `config.json`：运行时配置，App 用 `path_provider` 读写。
- 用户不手动编辑配置文件。

App 启动时：

1. 读 App 私有目录 `config.json`；
2. 不存在或损坏，读 `assets/config.json`；
3. 两边都没有合法配置，连接页显示配置错误。

### 2.2 配置字段

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

字段说明：

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

LCM topic 暂不做配置，固定：

```text
/preview/cameras/cam_head
/preview/cameras/cam_left
/preview/cameras/cam_right
/preview/cameras/cam_chest
/preview/joint_batch
```

### 2.3 写入规则

- 连接成功后，把当前 `robotIp` 写回 App 私有目录 `config.json`。
- 连接失败不覆盖旧 IP。
- 设置页改 IP：只写配置文件，下次启动生效，当前连接不变。
- 设置页按钮不再叫“保存并连接”，只保存。
- 不缓存任务。
- 不保存 token。

---

## 3. 连接和启动流程

### 3.1 连接页

- App 启动不自动连接。
- 从 `config.json` 读 IP 填入输入框。
- 用户点“保存并连接”才发起连接。
- 连接成功后自动写回 `robotIp`。
- 未连接时，顶部三个模式按钮可点，但只提示“请先连接机器人”。
- 连接过程中显示阶段：
  - 正在连接 WS
  - 正在获取 token
  - 正在同步任务
  - 正在获取任务
  - 正在获取模式

### 3.2 首次连接完整流程

```text
用户点连接
  → 打开 WS（5 秒超时）
      ├─ 失败：停在连接页，提示“连接机器人失败”
      └─ 成功：
          → POST /api/v1/cloud/token
              ├─ 失败：停在连接页，提示“获取云端 token 失败”
              └─ 成功：
                  → GET {cloudBaseUrl}/tasks
                      ├─ 成功：POST /api/v1/tasks/sync
                      │        ├─ 失败：停在连接页，提示“给机器人同步任务失败”
                      │        └─ 成功：继续
                      └─ 失败：跳过同步，继续
                  → GET /api/v1/tasks
                      ├─ 失败：停在连接页，提示“获取任务失败”
                      └─ 成功：
                          → GET /api/v1/mode
                              ├─ 失败：停在连接页，提示“获取模式失败”
                              └─ 成功：按模式跳页面
```

规则：

- 云端任务请求失败，不阻断连接；继续用机器人任务。
- 云端任务请求成功，但同步失败，阻断连接。
- token 获取失败，阻断连接。
- 机器人任务获取失败，阻断连接。
- 模式获取失败，阻断连接。
- 任务同步只在首次连接做一次。
- 自动重连不做任务同步，也不重新请求 mode/current/status。
- 连接页点“保存并连接”成功后才写 IP；失败不覆盖。

### 3.3 跳转

```text
GET /mode = collect  → 采集页
GET /mode = review   → 查看数据页
GET /mode = control  → 手动模式页
```

如果模式是 `collect`，进入采集页后再请求：

```http
GET /api/v1/collect/current
```

用于恢复正在录制的采集。

### 3.4 自动重连

- WS 断开，间隔 1、2、3、4、5 秒重连，共 5 次。
- 重连成功后不额外立即刷新 mode/current/status，也不重新同步任务。
- status/storage 恢复原来的 2 秒周期轮询。
- 重连成功，继续当前页面。
- 重连 5 次失败，回连接页。
- 回连接页后再次连接成功，重新走完整启动流程。

### 3.5 录制中 WS 断开

- 保持本地“录制中”状态。
- 计时继续。
- 不自动停止、不作废。
- 重连成功后继续计时。
- 重连失败回连接页，下一次连接后通过 `GET /collect/current` 恢复。

### 3.6 异常恢复

设备异常恢复弹层点“确定”后：

1. 重新 `GET /api/v1/mode`；
2. 按模式跳页面；
3. 如果模式是 `collect`，再 `GET /api/v1/collect/current`。

模式查询失败时留在当前页，提示错误，不清空本地数据。

---

## 4. 模式接口

### 4.1 GET /api/v1/mode

用途：读取机器人当前模式。

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

调用时机：

- 首次连接完整流程；
- 异常恢复弹层点“确定”后重新查询。

不轮询。

### 4.2 POST /api/v1/mode

用途：切换机器人模式。

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

规则：

- 返回 `true` 立即返回，服务在后台启停。
- pad 收到 `true` 后跳对应页面。
- 失败时页面不变，提示 `msg`。
- 采集中不允许切换模式，顶部三个模式按钮置灰。
- 必须先结束采集，按钮才恢复。
- 不做多 pad 同步；其他 pad 改了模式，当前 pad 不跟随。
- 服务启停状态由 `/processes` 轮询判断，不由 `POST /mode` 等待。

### 4.3 模式对应的服务启停

| 模式 | 双臂 | 底盘 | VR | 相机 |
|---|---|---|---|---|
| `collect` | 启动 | 启动 | 启动 | 启动 |
| `control` | 启动 | 启动 | 不要求 | 不要求 |
| `review` | 停止 | 停止 | 停止 | 停止 |

说明：

- 切到 `collect`：启动双臂、底盘、VR、相机。
- 切到 `control`：启动双臂、底盘。
- 切到 `review`：停止双臂、底盘、VR、相机，只保留回放。
- `POST /mode` 立即返回，实际启停是后台异步。
- 页面靠 `/status` 和 `/processes` 轮询到最终状态。

---

## 5. 任务接口

### 5.1 任务数据模型

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
| `brief` | string[] | 采集说明，逐条展示 |
| `persons` | string[] | 该任务可选人员 |
| `total` | int | 目标采集条数 |
| `updatedAt` | int | 毫秒时间戳 |

不包含：

- `taskId`
- `done`
- `size`
- `robot`
- `model`
- `state`

“已采集”由 pad 用采集条数量计算，不使用任务里的 `done`。

### 5.2 云端任务

```http
GET {cloudBaseUrl}/tasks
Authorization: Bearer {token}
```

成功：

```json
{
  "code": 200,
  "msg": "success",
  "data": {
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
}
```

失败：

- 网络错误、HTTP 错误、`code: 500` 都算失败；
- 失败不阻断连接，跳过同步，继续获取机器人任务。

### 5.3 同步任务到机器人

```http
POST /api/v1/tasks/sync
```

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

规则：

- 全量覆盖，原子替换。
- 校验通过后一次性替换；失败不改旧任务。
- 空数组按全量覆盖处理，表示机器人任务清空。
- 同步失败则停在连接页，提示“给机器人同步任务失败”。
- 只有云端任务成功时才调用同步；云端失败不调用。

### 5.4 机器人任务

```http
GET /api/v1/tasks
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

规则：

- 返回机器人当前保存的全部任务。
- 字段与云端任务完全一致。
- 不管云端任务成功还是失败，最终都必须调用这个接口。
- 失败则停在连接页，提示“获取任务失败”。
- pad 不缓存任务，只放内存。
- 采集页、查看数据页每次进入都重新调用。
- 页面刷新失败时保留当前数据，只弹提示。

### 5.5 任务进度

采集页进度：

```text
N / total
```

- `total` 来自当前任务。
- `N` = `GET /takes` 里 `taskName` 等于当前任务的采集条数量。
- `valid` 和 `invalid` 都算。
- 不包含 `recording`。
- 没有选中任务时显示 `0 / 0`，开始按钮禁用。

---

## 6. 采集条接口

### 6.1 采集条数据模型

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

字段：

| 字段 | 类型 | 说明 |
|---|---|---|
| `takeName` | string | 采集条唯一名称 |
| `taskName` | string | 所属任务 |
| `personName` | string | 采集人员 |
| `robotName` | string | 机器人名称，详情展示 |
| `startedAt` | int | 开始时间，毫秒 |
| `endedAt` | int | 结束时间，毫秒 |
| `durationMs` | int | 时长，毫秒 |
| `sizeBytes` | int | 文件大小，字节 |
| `status` | string | `valid` / `invalid` |
| `filePath` | string | MCAP 相对路径，用于拼回放 URL |
| `fileName` | string | 详情展示的文件名 |
| `storagePath` | string | 详情展示的存储目录 |

说明：

- 实际文件是 **MCAP**，不是 MP4。
- 原型里的 `.mp4` 只是 mock 文案。
- `filePath` 只用于回放 URL。
- `fileName`、`storagePath` 只用于详情展示。
- 列表不返回 `recording`。
- 不使用 `valid` 布尔字段。

### 6.2 GET /api/v1/takes

用途：获取全部采集条。

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

规则：

- 返回全部采集条，不按任务过滤。
- 按 `startedAt` 降序。
- 不服务端分页。
- pad 自己做筛选和分页。
- 不返回正在录制的采集条。
- 调用时机：
  - 采集页进入；
  - 采集页 stop 后；
  - 采集页作废后；
  - 查看数据页进入；
  - 标记有效/无效后。
- 刷新失败：保留当前数据，只弹提示。

### 6.3 POST /api/v1/takes/status

用途：修改采集条状态。

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

规则：

- 只允许 `valid` / `invalid`。
- 不允许改成 `recording`。
- 成功后再调用 `GET /takes` 刷新。
- 失败提示 `msg`，不改本地状态。

### 6.4 文件回放

pad 拼 URL：

```text
http://{robotIp}:{filePort}{filePath}
```

示例：

```text
http://192.168.13.4:8090/takes/compact_shoes_20261023_1421.mcap
```

Caddy 要求：

- 支持 `HEAD`。
- 支持 `Range`。
- Range 请求返回 `206 Partial Content`。
- 返回正确的 `Content-Range`、`Content-Length`、`Accept-Ranges: bytes`。
- 不要 gzip。
- 不要改文件内容。

---

## 7. 采集会话接口

### 7.1 GET /api/v1/collect/current

用途：查询当前是否有正在进行的采集。

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

说明：

- 没有 `status` 字段。
- `data: null` 表示空闲。
- 有数据表示正在录制。
- 进入采集页时调用。
- 恢复当前采集后：
  - 任务、人员下拉禁用；
  - 显示当前 `taskName/personName`；
  - 计时从 `startedAt` 继续；
  - 开始按钮变成“停止并保存”；
  - 作废按钮可用。

### 7.2 POST /api/v1/collect/start

用途：开始一条采集。

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

规则：

- `takeName` 由机器人生成。
- pad 保存 `takeName`，用于作废时改状态。
- 失败提示 `msg`，保持空闲，任务/人员选择不变。
- 页面在任务和人员都选中后才允许调用。
- 有当前采集时 pad 不再调用 start。
- 重复 start 的后端行为 TODO。

### 7.3 POST /api/v1/collect/stop

用途：结束当前采集并保存。

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

规则：

- 正常结束，采集条默认状态 `valid`。
- 成功后 pad 重新 `GET /takes`。
- 失败时提示 `msg`，保持“录制中”和计时不变。
- 不自动重试。

### 7.4 作废采集条

没有单独的作废接口。pad 按顺序调用：

1. `POST /collect/stop`，body `{ taskName }`；
2. `POST /takes/status`，body `{ takeName, status: "invalid" }`；
3. `GET /takes` 刷新列表。

说明：

- stop 成功后采集条先按 `valid` 保存；
- 第二次调用把它改成 `invalid`；
- 如果 stop 失败，不再调用 `takes/status`，保持录制中；
- 如果第二步失败，采集条仍是 `valid`，pad 提示失败；
- 作废条仍计入 `N`，因为 `N` 统计当前任务的全部采集条，`valid/invalid` 都算。

---

## 8. 采集页

### 8.1 进入页面请求

```http
GET /api/v1/tasks
GET /api/v1/takes
GET /api/v1/collect/current
```

同时全局轮询：

```http
GET /api/v1/status
GET /api/v1/storage
```

### 8.2 任务和人员

- 进入页面默认任务“全部任务”，人员为空。
- 没有选中任务时，开始按钮禁用。
- 选中任务后，人员下拉变成该任务 `persons`。
- 人员没有默认值，必须手动选。
- 任务和人员都选中后，开始按钮才可用。
- 有 `current` 时，任务/人员锁定为当前值，下拉禁用。
- 切换任务时，人员清空，等待重新选择。
- 任务列表为空时，页面显示空任务，不跳任务页，开始按钮禁用。

### 8.3 采集列表

- 默认显示全部任务的采集条。
- 选中任务后只显示该任务的采集条。
- 按 `startedAt` 降序。
- 高亮最新一条。
- 列表显示：
  - 时间
  - 大小
  - 状态
- 不显示时长。
- 高亮只是视觉，不触发回放。
- 刷新失败保留当前数据，只弹提示。

### 8.4 进度

```text
N / total
```

- `N` = 当前任务全部采集条数量；
- `valid` / `invalid` 都算；
- 没有任务时 `0 / 0`。

### 8.5 FSM

- FSM 从 `/status` 里的 `fsm` 项读取。
- 只显示，不可点击。
- 取值见第 10 节。

### 8.6 存储

- 只显示剩余空间；
- 不判断阈值；
- 不禁止开始采集；
- 是否可录制由机器人校验。

### 8.7 开始/停止/作废按钮

| 状态 | 开始按钮 | 作废 |
|---|---|---|
| 空闲，没有任务/人员 | 禁用 | 禁用 |
| 空闲，任务/人员已选 | “开始采集”可用 | 禁用 |
| 录制中 | “停止并保存”可用 | 可用 |
| 停止中 | 禁用 | 禁用 |

---

## 9. 查看数据页

### 9.1 进入页面请求

```http
GET /api/v1/tasks
GET /api/v1/takes
```

状态/存储用全局轮询。

### 9.2 默认筛选

- 任务：`全部任务`
- 人员：`全部人员`
- 状态：`全部`

### 9.3 默认选中

- 进入页面不默认选中任何采集条。
- 右侧显示空状态“请先选择左侧一条数据查看”。
- 列表为空时显示“还没有采集数据”，不显示详情/回放。
- 没选中时以下按钮全部禁用：
  - 播放
  - 上一条
  - 下一条
  - 详情
  - 最大化
  - 标记无效/标记有效

### 9.4 任务和人员筛选

任务未选：

- 人员下拉是“全部人员”；
- 人员候选 = 所有任务 `persons` 的合集；
- 列表显示全部采集条。

选中任务：

- 人员下拉变成该任务 `persons`，没有“全部人员”；
- 人员没有默认值；
- 列表先只按任务过滤；
- 选了人员后再按人员过滤。

### 9.5 切换筛选

切换任务/人员/状态后：

- 清空已选中的采集条；
- 重新显示空状态；
- 不自动选第一条。

### 9.6 列表

- 本地分页，每页 10 条。
- 按 `startedAt` 降序。
- 每条显示：
  - 任务名
  - 大小
  - 状态
- 不显示时间、时长、人员。
- 头部显示“共 N 条”。
- 页码显示“第 x/y 页”。

### 9.7 详情

选中一条后点“详情”展示：

- 任务名称 `taskName`
- 文件名称 `fileName`
- 采集时间 `startedAt`
- 采集人员 `personName`
- 机器人 `robotName`
- 存储地址 `storagePath`
- 文件大小 `sizeBytes`
- 视频时长 `durationMs`
- 采集说明：当前任务的 `brief`

详情不需要单独接口。

### 9.8 标记有效/无效

调用：

```http
POST /api/v1/takes/status
```

成功后：

- 重新 `GET /takes`；
- 如果原选中条仍在当前筛选结果里，保留选中；
- 如果被过滤掉，清空选中，显示空状态。

### 9.9 回放

- 选中后右侧内嵌播放。
- 用 `filePath` 拼 Caddy URL。
- 支持播放/暂停、上一条/下一条、进度条、倍速、循环、最大化。
- 不跳独立回看页。
- 没有单独的回看接口。

---

## 10. 状态、FSM、存储

### 10.1 GET /api/v1/status

用途：设备硬件状态 + FSM。

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

`online` 的含义：

- 表示**硬件已上电**；
- 不表示服务已启动；
- 服务是否运行看 `/processes`。

FSM 项：

```json
{ "name": "fsm", "state": "HOME" }
```

`state` 取值：

```text
HOME / HOLD / WAITING
```

前端映射：

```text
HOME    → HOME点
HOLD    → HOLD
WAITING → 待确认
```

规则：

- 不返回机器人型号、版本、存储、任务。
- FSM 项只返回 `state`，不带 `online`。
- FSM 只显示，不可点击。
- 连接成功后每 2 秒轮询一次，所有页面共用。
- WS 断开或回连接页时停止轮询；重连成功后恢复 2 秒轮询，不额外立即请求。

### 10.2 GET /api/v1/storage

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

规则：

- 只显示，不判断阈值，不禁止采集。
- 连接成功后每 2 秒轮询一次，所有页面共用。

### 10.3 轮询汇总

| 接口 | 频率 | 范围 |
|---|---|---|
| `/status` | 2 秒 | 连接后所有页面 |
| `/storage` | 2 秒 | 连接后所有页面 |
| `/processes` | 2 秒 | 设置页、手动模式页 |
| `/tasks` | 页面进入时 | 采集页、查看数据页 |
| `/takes` | 页面进入/stop/状态更新 | 采集页、查看数据页 |

---

## 11. 进程接口

### 11.1 GET /api/v1/processes

用途：进程列表。

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

字段：

| 字段 | 类型 | 说明 |
|---|---|---|
| `name` | string | 进程显示名 |
| `running` | bool | 是否运行 |
| `pid` | int | 进程 ID，动作用 |

调用：

- 设置页打开时每 2 秒轮询；
- 手动模式页轮询，用于判断双臂/底盘服务是否运行；
- 进程动作后不额外请求，等下一次轮询刷新。

### 11.2 POST /api/v1/processes/action

用途：启动/停止/重启进程。

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

规则：

- 按 `pid` 操作。
- 成功 `data: true`。
- 失败 `code: 500`，`msg` 是原因。
- 操作后不立即返回最新状态，由 `/processes` 轮询刷新。

### 11.3 双臂/底盘服务进程名

TODO。

手动模式页需要判断“双臂服务”和“底盘服务”是否运行，但具体用哪个 `name` 或 `pid` 还没定。

---

## 12. 云端接口

### 12.1 POST /api/v1/cloud/token

用途：从机器人获取云端访问 token。

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

规则：

- 只在首次连接时调用。
- pad 只保存在内存，不落盘。
- token 只用于云端任务请求。
- 获取失败停在连接页。
- token 过期：页面提示，用户手动重试/重连，pad 不自动刷新。
- token 失效后 pad 不自动重新获取。

### 12.2 GET {cloudBaseUrl}/tasks

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

规则：

- 云端和机器人任务字段完全一致。
- 云端失败不阻断连接，跳过同步，继续用机器人任务。
- 不把 token 发给机器人接口。

---

## 13. WebSocket

### 13.1 地址

```text
ws://{robotIp}:{apiPort}/api/v1/ws
```

默认 `apiPort=8080`。

### 13.2 连接

- 用户点连接时建立。
- 5 秒超时。
- 握手成功即代表连接成功。
- 不要求服务端先发 `hello`。
- 不做 `/healthz`。

### 13.3 消息

目前只用于判断连接/断线。

具体还承载什么，TODO：

- 是否传日志；
- 是否传模式/采集/状态事件；
- 是否要 ping/pong；
- 连接后是否要发消息。

当前实现可以只建立连接，不发送业务消息。

### 13.4 断开和重连

- 断开后自动重连 5 次，间隔 1、2、3、4、5 秒。
- 重连成功不重新请求 mode/current/status。
- 重连期间保持本地采集计时。
- 5 次失败回连接页。
- 回连接页后再次连接成功，重新走完整启动流程。

---

## 14. 文件服务

文件服务由 Caddy 提供，不在机器人业务 API 内。

要求：

- `HEAD` 返回 `200` 和 `Content-Length`。
- `GET` 无 Range 返回 `200`。
- `GET` 带 Range 返回 `206`。
- 返回 `Accept-Ranges: bytes`。
- 返回正确 `Content-Range`。
- 不压缩 MCAP。
- 文件路径和 `filePath` 一致。

pad 拼接：

```text
http://{robotIp}:{filePort}{filePath}
```

---

## 15. 页面请求汇总

### 接口总表

机器人本地 HTTP：

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
| `POST` | `/api/v1/processes/action` | 启停/重启进程 |

云端：

| 方法 | 路径 | 用途 |
|---|---|---|
| `GET` | `{cloudBaseUrl}/tasks` | 云端任务 |

其他：

| 协议 | 地址 | 用途 |
|---|---|---|
| WS | `/api/v1/ws` | 连接状态 |
| HTTP | `{filePort}{filePath}` | MCAP Range 回放 |

### 连接页

```text
WS /api/v1/ws
POST /api/v1/cloud/token
GET  {cloudBaseUrl}/tasks
POST /api/v1/tasks/sync
GET  /api/v1/tasks
GET  /api/v1/mode
```

### 采集页

进入：

```text
GET /api/v1/tasks
GET /api/v1/takes
GET /api/v1/collect/current
GET /api/v1/status       （全局 2 秒）
GET /api/v1/storage      （全局 2 秒）
```

操作：

```text
POST /api/v1/collect/start
POST /api/v1/collect/stop
POST /api/v1/takes/status
GET  /api/v1/takes
```

### 查看数据页

进入：

```text
GET /api/v1/tasks
GET /api/v1/takes
GET /api/v1/status       （全局 2 秒）
GET /api/v1/storage      （全局 2 秒）
```

操作：

```text
POST /api/v1/takes/status
GET  /api/v1/takes
GET  http://{robotIp}:{filePort}{filePath}
```

### 手动模式页

```text
GET /api/v1/status       （全局 2 秒）
GET /api/v1/storage      （全局 2 秒）
GET /api/v1/processes    （2 秒，判断服务）
```

底盘/机械臂控制接口 TODO。

### 设置页

```text
GET  /api/v1/status      （全局 2 秒）
GET  /api/v1/storage     （全局 2 秒）
GET  /api/v1/processes   （2 秒）
POST /api/v1/processes/action
```

操作日志是 pad 本地文件，不走机器人接口。

---

## 16. 设置页

### 16.1 基本设置

- 显示机器人 IP。
- 从 `config.json` 读取。
- 修改后只保存，下次启动生效。
- 不自动连接。
- 不读本地任务。
- 采集中 IP 只读。
- 不再有“保存并连接”的立即连接语义。

### 16.2 进程管理

- 列表来自 `GET /processes`。
- 每 2 秒轮询。
- 启用/停止/重启调用 `POST /processes/action`。
- 进程日志、日志下载 TODO。

### 16.3 日志查看

- 这是 pad 自己的操作日志。
- pad 运行过程中写本地文件。
- 查看、按时间范围筛选、下载都读本地文件。
- 不调用机器人接口。
- 日志格式、文件位置、下载格式属于 pad 内部实现，不在本接口清单。

### 16.4 设备状态

显示：

- 双臂
- 夹爪
- 底盘
- 四路相机
- 机载存储

不显示：

- 机器人（工控）卡片
- VR 卡片

数据来源：

- 设备状态来自 `/status`；
- 机载存储来自 `/storage`；
- 服务是否运行来自 `/processes`，不在设备状态卡片里体现。

---

## 17. 手动模式页

- 没有“一键连接”。
- 不主动启动双臂/底盘服务。
- 进入 `control` 模式时，`POST /mode` 已经让机器人后台启动双臂/底盘。
- 页面轮询 `/processes`，判断双臂/底盘服务是否已运行。
- 服务未运行时，方向键和机械臂按钮禁用。
- 硬件是否上电看 `/status`，服务是否运行看 `/processes`。
- 没有返回按钮；只能通过顶部模式按钮离开。
- 采集中模式按钮禁用，不能进入手动模式。

底盘和机械臂接口 TODO。

---

## 18. 已删除的接口/行为

以下不再使用，不要实现：

- `GET /healthz`
- `POST /api/v1/auth/login`
- `POST /api/v1/auth/logout`
- `POST /api/v1/device/register`
- `POST /api/v1/device/heartbeat`
- `POST /api/v1/device/credentials`
- `GET /api/v1/tasks/{taskName}`
- `POST /api/v1/tasks/refresh`
- `POST /api/v1/tasks/{taskName}/ensure`
- `GET /api/v1/takes/{takeName}`
- `GET /api/v1/takes/{takeName}/source`
- `POST /api/v1/collect/select`
- `POST /api/v1/collect/{takeName}/drop`
- `GET /api/v1/control/state`
- `POST /api/v1/control/connect`

同时删除：

- 登录页、登录弹层、云端/本地登录、角色、权限；
- 首页；
- 我的任务页；
- 已采页；
- 独立回看页；
- `idle` 模式；
- 任务 `done/size/robot/model/state` 字段；
- 采集条 `valid` 布尔字段；
- 服务端采集条分页；
- 设备注册、设备心跳；
- 健康检查。

---

## 19. TODO

以下还没定，不要按本文实现：

1. **进程日志**
   - HTTP 还是 WebSocket
   - 接口路径
   - 日志字段
   - 进程日志下载接口
2. **双臂/底盘服务进程名**
   - 手动模式页用 `/processes` 的哪个 `name` 或 `pid` 判断服务已运行
3. **机械臂三个位姿**
   - 接口路径
   - pose 取值
   - 请求/响应
   - UI 是一个按钮循环还是三个按钮
4. **底盘控制**
   - 移动/旋转/停止
   - 速度
   - seq、超时停车、急停
5. **WebSocket 业务消息**
   - 是否传日志
   - 是否传事件
   - ping/pong
   - 连接后是否发消息
6. **操作日志本地格式**
   - 只是 pad 内部实现，不影响机器人接口
7. **重复 start / 采集中切模式的后端行为**
   - pad 已禁用，但机器人侧是否还要校验
8. **多 pad 并发**
   - 当前不做同步，其他 pad 改了模式，本 pad 不跟随

---

## 20. 最小联调顺序

建议机器人按这个顺序实现：

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

这样 pad 可以先跑通：连接 → 采集 → 查看数据 → 回放。
