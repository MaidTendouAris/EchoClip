# EchoClip

EchoClip 是一个面向桌面与移动端的即时音频回放应用。它的目标不是替代传统录音机，而是在后台保留最近一段麦克风音频，让用户在需要时快速保存刚刚发生的声音片段。

项目当前以 Windows 与 Android 为主要目标平台，技术栈以 Flutter 前端、Rust 音频核心和 Android 原生采集服务为基础。iOS 暂不进入当前开发排期，但架构上保留未来兼容空间。

EchoClip 仍处于早期开发阶段。产品设计、平台约束、Rust core 边界、FFmpeg 导出链路和图标规范等核心内容请阅读 `docs/` 中的文档：

- [开发路线图](docs/DEVELOPMENT_ROADMAP.md)
- [Rust Core 设计](docs/rust-core.md)
- [图标设计](docs/ICON_DESIGN.md)

项目许可证见 [LICENSE](LICENSE)。

---

# EchoClip

EchoClip is an instant audio replay app for desktop and mobile devices. It is not intended to be a conventional voice recorder. Instead, it keeps a recent rolling microphone buffer in the background so users can quickly save audio that just happened.

The current project focuses on Windows and Android, using Flutter for the app UI, Rust for the audio core, and native Android services for microphone capture. iOS is not part of the current development target, but the architecture leaves room for future support.

EchoClip is still in early development. For product direction, platform constraints, Rust core boundaries, FFmpeg export behavior, and icon notes, see the documents under `docs/`:

- [Development Roadmap](docs/DEVELOPMENT_ROADMAP.md)
- [Rust Core Design](docs/rust-core.md)
- [Icon Design](docs/ICON_DESIGN.md)

See [LICENSE](LICENSE) for licensing.
