# EchoClip

EchoClip 是一个面向桌面与移动端的即时音频回放应用。它的目标不是替代传统录音机，而是在后台保留最近一段可用音频来源，让用户在需要时快速保存刚刚发生的声音片段。

0.6.0 新增由 Rust Core 管理的一次性定时任务，可按倒计时或指定时间开启/关闭录音、保存最近片段并切换实时上传。任务支持留空自动命名，以及最多 9 个用于快速新建的本地预设。独立音频处理模块已移除；FFmpeg、MP3 导出和录音库 WAV 转 MP3 继续保留。

目前版本的app已经高度可用，但还没来得及做更多的测试，如有问题请提交issues。

产品设计、平台约束、Rust core 边界、FFmpeg 导出链路和图标规范等核心内容请阅读 `docs/` 中的文档：

- [开发路线图](docs/DEVELOPMENT_ROADMAP.md)
- [Rust Core 设计](docs/rust-core.md)
- [定时任务设计与实现](docs/SCHEDULED_TASKS_DESIGN.md)
- [图标设计](docs/ICON_DESIGN.md)

项目许可证见 [LICENSE](LICENSE)。

---

# EchoClip

EchoClip is an instant audio replay app for desktop and mobile devices. It is not intended to be a conventional voice recorder. Instead, it keeps a recent rolling buffer from the available audio sources so users can quickly save audio that just happened.

Version 0.6.0 adds one-shot scheduled tasks owned by Rust Core. A countdown or time point can start or stop recording, save recent audio, and switch live upload. Task names can be generated automatically, and up to 9 local presets can be saved for quick task creation. The standalone processing module has been removed; bundled FFmpeg, MP3 export, and library WAV-to-MP3 conversion remain available.

The current version of the app is highly usable, but there hasn't been enough time to conduct more extensive testing yet. If you encounter any issues, please submit them via the Issues page.

For product direction, platform constraints, Rust core boundaries, FFmpeg export behavior, and icon notes, see the documents under `docs/`:

- [Development Roadmap](docs/DEVELOPMENT_ROADMAP.md)
- [Rust Core Design](docs/rust-core.md)
- [Scheduled Tasks Design and Implementation](docs/SCHEDULED_TASKS_DESIGN.md)
- [Icon Design](docs/ICON_DESIGN.md)

See [LICENSE](LICENSE) for licensing.
