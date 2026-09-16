# EchoClip Android 正式签名

自己创建并长期保管的签名密钥即可用于发布 APK，无需购买 CA 证书。Release 是构建模式，真正决定应用身份的是签名密钥；仅把文件名改成 `release.apk` 不会改变签名。

本项目现在从 `apps/echoclip/android/key.properties` 读取 Release 签名配置。缺少配置、必要字段或密钥文件时，Release 构建会失败，Debug 构建不受影响。配置只在本地使用，不会提交到 Git。

## 当前项目的签名配置（2026-09-15）

已按用户要求创建并配置正式密钥。后续构建直接运行第 3 节脚本；不要再次生成密钥。

- 密钥：`%USERPROFILE%/.android-signing/echoclip-release.jks`，别名 `echoclip`。
- 本地恢复配置：`%USERPROFILE%/.android-signing/echoclip-release.properties`，包含密钥库位置、别名和随机生成的密码。
- 当前构建配置：`apps/echoclip/android/key.properties`，已被 Git 忽略。私密目录与构建配置的 Windows ACL 仅授予当前用户和 SYSTEM 访问权限。
- 公共证书：`%USERPROFILE%/.android-signing/echoclip-release-cert.der`。RSA 3072 位，SHA256withRSA，自签名证书有效至 2054-01-31。
- 证书 SHA-256：`d5c63e64a36ea2566ebbf3988da943c4e0aa3d21359904fc1f198cce60280c3b`。

请将整个 `.android-signing` 文件夹备份到安全位置。JKS 和密码配置需要一起保留；密码配置包含明文口令，不应上传到代码仓库或附在公开发布文件中。在新电脑恢复时，将备份 properties 复制为 `android/key.properties`，再按实际密钥位置调整 `storeFile`，继续使用原 JKS 和密码。

正式签名与过去的 Android Debug 签名不同，首次切换无法直接覆盖安装。先导出录音并记录设置，再卸载旧版、安装正式版；以后持续沿用此密钥并递增版本号。

## 1. 准备密钥（只做一次）

如果已经按此前的步骤生成了 `echoclip-release.jks`，直接进入第 2 步。之后每次更新都使用同一把密钥，不要重新生成。

在 PowerShell 中执行以下命令；JDK 路径按实际安装位置调整。密码通过交互提示输入，不写在命令行里。

```powershell
$signingDir = "$env:USERPROFILE\.android-signing"
New-Item -ItemType Directory -Force -Path $signingDir | Out-Null
& "C:\Program Files\Java\jdk-17\bin\keytool.exe" -genkeypair -v `
  -keystore "$signingDir\echoclip-release.jks" `
  -storetype JKS -alias echoclip `
  -keyalg RSA -keysize 3072 -validity 10000
```

记住密钥库密码、密钥密码和别名。若创建时在密钥密码提示处直接回车，密钥密码与密钥库密码相同。妥善备份 JKS 文件与密码，不要把它们放进 GitHub、安装包或聊天消息里。

## 2. 配置本地签名

在仓库根目录执行，只在配置不存在时复制示例：

```powershell
Set-Location D:\github\EchoClip
$signingConfig = 'apps/echoclip/android/key.properties'
if (-not (Test-Path -LiteralPath $signingConfig)) {
  Copy-Item -LiteralPath 'apps/echoclip/android/key.properties.example' `
    -Destination $signingConfig
}
notepad $signingConfig
```

填写以下四项并保存为 UTF-8（无 BOM）。尖括号内容需要替换为真实密码，不要保留尖括号：

```properties
storeFile=C:/Users/MaidT/.android-signing/echoclip-release.jks
keyAlias=echoclip
storePassword=<创建时设置的密钥库密码>
keyPassword=<创建时设置的密钥密码>
```

- `storeFile` 改为你实际的 JKS 路径；Windows 路径建议使用 `/`，不要加引号。相对路径以 `apps/echoclip/android/` 为基准，`~` 和 `$env:USERPROFILE` 不会自动展开。
- `keyAlias` 必须与创建密钥时的 `-alias` 相同。
- Java properties 把反斜杠当作转义字符；密码里如果包含一个 `\`，配置中要写成 `\\`。
- `key.properties` 和 Android 目录下的 `*.jks`、`*.keystore` 已被 Git 忽略。密钥仍建议保存在仓库外。

## 3. 构建正式 APK

在仓库根目录执行：

```powershell
pwsh -NoProfile -File scripts/build_android_package.ps1 -BuildMode release
```

脚本会先检查签名配置，再构建原生依赖和 APK。它读取 `apps/echoclip/pubspec.yaml` 中的版本，生成：

```text
dist/android/<版本名>/EchoClip-<版本名>+<版本号>-arm64-v8a-release.apk
```

该次新生成的 APK 已使用本地正式密钥签名，无需再运行 `apksigner sign`。重新打包前已有的旧 APK 不会因修改配置而自动换签名；构建失败时不要把旧文件当成本次产物。

发布更新时沿用同一份签名配置，并递增 versionCode，例如使用脚本的 `-VersionName` 和 `-VersionCode` 参数。只做日常调试可使用 `-BuildMode debug`，不需要正式签名配置。

原生依赖已准备好时，直接运行 Flutter 的 Release APK 或 App Bundle 构建也会使用相同配置。

## 4. 验证签名

下面以当前 `0.6.1+10` 为例。SDK Build Tools 版本和 APK 文件名有变化时替换对应路径。

```powershell
$apk = 'D:\github\EchoClip\dist\android\0.6.1\EchoClip-0.6.1+10-arm64-v8a-release.apk'
$apksigner = "$env:LOCALAPPDATA\Android\Sdk\build-tools\36.1.0\apksigner.bat"
& $apksigner verify --verbose --print-certs $apk
& "C:\Program Files\Java\jdk-17\bin\keytool.exe" -list -v `
  -keystore "$env:USERPROFILE\.android-signing\echoclip-release.jks" `
  -alias echoclip
```

确认 APK 校验通过，并比较两份输出的证书 SHA-256 指纹，应当一致（忽略冒号和大小写）。这能确认使用了自己的密钥，而不是 Android Debug 密钥。APK 文件本身的 SHA-256 与证书指纹是不同的值。

## 已安装版本与 Google Play

此前 EchoClip 安装包采用 Debug 签名。换成新密钥后，普通覆盖安装会因签名不一致而失败。先导出需要保留的录音、记录设置，再卸载旧版并安装正式签名版；卸载会清除应用私有数据。后续持续使用同一密钥即可正常升级。

如果将来发布到 Google Play，需要区分“上传密钥”和“应用签名密钥”：上传的 AAB 使用上传密钥签名，用户下载的 APK 由 Play App Signing 使用应用签名密钥签名。希望 GitHub APK 与 Play 版可以互相覆盖更新时，首次接入 Play App Signing 就应安排相同的应用签名密钥，而不是让两边各自生成一把。

官方参考：[Flutter Android 发布与签名](https://docs.flutter.dev/deployment/android)、[Android 应用签名](https://developer.android.com/studio/publish/app-signing)、[apksigner](https://developer.android.com/tools/apksigner)。

## 本次正式包验证（2026-09-15）

已生成 `dist/android/0.6.1/EchoClip-0.6.1+10-arm64-v8a-release.apk`（11,500,044 字节）。APK v2 签名通过，证书 SHA-256 与上述正式证书一致，且不同于 Debug APK 的证书。确认 versionName 为 0.6.1、versionCode 为 10，仅 arm64-v8a，并未启用 debuggable。

分发 APK 与 Gradle 输出一致，原生代码与上一轮已通过测试的录音核心一致。已逐项检查 APK 中没有 JKS、私密 properties 文件或生成的密码。分发目录的 SHA256SUMS.txt 包含本轮 Debug / Release 两个包，SIGNING_CERTIFICATE_SHA256.txt 仅记录公开证书信息。
