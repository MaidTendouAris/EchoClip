# EchoClip 实时同步服务设计

## 1. 目标与边界

EchoClip 服务端用于接收 App 实时上传的原始 PCM，并用现有
`echoclip_core` 完成与本地客户端一致的 60 秒分片、缓存恢复、快照与导出。
服务端通过 WebUI 查看状态和保存录音，最终以单个 Docker 容器分发，优先支持
Debian 命令行服务器。

本方案刻意保持简单：

- App 上传链路必须保密，并能发现篡改、伪造、重放和乱序。
- WebUI 使用普通 HTTP，不在 EchoClip 内实现 TLS 或完整的公网管理面安全。
- WebUI 默认只接受本机和私有网络来源；需要公网访问时，管理员修改 TOML 并重启服务。
- 不依赖 Caddy、Nginx、ACME 或证书服务。
- 客户端与服务端只共享一套现有 `echoclip_core`，不创建“服务端 core”。
- 一个服务进程或 Docker 容器只服务一个客户端；客户端只配置 IP/域名、上传端口和密钥。
- 多客户端场景通过部署多个实例实现，每个实例使用独立的 Web 端口、上传端口、数据卷和密钥。
- 回放缓存时长由 WebUI 管理并持久化，上传协议不接受客户端缓存策略。

不在本次范围内：

- 防止攻击者阻断、延迟或限速网络连接；
- WebUI 公网暴露后的认证、加密与安全代理配置；
- 服务器磁盘静态加密；
- 多租户、组织权限、云端转码或服务器主动推送。

## 2. 总体架构

服务端是一个 Rust 进程、一个 WebUI 静态站点和一个 Docker 容器，但监听两个端口：

```text
EchoClip App
  原生采集
      │ PCM
      ▼
共享 echoclip_core ── PcmCommitted 观察事件
      │                         │
      │ 本地 60s 分片           ▼
      │                  echoclip_sync_client
      │                  AEAD 加密上传
      │                         │
      └─────────────────────────┼──────── 公网/局域网
                                ▼
                    :32581 App 上传入口（HTTP 承载密文）
                                │ 解密、认证、顺序校验
                                ▼
                    共享 echoclip_core
                    60s 分片 / 恢复 / 快照 / 导出
                                ▲
                                │
                    :32580 WebUI（普通 HTTP）
                    默认仅本机和私有网段可访问
```

两个 HTTP 入口的安全含义不同：

- `upload` 入口可以直接暴露到公网。HTTP 请求体中的业务内容全部经过应用层 AEAD
  加密，录音和控制字段不会以明文传输。
- `webui` 入口不使用该 App 上传密钥，也不承诺公网安全。它默认由来源 IP
  白名单限制在内网；管理员显式开放公网即表示自行承担风险或在外部部署安全代理。

## 3. 代码与 crate 划分

只保留一个核心 crate：

```text
crates/
  echoclip_core/          # 唯一核心：分片、恢复、缓存、快照、导出
  echoclip_sync_protocol/ # 上传消息、加密信封和协议编解码
  echoclip_sync_client/   # App 侧上传状态机
  echoclip_server/        # HTTP、WebUI、身份认证、会话 actor
```

`echoclip_sync_protocol` 是协议库，不是另一套录音核心。`echoclip_server` 直接依赖
现有 `echoclip_core`。

### 3.1 对现有 core 的通用扩展

对 `echoclip_core` 增加可被所有运行形态复用的能力：

1. `PcmCommitted` 非阻塞观察接口：core 接受 PCM 后报告稳定的样本区间，观察者失败
   不阻塞本地录音。
2. 按样本范围读取缓存快照：上传失败后只从“本次启用上传”的样本边界之后补传，不读取
   开启上传之前的历史缓存，也不维护第二份无限增长的上传缓存。
3. 稳定的逻辑流 ID、音频格式和 `next_sample` 状态。
4. 明确的 flush/恢复结果，供客户端上传和服务端 ACK 使用。

这些 API 不含 HTTP、密钥、Docker 或 WebUI 概念。Android、Windows 和未来桌面平台
继续使用同一 Flutter 前端与同一 core。

## 4. 唯一密钥模型

每个 EchoClip 服务实例使用一个由操作系统密码学安全随机源生成的 256 位上传主密钥。
首次运行且密钥文件不存在时，服务器自动生成权限为 0600 的密钥文件，并在当前命令行
打印一次完整密钥和 key_id；Docker 部署中该输出可从首次启动日志读取。已有密钥的普通
启动和 reboot 只打印 key_id，不重复输出完整密钥。

管理员可在任意工作目录执行：

    echoclip reset key

命令先说明旧密钥将立即失效，并要求输入精确的小写 yes。确认后，请求由本机运行描述文件
中的随机控制令牌认证；运行中的服务器生成新密钥，以原子替换写入原密钥路径，同时切换
内存认证状态、生成新的 server_instance_id 并清空全部旧 epoch。新密钥返回到执行命令的
终端，原密钥和所有既有会话从切换点起不再被接受。输入其他内容只取消操作。

密钥规则：

- 必须来自操作系统密码学安全随机数源，不允许使用用户口令直接充当密钥。
- 服务端保存实际密钥以解密上传内容，不能只保存哈希。
- 密钥不写入镜像、TOML、数据库、录音目录或 WebUI。
- 完整密钥只允许出现在首次生成输出、reset key 的确认终端和密钥文件中；这些终端输出及
  Docker 首次启动日志必须按敏感信息处理。日常日志仅记录短指纹 key_id。
- App 通过可信的手工渠道导入一次。轮换后必须立即更新该实例对应的客户端。
- Android 使用 Android Keystore 保护本地密钥；Windows 使用 Credential Manager 或
  DPAPI。Flutter/Dart 层不处理明文 PCM，也尽量不长期持有主密钥。

单一主密钥配合“一实例只服务一个客户端”的部署模型，不提供用户账户或多设备密钥路由。
需要多个客户端时部署多个独立实例，并为每个实例使用不同端口、数据卷和密钥。

## 5. 上传加密协议

### 5.1 算法选择

使用标准算法，不自行设计密码原语：

- AEAD：ChaCha20-Poly1305；
- KDF：HKDF-SHA-256；
- 主密钥：随机 32 字节；
- nonce：96 位；
- 认证标签：128 位。

Rust 可采用经过审计并广泛使用的 RustCrypto 实现，例如
`chacha20poly1305`、`hkdf`、`sha2` 和 `zeroize`。这些只是编译进程序的代码依赖，
不会增加部署服务。

AEAD 同时提供机密性和完整性。只有持有主密钥的 App 才能生成服务器接受的消息；任何对
密文、认证头或标签的修改都会导致认证失败，并且失败的数据绝不能进入 `echoclip_core`。

### 5.2 为什么不能直接用固定密钥和递增计数

ChaCha20-Poly1305 要求同一个密钥下 nonce 永不重复。App 重启、数据清除、恢复旧备份或
两台设备同时上传时，单纯从零开始的本地计数器会重复 nonce，严重破坏保密性和认证能力。

因此每次连接先获取服务端生成的随机 epoch，再从主密钥派生仅用于本次连接的方向密钥。

### 5.3 建立 epoch

App 发起：

```http
POST /upload/v1/challenge HTTP/1.1
Content-Type: application/json

{"key_id":"a1b2c3d4"}
```

服务端返回：

```json
{
  "protocol": 1,
  "server_instance_id": "16-byte-random-or-stable-id",
  "epoch_id": "16-byte-random-id",
  "expires_at": 1787200000
}
```

规则：

- `epoch_id` 使用密码学安全随机数生成，针对同一 `key_id` 不得复用。
- challenge 有较短有效期，例如 60 秒；未建立会话的 challenge 到期即删除。
- challenge 接口不接收录音，也不证明身份，因此必须做请求大小、并发和速率限制，避免
  被用于资源耗尽。
- 服务器重启后，未完成的 challenge 全部作废。App 获取新 epoch 后继续逻辑录音流。

双方派生两个方向密钥：

```text
salt  = server_instance_id || epoch_id
K_c2s = HKDF-SHA256(master_key, salt, "echoclip-upload-v1-c2s")
K_s2c = HKDF-SHA256(master_key, salt, "echoclip-upload-v1-s2c")
```

上下行使用不同密钥，因此两个方向可分别从序号 0 开始。

### 5.4 nonce 和序号

每个方向的 nonce 由固定 32 位域标识和 64 位大端序消息序号组成：

```text
nonce = direction_domain_u32 || sequence_u64_be
```

- 新 epoch 的首条消息序号为 0，每成功发送一条加 1。
- 序号溢出前必须建立新 epoch；实际上单次连接不可能达到该数量。
- 重连总是获取新 epoch 和新方向密钥，不跨 epoch 复用 nonce。
- 服务端持久化活动逻辑流的 `next_sample`，epoch 只是传输会话，不是录音身份。

### 5.5 加密信封

所有已认证请求通过统一端点发送：

```http
POST /upload/v1/envelope HTTP/1.1
Content-Type: application/octet-stream
```

信封结构：

```text
明文且作为 AEAD AAD 认证：
  magic
  protocol_version
  key_id
  epoch_id
  sequence
  ciphertext_length

AEAD 密文：
  message_type
  message_body
  authentication_tag
```

明文头只用于路由和找到会话密钥，整个头必须作为 Additional Authenticated Data
参与认证。任何未经认证的字段都不得影响 PCM 写入、文件路径、音频格式或 core 行为。

加密消息类型：

```text
OpenOrResume
  device_id
  client_stream_id
  sample_rate
  channels
  sample_format = pcm_s16le
  source_start_sample

Pcm
  server_stream_id
  start_sample
  sample_count
  pcm_bytes

Close
  server_stream_id
  final_sample

MarkIncomplete
  server_stream_id
```

服务端响应同样使用 `K_s2c` 加密，至少包含：

```text
status
server_stream_id
next_sample
accepted_sample_count
error_code
```

这样不仅上传内容不可被篡改，攻击者也不能伪造“服务器已保存”的 ACK 诱导客户端丢弃
待补传区间。

### 5.6 重试、重放和乱序

HTTP 超时后，App 必须重发完全相同的已序列化信封，即相同序号、AAD、nonce 和密文，
不能用相同序号重新加密不同内容。

服务端行为：

- 首次收到期望序号：认证、校验并处理，持久化结果后返回加密 ACK。
- 收到已处理序号且密文完全相同：返回缓存的相同处理结果，不重复写 PCM。
- 收到相同序号但密文不同：拒绝并记录安全事件。
- 收到高于期望序号：拒绝为 gap，返回当前 `next_sample`。
- 收到无效标签、未知 epoch、过期 challenge 或错误密钥：统一拒绝，不暴露详细认证原因。

协议还要求：

```text
Pcm.start_sample == server.next_sample
pcm_bytes.length == sample_count * channels * sizeof(i16)
音频格式 == OpenOrResume 中已认证的固定格式
```

服务端只有在 AEAD 认证、序号、样本位置、长度和资源限制全部通过后，才能调用 core。

## 6. 实时 PCM 与 core 的衔接

### 6.1 App 侧

1. 原生采集把 PCM 直接送入共享 echoclip_core，保持现有本地录音行为。
2. 实时上传开关独立即时生效；从关闭切换为开启时，记录当前 total_samples_written 作为
   upload_start_sample，并为本次启用生成新的逻辑流 ID。
3. core 提交样本后触发轻量 PcmCommitted 事件；事件只用于提示，不直接触发一次 HTTP 请求。
4. echoclip_sync_client 每 250ms 最多发送一个 PCM 包，读取范围不得早于
   max(upload_start_sample, retained_start_sample)。
5. 服务端 ACK next_sample 后，客户端记录远端进度。
6. 网络失败时本地录音不停止；恢复后只补传本次启用之后且仍由 core 保留的分片。关闭再
   开启会创建新的上传边界，任何情况下都不会回溯上传开启前的 12 小时等历史缓存。

上传队列必须有界，不能让弱网造成内存无限增长。只保留样本位置和少量正在发送的密文，
大块补传数据从 core 分片按范围读取。

客户端界面保持平台共享，不为 Windows 或 Android 复制页面：

- 主页模式切换按钮左侧只显示一个可点击的纯色圆点，不常驻状态文字；未配置为灰色，
  正在连接、已连接和失败分别使用不同颜色；
- 点击圆点才显示地址、当前状态和最近错误，并可跳转到设置；
- 一级设置页只有“服务器设置”入口；实时上传开关使用独立面板并在切换时立即持久化、启停
  上传客户端，不受“保存设置”按钮控制；连接表单只包含 IP/域名、上传端口和上传密钥三个
  输入框，保存连接参数时保持当前开关状态；
- 客户端只负责上传启用之后的录音，不显示或修改服务端缓存与其他服务器设置；
- 明文上传密钥只在首次录入时短暂存在。Android 用 Keystore 包装，Windows 用 DPAPI 包装，
  常规设置读取不会把密钥返回 Flutter。

若服务端需要的、且位于本次上传启用边界之后的样本已经被本地缓存淘汰：

- 将原服务端逻辑流标记为 `incomplete`；
- 从 max(upload_start_sample, retained_start_sample) 创建新的逻辑流；
- WebUI 显示缺口，不用静音或伪造样本掩盖丢失；
- 服务端缓存长度完全由 WebUI 管理，不要求与客户端本地缓存长度相同。

### 6.2 服务端侧

单个服务实例只维护一个全局 `echoclip_core::SegmentedRecorder`。每次客户端开启上传会创建
独立的协议续传游标，但不会创建新的录音缓存：

1. 解密层验证信封并生成已认证的 `Pcm` 命令；
2. 串行写入锁用协议会话的 `source_start_sample` 与全局 `cache_start_sample` 校验位置；
3. PCM 追加到全局唯一 recorder，core 按 60 秒生成分片并原子更新 manifest；
4. flush/manifest 成功后更新该协议会话的 `next_sample` 并返回加密 ACK；
5. 关闭、重连或下一次开启上传只关闭/新建游标，全局缓存继续滚动保留。

服务器进程崩溃后，core 恢复 `data_dir/cache` 中的分片和 manifest，持久化的上传会话映射
继续提供 `OpenOrResume` 所需的 `next_sample`。旧版本 `data_dir/streams/*` 会在首次升级启动
时按创建时间合并，原目录不删除；音频格式不兼容的旧流不会混入同一 PCM 缓存。

### 6.3 保存逻辑

服务端不在 App 侧提供“保存远端录音”操作。管理员进入 WebUI：

- 查看在线设备、远端缓冲时长、最后上传时间和缺口状态；
- 选择“保存最近 N 秒”或自定义时间范围；
- 由服务端直接调用共享 core 的 snapshot/export；
- 浏览、试听、调速、下载、重命名、移动和单项/批量删除已保存录音；
- 创建、重命名和删除与客户端一致的录音分组。

首次打开 WebUI 且没有旧版录音目录或持久化状态时，管理员必须填写服务器上的绝对录音
目录。服务端创建并验证目录可写后，将选择保存到 data_dir/server-state.json；未完成设置前
实时上传仍可写入滚动缓存，但保存、浏览和下载录音会被拒绝。浏览器不使用客户端本地目录
选择器，避免把管理端设备路径误当作服务器路径。

WebUI 直接调用 core 保存 WAV，并复刻客户端中适用于服务器的录音页、录音库和设置页。服务端
不提供音频处理页，也不展示音频输入、托盘、热键等当前平台不可用功能。

## 7. WebUI HTTP 与内网限制

WebUI 是独立的普通 HTTP listener，不复用 App 上传密钥，也不提供 EchoClip 内建 TLS。

`GET /api/events` 提供单向 SSE 实时状态流。每次缓存写入、会话开关或缓存设置变化只发布最新一代状态，`watch` 通道合并中间值，不允许慢浏览器形成无界队列。事件含服务器毫秒时间、全局缓存快照、连接状态及音量电平，连接每 15 秒保活。浏览器通过 `requestAnimationFrame` 平滑音量，并在最新快照基础上本地插值缓存时长；原生 EventSource 负责重连，连接不可用时退回 2 秒状态轮询。PCM 不进入 SSE。

默认允许来源：

- `127.0.0.0/8`、`::1/128`；
- RFC 1918：`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`；
- IPv6 ULA：`fc00::/7`。

服务器按实际 TCP peer IP 判断来源，默认不信任 `X-Forwarded-For`、`Forwarded` 等请求头，
防止客户端伪造内网地址。若未来需要反向代理，应另设明确的 `trusted_proxy_cidrs`，不自动
继承当前白名单。

管理员决定公网开放时，在 TOML 中设置：

```toml
[webui]
allow_public = true
```

修改只在服务启动时读取，必须重启后生效。启用时服务端应：

- 在启动日志打印醒目且不含密钥的安全警告；
- 在 WebUI 顶部持续显示“公网访问已允许，连接未由 EchoClip 加密”的警告；
- 不暗示 App 上传 AEAD 能保护 WebUI 会话。

公网 WebUI 的认证、TLS、VPN、防火墙或反向代理由用户自行选择并承担风险。

## 8. TOML 配置

建议默认配置：

```toml
[server]
data_dir = "/data"
log_level = "info"

[upload]
bind = "0.0.0.0:32581"
key_file = "/run/secrets/echoclip_upload_key"
max_envelope_bytes = 262144
challenge_ttl_seconds = 60
epoch_idle_seconds = 300
max_pending_challenges = 1024
max_connections_per_ip = 8
max_requests_per_minute_per_ip = 3600
max_active_streams = 128
max_replay_seconds = 86400

[webui]
bind = "0.0.0.0:32580"
allow_public = false
allowed_cidrs = [
  "127.0.0.0/8",
  "::1/128",
  "10.0.0.0/8",
  "172.16.0.0/12",
  "192.168.0.0/16",
  "fc00::/7",
]

[recording]
segment_seconds = 60
buffer_seconds = 86400
```

`recording.buffer_seconds` 仅作为首次启动默认值。管理员在 WebUI 修改缓存时长后，
服务会将其写入 `server-state.json`，立即更新全局唯一缓存；客户端不能覆盖。
监听端口属于实例部署参数，多个客户端需要复制实例并修改两个监听端口与数据卷。

配置校验：

- 服务二进制在上传密钥缺失时以 0600 自动生成正式随机密钥并打印一次；长度错误或权限
  过宽时拒绝启动。密钥持久化后，普通重启和 reboot 不会轮换，只有确认后的 reset key
  会替换密钥。
- `segment_seconds` 首版固定为 60；配置与 core 不一致时拒绝启动。
- 限制最大 envelope、音频格式、采样率、通道数、活动流数量和每设备速率。
- TOML 不允许内联上传主密钥，避免密钥进入 compose、备份和版本控制。

## 9. Docker 分发

首版交付物：

```text
deploy/server/
  Dockerfile
  compose.yaml
  server.toml
  README.md
```

容器约束：

- Rust builder + Debian bookworm slim 多阶段构建；
- 单个 echoclip 进程，以非 root 用户运行；
- /var/lib/echoclip 为滚动缓存、首次设置状态和推荐录音目录的持久化卷；
- `/var/lib/echoclip-secrets/upload.key` 为独立持久化密钥文件，首次启动以 `0600` 生成；
- `32581/tcp` 为 App 加密上传入口；
- `32580/tcp` 为 WebUI，Rust 按 TOML 的私网 CIDR 限制来源；
- Linux 使用 host network，确保 CIDR 判断基于真实 TCP peer，而不是 Docker NAT 网关地址；
- root 文件系统只读，删除全部 capabilities，并启用 `no-new-privileges`；
- 不包含 Caddy、Nginx、证书、ACME 客户端或第二个服务容器。

容器直接执行同一个 echoclip serve 入口。该二进制也提供全局 echoclip stop、
echoclip reboot 和 echoclip reset key；控制命令通过当前用户临时目录中的 0600 运行
描述文件定位实例，只连接本机控制地址并携带每次启动重新生成的随机令牌。reboot 在同一
进程中优雅重建 listener 并重新读取 TOML；reset key 在同一进程内原子替换磁盘与内存
认证状态，两者都不依赖调用命令时的工作目录。
示意 compose：

```yaml
services:
  echoclip-server:
    build:
      context: ../..
      dockerfile: deploy/server/Dockerfile
    restart: unless-stopped
    network_mode: host
    read_only: true
    volumes:
      - ./server.toml:/etc/echoclip/server.toml:ro
      - echoclip-data:/var/lib/echoclip
      - echoclip-secrets:/var/lib/echoclip-secrets
```

host network 是 Debian/Ubuntu 部署约束。若改用普通端口转发，容器可能只看到 Docker
网关地址，不能再把服务内的 peer-IP CIDR 检查当成公网隔离边界。

## 10. 能保护什么、不能保护什么

上传 AEAD 能够：

- 防止旁路观察者读取 PCM 和已认证的业务元数据；
- 检测 PCM、消息类型、样本位置、音频格式和 ACK 的任何篡改；
- 拒绝不知道密钥的伪造客户端；
- 配合 epoch、序号和样本位置拒绝重放、重复写入、乱序和插入。

它不能：

- 防止攻击者丢包、断网、延迟请求或耗尽公网带宽；
- 隐藏 IP、连接时间、请求尺寸和流量模式；
- 保护已被恶意软件控制的 App 或服务器；
- 自动加密服务器磁盘上的 PCM、WAV、MP3 和备份；
- 保护按用户选择开放到公网的普通 HTTP WebUI。

服务器录音目录建议位于加密磁盘，并使用加密备份。应用层加密只覆盖 App 与上传入口之间的
传输，在服务器通过认证后会解密为 core 使用的原始 PCM。

## 11. 安全实现约束

- 认证失败时先丢弃完整消息，再返回统一错误；严禁部分 PCM 进入 core。
- 密钥、派生密钥和解密缓冲在使用后尽快清零；禁止 Debug 输出。
- 先验证长度上限再分配内存，避免畸形 `ciphertext_length` 导致大分配。
- AEAD 解密与协议解析放在写盘之前；解析后的文件路径只能由服务端生成。
- 对 challenge、连接数、活动流数、包大小和每 IP 速率设置硬上限。
- 错误响应不区分未知 `key_id`、错误标签和过期 epoch，减少身份枚举信息。
- 记录安全事件时只写时间、来源 IP、公开 key 指纹和错误类别。
- 加密响应必须有独立下行序号，不能重复使用 nonce。
- 服务时钟异常不能导致 epoch ID 重复；epoch 完全依赖随机数而不是时间戳。
- 协议版本和算法套件进入 AAD；不允许无提示降级到明文上传。

## 12. 测试与验收

### 12.1 协议安全测试

- 使用错误主密钥，服务器拒绝且 core 没有新增样本。
- 分别翻转 AAD、密文和 tag 任意一位，全部在写盘前拒绝。
- 篡改服务端加密 ACK，客户端不得推进远端进度。
- 重放完全相同的包，只返回缓存 ACK，不重复追加 PCM。
- 相同 epoch/sequence 发送不同密文，明确拒绝。
- 跳过序号、倒序、跨 epoch 重放、过期 challenge 全部拒绝。
- 模拟 App 重启和计数归零，确认新 epoch 生成不同方向密钥和 nonce 空间。
- fuzz 信封长度、消息类型、样本数、通道数和截断 tag，无 panic 和越界分配。

### 12.2 录音一致性测试

- 同一 PCM 同时输入本地 core 和服务端 core，分片边界与导出 WAV 样本一致。
- 跨越多个 60 秒分片保存最近 N 秒，结果与客户端一致。
- 请求超时后重复发送，不重复样本。
- 客户端已有 12 小时缓存时开启上传，upload_start_sample 从当前尾部开始，历史样本数不会
  出现在待上传数量中。
- 断网后仅补传本次启用后的本地分片，服务端从 next_sample 无缝继续。
- 本次启用后的缓存已经淘汰缺口时，旧协议会话标记 incomplete，不伪造静音。
- 连续两次启用上传、断线重连和服务器重启后，录音仍按时间顺序进入同一个全局缓存。
- 旧版逐上传 streams 在升级时合并到全局 cache，样本顺序正确且旧目录不删除。
- 持续实时录音和积压恢复均保持每 250ms 最多一个 PCM 请求，在部署限额下不产生 429。
- 服务端在分片写入、manifest 更新和 ACK 各阶段崩溃后均可恢复。

### 12.3 WebUI 与部署测试

- `allow_public=false` 时，本机和配置私网可访问，非白名单 peer IP 返回拒绝。
- 伪造 `X-Forwarded-For: 127.0.0.1` 不能绕过 peer IP 限制。
- 修改 TOML 但不重启时行为不变；重启后 `allow_public=true` 才生效。
- 公网模式启动日志和 WebUI 警告均可见。
- /api/events 建连后立即返回当前快照；连续 PCM 写入只推最新状态，15 秒保活可检测半开连接。
- 浏览器收到离散快照后缓存时间连续前进、音量平滑变化；SSE 断开时自动重连并启用低频轮询，恢复后停止轮询。
- 当前 Debian/Ubuntu LTS 命令行服务器上只用 Docker/Compose、配置、密钥和数据卷即可启动。
- 容器内只有一个 EchoClip 服务进程，不要求 Caddy 或证书。

## 13. 实施顺序

1. 为现有 `echoclip_core` 增加提交观察和按样本范围读取能力，并补跨分片测试。
2. 实现 `echoclip_sync_protocol` 的 HKDF、AEAD 信封、epoch、序号和测试向量。
3. 实现 App 侧有界上传状态机，先完成断网重试和从 core 补传。
4. 实现服务端 challenge/envelope、协议会话游标、全局唯一 core 缓存和旧流迁移。
5. 实现 WebUI 的状态、保存、播放、下载和文件管理。
6. 加入 TOML 私网访问控制、Docker、Secret 和 Debian 验收。
7. 完成错误密钥、篡改、重放、崩溃恢复和长时间公网弱网测试。

## 14. 最终技术路线确认

首版采用以下固定路线：

- **核心复用**：客户端和服务端使用同一个现有 `echoclip_core`；
- **服务端**：Rust + WebUI，单进程、单 Docker 容器、Debian 优先；
- **录音存储**：服务端接收原始 PCM，所有上传会话追加到一个全局 core 缓存并生成 60 秒分片；
- **保存入口**：远端录音只在 WebUI 执行保存和管理；
- **上传安全**：每服务实例唯一 256 位主密钥，HKDF-SHA-256 派生连接方向密钥，
  ChaCha20-Poly1305 加密并认证所有上传和 ACK；
- **防篡改**：AAD、严格序号和 `next_sample` 共同保护元数据、PCM 顺序与幂等性；
- **WebUI**：普通 HTTP，默认仅本机/私网，TOML 显式允许公网且重启生效；
- **部署依赖**：不引入 Caddy、Nginx、证书或 ACME 服务。

该路线满足“唯一密钥、部署简单、录音不可被网络攻击者静默篡改”的目标，同时明确把
WebUI 公网安全和服务器磁盘安全留给部署者管理。

## 15. 参考标准与平台文档

- [RFC 5116: An Interface and Algorithms for Authenticated Encryption](https://www.rfc-editor.org/rfc/rfc5116.html)
- [RFC 8439: ChaCha20 and Poly1305 for IETF Protocols](https://www.rfc-editor.org/rfc/rfc8439.html)
- [RFC 5869: HKDF](https://www.rfc-editor.org/rfc/rfc5869.html)
- [Android Keystore system](https://developer.android.com/privacy-and-security/keystore)
- [Microsoft Data Protection API: CryptProtectData](https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata)
