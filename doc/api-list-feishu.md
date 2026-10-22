# 端侧采集平板接口清单（飞书版）

这版没有表格，每个接口一块，直接全选粘贴到飞书就能读；标题和项目符号飞书会自动识别。

## 通用约定

- 本地 API：http://{robotIp}:8080/api/v1
- 健康检查：http://{robotIp}:8080/healthz（不带 /api/v1）
- 事件 WebSocket：ws://{robotIp}:8080/api/v1/ws?lastSeq=
- 日志 WebSocket：ws://{robotIp}:8080/api/v1/ws/logs
- 文件服务：http://{robotIp}:8090{filePath}，支持 HEAD/Range/206
- 云端：https://{cloudBaseUrl}/api/v1
- 除 /healthz 和 /auth/login 外，其余请求都带 Authorization: Bearer {padToken}
- 设备相关请求再带 X-Robot-Code 和 X-Device-Id
- 错误统一返回 code、message、detail；pad 只展示 message 的中文映射

## 一、健康、认证、设备

### 1. GET /healthz

- 地址：http://{robotIp}:8080/healthz
- 用途：判断机器人是否存活，是连接页唯一放行条件；2 秒超时
- 入参：无
- 返回：ok、robotCode、model、version、serverTime、bootId
- 备注：不鉴权；ok=true 才写本地 IP、才进登录

### 2. POST /api/v1/auth/login

- 用途：云端或本地登录，拿 pad token、用户、角色、权限
- 入参：mode（cloud/local）、username、password、role（本地登录时）
- 返回：token、expiresAt、user（id/name/role）、permissions
- 备注：云端离线时返回 OFFLINE，pad 提示改用本地登录

### 3. POST /api/v1/auth/logout

- 用途：注销当前 token
- 入参：无
- 返回：ok
- 备注：pad 同时清内存 token，回登录页

### 4. POST /api/v1/device/register

- 用途：pad 注册，拿 deviceId，用于心跳和事件
- 入参：padId、appVersion、os
- 返回：deviceId
- 备注：登录后调用；机器人汇总后同步云端

### 5. POST /api/v1/device/heartbeat

- 用途：5 秒一次上报 pad 状态，机器人转发云端
- 入参：deviceId、mode、collecting、collectId、taskId、userId、appTime
- 返回：ok、serverTime
- 备注：断网只保留最近一条，恢复后补发，不补历史

### 6. GET /api/v1/device/credentials

- 用途：取 robotCode、云端地址、短期 cloudToken，供 pad 在线拉任务
- 入参：无
- 返回：robotCode、cloudBaseUrl、cloudToken、expiresAt
- 备注：cloudToken 只用于任务目录，10 分钟过期，不给文件/控制权限

## 二、首屏、状态、模式

### 7. GET /api/v1/bootstrap

- 用途：首屏和断线重连的聚合接口，减少并发请求
- 入参：无
- 返回：robot、mode、status、collect、serverTime
- 备注：WS 重连 lastSeq 过期时也调它做全量对齐

### 8. GET /api/v1/status

- 用途：硬件状态、FSM、网络、存储
- 入参：无
- 返回：robot、gripper、upperArm、chassis、vr、camHead、camPanorama、camLeft、camRight、storage、fsm、network
- 备注：1 秒刷新；storage.remainGb 小于 50 黄色提示，小于 20 禁止开始采集

### 9. GET /api/v1/mode

- 用途：查当前模式，重连后对齐
- 入参：无
- 返回：mode（collect/review/idle）、since
- 备注：pad 不以本地状态为准

### 10. POST /api/v1/mode

- 用途：切采集/回看/空闲，机器人负责启动或停止采集服务
- 入参：mode
- 返回：mode、services
- 备注：采集中禁止切换；5 秒超时；成功后发 mode.changed

## 三、任务

### 11. GET /api/v1/tasks

- 用途：机器人缓存的任务列表，离线时用
- 入参：无
- 返回：items（id、name、done、total、size、state、robot、model、brief、persons、updatedAt）
- 备注：pad 在线优先走云端，失败退回这里

### 12. GET /api/v1/tasks/{id}

- 用途：单个任务详情，已采页/采集页补数据
- 入参：taskId
- 返回：任务完整配置、brief、persons、done/total
- 备注：切换任务前可用它刷新当前任务

### 13. POST /api/v1/tasks/refresh

- 用途：让机器人去云端同步一次任务
- 入参：无
- 返回：同步结果、任务列表
- 备注：有公网时调用；成功后发 task.updated

### 14. POST /api/v1/tasks/{id}/ensure

- 用途：确保机器人已有该任务配置，没有就下载
- 入参：taskId
- 返回：ready、downloaded
- 备注：进入采集前调用，防止 pad 从云端看到任务、机器人却没有

### 15. POST /api/v1/tasks/config

- 用途：云端向机器人下发任务配置
- 入参：任务完整配置
- 返回：ok
- 备注：云端/机器人内部接口，pad 不调用；机器人更新后发 task.updated

### 16. GET https://{cloudBaseUrl}/api/v1/tasks

- 用途：pad 在线时直接拉云端任务目录
- 入参：robotCode（查询参数）
- 返回：items，结构同本地任务
- 备注：带 cloudToken；失败/离线回退 GET /tasks

## 四、采集

### 17. POST /api/v1/collect/select

- 用途：切换任务/人员，通知机器人
- 入参：taskId、personId
- 返回：当前任务、人员、会话状态
- 备注：采集中返回 409 COLLECT_BUSY；成功后 pad 更新下拉

### 18. GET /api/v1/collect/current

- 用途：查当前采集会话，断线/重启后恢复状态
- 入参：无
- 返回：collecting、collectId、startedAt、taskId、personId、lastTake
- 备注：collecting=false 就是空闲；pad 不自己判断是否在录

### 19. POST /api/v1/collect/start

- 用途：开始采集，机器人开始录制
- 入参：taskId、personId
- 返回：collectId、startedAt
- 备注：校验模式、存储、设备；成功后发 collect.started

### 20. POST /api/v1/collect/stop

- 用途：停止并保存，返回新采集条和任务进度
- 入参：collectId
- 返回：take、task（done/total）
- 备注：成功后发 collect.stopped 和 take.created

### 21. POST /api/v1/collect/{id}/drop

- 用途：作废当前采集，不保存、不计数
- 入参：collectId
- 返回：ok
- 备注：pad 弹确认；成功后回空闲

## 五、采集条

### 22. GET /api/v1/takes

- 用途：采集条分页/过滤，采集页、已采页、查看数据共用
- 入参：taskId、personId、valid、status、page、pageSize、sort
- 返回：items、total、page、pageSize
- 备注：服务端分页；sort 默认 capturedAt:desc；采集页 2 秒轮询当前页

### 23. GET /api/v1/takes/{id}

- 用途：单条采集条详情
- 入参：takeId
- 返回：take 完整字段（任务、人员、时间、时长、大小、有效、状态、filePath）
- 备注：回看页刷新单条状态时用

### 24. PATCH /api/v1/takes/{id}

- 用途：标记有效/无效
- 入参：valid
- 返回：更新后的 take
- 备注：默认有效；成功后发 take.updated

### 25. GET /api/v1/takes/{id}/source

- 用途：拿回放地址和文件信息
- 入参：takeId
- 返回：url、sizeBytes、durationMs
- 备注：url 指向 Caddy；pad 用 HTTP Range 按需读，不整包下载

## 六、进程、日志

### 26. GET /api/v1/processes

- 用途：进程列表和运行状态
- 入参：无
- 返回：name、pid、running、startedAt、version
- 备注：设置页 2 秒刷新；也可由 process.changed 推送

### 27. POST /api/v1/processes/{name}/start

- 用途：启动指定进程
- 入参：进程名
- 返回：最新进程状态
- 备注：采集中/查看数据页禁用

### 28. POST /api/v1/processes/{name}/stop

- 用途：停止指定进程
- 入参：进程名
- 返回：最新进程状态
- 备注：需要二次确认

### 29. POST /api/v1/processes/{name}/restart

- 用途：重启指定进程
- 入参：进程名
- 返回：最新进程状态
- 备注：需要二次确认

### 30. GET /api/v1/logs

- 用途：拉历史日志
- 入参：type（system/collect/device/error）、range、limit、cursor
- 返回：日志条目（ts、level、source、message）、nextCursor
- 备注：打开日志页先拉最近 200 条

### 31. GET /api/v1/logs/download

- 用途：下载日志文件
- 入参：type、from、to
- 返回：文件流
- 备注：pad 存到本地下载目录并提示路径

### 32. WS /api/v1/ws/logs

- 用途：实时日志流，替代轮询
- 入参：订阅消息 name、type、range
- 返回：ts、level、source、message
- 备注：断线重连后从最后一条时间戳续订

## 七、手动控制

### 33. GET /api/v1/control/state

- 用途：底盘/双臂连接状态、当前点位
- 入参：无
- 返回：chassis、arm、pose、updatedAt
- 备注：手动控制弹层打开时刷新

### 34. POST /api/v1/control/connect

- 用途：一键连接底盘、双臂
- 入参：无
- 返回：各服务连接状态
- 备注：失败时按钮保持禁用，提示具体哪个服务

### 35. POST /api/v1/control/arm/home

- 用途：双臂回 home/pack/standby
- 入参：pose、seq
- 返回：accepted、targetPose
- 备注：执行前 pad 弹确认框；采集中返回 409

### 36. POST /api/v1/control/chassis/move

- 用途：底盘移动，按住方向键时 10Hz 持续发
- 入参：direction、speed、seq
- 返回：accepted、seq
- 备注：direction 取 forward/back/left/right/rotate_left/rotate_right；后端 300ms 没新命令自动停

### 37. POST /api/v1/control/chassis/stop

- 用途：底盘停止，松开/离开按钮时发
- 入参：seq
- 返回：ok
- 备注：不能只依赖 pad 的 pointerup，后端必须超时停车

## 八、事件 WebSocket

### 38. WS /api/v1/ws?lastSeq=

- 用途：接收模式、状态、采集、采集条、任务、设备、进程、控制事件
- 入参：lastSeq（重连时带最后收到的事件序号）
- 返回：type、seq、ts、data
- 备注：服务端保留 5 分钟事件；超过则 pad 调 /bootstrap 全量对齐

事件类型：

- hello：建连成功，返回 serverTime、bootId
- mode.changed：模式变化
- status.updated：硬件状态/存储/网络变化
- fsm.changed：FSM 状态变化
- collect.started：开始录制，pad 开始计时
- collect.stopped：停止并保存，pad 停表、刷新列表
- collect.aborted：设备异常/机器人重启导致采集中断
- take.created：新采集条生成，刷新列表、会话计数 +1
- take.updated：采集条有效/无效变化
- task.updated：任务配置/进度变化
- device.changed：单个设备在线状态变化
- process.changed：进程启动/停止/重启
- control.state：控制状态/位姿变化
- error：服务端主动错误通知

## 九、文件通道

### 39. GET http://{robotIp}:8090{filePath}

- 用途：Caddy 提供 MCAP 文件，回放按 chunk 读取
- 入参：Range、If-Range
- 返回：206 Partial Content、Content-Range、文件字节
- 备注：必须支持 HEAD/Range，不能返回 200；不能 gzip；公网暴露时用 5 分钟签名 URL

## 十、几个约定

- /takes 全部服务端分页，pad 不拉全量再自己分页。
- 采集页条数：机器人 done/total 为准，pad 只额外显示“本次 N 条”。
- 采集状态以 /collect/current 和 collect.* 事件为准，pad 不本地猜。
- 控制命令全部带 seq，服务端去重并做超时停车。
- 所有时间戳统一毫秒；MCAP 内部纳秒由回放器转换。
- 云端任务失败/离线时，pad 用 GET /tasks 的机器人缓存，并显示“当前离线”。
