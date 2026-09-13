# EchoClip 0.6.0 工程交接说明

- 交接日期：2026-09-06
- 接手模型：GPT-6 Astra
- 项目目录：`D:\github\EchoClip`
- 当前版本：客户端 `0.6.0+9`
- 目标平台：Windows x64、Android arm64-v8a、Ubuntu 服务端

## 1. 接手前必须遵守

1. 当前 Git 工作树包含大量有意保留的已修改和未跟踪文件。不得执行 `git reset --hard`、`git checkout --`、全量清理或删除未知文件。
2. 所有现有工作区改动均视为用户资产。修改前先运行 `git status --short`，只处理当前需求涉及的文件。
3. Windows 命令必须使用 PowerShell 7：

   ```text
   C:\Users\MaidT\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\powershell\pwsh.exe
   ```

   禁止回退到旧版 Windows PowerShell。
4. 不要删除 `apps/echoclip/android/java_pid100384.hprof` 或其他既有未跟踪内容。
5. 核心业务必须由 `echoclip_core` 实现。Flutter、Kotlin、JNI、Windows FFI 及操作系统集成层只负责 UI、权限、唤醒、设备、文件系统和效果分发。
6. 服务端和容器按“单实例服务单客户端”设计。多用户通过部署多个容器并分配不同端口解决，不在单实例内增加账号体系。
7. Ubuntu 目标服务器为 `192.168.1.231`，账号为 `ubuntu`。密码不写入仓库；需要重新部署时向用户索取或使用当前会话授权信息。

## 2. 当前架构

```text
Flutter UI
   │ 结构化 DTO / 用户操作
   ▼
Windows FFI 或 Android JNI
   │ 平台唤醒、权限、设备与效果执行
   ▼
echoclip_core
   ├─ 持续录音与分段滚动缓存
   ├─ 保存最近录音
   ├─ 定时任务状态机与持久化
   ├─ 动作排序、幂等、迟到策略与历史
   └─ WAV → MP3

客户端实时 PCM
   │ 开启上传后的新录音
   ▼
echoclip_sync_client / protocol
   ▼
echoclip_server
   └─ 单一全局 Rust Core 滚动缓存
```

## 3. 服务端已完成内容

### 3.1 单二进制与生命周期

- 新增 `echoclip_server` 单二进制服务端。
- 支持全局 `echoclip stop` 和 `echoclip reboot`。
- WebUI 首次打开时要求选择绝对录音目录，保存后由服务端持久化。
- 默认端口：
  - WebUI：`32580`
  - 上传：`32581`
- 端口已同步到代码、部署配置和文档。

### 3.2 上传密钥

- 服务端首次运行自动生成上传密钥并打印到命令行。
- `echoclip reset key` 会二次确认。
- 用户输入 `yes` 后立即废弃旧密钥、生成并打印新密钥。
- 客户端密钥由平台安全存储保存；仓库和日志不得持久化明文密钥。

### 3.3 单客户端上传模型

- 一个服务器或 Docker 容器只服务一个客户端。
- 服务器不维护多用户或多客户端录音缓存。
- 所有上传会话、重连和新上传激活均写入同一个全局滚动缓存，不按每次上传建立独立录音缓存。
- 上传开关启用后只发送该边界之后的新 PCM。
- 网络失败重试只重发开启上传之后的数据，不补传客户端已有的数小时历史缓存。
- 连接探测不创建上传会话或录音缓存。
- 已修复客户端连接时出现的 429 问题，并调整默认限流以容纳实时上传与合理重试。

### 3.4 WebUI

- WebUI 功能按客户端复刻，但不包含音频处理页和平台不可用能力。
- 服务端缓存长度、录音目录等服务器设置只由 WebUI 管理。
- 实时状态采用 SSE 服务端推送与浏览器本地插值。
- 服务端所有录音进入同一个缓存。
- 已移除页面中的冗余架构说明。

主要位置：

- `crates/echoclip_server/`
- `crates/echoclip_sync_client/`
- `crates/echoclip_sync_protocol/`
- `deploy/`
- `docs/REALTIME_SERVER_SYNC_DESIGN.md`

## 4. 客户端连接与上传

- 服务器连接设置拆分为三个输入：IP 或域名、上传端口、上传密钥。
- “录音时实时上传”开关与“保存设置”完全解耦。
- 只有显式开启实时上传后才上传新录音。
- 启用服务器配置后，客户端每次启动执行一次连通性探测。
- 设置页提供手动服务器连通性测试。
- 客户端不再控制服务端回放缓存时长或其他服务器配置。
- 客户端只负责上传实时录音，不上传已保存录音文件。

主要位置：

- `apps/echoclip/lib/pages/server_settings_page.dart`
- `apps/echoclip/lib/services/replay_service_client.dart`
- `apps/echoclip/lib/services/windows_replay_service.dart`
- `apps/echoclip/android/app/src/main/kotlin/com/echoclip/echoclip/UploadKeyStorage.kt`

## 5. Windows 客户端修复

- 修复前端窗口仍打开时，通过托盘菜单退出导致窗口卡住的问题。
- 后端关闭增加超时和正确的窗口生命周期处理。
- 修复录音状态中“上次录制”错误显示为 `1970-01-01` 的问题。
- 桌面窗口不再固定为 3:2：
  - 最小尺寸：`960 × 640`
  - 最小宽高比：`4:3`
  - 最大宽高比：`16:9`
- Windows 原生调度器独立于 Flutter 窗口；隐藏窗口不会终止等待中的定时任务，但完全退出托盘进程后不承诺执行。

## 6. 定时任务

### 6.1 Rust Core

核心实现：

- `crates/echoclip_core/src/scheduler.rs`
- `crates/echoclip_core/src/lib.rs`

Core 负责一次性倒计时与指定时间点任务、持久化、修订号、并发修改检查、到期判断、五分钟动作敏感迟到策略、动作固定顺序、幂等、中断恢复、执行历史、重新武装、WAV 保存和 MP3 导出。平台层不能重新实现这些规则。

### 6.2 平台接入

Windows：

- FFI 内保持独立调度线程。
- Flutter 窗口隐藏或关闭不影响托盘进程中的任务等待。
- 只执行 Core 返回的效果请求。

Android：

- JNI 维护进程级 Scheduler。
- `AlarmManager` 负责系统唤醒。
- 支持开机恢复和精确闹钟权限。
- 涉及后台录音时使用前台服务。
- 多个同一时刻到期的动作执行完成前不会错误停止前台服务。

主要位置：

- `crates/echoclip_windows_ffi/src/lib.rs`
- `crates/echoclip_android_jni/src/lib.rs`
- `apps/echoclip/android/app/src/main/kotlin/com/echoclip/echoclip/ScheduleCoordinator.kt`
- `apps/echoclip/android/app/src/main/kotlin/com/echoclip/echoclip/ReplayForegroundService.kt`

### 6.3 Flutter 界面

- 原“音频处理”导航和页面已删除，由“定时任务”替代。
- FFmpeg 仍保留；录音库提供 WAV 转 MP3。
- Flutter 每秒刷新仅用于显示插值，不参与到期执行。
- 新建/编辑任务使用独立二级页面，带返回按钮和固定底部保存栏，不再使用 `AlertDialog`。
- 倒计时使用时、分、秒轮盘：时 0–23，分 0–59，秒 0–59，合法总范围为 `00:00:01–23:59:59`。
- 指定时间使用日历选择日期，并复用同一套时、分、秒轮盘。
- 指定时间按轮盘可见值规范到整秒，不保留隐藏毫秒。
- 三个动作分别使用独立功能开关：
  - 录音：启用配置后选择开启或关闭录音；
  - 上传：启用配置后选择开启或关闭上传；
  - 保存最近片段：启用后以秒为单位配置保存时长。
- 保存片段仍保留 MP3/WAV、MP3 码率和缓存不足时保存可用部分的配置。
- 主页面已移除标题下说明、“调度精度”和“录音目录已就绪”常态标签。
- Android 仅在缺少精确闹钟权限时显示操作入口。

主要位置：

- `apps/echoclip/lib/pages/scheduled_tasks_page.dart`
- `apps/echoclip/test/desktop_navigation_test.dart`
- `docs/SCHEDULED_TASKS_DESIGN.md`

## 7. 已移除与必须保留

已移除：

- 独立音频处理页面；
- 增益处理 UI 和处理副本流程；
- processing 专用缓存统计、清理和旧接口。

必须保留：

- FFmpeg 二进制、构建脚本和许可证；
- 定时保存 MP3；
- 已保存 WAV 转 MP3；
- 用户已有录音、缓存、上传配置和密钥。

## 8. 最近验证结果

```text
cargo test --workspace
全部通过，共 60 项 Rust 测试

flutter analyze --no-pub
No issues found

flutter test --no-pub
全部通过，共 38 项 Flutter 测试

:app:testDebugUnitTest（2026-09-11）
全部通过，共 9 项 Android 测试（6 项生命周期、3 项 RMS/峰值校准）；Android 系统调用为 JVM stub，不涉及真实麦克风

git diff --check
通过，仅有既有 CRLF 转换警告
```

Flutter 回归测试覆盖桌面/移动导航、任务编辑、中英文轮盘拖动/对齐、9 个预设上限，以及退出并行清理、重复退出、后端超时和插件失败。

## 9. 现有安装包

目录：

- `dist/windows/0.6.0/`
- `dist/android/0.6.0/`

已有 Windows 安装器、Windows 便携 ZIP、Android arm64-v8a Debug/Release APK。

2026-09-06 17:15 已重新构建上述四个安装包，包含任务编辑/预设改进，以及本轮 Windows 退出优化和共享上传取消逻辑。Windows ZIP 内 Dart AOT 与原生 DLL 已核对匹配最新构建，Android APK 已通过版本与 arm64-v8a 原生库校验。两个产物目录均已更新 `SHA256SUMS.txt`。后续源码变化后发布仍需重新打包并计算哈希。Android Release 当前仍沿用项目既有 Debug 签名配置。

打包脚本：

```powershell
pwsh -NoProfile -File scripts/build_windows_package.ps1 -VersionName 0.6.0 -BuildNumber 9 -SkipFfmpegBuild
pwsh -NoProfile -File scripts/build_android_package.ps1 -BuildMode both -VersionName 0.6.0 -VersionCode 9 -SkipFfmpegBuild
```

Android 打包不得使用 `-SkipRustBuild`。FFmpeg 未变化时可以使用 `-SkipFfmpegBuild`。

## 10. 建议接手检查顺序

1. 运行 `git status --short`，确认既有修改和未跟踪文件仍在。
2. 阅读 `docs/SCHEDULED_TASKS_DESIGN.md`、`docs/REALTIME_SERVER_SYNC_DESIGN.md`、`docs/rust-core.md` 和 `README.md`。
3. 检查最新 UI 与测试：
   - `apps/echoclip/lib/pages/scheduled_tasks_page.dart`
   - `apps/echoclip/test/desktop_navigation_test.dart`
4. 检查 Core 与平台桥接：
   - `crates/echoclip_core/src/scheduler.rs`
   - `crates/echoclip_windows_ffi/src/lib.rs`
   - `crates/echoclip_android_jni/src/lib.rs`
   - `ScheduleCoordinator.kt`
5. 仅在下一项需求涉及相关代码时复跑对应测试。
6. 用户要求发布时重新构建 Windows 与 Android 包，不要沿用旧哈希。

## 11. 交接结论

当前源码已经完成服务端单实例同步模型、连接探测、SSE WebUI、Windows 生命周期修复、桌面窗口约束、Rust Core 定时任务、Windows/Android 平台调度以及最新的二级任务编辑界面。

接手后应继续在现有工作树上增量修改，不要重做已经通过测试的功能，也不要清理不属于当前需求的文件。

## 12. 2026-09-06 任务编辑与预设更新

- 时间轮盘标题独立成行，冒号与选中数字共用垂直中心；Windows 支持鼠标拖动。
- 空任务名称由 Core 按界面语言生成编号名称；录音、上传、保存详情常态显示，未启用时置灰。
- Core 在原调度文件新增 `presets`，旧文件默认空列表；最多 9 个，保存不创建或武装任务。编辑页保存预设，任务列表点击预设进入新建页；支持删除，已有任务不受影响。
- 指定时间预设保留原日期时间，创建任务前仍需校验并修正过去日期。
- Windows FFI 与 Android JNI 的原 upsert JSON 通道接入 Core `editor_command_json`，支持普通任务输入及 `save_preset` / `delete_preset`。
- 中英文、400px 窄屏、鼠标拖动和冒号几何位置通过交互测试；实际字体截图位于 `apps/echoclip/build/qa/`。未做实机安装测试。
- 新增回归：`apps/echoclip/test/scheduled_task_editor_test.dart`，以及 Core 预设持久化/上限/兼容/自动命名测试。

## 13. 退出流程优化

- Windows 显式退出调用完整后端 dispose，不再排队调用 stopReplay；退出开始后拒绝新请求并防止重建原生句柄。
- 隐藏窗口、移除托盘/热键与后端关闭并行执行；后端清理预算 2 秒，平台操作预算 300ms，异常超时才使用进程退出兜底，正常路径仍关闭窗口。
- 原生关闭先通知上传停止、取消未完成导出，再结束采集、调度和写入线程；正常关闭会将缓存刷新落盘，已有录音和待执行任务保留。
- 上传停止会关闭当前 HTTP socket，不再等待默认 10 秒读超时；不可中断的 DNS/连接最多等待线程 250ms，残余线程检查取消后不会发送新数据。
- 回归中服务器不响应时停止上传约 6ms，带缓存/待执行任务的原生关闭约 7ms。这是本机自动化测试数据，不代表所有音频设备的实际退出时间。
- 退出时尚未完成的导出按现有取消流程清理临时输出，原始滚动缓存保留。

- Windows 后端会等待已有探测/转换等 FFI 请求结束，避免窗口销毁后 Flutter 引擎仍被后台 isolate 拖住；退出超时兜底适用于这些异常请求。
- 最后一次设置写入放在初始化和已有请求完成之后，避免刚启动就退出时覆盖尚未读取的用户配置。
- 新增测试：`apps/echoclip/test/desktop_exit_test.dart`；Rust 上传取消及原生关闭/缓存恢复测试位于对应 crate 内。

## 14. 2026-09-11 移动端锁屏录音修复

- 根因：`stopManualCapture` 仅停止采集，未解除锁屏广播监听和待命状态；模式设置只持久化，后台继续上报旧模式；Flutter 又将仅为定时任务驻留的服务误当成锁屏录音已开启。
- 手动停止（包括通知停止按钮）会先解除锁屏监听，再停止采集；AudioRecord 先 stop 以唤醒阻塞读取，再等待线程退出。待命和采集中均可停止，并可再次开始。
- Android 模式切换即时更新后台模式，同时暂停当前录音、解除旧模式待命；新模式需用户点击开始。修改锁屏触发条件不会重新开启已停止的录音。
- 定时任务或正在执行的任务仍可保留前台服务。按钮由采集/锁屏待命状态决定，不再由服务是否驻留决定。
- Flutter 开始/停止/模式设置互斥；命令前发出的旧状态/电平响应不会覆盖新状态。停止也不再依赖录音目录仍然可用。
- 新增 `mobile_recording_mode_test.dart`，中英文覆盖停止/重启/模式切换、定时任务服务驻留、迟到响应、等待权限时重复操作；新增 `RecordingModeLifecycleTest.kt` 验证真实服务方法的状态变化（Android 效果使用 JVM stub）。
- 本次没有连接 Android 真机；已通过静态检查、33 项 Flutter 测试和 6 项 Android 生命周期测试。Rust 未变化，沿用前一轮 60 项通过记录。

- 2026-09-11 14:11 已重建 Android 0.6.0+9 arm64 Debug/Release APK，通过版本和原生库校验，并更新 Android 目录 SHA256SUMS.txt；沿用项目既有 Debug 签名。Windows 安装包仍为 2026-09-06 构建，本轮未重打桌面包。

## 15. 2026-09-11 实时响度重设计

- 以墨绿色仪表面板替换旧楔形柱条，突出当前 dBFS 数字与独立峰值，新增最近 6 秒真实输入轨迹、统一分段刻度与高电平状态。手机使用上下布局，桌面采用读数/轨迹并排布局。
- `LoudnessMeterModel` 仅负责显示：35ms 上升、280ms 回落、1 秒峰值保持、约 8Hz 数字更新、120 个 50ms 历史采样与帧间连续滚动。暂停后停止 ticker，历史冻结；重新开始清空历史，离屏长间隔清除未知轨迹。
- 对数刻度覆盖 -60 到 0 dBFS。读数来源是数字 RMS 和独立样本峰值，并非 LUFS 或环境声压级；UI 平滑不会修改录音样本。测量区分可参考 [Audacity Meter Toolbars](https://manual.audacityteam.org/man/meter_toolbar.html)。
- Android 原先将 RMS/峰值混合、开平方和再次平滑后用于 dB，导致虚高；现在返回原始线性 RMS 和独立样本峰值，显示平滑/保持统一由 Flutter 完成。16 位 PCM 采用 32768 标定，负满刻度不会超过 1。
- 新增中英文状态文案；280/400/960px 与 2 倍字体布局、暂停不持续刷新、电平刻度/峰值保持/历史上限均通过回归。手机与桌面实际 Flutter 预览位于 `apps/echoclip/build/qa/loudness-*.png`，图中输入为明确标注的模拟信号。
- 新增 `test/loudness_meter_test.dart`、`AudioMeterCalibrationTest.kt`。现有移动端菜单回归改为等待菜单过渡，不等待持续工作的响度动画完全静止；旧响应模拟仅拦截首次请求，避免将旧快照当作新请求结果。
- 本轮静态检查、38 项 Flutter 与 9 项 Android JVM 测试通过，Rust 业务代码未变化；无真机麦克风验证。

- 2026-09-11 15:17 已重建 Windows 安装器/便携 ZIP 与 Android arm64 Debug/Release APK（0.6.0+9），包含本轮响度重设计及此前锁屏修复；Windows ZIP 内应用与最新 AOT 构建哈希一致，Android 版本/ABI 校验通过，两端 SHA256SUMS.txt 已更新。Android Release 沿用既有 Debug 签名。

## 16. 2026-09-11 响度配色、曲线边界与坐标修订

- 面板改为浅灰绿色、深色数字和柔和青绿曲线，与现有浅色界面协调；峰值与分段电平保留独立显示。
- 右上角状态仅根据是否正在录制显示“录制中 / 未录制”（Recording / Not recording）。移除环境安静、正在接收、接近上限的状态判断和对应未使用文案。
- 历史曲线采用固定 6 秒视口（120 个 50ms 间隔），保留 122 个采样以覆盖左边界外的衔接段。曲线和填充限制在固定绘图区内，避免删除最旧点时起点、圆形线帽和填充边缘跳动或侵入坐标区。
- 曲线与网格共享坐标映射；纵轴显示 0 / −30 / −60 dBFS，横轴显示 −6 / −4 / −2 / 0 秒，中英文单位适配；空间不足时仅显示 −6 和 0 秒。大字体时增加曲线高度，读数与峰值改为上下排列。手机和桌面实际字体预览已检查，包括 280px、2 倍字体。
- 新增中英文双状态回归，以及跨多次 50ms 采样移除的左边界像素比较（包括绘图区外侧，检测溢出）。静态检查和全部 40 项 Flutter 测试通过；280 / 400 / 960px 与 2 倍字体布局通过。历史上限测试调整为 122 点。
- 本轮仅修改 Flutter 展示与本地化；模拟信号预览位于 `apps/echoclip/build/qa/loudness-*.png`，未进行真机麦克风测试。

- 2026-09-11 15:49 已按最终源码重建 Windows 安装器/便携 ZIP 与 Android arm64 Debug/Release APK（0.6.0+9），包含上述浅色配色、曲线边界、双状态及大字体坐标修订。Windows ZIP 内 Dart AOT/原生 DLL 与最新构建一致；Android 版本/ABI 校验通过，两端 SHA256SUMS.txt 已更新。Android Release 沿用项目既有 Debug 签名。

## 17. 2026-09-11 保存操作区与录音库重设计

- 保存区将原有按钮、分段开关、输入框合并为“时长选择 → 保存”两个等宽等高控件，默认 52px 高和 12px 圆角；桌面横排，手机和大字体上下整行排列。预设时长与自定义统一在菜单中，自定义置顶；对话框校验 1–86400 秒，取消保留原选择，保存始终使用当前选定秒数。
- 录音库移除整页大面板，改为摘要、搜索、分组筛选与独立白色录音条目。文件名、格式/分组、大小和保存时间分层显示；桌面按列对齐，窄屏将元数据移到文件名下方。只展示真实已有元数据，不推算未知时长。
- 支持按名称搜索和最新/最早/文件名排序；分组筛选包含全部、未分组和用户分组，空分组仍可重命名/删除。录音列表使用 SliverList 按需构建。
- 批量全选仅选择当前筛选结果；改变搜索或分组时清除旧选择，防止误删不可见录音。分组被删除后自动回到全部列表。
- 当前播放面板固定在录音库底部，筛选隐藏当前录音时仍可暂停、继续、拖动进度、停止和调整速度；条目播放按钮可暂停/继续当前录音。保留新建/重命名/删除分组、重命名/移动/删除录音、WAV 转 MP3 和刷新功能。
- 修复已有通用名称弹窗在关闭动画结束前释放 TextEditingController 的问题，控制器改由弹窗 State 在销毁时释放。大字体时播放控制可换行。
- 新增中英文文案及 `recording_library_design_test.dart`、`test/fixtures/library_fixture.dart`；`RecorderPage` 和 `LibraryPage` 作为可独立测试的页面组件公开。静态检查和完整 47 项 Flutter 测试通过；新增 7 项覆盖 320/400/1000px、2 倍字体、控件尺寸、自定义时长、筛选/批量删除、排序、空分组、播放、重命名/移动/转码。
- 实际 Flutter 渲染预览位于 `apps/echoclip/build/qa/library-*.png` 和 `recorder-*.png`，使用示例数据、真实中文字体及 Material 图标。未进行真机麦克风或安装后实测；本轮不修改 Rust/Android 业务逻辑。

- 2026-09-11 20:24 已按最终源码重建 Windows 安装器/便携 ZIP 及 Android arm64 Debug/Release APK（0.6.0+9），包含本轮保存区和录音库重设计。Windows ZIP 内 Dart AOT/原生 DLL 与最新构建一致，Android 版本与 ABI 校验通过，两端 SHA256SUMS.txt 已更新。Android Release 沿用既有 Debug 签名。

## 18. 2026-09-12 三个主页面视觉统一

- 以录音库的浅灰绿背景、深绿标题、14px 圆角白色卡片和柔和图标底色为基准，新增共享页标题、分组标题、图标和空状态组件，统一主页、定时任务及设置页。
- 主页拆成计时、响度、保存三张卡片，开始/暂停按钮改用稳重的绿色。普通录音状态不重复显示，权限/错误/锁屏待命等说明保留。大字体和极窄屏下计时上下排列，底部留出悬浮按钮空间。
- 定时任务页移除整页套卡和空任务时冗余的“没有等待执行任务”提示，使用摘要、预设、独立任务条目、轻量空状态与执行历史；保留新增/编辑/启停/删除/预设和精确定时权限操作。任务编辑页同步卡片配色、圆角和间距。
- 设置页按目录、语言、音频来源、录制参数、锁屏录音、服务器、缓存、项目分组；宽屏使用双栏，手机和大字体使用单列。Android 标准存储目录用“内部存储 / EchoClip”一类友好名称展示，完整原始地址保留在提示中，未知提供方地址不改写。
- 顶层录音库、定时任务、设置页取消重复 AppBar，保留页面内标题和统计信息。主页保留 EchoClip 品牌及录音模式操作；二级编辑与服务器设置页保留返回导航。
- 实际渲染时发现并修复原有本地化参数顺序问题：下次执行/任务计划的日期与剩余时间、保存操作的秒数与格式不再互换；中英文均增加回归。
- 新增 `unified_page_design_test.dart` 六项回归和示例数据 fixture；旧保存控件测试改为滚动寻找离屏控件。静态检查无问题，完整 53 项 Flutter 测试通过；覆盖中英文 320/400/1000px、2 倍字体、滚动全页、标题去重、目录操作、任务开关和预设进入编辑器。
- 实际字体 Flutter 预览位于 `apps/echoclip/build/qa/unified-*.png`，含空状态与示例任务。此轮未修改原生录音业务逻辑，也未进行真机安装/麦克风实测。

- 2026-09-12 01:20 已按最终源码重建 Windows 安装器/便携 ZIP 及 Android arm64 Debug/Release APK（0.6.0+9）。Windows ZIP 内 Dart AOT/原生 DLL 与最新构建一致；Android 版本、ABI、ELF 及 Release 签名校验通过，两端 SHA256SUMS.txt 已更新。Android Release 沿用既有 Debug 签名。Android 首次复制原生库遇到临时文件占用，检查构建进程后重试成功，无源码或构建脚本绕过。

## 19. 2026-09-12 桌面顶栏稳定与任务空状态修正

- 桌面及使用侧栏的宽屏布局始终保留 EchoClip 品牌顶栏，切换四个主页面时顶栏高度、侧栏位置和内容起点保持一致。主页的录音模式/连接状态操作仍在主页显示；页面名称继续只在内容区展示，避免恢复重复页标题。
- 手机底部导航布局继续使用单一页面标题。二级任务编辑页的返回导航保留。
- 定时任务的空状态与加载状态使用同样的白色圆角卡片；预设、任务内容、执行历史之间统一为 16px 间距。已有任务条目仍使用独立卡片。
- 更新导航回归，比较切页前后顶栏/侧栏矩形和内容起点；覆盖 800px 桌面、1200px 桌面/宽屏移动平台、400px 手机及中英文，并验证切回主页的录音模式操作。
- 静态检查、全部 53 项 Flutter 测试通过。新增完整应用外壳的实际字体预览 `apps/echoclip/build/qa/shell-fixed-*.png`，测试后端使用模拟数据，未进行真机录音或安装验证。

- 2026-09-12 01:41 已重新生成 Windows 安装器/便携 ZIP 与 Android arm64 Debug/Release APK（0.6.0+9）。Windows 包内 AOT/原生 DLL 与本次构建一致；Android 版本、ABI/ELF、Release 签名校验通过，两端 SHA256SUMS.txt 已更新。Android Release 沿用既有 Debug 签名。

## 20. 2026-09-12 导航命名、主页操作区与平台顶栏调整

- 中文导航名称“已保存录音”统一为“录音列表”，与页面内标题一致；英文导航与标题继续统一使用 Recordings。缓存说明中的“已保存录音”仍表示已保存的文件，不作为页面标题。
- 连接状态指示与录音模式菜单移入主页标题区域。普通字体时与“录制已暂停/Instant replay running”等主标题垂直居中对齐，时间副标题置于其下；大字体或极窄空间下操作区可换行。
- RecorderPage 通过 headerActions 接收现有状态和模式控件，沿用原回调。移动端模式图标触控区域为 48px；连接详情弹窗支持滚动，修复 320px、2 倍字体、英文下的内容溢出。
- 品牌顶栏仅在 Windows/macOS/Linux 桌面平台的四个主页面显示。手机和平板主页面（含主页、宽屏侧栏布局）均不显示品牌顶栏；二级页面返回导航继续保留。
- 去除应用启动时固定英文 Recording service stopped 占位提示；页面已有本地化录音状态标题，后端状态/错误到达后继续正常显示。
- 更新导航回归，覆盖中文/英文、400px 手机、800/1200px 桌面、1200px 平板、320px 手机和 800px 桌面 2 倍字体；比较标题与操作中心、顶栏/侧栏几何位置，并实际打开/关闭连接详情及录音模式菜单。
- 静态检查和完整 53 项 Flutter 测试通过；完整应用实际字体预览为 `apps/echoclip/build/qa/header-final-*.png`，含桌面、手机、平板及大字体。预览使用模拟或无后端状态，未进行真机安装/录音验证。

- 2026-09-12 17:33 已重建 Windows 安装器/便携 ZIP 和 Android arm64 Debug/Release APK（0.6.0+9）。Windows ZIP 内应用 AOT/原生 DLL 与本次构建一致，Android 版本、ABI/ELF 和 Release 签名验证通过，两端 SHA256SUMS.txt 已更新。Android Release 沿用既有 Debug 签名。

## 21. 2026-09-12 Android 主页对齐、保存进度/取消与录音分享

- 移动端主页的标题/副标题与操作区分开布局，标题从内容区顶部开始；平板等宽屏移动布局同步使用顶部对齐，避免 48px 触控区域把标题撑低。桌面操作区仍与主标题居中对齐。
- 取消保存状态插入主页信息卡的行为，成功/失败/取消使用 SnackBar，保存不再推移计时、响度和保存区域。录音权限、锁屏状态等原有说明保留。
- Android 保存按钮内显示编码等待指示、写入 SAF 文件的实际字节百分比；再次点击取消。取消请求可在后台任务 ID 返回之前排队，任务完成与取消回复竞争不会让按钮重新进入忙碌；保存期间切页仍跟踪原任务，完成后再刷新录音列表。大字体保留简洁的取消文字和进度语义。
- 运行中的服务、暂停后缓存保存和定时保存复用 ClipSaveJobs。原生编码明确确认取消后才清理临时文件，写入中逐块检查取消并删除未完成文件；最后一块数据与完成提交之间也检查取消。删除失败显示错误，不伪报取消成功。
- ReplayRecorderOwner 让缓存录音器由采集和保存共同持有。暂停/恢复录音与离线保存只使用一个缓存写入器；服务销毁不会提前释放正在导出使用的句柄，最后一个使用者完成后才关闭。保存期间保护缓存清理。
- Android 录音条目菜单增加“分享/Share”，将选中 MP3/WAV 的 content URI、正确 MIME 类型、ClipData 和临时只读授权交给系统分享面板；先检查文件可读性，权限撤销或文件已删除时显示本地化错误。不复制整份录音，不申请额外存储权限。
- Windows 保持原有导出方式，按钮显示保存中并避免重复提交；本轮 Android 的取消与系统分享不会冒充桌面功能。
- 静态检查无问题，完整 61 项 Flutter 测试与 17 项 Android JVM 测试通过。新增覆盖早期取消、复制中取消、最后一次写入取消、真实字节进度/音频内容、保存中切页、失败重试、延迟取消回复、共享缓存录音器生命周期、MP3/WAV 分享入口及中英文。
- 实际字体预览：apps/echoclip/build/qa/header-final-*.png、save-exporting-*.png、save-copying-*.png，覆盖中英文手机、平板和 2 倍字体。预览和 Flutter 测试使用模拟后端，未进行真机麦克风/系统分享目标应用验证。
- Android 分享实现依据官方文档：https://developer.android.com/training/secure-file-sharing/share-file 。

- 本轮交付完成：Windows 安装器/便携 ZIP 于 2026-09-12 21:26 重建，Android arm64 Debug/Release APK 分别于 21:28/21:31 重建（0.6.0+9）。Windows 包内 Dart AOT/原生 DLL 与最新构建一致；Android 两个分发 APK 与 Gradle 输出哈希一致，Release DEX 已确认 getSaveJob/cancelSaveJob/shareRecording 接口。版本与 arm64 ELF 校验、Release 签名验证通过，两端 SHA256SUMS.txt 和 Android 更新说明已更新。Release 仍使用 Android Debug 签名。
- 发布包：dist/windows/0.6.0/EchoClip-0.6.0-x64-Setup.exe；dist/android/0.6.0/EchoClip-0.6.0+9-arm64-v8a-release.apk。

## 22. 2026-09-13 保存区域内的状态反馈

- 将保存相关的成功、取消、失败提示移至保存卡片顶部“保存最近的音频”所在位置，避免底部通知干扰。成功显示“录音已保存”，成功/取消约 4 秒后恢复默认文字；失败/取消失败保留 8 秒，详细错误可悬停或长按查看。
- 保存中、写入中、取消中在同一行显示对应状态，沿用按钮内进度和取消操作。使用柔和的成功色、小图标和 180ms 淡入淡出；行高在状态切换中保持一致，大字体使用简短文案和可访问的完整语义说明，遵循系统减少动画设置。
- 反馈由主页状态持有，跨页面切换保持既定有效期；新保存或取消请求清除旧提示并重置计时，销毁页面时释放计时器。保存完成后异步刷新列表，列表刷新失败不会误报导出失败。
- 中文/英文均适配。静态分析无问题，完整 65 项 Flutter 回归通过；新增即时导出完成、列表刷新失败、提示自动恢复、连续保存计时重置、错误详情、切页期间保存完成等验证。原生录音/导出/分享接口本轮没有修改。
- 实际字体预览：apps/echoclip/build/qa/save-saved-*.png、save-failed-*.png、save-exporting-*.png、save-copying-*.png，覆盖手机、宽屏和 2 倍字体；完整桌面外壳继续通过布局回归。预览使用模拟数据，未进行真机安装测试。

- 已完成本轮打包：Windows 安装器与便携 ZIP 于 2026-09-13 16:06 生成，Android arm64 Debug/Release APK 分别于 16:08/16:10 生成（0.6.0+9）。Windows 包内 AOT/原生 DLL 与最新构建一致；Android 分发 APK 与 Gradle 输出哈希一致，版本、arm64 ELF 和 Release 签名校验通过，两端 SHA256SUMS.txt 已更新。Android Release 沿用现有 Android Debug 签名。
