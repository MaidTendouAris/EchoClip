# EchoClip 0.7.1 — 启动操作、缓存区间和录制音量

> 0.8.0 更新：Android 开机自启已取消，Windows 新增静默启动。以下启动行为描述为历史实现，当前行为见 [STARTUP_EXPORT_FORMATS.md](STARTUP_EXPORT_FORMATS.md)。

## 使用

- 设置 → 开机自启 → 启动操作：自启默认关闭；二级页只有录音操作、实时上传两个开关，自动保存，下次启动立即应用。
- Windows 在当前用户登录后打开应用，应用上述设置。手动打开不触发启动操作。仅管理当前用户的 EchoClip Run 注册表值；卸载时仅删除指向本安装目录的自启项。
- Android 开机后显示通知；点击通知或打开应用后执行启动操作。需要通知权限，录音还需要麦克风权限。开机广播不会直接启动麦克风前台服务；首次启用需等下次重启。
- 主页保存时长菜单 → 缓存区间：最小单位为 1 秒，显示 HH:MM:SS。起始、结束时间各有时、分、秒三个输入框，与区间条联动。00:00:00 是打开窗口时缓存的最早位置，不满一秒的末尾不纳入选区。
- 选区固定到音频样本，继续录音不会使所选片段右移。超过缓存保留期、清理缓存或恢复改变音频位置后需要重新选择。
- 麦克风和系统声音分别提供 0%–300% 音量条及精确整数输入，默认 100%。0% 静音。连续滑动仅更新界面，松手后应用和保存；输入完成或离开输入框后提交。保存期间可以继续调整，写入串行执行并合并最新值，不重启录音。
- 范围标记与音量条同排，置于同一分组内；系统声音仅在支持该音源的平台可调。
- 设置页底部从 Android BuildConfig / Windows Flutter 构建常量读取真实版本与构建号。

## 实现和兼容

- 核心 BufferWindow / ExportRange 保存持久化时间线 ID 及绝对交错样本位置。导出前校验时间线、区间及声道对齐；过期选区返回 BUFFER_RANGE_EXPIRED，不静默替换为其他音频。客户端仅允许整秒选择，原生样本级导出接口保持原有精度。
- startupActions 保存两个布尔值，映射为一个立即执行的内部启动模板。旧模板按原先延迟顺序折叠录音、上传的最终状态，移除旧的待执行启动任务和保存片段动作；普通定时任务和历史保留。
- 编辑启动设置不会运行操作。启动标识与激活事务共同持久化，同一次启动重试不重复执行，后续启动复用执行任务。Windows 启动参数为 --autostart，并有单实例保护；Android 用 boot count 去重。
- Windows 在两路混音时独立加权；Android 在麦克风 PCM 进入缓存、上传和响度统计前应用整数增益，输出饱和限幅。
- 中文和英文文案、窄屏与桌面布局均保留。

## 验证

- Rust workspace：74 项通过，包括旧启动配置迁移、普通任务保留、即时配置不执行、持久化与去重，以及既有固定区间、音频限幅等回归。
- Flutter：80 项通过，包括跨小时输入、整秒边界、无效分秒、样本坐标传参、窄屏时间刻度、两个启动开关、拖动不写入、松手提交、输入校验、排队提交和真实版本读取。静态分析通过。
- Android JVM：18 项通过，Kotlin 编译通过。
- Flutter 渲染检查覆盖 400 和 1100 像素宽度的缓存区间、音量控制和启动操作页，预览保存在本地 apps/echoclip/build/ui-preview/071-*.png。
- 本轮未连接物理设备做真实重启、持续录音或麦克风端到端验证；自动化测试不替代真机手感和 OEM 后台限制测试。

## English

Startup is opt-in. Its detail page contains only recording and live-upload switches. Existing delayed startup templates migrate to immediate actions without changing ordinary timers or execution history. Windows activates at sign-in; Android posts a boot notification and waits for the app to enter the foreground.

Custom saving uses a dual-thumb slider with whole-second precision and six hour/minute/second fields. The selected audio stays fixed while recording continues. Continuous gain sliders and exact 0–300% inputs commit only after release or submission; pending writes do not block dragging. Settings displays the version from native build metadata.
