# EchoClip

EchoClip 是一个面向桌面与移动端的即时音频回放应用。它的目标不是替代传统录音机，而是在后台保留最近一段麦克风音频，让用户在需要时快速保存刚刚发生的声音片段。

音频处理功能还没做好，目前版本的该功能还只是个demo，等更新吧。

目前版本的app已经高度可用，但还没来得及做更多的测试，如有问题请提交issues。

产品设计、平台约束、Rust core 边界、FFmpeg 导出链路和图标规范等核心内容请阅读 `docs/` 中的文档：

- [开发路线图](docs/DEVELOPMENT_ROADMAP.md)
- [Rust Core 设计](docs/rust-core.md)
- [图标设计](docs/ICON_DESIGN.md)

项目许可证见 [LICENSE](LICENSE)。

---

# EchoClip

EchoClip is an instant audio replay app for desktop and mobile devices. It is not intended to be a conventional voice recorder. Instead, it keeps a recent rolling microphone buffer in the background so users can quickly save audio that just happened.

The audio processing feature is not yet ready. In the current version, this feature is just a demo. Please stay tuned for updates.

The current version of the app is highly usable, but there hasn't been enough time to conduct more extensive testing yet. If you encounter any issues, please submit them via the Issues page.

For product direction, platform constraints, Rust core boundaries, FFmpeg export behavior, and icon notes, see the documents under `docs/`:

- [Development Roadmap](docs/DEVELOPMENT_ROADMAP.md)
- [Rust Core Design](docs/rust-core.md)
- [Icon Design](docs/ICON_DESIGN.md)

See [LICENSE](LICENSE) for licensing.
