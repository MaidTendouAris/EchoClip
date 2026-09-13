# EchoClip Server 部署

echoclip_server 只产出一个可执行文件：echoclip。同一个二进制同时提供 App 加密上传、WebUI、密钥生成和进程控制：

- 32581/tcp：App 实时上传。HTTP 上承载 EchoClip 自有的 ChaCha20-Poly1305 加密消息；服务器只在认证成功后向共享 echoclip_core 写入 PCM。
- 32580/tcp：纯 HTTP WebUI，按客户端复刻“录音、录音库、设置”三类服务端可用功能；不包含音频处理页或平台专属功能。它默认只接受回环、RFC1918 和 IPv6 ULA 来源。
- echoclip stop / echoclip reboot / echoclip reset key：从任意工作目录控制当前由同一全局二进制启动的实例。控制请求仅连接本机，并使用运行时随机令牌。

## Docker 启动

    cd deploy/server
    docker compose up -d --build
    docker compose logs -f echoclip-server

镜像中只复制并直接启动 /usr/local/bin/echoclip，没有 Web 服务器、证书服务或额外入口程序。首次启动且密钥文件不存在时，二进制会在独立 Docker 卷中生成权限为 0600 的随机 256 位上传密钥，并将完整密钥打印到首次启动日志：

    docker compose logs echoclip-server

也可以随时从持久卷读取当前密钥：

    docker compose exec echoclip-server sh -c 'cat /var/lib/echoclip-secrets/upload.key'

首次启动日志含完整密钥，应按敏感信息处理。后续普通启动和 reboot 只打印 key_id，不会再次打印已有密钥。

客户端“服务器设置”只填写三个输入框：IP/域名（不带 `http://`）、上传端口 `32581`、上传密钥。WebUI 地址为 http://服务器地址:32580。密钥不会写入镜像、Compose 文件、TOML、WebUI 或录音目录。

实时上传开关独立即时生效，不由“保存设置”按钮控制。每次从关闭切换为开启时，客户端以当前录音尾部为上传起点，只发送此后新录制的 PCM；网络恢复也只补传本次启用之后的录音，不会上传已有的长时间历史缓存。服务端使用自己的 WebUI 缓存时长，不要求与客户端缓存一致。

一个服务进程或 Docker 容器只服务一个客户端。多人使用时应复制部署，为每个客户端使用独立的 Web 端口、上传端口、数据卷和密钥；服务端不提供多用户路由。

第一次打开 WebUI 时必须确认服务器上的录音目录。Docker 部署建议直接采用界面预填的 /var/lib/echoclip/recordings；该路径位于 echoclip-data 持久化卷中。选择结果保存到 /var/lib/echoclip/server-state.json，后续重启不会再次询问，也可随时在设置页修改。浏览器不能访问服务器原生文件选择器，因此界面填写的是服务器绝对路径。

回放缓存时长只在 WebUI 的“服务器设置”中管理，保存后立即应用于全局唯一滚动缓存，并持久化到同一 server-state.json。每次开启上传或断线重连只建立新的协议续传游标，PCM 始终追加到同一缓存；客户端不再显示或发送服务器缓存时长。

WebUI 的实时状态通过 `/api/events` 使用 SSE 推送。服务端用最新值覆盖旧状态，避免慢页面积压事件，并每 15 秒发送连接保活；浏览器收到音量和缓存快照后使用动画帧平滑过渡、在两次上传之间本地推进缓存计时。EventSource 会自动重连，SSE 不可用时页面退回每 2 秒一次的状态轮询。SSE 只承载界面状态，不传输 PCM。

## 独立单二进制

在已安装 Rust 工具链的 Debian/Ubuntu 上构建并安装到全局 PATH：

    cargo build --locked --release --package echoclip_server
    sudo install -m 0755 target/release/echoclip /usr/local/bin/echoclip
    sudo install -d /etc/echoclip /var/lib/echoclip
    sudo install -m 0644 deploy/server/server.toml /etc/echoclip/server.toml
    echoclip serve --config /etc/echoclip/server.toml

echoclip serve 也可以省略 serve。配置查找顺序为 --config、ECHOCLIP_CONFIG、二进制旁的 server.toml，Linux 最后会尝试 /etc/echoclip/server.toml。相对数据和密钥路径按二进制目录解析；全局安装建议在 TOML 中使用绝对路径。

服务运行后，可在其他工作目录或终端执行：

    echoclip reboot
    echoclip stop
    echoclip reset key

reset key 会先警告旧密钥将立即失效，并要求输入精确的小写 yes。确认后，运行中的服务器使用操作系统安全随机源生成新密钥，以原子文件替换更新持久卷，同时切换内存认证状态并清空旧会话；命令完成时在当前终端打印新密钥。输入其他内容会取消，不修改密钥。所有客户端随后都必须填写新密钥。

reboot 会优雅关闭两个 HTTP listener、重新读取 TOML 并等待新 listener 就绪；stop 会等待运行实例完成关闭。运行描述文件位于当前用户的临时目录，带 0600 权限和每次启动重新生成的令牌，不依赖当前目录或 WebUI 端口的旧配置。

容器内使用相同命令：

    docker compose exec echoclip-server echoclip reboot
    docker compose exec echoclip-server echoclip stop
    docker compose exec echoclip-server echoclip reset key

Compose 配置了 restart: unless-stopped。如果希望容器保持停止状态，应使用 docker compose stop；容器内的 echoclip stop 退出主进程后，Docker 可能按重启策略再次启动它。

## 网络与安全边界

Compose 在 Linux 上使用 host network，使 Rust 服务能够看到真实客户端 IP，并据此执行 allowed_cidrs。这是默认内网限制的一部分，不应改为普通 Docker 端口转发后仍依赖来源 IP 判断。

App 上传虽然使用 HTTP，但 URL、设备 ID、PCM、ACK 和顺序号均受应用层 AEAD 认证；网络中的修改会在 PCM 写盘前被拒绝。WebUI 不加密、不认证，默认不得暴露到公网。

如管理员明确接受 WebUI 风险，可编辑 [server.toml](server.toml)，设置 webui.allow_public = true，然后执行 echoclip reboot（Docker 中通过 docker compose exec 执行）。服务只在启动时读取 TOML，公网模式会输出安全警告。

## 数据与更新

- 全局唯一的实时滚动分片和 manifest 位于 server.data_dir/cache。升级时会按创建时间把旧 server.data_dir/streams 中格式兼容的逐上传缓存合并进全局缓存；旧目录保留，便于回滚或人工核对。
- WebUI 保存的 WAV 和录音分组位于所选录音目录；WebUI 支持播放、倍速、下载、重命名、移动、单项/批量删除及分组管理。
- 唯一上传密钥位于 echoclip-secrets 卷；可用 echoclip reset key 主动轮换，删除该卷后首次启动也会生成新密钥，所有客户端都必须重新配置。
- 更新容器时运行 docker compose up -d --build，数据卷不会被重建。
- 备份时应同时备份数据目录、录音目录和密钥，并将密钥备份视为敏感信息。
