# EchoClip 定时任务设计

- 状态：已实现
- 实现版本：0.6.0
- 设计日期：2026-08-31
- 实现日期：2026-09-01
- 适用范围：Windows 客户端、Android 客户端、Flutter 公共界面、Rust Core
- 不在范围：服务端、WebUI、上传协议、多用户服务端设计

## 0. 实现落点

0.6.0 已按本文档完成 V1 落地：

- `echoclip_core::scheduler` 是任务模型、验证、动作排序、迟到策略、修订号、持久化、恢复和执行历史的唯一权威实现；
- Windows FFI 在托盘进程中维持独立调度线程，Flutter 窗口关闭不影响任务等待和执行；
- Android JNI 复用同一个 Core 调度器实例，`AlarmManager`、开机 Receiver 和前台服务只负责系统唤醒与平台效果执行；
- Flutter 原“音频处理”导航及页面已替换为定时任务列表、独立二级编辑页和执行历史；页面倒计时只做本地显示插值；
- 通用增益/处理副本流程及 processing 专用缓存代码已移除；FFmpeg、MP3 导出和录音库中的单文件 WAV 转 MP3 保留；
- 定时上传只切换现有全局实时上传状态，不读取或补传启用前的滚动缓存；
- 服务端、WebUI、上传协议、默认端口 `32580/32581` 和单实例单客户端部署模型未改动。

本文件同时作为 0.6.0 的架构约束与后续回归基线；“后续候选”章节仍不属于 V1。

## 1. 背景

EchoClip 当前提供持续录音、滚动缓存、保存最近录音和实时上传能力。下一阶段需要增加定时任务，让用户按倒计时或指定时间点执行以下操作：

- 开启录音；
- 关闭录音；
- 保存最近指定时长的录音；
- 开启、关闭或保持当前实时上传状态。

定时任务将替换现有“音频处理”模块及其导航位置。独立的增益处理、生成处理副本等功能退出产品，但 FFmpeg 依赖和 MP3 能力必须保留；已有 WAV 文件仍应能够从“已保存录音”上下文转换为 MP3。

本设计坚持现有架构原则：业务规则、状态机、任务持久化、执行顺序和故障恢复均由 echoclip_core 负责。Flutter、Kotlin、JNI、Windows FFI 和操作系统集成代码只承担界面、唤醒、权限、音频设备和文件系统等平台能力。

## 2. 设计结论

本期采用以下固定方案：

1. 定时任务是客户端本地能力，不修改 echoclip_server、WebUI、Docker 配置或同步协议。
2. V1 只支持一次性任务，支持“倒计时”和“指定时间点”两种触发方式；周期任务不在本期范围。
3. 每个任务可组合录音动作、保存动作和上传状态动作，Rust Core 按固定顺序执行并记录每一步结果。
4. “上传”指切换现有的实时上传开关，只影响切换后新产生的 PCM，不上传开启前的历史缓存，也不上传已保存文件。
5. 任务不是跨动作事务。一个平台动作失败时，其余可安全执行的动作继续执行，最终结果可为“部分成功”。
6. Flutter 不使用 Timer 决定任务是否到期；Android 和 Windows 也不解释任务业务规则。平台只唤醒 Rust Core，并执行 Rust Core 返回的平台效果请求。
7. Android 的精确闹钟权限和后台麦克风限制必须在界面中显式展示。不能满足后台启动条件时，任务记录为“平台阻止”，并通知用户，不得显示为成功。
8. Windows V1 要求 EchoClip 托盘进程仍在运行。应用完全退出后不承诺执行任务；Windows 服务或任务计划程序集成不在本期范围。
9. 原“音频处理”页面、增益处理和处理副本流程移除；FFmpeg 二进制、构建脚本、许可证、MP3 保存和 WAV 转 MP3 能力保留。
10. 用户已有录音、录音缓存、上传配置和密钥不得因迁移被删除或重置。

## 3. 目标与非目标

### 3.1 目标

- 用户可创建、编辑、启用、停用和删除一次性定时任务。
- 用户可查看下次执行时间、预计精度、动作摘要和最近执行结果。
- 任务在应用 UI 重启后仍然存在。
- Windows 托盘进程运行时，任务可在窗口关闭、最小化或系统睡眠恢复后继续执行。
- Android 在系统允许的条件下唤醒任务；涉及后台开启录音时使用明确的“任务待命”前台服务。
- 所有任务验证、到期判断、迟到策略、动作排序、幂等和历史记录由 Rust Core 处理。
- 定时保存复用现有滚动缓存和异步导出能力。
- 定时上传复用现有实时同步开关和重连机制，保持“开启之后才上传”的边界。
- 删除独立音频处理模块，同时保留用户可发现的 WAV 转 MP3 入口。

### 3.2 非目标

- 周期任务、Cron 表达式、工作日规则、节假日规则。
- 云端任务同步或多设备同步。
- 服务端发起或管理客户端任务。
- 应用被用户强制停止、设备断电或系统禁止后台运行时的绝对执行保证。
- Windows 系统服务、登录前任务或操作系统任务计划程序。
- 精确保存“计划时间点之前”的历史片段。V1 的保存截止点是任务实际执行时刻。
- 上传已保存文件、补传开启上传之前的缓存、服务端文件管理。
- 音频增益、滤镜、降噪、任意格式互转等通用音频处理功能。

## 4. 用户功能定义

### 4.1 触发方式

倒计时：

- 用户通过时、分、秒轮盘选择时长，不使用自由数字输入。
- 可选范围为 00:00:01 至 23:59:59；00:00:00 不允许保存。
- 创建并启用时，Rust Core 计算绝对到期时间。
- 进程存活期间同时使用单调时钟判断，避免系统时间小幅调整造成重复或提前执行。
- 重启恢复时使用已持久化的 UTC 到期时间。
- 停用后重新启用倒计时任务，倒计时从重新启用时重新开始。
- 修改倒计时时长会生成新任务修订号并重新计算到期时间。

指定时间点：

- 用户通过日历选择本地日期，并复用倒计时的时、分、秒轮盘选择具体时间。
- 创建时记录时区标识、当时 UTC 偏移以及解析后的固定 UTC 到期时间。
- 后续系统时区变化不静默移动任务；界面显示“按创建时的时区执行”，用户编辑后才重新解析。
- 夏令时导致本地时间不存在或存在两个候选时间时，必须让用户明确选择或修改，不能由平台适配层猜测。
- 已过去的时间点不能作为新任务启用。

### 4.2 可配置动作

界面提供结构化字段，不直接暴露任意动作脚本：

- 录音：保持不变、开启、关闭；
- 保存：不保存，或保存最近 N 秒/分钟/小时；
- 保存格式：MP3 或 WAV；
- MP3 码率：复用现有导出选项；
- 上传：保持不变、开启、关闭；
- 缓存不足时：默认保存现有可用部分，并在历史中标记“部分时长”。

Rust Core 将表单标准化为有序动作列表：

1. 修改上传状态；
2. 开启或关闭录音；
3. 保存最近指定时长。

固定顺序确保“开启上传并开始录音”时，第一批新采样即可进入实时上传链路；“关闭上传并停止录音”时，不会在停止过程继续扩展上传范围。

### 4.3 上传语义

定时任务中的上传选项只操作现有的全局实时上传状态：

- “开启”从动作成功后的新 PCM 开始上传；
- “关闭”立即停止接收新的待上传 PCM，并丢弃尚未发送成功的重试队列；
- “保持不变”不修改当前状态；
- 不扫描或补传本地滚动缓存；
- 不上传由“保存最近片段”产生的 WAV/MP3 文件；
- 断线重试只覆盖上传开启边界之后、且上传开关仍保持开启时进入同步队列的 PCM；
- 网络暂时不可达不阻止本地录音或保存动作；
- 缺少服务器地址、端口或密钥时，创建包含“开启上传”的任务应提示配置不完整；若配置后来被移除，执行记录为部分失败。

这与当前单客户端、单服务端实例的简化连接模型保持一致。

### 4.4 动作冲突和幂等

- 已经录音时执行“开启录音”：成功，无操作。
- 已经停止时执行“关闭录音”：成功，无操作。
- 上传状态已经相同时再次设置：成功，无操作。
- 缓存为空时保存：失败，并保留清晰错误码。
- 缓存短于请求时长且允许部分保存：保存全部可用内容，动作结果为部分时长成功。
- 同一任务修订号的同一次 execution_id 不得导出两个文件。
- V1 不允许同一任务同时配置“开启录音”和“关闭录音”。
- 任务执行期间的手动操作与任务动作通过同一 Rust Core 命令队列串行化，不允许 Flutter 或平台层自行抢占。

### 4.5 执行迟到

操作系统唤醒是尽力而为。平台唤醒后，Rust Core 计算 late_by_ms，并应用动作感知的默认策略：

| 动作 | 默认迟到策略 |
| --- | --- |
| 关闭录音 | 无论迟到多久都立即执行 |
| 关闭上传 | 无论迟到多久都立即执行 |
| 开启录音 | 迟到不超过 5 分钟则执行，否则标记错过 |
| 开启上传 | 迟到不超过 5 分钟则执行，否则标记错过 |
| 保存最近片段 | 迟到不超过 5 分钟则执行，否则标记错过 |

关闭类动作优先保证资源和隐私状态收敛。开启和保存类动作如果过度迟到，盲目执行可能产生与用户预期完全不同的录音，因此默认放弃。V1 不在 UI 中暴露高级迟到策略。

V1 的“保存最近 N 秒”以实际执行时刻为片段终点。执行历史必须显示计划时间、实际时间和迟到量，避免用户误以为保存内容精确截止于计划时间。

## 5. 总体架构

数据与控制流如下：

    Flutter 定时任务页面
              |
              | FFI/JNI：CRUD、状态、历史
              v
    echoclip_core::scheduler
      - 数据模型与验证
      - 任务状态机
      - 到期与迟到判断
      - 动作排序与幂等
      - 持久化与恢复
      - 执行历史
              |
              | EffectRequest / EffectResult
              v
    平台能力分发器
      - Windows 音频捕获与进程唤醒
      - Android AlarmManager、前台服务、通知
      - SAF/文件选择、FFmpeg 路径
              |
              v
    RecorderWorker / SyncClient / Export

平台适配层可以通知“时间到了”，但只有 Rust Core 可以判定哪个任务到期、是否迟到、执行哪些动作以及最终状态。

### 5.1 Rust Core 职责

在 crates/echoclip_core 中新增 scheduler 模块，负责：

- ScheduledTask、Trigger、ScheduledAction 和 ExecutionRecord 模型；
- 输入验证、规范化和任务修订号；
- SchedulerEngine 状态机；
- Clock 抽象和下一唤醒时间计算；
- 任务及执行历史持久化；
- 到期任务选择、迟到策略和去重；
- 动作顺序和部分成功语义；
- 与 RecorderWorker 保存队列的集成；
- 与实时上传控制器的集成；
- 崩溃恢复和执行记录对账；
- 稳定、可测试的错误码；
- 向适配层产生最少的平台 EffectRequest。

### 5.2 平台适配层职责

平台层只承担无法跨平台实现的能力：

- 安排操作系统下一次唤醒；
- 将唤醒事件转发给 Rust Core；
- 申请和报告权限；
- 启动、停止操作系统音频捕获；
- 维持 Android 前台服务和通知；
- 将导出结果复制到 Android SAF 目标；
- 提供用户选择的录音目录；
- 提供随包 FFmpeg 可执行文件路径；
- 将每个 EffectRequest 的结果按 execution_id 和 action_id 回报 Rust Core。

平台层不得：

- 在 Dart、Kotlin 或 C++ 中保存另一份权威任务列表；
- 自行判断任务是否到期或应用迟到策略；
- 自行重排、跳过或重试业务动作；
- 用 Flutter Timer、Android Handler 或 Windows UI Timer 执行核心调度；
- 自行决定缓存不足、上传边界或导出重复处理；
- 在 SharedPreferences、DataStore 或注册表中保存与 Rust Core 不一致的任务业务数据。

### 5.3 Flutter 职责

Flutter 只负责：

- 任务列表、创建编辑、删除确认和历史展示；
- 输入格式化与即时提示；
- 展示 Rust Core 返回的验证错误、精度和平台能力；
- 展示倒计时动画。该动画只影响显示，不参与执行；
- 请求系统权限或引导用户进入设置；
- 订阅任务状态变化并刷新界面。

## 6. 核心数据模型

建议采用以下逻辑模型；实际 Rust 命名可在实现中微调，但字段语义必须保持：

    ScheduledTask
      schema_version: u32
      id: TaskId
      revision: u64
      name: String
      enabled: bool
      trigger: Trigger
      actions: Vec<ScheduledAction>
      state: TaskState
      created_at_utc_ms: i64
      updated_at_utc_ms: i64
      next_due_utc_ms: Option<i64>

    Trigger
      Countdown
        created_at_utc_ms: i64
        delay_ms: u64
        due_at_utc_ms: i64
      TimePoint
        local_datetime: String
        timezone_id: String
        utc_offset_minutes: i32
        due_at_utc_ms: i64

    ScheduledAction
      SetUploadEnabled
        enabled: bool
      StartRecording
      StopRecording
      SaveRecent
        duration_ms: u64
        format: Mp3 | Wav
        mp3_bitrate_kbps: Option<u16>
        allow_partial: bool

    TaskState
      Pending | Armed | Running | Succeeded
      PartiallySucceeded | Failed | Missed
      Disabled | Canceled

    ExecutionRecord
      execution_id: ExecutionId
      task_id: TaskId
      task_revision: u64
      scheduled_for_utc_ms: i64
      started_at_utc_ms: i64
      finished_at_utc_ms: Option<i64>
      late_by_ms: u64
      action_results: Vec<ActionResult>
      result: ExecutionResult
      error_code: Option<String>

补充约束：

- task_id 和 execution_id 使用随机 128 位标识。
- 每个任务最多 8 个标准化动作。
- 默认最多保存 128 个任务和最近 200 条执行记录。
- 任务名称按 Unicode 字符数限制，并在 Rust Core 统一验证。
- 保存时长不得超过当前录音缓存上限，也不得小于现有导出最小时长。
- 任务文件不保存服务器地址、端口、上传密钥或录音目录；它只保存动作意图。
- UI 收到的数据是 Rust Core 的只读快照，不允许直接修改内存对象。

## 7. 状态机与执行流程

### 7.1 任务生命周期

    创建/修改
        -> Pending
        -> Armed
        -> Running
        -> Succeeded | PartiallySucceeded | Failed | Missed

其他转换：

- Armed -> Disabled：用户停用。
- Disabled -> Armed：重新启用；倒计时重新计算，时间点保持原 UTC 到期时间。
- Pending/Armed -> Canceled：用户删除，历史可保留。
- Running -> Failed/PartiallySucceeded：平台效果失败或进程恢复对账。
- 一次性任务结束后不自动重新 Armed。

### 7.2 到期流程

1. 平台唤醒或进程内部等待器到期。
2. 平台调用 scheduler_tick(now)。
3. Rust Core 读取自己的持久化快照并选出到期任务。
4. Rust Core 生成 execution_id，写入“开始执行”日志并原子落盘。
5. Rust Core 逐个产生 EffectRequest，或直接执行纯 Core 动作。
6. 平台执行效果并返回结构化 EffectResult。
7. Rust Core 写入每个动作结果，继续可安全执行的后续动作。
8. Rust Core计算最终状态并原子提交。
9. Rust Core 返回新的 next_wakeup。
10. 平台只更新一个下一次操作系统唤醒。

### 7.3 非事务动作

录音、上传和文件导出无法组成真正的跨平台事务，因此采用“顺序执行、逐步记账、尽力继续”：

- 上传开启失败不阻止本地开启录音或保存；
- 本地录音开启失败不伪造上传成功，但上传状态动作本身可成功；
- 保存失败不回滚此前成功的停止录音；
- 最终结果包含每一步成功、无操作、部分成功、失败或平台阻止；
- UI 不用单一绿色状态掩盖部分失败。

## 8. 持久化、恢复与去重

### 8.1 存储

Rust Core 接收平台提供的 core_data_dir，并在其 scheduler 子目录保存：

- tasks-v1.json：任务权威快照；
- executions-v1.jsonl 或等价日志：执行历史和进行中执行；
- quarantine：损坏文件隔离信息。

写入流程采用同目录临时文件、刷新数据、原子替换。具体文件格式可改为二进制，但必须保留 schema_version 和迁移测试。

若任务文件损坏：

- 将原文件移动到隔离名称；
- 禁止自动执行无法验证的任务；
- 向 UI 返回明确恢复错误；
- 不静默创建空任务列表覆盖原文件；
- 不影响录音缓存、保存录音或上传配置。

### 8.2 崩溃恢复

进程启动时 Rust Core 执行 reconcile：

- 读取未完成 ExecutionRecord；
- 获取当前录音、上传和导出运行快照；
- 幂等动作按当前状态完成对账；
- 已开始的保存动作使用 execution_id 查询导出记录；
- 无法证明成功的动作标记 Interrupted 或 Failed，不盲目重复导出；
- 对账完成后再计算下一次唤醒。

导出文件使用 execution_id 参与暂存名或元数据，确保崩溃后不会生成重复文件。Android SAF 复制也必须回报 execution_id 映射；平台只保存复制结果索引，不保存任务规则。

## 9. Core API 与跨语言边界

Rust 内部建议接口：

    Scheduler::open(data_dir, clock, limits)
    Scheduler::create(command)
    Scheduler::update(task_id, expected_revision, command)
    Scheduler::delete(task_id)
    Scheduler::set_enabled(task_id, expected_revision, enabled)
    Scheduler::list()
    Scheduler::history(task_id, page)
    Scheduler::next_wakeup()
    Scheduler::tick(now)
    Scheduler::complete_effect(execution_id, action_id, result)
    Scheduler::reconcile(runtime_snapshot)

Clock 必须可注入，以便测试倒计时、系统时间跳变、睡眠恢复和夏令时边界。

FFI/JNI 建议使用版本化 JSON DTO，减少一次性增加大量 ABI 函数，但所有 JSON 都由 Rust Core 解析和验证。对外能力可包括：

- schedule_capabilities_json；
- schedule_list_json；
- schedule_upsert_json；
- schedule_delete；
- schedule_set_enabled；
- schedule_history_json；
- scheduler_tick_json；
- scheduler_next_wakeup_json；
- scheduler_complete_effect_json。

DTO 必须带 api_version；未知动作、未知枚举和超出范围的时长由 Rust Core 拒绝。平台只按已知 EffectKind 分发，不解析业务组合。

## 10. 与录音、保存和上传模块的集成

### 10.1 录音

所有手动和定时录音操作进入同一个 Rust Core 命令队列。Core 维护权威的录音期望状态和状态转换，平台仅报告音频设备启动或停止结果。

Windows 的音频捕获实现在 Rust 平台 crate 中，可由调度器效果分发直接调用。Android 的 AudioRecord 生命周期必须由 Kotlin 前台服务执行，但 Rust Core 决定何时请求启动和停止。

### 10.2 保存最近片段

SaveRecent 复用现有 RecorderWorker 和异步导出：

- 从全局滚动缓存生成一个保存任务；
- 不创建独立定时任务缓存；
- 不阻塞采集线程；
- 缓存不足规则由 Rust Core 处理；
- 文件名生成、去重和导出结果进入执行历史；
- Android 目标复制失败时保留 Core 暂存结果，并允许用户重试复制，不重复编码。

### 10.3 上传

SetUploadEnabled 复用 echoclip_sync_client 的全局实时上传状态机：

- 开启动作建立新的上传边界；
- 只有边界后的 PCM 能进入同步队列；
- 关闭动作停止后续队列输入并丢弃未完成的重试队列；
- 定时任务不创建第二套连接配置或第二个上传队列；
- Core 记录“配置不完整”“认证失败”“网络不可达”等结构化结果；
- 服务端仍把收到的所有会话写入同一个全局滚动缓存。

## 11. Windows 平台方案

### 11.1 唤醒机制

crates/echoclip_windows_ffi 中增加进程内调度等待器：

- 从 Rust Core 获取 next_wakeup；
- 使用专用线程和条件变量等待；
- 任务增删改、系统恢复和时钟变化时重新计算；
- 到期时调用 Rust Core tick；
- 不依赖 Flutter 窗口或 Dart isolate；
- 托盘窗口隐藏、关闭前端窗口不停止等待器；
- 通过全局退出命令真正结束进程时停止等待器。

### 11.2 运行保证

- EchoClip 托盘进程运行：支持。
- 前端窗口关闭但托盘仍运行：支持。
- 系统睡眠后恢复：恢复时立即 tick，并应用迟到策略。
- 用户完全退出 EchoClip：不执行。
- 用户注销、机器关机：不执行，重启后对已过期任务应用迟到策略。
- Windows 系统服务和任务计划程序：未来能力。

平台适配层不得把任务复制到 Windows Task Scheduler，也不得在注册表维护一套任务状态。

## 12. Android 平台方案

### 12.1 AlarmManager 只负责唤醒

新增轻量平台组件：

- ScheduleAlarmCoordinator：根据 Rust Core 返回的 next_wakeup 安排或取消一个系统闹钟；
- ScheduleAlarmReceiver：收到闹钟后启动允许的执行入口并调用 Rust Core tick；
- ScheduleBootReceiver：开机后加载 Rust Core，获取 next_wakeup 并重新安排；
- ReplayForegroundService：为需要后台麦克风的已武装任务维持“任务待命”状态和通知。

BroadcastReceiver 不读取或解释任务动作，不自行决定哪一个任务执行。PendingIntent 只携带唤醒世代号或 token，用于丢弃旧闹钟。

### 12.2 精确与近似模式

Android 12 及以上的精确闹钟需要特殊访问。V1 使用 SCHEDULE_EXACT_ALARM，并在真正创建时间敏感任务时向用户解释并引导授权；不使用适用范围更窄、应用商店限制更强的 USE_EXACT_ALARM。

- 已授权且系统允许：使用精确闹钟，UI 显示“精确”。
- 未授权：使用非精确闹钟，UI 显示“近似”，并说明可能明显延迟。
- 每次调度前调用 canScheduleExactAlarms。
- 权限变化后重新读取 Rust Core 的 next_wakeup 并重排。
- Doze、电池优化和厂商后台策略造成的延迟进入 late_by_ms，不由 Kotlin 改写。

### 12.3 后台开启录音

精确闹钟并不自动消除麦克风 while-in-use 权限限制。为了让“定时开启录音”在 Android 上尽可能可靠：

- 用户启用包含 StartRecording 的任务时，Activity 在前台启动 ReplayForegroundService 的“任务待命”模式；
- 服务显示持续通知，持有调度运行环境，但在到期前不采集音频；
- 到期后 Rust Core 请求服务启动 AudioRecord；
- 没有麦克风权限、前台服务未存活、应用被强制停止或系统禁止后台麦克风时，返回 PLATFORM_MICROPHONE_BLOCKED；
- 系统通知引导用户打开应用恢复，不伪装成功；
- 用户停用最后一个需要后台启动录音的任务后，可退出待命模式；
- StopRecording、SaveRecent 和上传状态动作仍按平台实际能力执行。

该限制必须在任务保存前展示。用户强制停止应用后，Android 不保证任何定时任务运行。

### 12.4 清单和权限

实现阶段预计调整：

- AndroidManifest.xml 的闹钟、开机广播和前台服务声明；
- 精确闹钟特殊访问流程；
- Android 13+ 通知权限提示；
- 麦克风前台服务类型与现有权限；
- BootReceiver 导出规则和显式 Intent；
- ProGuard/R8 和测试构建配置。

权限请求属于平台层，但“此任务是否可武装”由 Rust Core 根据平台 CapabilitySnapshot 和任务动作统一判断。

## 13. Flutter 界面设计

### 13.1 导航替换

原 AppSection.processing 和“音频处理”导航项替换为 AppSection.scheduledTasks：

- 保持原导航位置；
- 图标改为日程或闹钟；
- 桌面和 Android 使用同一信息架构；
- 原 processing_page.dart 在迁移完成后删除；
- 不保留空壳或跳转到旧处理页面。

### 13.2 页面结构

任务列表页：

- 下一个任务和剩余时间；
- 每项显示名称、计划时间和动作摘要；
- 启用开关；
- 最近结果和迟到量；
- 新建任务按钮；
- 执行历史入口；
- 仅在 Android 缺少精确闹钟权限时显示操作入口；不常驻显示调度精度和录音目录状态说明。

创建/编辑页：

- 使用带返回入口的独立二级页面，不使用弹窗或列表内卡片表单；
- 名称可留空，由 Core 使用界面语言的前缀生成不重名的编号名称；
- 倒计时使用 0–23 时、0–59 分、0–59 秒轮盘；
- 指定时间点使用日期日历，并复用同一套时、分、秒轮盘；
- 录音动作使用独立开关，开启/关闭选项常态显示，未启用配置时置灰；
- 上传动作使用独立开关，开启/关闭选项常态显示，未启用配置时置灰；
- 保存最近片段使用独立开关，时长、格式、码率和部分保存设置常态显示，未启用时置灰；
- MP3/WAV 和 MP3 码率；
- 缓存不足时是否保存可用部分；
- 保存后是否启用任务。

历史页：

- 计划时间和实际时间；
- 每个动作的结果；
- 保存文件入口；
- 错误码及可操作建议；
- 部分成功和错过状态不可只用颜色区分。

### 13.3 任务预设与时间输入（2026-09-06）

- Core 在原 `state-v1.json` 中以新增 `presets` 字段持久化最多 9 个预设；旧文件缺少该字段时按空列表加载，不改动已有任务和历史。
- 编辑页可单独“保存预设”；预设保存触发方式、录音/上传/保存动作及启用状态，不创建任务、不武装、不录音。
- 列表显示预设及数量，点击进入已填好配置的新建页；任务 ID、修订号和执行历史不从预设复制。倒计时从新任务保存时重新计算。
- 指定时间预设保留原日期和时间，用户创建任务时必须确认或修改已过去的时间。
- 预设可删除以释放名额，删除不影响已创建任务。数量上限和名称生成均由 Core 统一负责。
- Windows FFI 与 Android JNI 共用 `editor_command_json`；现有 upsert JSON 通道继续接受任务输入，另接受 `save_preset`（携带 `task`）和 `delete_preset`（携带 `id`）命令。
- 时间轮盘标题使用独立行，冒号与数字选中行共用垂直中心；轮盘支持鼠标拖动以及原有触摸、滚轮输入。

### 13.4 UI 实时性

倒计时显示可用浏览器/Flutter 本地插值每秒更新，但它只基于 Rust Core 返回的 next_due 快照。应用恢复、任务变化或平台状态变化时重新读取快照。即使显示动画暂停，Core 和平台唤醒仍独立工作。

## 14. 舍弃音频处理模块后的 FFmpeg 方案

### 14.1 移除内容

- 独立“音频处理”页面；
- 增益调节 UI 和增益处理参数；
- 选中录音后生成任意“处理副本”的流程；
- processing 专用缓存大小和清理设置；
- ReplayServiceClient.processRecording 等只服务于通用处理页面的接口；
- Android MainActivity 中处理页专用的增益、格式和码率编排；
- WindowsReplayService 中处理页专用目录和业务逻辑；
- processing 专用本地化和页面测试。

### 14.2 保留内容

- echoclip_core 的 MP3 导出能力；
- ExportOptions 中 MP3 格式和码率；
- Windows 随包 ffmpeg.exe；
- Android 随包 FFmpeg 可执行库；
- scripts/build_windows_ffmpeg.ps1；
- scripts/build_android_ffmpeg.ps1；
- 打包脚本中的 FFmpeg 复制、校验和许可证；
- 第三方许可证和源码获取说明；
- 定时保存和手动保存中的 MP3 输出；
- 已保存 WAV 的 WAV 转 MP3 能力。

### 14.3 WAV 转 MP3 的新入口

WAV 转 MP3 不再作为独立“音频处理模块”，而是放到“已保存录音”的单文件操作菜单：

- 仅当输入是 WAV 时显示“转换为 MP3”；
- 用户可选择已有的有限码率档位；
- 默认保留原 WAV，成功后产生一个 MP3 文件；
- 覆盖或删除原文件必须另行明确操作，转换本身不做；
- 编码核心位于 echoclip_core，例如 transcode_wav_to_mp3；
- Core 负责 WAV 解析、FFmpeg 参数、进度、取消、暂存文件和原子完成；
- 平台只提供 FFmpeg 路径和目标文件传输；
- 定时保存选择 MP3 时应尽可能直接从 PCM 导出 MP3，避免先写 WAV 再转码。

因此“舍弃音频处理模块”不等于移除 FFmpeg，也不等于移除格式转换的必要能力。

## 15. 预计代码改动范围

| 区域 | 预计新增/修改 | 说明 |
| --- | --- | --- |
| crates/echoclip_core | scheduler 模块、持久化、Clock、执行历史、导出对接、WAV 转 MP3 API | 核心业务主体 |
| crates/echoclip_core/src/lib.rs | 导出稳定调度 API | 不暴露内部状态 |
| crates/echoclip_windows_ffi | 调度 DTO、等待线程、效果分发、状态通知 | 不保存任务规则 |
| crates/echoclip_windows_ffi/include | 新增版本化调度接口 | 保持 ABI 可检测 |
| crates/echoclip_android_jni | 调度 DTO、tick、效果回报、能力快照 | 业务验证仍在 Core |
| Android MainActivity/RustAudioCore | UI 桥接、权限入口、效果分发 | 移除处理页业务 |
| Android ReplayForegroundService | 任务待命、录音效果执行、通知 | 不判断任务到期 |
| Android 新增 alarm/boot 组件 | 操作系统唤醒和重排 | 只维护一个 next wake |
| AndroidManifest.xml | 权限、Receiver、Service 声明 | 遵循各版本限制 |
| Flutter models | AppSection.scheduledTasks、DTO | 替换 processing |
| Flutter pages | scheduled_tasks_page.dart、编辑页、历史页 | 新 UI |
| ReplayServiceClient | 调度 CRUD、状态流、WAV 转 MP3 | 删除 processRecording |
| WindowsReplayService/FFI wrapper | 调度接口和状态映射 | 删除 processing 缓存逻辑 |
| l10n | 定时任务、平台能力和错误文案 | 删除 processing 专用文案 |
| tests | Core、FFI/JNI、Flutter、平台集成测试 | 见测试章节 |
| docs | 架构、用户文档、打包说明更新 | 实现阶段同步 |

明确不改：

- crates/echoclip_server；
- 服务端 WebUI；
- crates/echoclip_sync_protocol 的线上协议；
- 默认 Web/上传端口 32580/32581；
- 单服务端实例服务单客户端的部署模型；
- 已有录音缓存格式和录音库数据；
- 上传密钥生成与重置流程。

## 16. 能力快照与错误模型

平台向 Rust Core 提供 CapabilitySnapshot：

- supports_scheduling；
- scheduling_precision：exact / approximate / unavailable；
- exact_alarm_permission；
- microphone_permission；
- notification_permission；
- background_microphone_ready；
- ffmpeg_available；
- recording_destination_ready；
- upload_configured；
- process_resident。

Rust Core 根据任务动作返回可武装、可降级或不可执行。网络当前是否连通只作为状态提示，不作为“开启上传”任务的硬性创建条件。

稳定错误码至少包括：

- INVALID_TRIGGER；
- TIME_POINT_IN_PAST；
- AMBIGUOUS_LOCAL_TIME；
- DURATION_OUT_OF_RANGE；
- ACTION_CONFLICT；
- UPLOAD_NOT_CONFIGURED；
- EXACT_ALARM_NOT_GRANTED；
- PLATFORM_SCHEDULING_UNAVAILABLE；
- PLATFORM_MICROPHONE_BLOCKED；
- MICROPHONE_PERMISSION_DENIED；
- RECORDING_START_FAILED；
- EXPORT_BUFFER_EMPTY；
- EXPORT_PARTIAL_DURATION；
- FFMPEG_UNAVAILABLE；
- EXPORT_FAILED；
- PERSISTENCE_CORRUPT；
- EXECUTION_INTERRUPTED。

显示文案由 Flutter 本地化，历史记录保存稳定错误码和必要的非敏感诊断数据。

## 17. 并发、资源和安全约束

- SchedulerEngine 与 RecorderWorker 通过命令通道交互，不直接锁住采集热路径。
- tick 可以重复调用；同一 task revision 只创建一次 execution_id。
- 保存导出沿用后台工作线程，不在 AlarmReceiver 或 UI 线程编码。
- Android Receiver 必须快速移交工作，不能在 onReceive 中执行长时导出。
- 任务数量、动作数量、名称长度和保存时长必须有限制。
- 任务文件不包含上传密钥。
- 日志不得打印上传密钥、完整本地隐私路径或音频内容。
- 删除任务不删除已生成录音。
- 移除处理模块时不删除旧 processing 输出；仅可清理确认属于临时缓存的文件。
- 更新应用时先迁移任务 schema，迁移失败则保持旧文件并禁止错误执行。

## 18. 测试计划

### 18.1 Rust Core 单元测试

- 倒计时创建、停用、重新启用和修改；
- 指定时间点解析、过去时间、时区变化；
- 夏令时不存在和重复时间；
- 单调时钟与 UTC 时钟跳变；
- 动作规范化顺序；
- 冲突动作拒绝；
- 已录音/已停止/上传状态相同的幂等；
- 缓存不足的部分保存；
- 所有迟到策略边界；
- 重复 tick 去重；
- execution_id 导出去重；
- 每个持久化步骤的崩溃恢复；
- 损坏文件隔离；
- 手动命令和定时命令并发串行化；
- 上传开启前缓存绝不进入同步队列；
- FFmpeg 缺失和编码失败；
- WAV 转 MP3 保留原文件。

### 18.2 Windows 测试

- 窗口打开、隐藏和关闭到托盘时任务执行；
- 从睡眠恢复后的迟到处理；
- 修改任务后等待线程重新唤醒；
- 全局 stop/reboot/退出时等待线程正确收尾；
- 录音设备失败的结构化回报；
- MP3 打包产物包含可用 FFmpeg；
- 旧音频处理入口完全移除。

### 18.3 Android 测试

- 精确闹钟已授权、未授权和撤销；
- 非精确闹钟状态展示；
- 重启后重新安排 next_wakeup；
- Doze 和电池优化下的迟到记录；
- “任务待命”前台服务通知；
- 麦克风权限缺失；
- 后台麦克风被系统阻止；
- 应用强制停止后的明确限制；
- SAF 导出成功、失败和重试去重；
- Android 包仍包含 FFmpeg，WAV 转 MP3 可用。

### 18.4 Flutter 测试

- 原音频处理导航被定时任务替换；
- 两种触发方式表单；
- 动作组合和冲突提示；
- 精确/近似/不可用能力展示；
- 倒计时插值不触发业务执行；
- 部分成功、错过和平台阻止历史；
- WAV 文件上下文中的“转换为 MP3”；
- 中英文文案和小屏布局。

### 18.5 回归测试

- 持续录音和滚动缓存；
- 手动保存预设/自定义范围；
- 录音库播放和删除；
- Windows 托盘关闭流程；
- Android 前台服务生命周期；
- 实时上传开关、断线重连和 429 修复；
- 客户端启动连通性检查和手动测试；
- 服务端单一全局缓存；
- Windows/Android 0.6.0 现有配置迁移。

## 19. 验收场景

1. 创建“10 分钟后开启录音并开启上传”。到期后只上传到期后产生的 PCM，之前 12 小时缓存不会上传。
2. 创建“今天 23:00 关闭录音、关闭上传并保存最近 30 秒为 MP3”。动作按固定顺序执行，历史显示每一步结果。
3. 应用 UI 重启后任务仍存在；Windows 托盘进程仍运行时继续执行。
4. Windows 睡眠超过计划时间 20 分钟后恢复：“关闭录音”立即执行，“开启录音”标记错过。
5. Android 未授予精确闹钟权限时，任务显示“近似”，而不是假装精确。
6. Android 无法从后台访问麦克风时，StartRecording 记录 PLATFORM_MICROPHONE_BLOCKED 并通知用户。
7. 缓存只有 12 秒而任务要求保存 30 秒时，产生 12 秒文件并标记部分时长成功。
8. 任务执行过程中进程崩溃并恢复，不生成第二个相同保存文件。
9. 导航中不再出现“音频处理”，原位置显示“定时任务”。
10. 已保存 WAV 可从录音库转换为 MP3；原 WAV 默认保留。
11. Windows 和 Android 安装包继续携带并校验 FFmpeg。
12. 服务端、WebUI、端口和上传协议无行为变化。

## 20. 实施阶段

### 阶段 A：Core 模型与持久化

- 引入 Clock、任务模型、验证、状态机和存储；
- 完成纯 Rust 单元测试和故障注入；
- 接入 RecorderWorker 与同步状态机；
- 增加窄化的 WAV 转 MP3 Core API。

### 阶段 B：平台桥接

- 扩展 Windows FFI 和进程内等待器；
- 扩展 Android JNI；
- 实现 AlarmManager、Receiver 和任务待命前台服务；
- 建立 CapabilitySnapshot 和 EffectResult。

### 阶段 C：Flutter 和模块迁移

- 替换导航和页面；
- 增加任务编辑、列表和历史；
- 将 WAV 转 MP3 移至录音库上下文；
- 删除 processing 页面和处理页专用接口；
- 更新本地化和测试。

### 阶段 D：集成与发布

- 运行跨平台回归、休眠、重启、权限和崩溃测试；
- 验证 FFmpeg 打包和许可证；
- 更新用户文档、架构文档和发布说明；
- 重新打包 Windows 与 Android 客户端。

每一阶段都应保持现有录音、保存和上传主流程可用。删除旧处理代码只能在新导航、MP3 保存和 WAV 转 MP3 回归通过后进行。

## 21. 风险与后续事项

### 已接受风险

- 移动操作系统不能提供绝对准时保证。
- Android 后台麦克风受权限、前台服务、强制停止和厂商策略影响。
- Windows 完全退出后 V1 不执行定时任务。
- 保存片段以实际执行时刻为终点，不是原计划时刻。

### 后续候选

- 周期任务和工作日规则；
- 自动生成成对的开始/停止任务；
- Windows 系统任务或服务模式；
- Android 更细的电池策略诊断；
- 精确按计划时间点截取历史缓存；
- 任务导入导出；
- 任务执行通知策略；
- 服务端控制客户端任务。

这些候选不应提前进入平台层。未来扩展仍需先进入 Rust Core 的版本化模型和状态机。

## 22. Android 官方约束参考

- Android 闹钟调度：https://developer.android.com/develop/background-work/services/alarms
- 后台启动前台服务限制：https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start
- Android 14 精确闹钟变化：https://developer.android.com/about/versions/14/changes/schedule-exact-alarms

实现时应以目标 SDK 对应的最新官方文档和应用商店政策复核权限方案。平台政策变化只影响 CapabilitySnapshot 和平台实现，不应把业务规则迁移出 Rust Core。
