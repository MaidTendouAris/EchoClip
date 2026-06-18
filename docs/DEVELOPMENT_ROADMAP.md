# EchoClip 开发路线图

最后更新：2026-06-16

## 1. 产品定位

EchoClip 是一个“即时音频回放”应用。它的核心承诺是：

> 持续保留最近一段声音，在事情已经发生后，一键保存刚刚错过的片段。

它不应该只是普通录音机，而应该更像音频版的即时重放。产品气质应该是轻量、隐私友好、可靠、低打扰。移动端是核心场景，但必须围绕 Android 和 iOS 的后台录音限制来设计，不能把它包装成隐形常驻录音器。

典型场景：

- 课堂、会议、访谈、线下交流中，事后保存刚刚提到的重点。
- 日常生活里捕获突然出现的灵感、环境声音或重要对话片段。
- 不想提前手动录完整长音频，只想保存最近一小段。
- 本地整理、裁剪、调音量、命名、打标签。

第一阶段不做：

- 隐蔽录音。
- 电话录音。
- 专业音频工作站级编辑。
- 在录音可靠性验证前投入复杂云同步或 AI 功能。

## 2. 平台策略

### 推荐开发顺序

1. Windows 桌面 demo 和 Rust 音频核心
2. Android 移动端 MVP
3. Flutter UI 稳定化与跨端复用
4. Windows 桌面完整 MVP
5. 未来 iOS 兼容预留
6. 跨设备体验、可选转写、可选同步

当前开发环境缺少 macOS，因此暂时不做 iOS 版本。Windows 和 Android 是核心目标：Windows 用来快速验证 Rust 音频核心、桌面后台体验和文件管理；Android 用来验证移动端即时录音的真实生活场景。iOS 只在架构上保留未来兼容空间。

### Android 现实约束

Android 14+ 要求前台服务声明正确类型。麦克风采集需要：

- `android:foregroundServiceType="microphone"`
- `FOREGROUND_SERVICE_MICROPHONE`
- `RECORD_AUDIO`
- 录音期间展示前台服务通知

关键限制：麦克风权限属于 while-in-use 权限。Android 14+ 上，麦克风前台服务通常必须在应用可见时启动，除非命中特定豁免场景。

对 EchoClip 的产品含义：

- 用户需要明确从应用或通知操作中启动“即时回放模式”。
- EchoClip 在缓冲期间保留一个常驻前台通知。
- 通知提供快捷动作，例如 `保存最近 30 秒`、`保存最近 2 分钟`、`停止`。
- 服务启动后维护内存环形缓冲区，用户触发时再保存片段。

官方参考：

- Android foreground service types: https://developer.android.com/develop/background-work/services/fgs/service-types
- Android foreground-service background start restrictions: https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start

### iOS 未来兼容

iOS 暂不进入开发排期，只保留设计约束。未来如果具备 macOS 开发环境，EchoClip 不应承诺“完全隐形、永久常驻”的录音体验。更可行的形态是：

- 用户打开 EchoClip 并启动一次录音会话。
- 应用配置合适的 `AVAudioSession` 录音模式。
- 必要时声明对应后台音频能力。
- 应用进入后台后录音继续运行，但必须接受系统行为、中断、隐私指示器和 App Store 审核约束。

对 EchoClip 的产品含义：

- iOS 版本更适合叫“会话回放模式”，而不是“永久即时回放”。
- 录音状态必须明确可见。
- 保存动作优先使用应用内控件；可探索锁屏/通知能力、Widget、Shortcuts，但要保留应用内兜底路径。

官方参考：

- iOS `UIBackgroundModes`: https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/iPhoneOSKeys.html

## 3. 总体架构

采用 Flutter 做产品界面与跨平台壳，Rust 做音频缓冲和处理核心。

```text
Flutter App
  - 首次引导与权限说明
  - 录音状态
  - 片段库
  - 设置页
  - 简单编辑器
  - MethodChannel / FFI 边界

Native Platform Layer
  - Android Foreground Service
  - Android 通知快捷动作
  - Android AudioRecord / Oboe 桥接
  - iOS AVAudioSession / AVAudioEngine 桥接
  - 生命周期、中断、音频路由变化

Rust Core
  - 环形缓冲区
  - PCM 标准化
  - 片段提取
  - 音量增益
  - 峰值限制
  - WAV / Opus 编码接口
  - 元数据模型

Local Storage
  - 音频文件
  - SQLite 元数据
  - 波形缓存
```

推荐边界：

- 平台原生层负责音频采集，因为移动端权限、生命周期和后台行为高度平台相关。
- Rust 负责跨平台复用的音频数据结构、缓冲、处理和编码。
- Flutter 负责全部用户可见流程。

这样可以避免过早把移动端后台采集全部压到 `cpal` 这类跨平台库上。桌面端后续仍然可以评估 `cpal`。

## 4. 核心技术设计

### 环形缓冲区

持续把 PCM frame 写入固定时长的 rolling buffer。

初始默认值：

- 采样率：优先 48 kHz，否则使用设备默认值
- 声道：MVP 使用 mono
- 样本格式：Rust 边界使用 16-bit PCM
- 默认缓冲时长：5 分钟
- 可选缓冲时长：30 秒、1 分钟、2 分钟、5 分钟、10 分钟

内存估算：

```text
48,000 samples/s * 2 bytes * 1 channel * 300s = 28.8 MB
```

这个量级对 Android 可接受，真正要控制的是 CPU 唤醒、锁屏稳定性和磁盘写入频率。

### 保存片段流程

```text
音频输入
  -> 平台采集回调
  -> Rust 环形缓冲区
  -> 用户触发：保存最近 N 秒
  -> 提取片段
  -> 可选增益 / normalize
  -> 编码
  -> 写入文件
  -> 写入元数据
  -> 出现在片段库
```

### MVP 音频处理

第一版音频处理要小而确定：

- 音量增益：`-12 dB` 到 `+12 dB`
- 峰值限制，避免放大后爆音
- normalize 到目标峰值
- 手动裁剪开头和结尾
- 波形预览缓存

后续再考虑：

- 自动静音裁剪
- 降噪
- 人声增强
- 转文字
- 基于语义的片段搜索

## 5. 里程碑

### Phase 0：Windows 地基 Demo

目标：先用 Windows 快速证明 Rust 音频核心、Flutter 壳和构建链路可靠，再进入真实录音采集。

交付物：

- Rust 环形缓冲区 crate
- Windows demo 可执行程序
- Flutter Windows/Android 项目骨架
- 从缓冲区提取并写出 WAV demo
- Windows release 构建产物

退出标准：

- Rust 单元测试通过。
- Windows demo 可以编译运行。
- Flutter Windows release 可以编译。
- demo 能生成最近 5 秒 WAV 样例。

### Phase 1：Windows 真实录音 Spike

目标：把 demo 从模拟音频推进到真实麦克风采集。

交付物：

- Windows 麦克风设备枚举
- 真实 PCM 采集
- 写入 Rust 环形缓冲区
- 保存最近 30 秒 / 2 分钟 WAV
- 最小 Flutter 控制界面

退出标准：

- Windows 桌面端可以真实录制麦克风。
- 后台运行 30 分钟后仍能保存最近片段。
- 保存片段没有明显断裂、重复、爆音。

### Phase 2：Android MVP

目标：让核心产品在 Android 上能日常使用。

交付物：

- 首次引导和权限说明
- 采集状态页
- 前台通知快捷动作：
  - 保存最近 30 秒
  - 保存最近 2 分钟
  - 停止
- 片段库
- 播放
- 删除和重命名
- 基础设置：
  - 缓冲时长
  - 默认保存时长
  - 音频质量
  - 存储位置
- 优先支持 WAV 输出，Opus 在编码链路稳定后加入
- 崩溃安全的元数据存储

退出标准：

- 用户可以安装、授权、启动即时回放、保存片段、播放和管理文件。
- 可以处理来电、蓝牙切换、麦克风被占用等中断。

### Phase 3：音频体验打磨

目标：让保存下来的片段更好听、更好用。

交付物：

- 音量增益
- normalize
- 简单裁剪 UI
- 波形渲染
- 分享 / 导出
- 标签和备注
- 存储占用视图
- 自动清理策略

退出标准：

- 用户可以拯救音量偏小的片段，并避免明显削波。
- 用户可以裁剪并用系统分享流程导出。

### Phase 4：Windows MVP

目标：把 Windows demo 扩展为能日常使用的桌面版。

交付物：

- Windows 托盘应用
- 全局快捷键
- 麦克风采集
- 保存最近 30 秒 / 2 分钟 / 5 分钟
- 本地片段库
- 基础音量处理
- 可选系统音频采集调研

退出标准：

- 桌面端可以在后台运行。
- 用户可以通过快捷键保存最近麦克风音频。
- Rust core 被实际复用。

### Phase 5：iOS 适配预留

目标：交付一个诚实、符合平台限制的 iOS 版本。

交付物：

- iOS 录音会话流程
- `AVAudioSession` 配置
- 必要的后台模式配置
- 清晰的录音中状态
- 与 Android 基本一致的本地片段库
- 中断处理
- 音频路由变化处理

退出标准：

- 用户从前台启动会话。
- 应用进入后台后，在预期条件下录音继续。
- 保存片段可靠。
- 产品文案不暗示隐藏式常驻录音。

### Phase 6：智能层

目标：在采集可靠后增加高价值能力。

交付物：

- 本地转写选项
- 转写文本搜索
- 自动标题建议
- 基于音量 / 语音活动检测的精彩片段提示
- 可选加密同步

退出标准：

- AI 功能保持可选。
- 不登录、不联网时核心录音能力仍然完整。

## 6. 仓库结构计划

建议从一开始使用 monorepo：

```text
EchoClip/
  apps/
    mobile/              # Flutter app
  crates/
    echoclip_core/       # ring buffer, processing, metadata types
    echoclip_ffi/        # Flutter/Rust FFI bridge
  native/
    android/             # service and audio capture experiments if kept separate
    ios/                 # AVAudioSession experiments if kept separate
  docs/
    DEVELOPMENT_ROADMAP.md
    ARCHITECTURE.md
    MOBILE_BACKGROUND_CAPTURE.md
```

第一阶段只有移动端是可运行产品也没关系，但 Rust crates 要为桌面复用留好边界。

## 7. 立即开发路径

下一步建议按这个顺序做：

1. 在 `apps/echoclip` 维护 Flutter Windows/Android app。
2. 在 `crates/echoclip_core` 维护 Rust 音频核心。
3. 用 Windows demo 验证环形缓冲区、增益和 WAV 输出。
4. 接入 Windows 真实麦克风采集。
5. 把采集数据桥接进 Rust buffer。
6. 从最近 N 秒缓冲中保存 WAV。
7. 做一个极简 Flutter UI：开始、停止、保存、片段列表。
8. Windows 链路可靠后，再实现 Android foreground service。

早期测试矩阵：

- Android 12、13、14、15+
- 亮屏 / 锁屏
- App 前台 / 后台
- 手机麦克风、有线耳机、蓝牙耳机
- 省电模式开 / 关
- 来电中断
- 低存储空间

## 8. Phase 0 后再定的产品决策

- 默认缓冲时长选 2 分钟还是 5 分钟。
- 默认格式用 WAV 追求可靠，还是 Opus 追求省空间。
- Android 通知文案。
- 通知是否需要保持展开状态。
- iOS 是否作为同等产品发布，还是明确标注为适配模式。
- 转写是本地优先，还是允许云端辅助。

## 9. 主要风险

- 移动系统限制会变化，而且录音是隐私敏感能力。
- Android 厂商省电策略可能杀掉前台服务。
- iOS 审核可能拒绝看起来像静默后台录音的行为。
- Flutter 插件可能无法提供足够的生命周期控制，因此需要写原生 Android/iOS 代码。
- 音频路由变化和中断处理容易被低估。

风险压缩原则：

> 先做移动端采集可行性验证，再投入 UI、品牌、AI 和复杂编辑功能。
