# EchoClip

EchoClip 是一个面向桌面与移动端的即时音频回放应用。它的目标不是替代传统录音机，而是在后台保留最近一段可用音频来源，让用户在需要时快速保存刚刚发生的声音片段。

音频处理功能还没做好，目前版本的该功能还只是个demo，等更新吧。

目前版本的app已经高度可用，但还没来得及做更多的测试，如有问题请提交issues。

产品设计、平台约束、Rust core 边界、FFmpeg 导出链路和图标规范等核心内容请阅读 `docs/` 中的文档：

- [开发路线图](docs/DEVELOPMENT_ROADMAP.md)
- [Rust Core 设计](docs/rust-core.md)
- [图标设计](docs/ICON_DESIGN.md)

项目许可证见 [LICENSE](LICENSE)。

## Windows x64 能力与架构

Windows 与 Android 共用同一套 Flutter 界面和设置页，不维护 Windows 专用
前端。平台服务只向共享界面报告能力；当前平台不支持的选项会自动置灰，
例如 Android 上的系统音频录制和输入设备选择。

Windows 录音生命周期由 Rust 后端统一管理：

- `echoclip_windows_ffi` 通过 CPAL/WASAPI 枚举麦克风端点。指定设备时保存
  Windows 的不透明稳定端点 ID；选择“系统默认输入设备”时保存 `null`，并在
  下次开始录音时重新解析当前默认输入设备。
- 系统音频通过当前默认输出端点的 WASAPI loopback 获取。用户可以选择只录
  麦克风、只录系统音频，或同时录制两者。
- 两个来源先在 Rust 中降混并重采样，再由单一 10 ms 固定时轴混音器生成
  一路单声道 PCM，交给共用的 `RecorderWorker`。来源暂时缺帧时填充静音，
  因此系统没有播放声音时录制时长仍会正常前进。
- `echoclip_core` 默认把滚动缓存写成 60 秒的 PCM 分片，保存时从所需分片
  拼接导出。Windows x64 FFmpeg/LAME 会从源码构建并与应用一起打包，用于
  后续音频处理和 MP3/WAV 输出，无需用户另行安装 FFmpeg。

当前 Windows 实现属于 MVP：录音期间更改默认设备或拔插端点不会无缝迁移，
需要停止并重新开始录音；双来源采用有界 FIFO 与墙钟时轴对齐，并非基于
WASAPI QPC 时间戳的高精度同步。长时间双来源录音仍需在不同声卡和采样率的
实机上验证时钟漂移、补零与丢帧情况。

## Windows x64 构建

在安装 Flutter Windows 桌面工具链、Visual Studio C++ 工作负载与 Rust
`x86_64-pc-windows-msvc` 工具链后，从仓库根目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build_windows_package.ps1
```

脚本会从源码构建随应用发布的 x64 FFmpeg/LAME、Rust 原生录音 DLL、Flutter
Release、便携 ZIP 与 Inno Setup 安装包。产物位于 `dist/windows/<version>/`。

---

# EchoClip

EchoClip is an instant audio replay app for desktop and mobile devices. It is not intended to be a conventional voice recorder. Instead, it keeps a recent rolling buffer from the available audio sources so users can quickly save audio that just happened.

The audio processing feature is not yet ready. In the current version, this feature is just a demo. Please stay tuned for updates.

The current version of the app is highly usable, but there hasn't been enough time to conduct more extensive testing yet. If you encounter any issues, please submit them via the Issues page.

For product direction, platform constraints, Rust core boundaries, FFmpeg export behavior, and icon notes, see the documents under `docs/`:

- [Development Roadmap](docs/DEVELOPMENT_ROADMAP.md)
- [Rust Core Design](docs/rust-core.md)
- [Icon Design](docs/ICON_DESIGN.md)

See [LICENSE](LICENSE) for licensing.

## Windows x64 capabilities and architecture

Windows and Android use the same Flutter UI and settings page; there is no
Windows-specific frontend. Platform services only advertise capabilities to
that shared UI. Controls for unsupported features are disabled, such as system
audio capture and input-device selection on Android.

Rust owns the Windows capture lifecycle:

- `echoclip_windows_ffi` enumerates microphone endpoints through CPAL/WASAPI.
  A selected endpoint is persisted by its opaque, stable Windows ID. Selecting
  the system default stores `null`, so the current default input is resolved
  again when the next recording starts.
- System audio uses WASAPI loopback on the current default output endpoint.
  Users can record the microphone, system audio, or both.
- Each source is downmixed and resampled in Rust. A single 10 ms fixed-timeline
  mixer produces one mono PCM stream for the shared `RecorderWorker`. Missing
  source frames contribute silence, so the recording timeline continues while
  the system output is silent.
- `echoclip_core` stores the rolling cache as 60-second PCM segments and joins
  the required ranges when saving. Windows x64 FFmpeg/LAME is built from source
  and bundled for later audio processing and MP3/WAV output; users do not need
  a system FFmpeg installation.

The Windows implementation is currently an MVP. Changing or unplugging an
audio endpoint while recording requires stopping and restarting capture. The
dual-source mixer aligns bounded FIFO queues to a wall clock; it is not
high-precision WASAPI QPC timestamp synchronization. Long-running dual-source
capture still requires hardware testing for clock drift, silence insertion,
and dropped samples across different devices and sample rates.

## Windows x64 build

After installing the Flutter Windows toolchain, Visual Studio C++ workload,
and Rust `x86_64-pc-windows-msvc` toolchain, run from the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build_windows_package.ps1
```

The script builds the bundled x64 FFmpeg/LAME executable from source, the Rust
recorder DLL, the Flutter release, a portable ZIP, and an Inno Setup installer.
Artifacts are written under `dist/windows/<version>/`.
