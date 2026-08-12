<#
    EchoClip Android 构建脚本

    这个脚本把 Android 版本发布时容易忘记的步骤集中到一个入口：
    1. 读取或更新 Flutter pubspec.yaml 中的 version 字段；
    2. 同步 android/local.properties 中的 Flutter/Android 构建版本；
    3. 自动寻找 Flutter SDK、Android SDK、Java 17+、Gradle；
    4. 构建 debug、release 或两者；
    5. 使用 Android SDK 的 aapt 校验 APK 内真实 versionName / versionCode；
    6. 校验 APK 仅包含 arm64-v8a，并逐个确认原生库为 ELF64 AArch64；
    7. 将产物复制到 dist/android/<version>/；
    8. 生成一份 changelog 草稿，方便发 GitHub Release 时整理。

    示例：
      powershell -ExecutionPolicy Bypass -File scripts\build_android_package.ps1 -BuildMode both
      powershell -ExecutionPolicy Bypass -File scripts\build_android_package.ps1 -BuildMode release -VersionName 0.5.0 -VersionCode 6
#>

[CmdletBinding()]
param(
    # 构建模式：debug、release，或 both 一次构建两种包。
    [ValidateSet("debug", "release", "both")]
    [string]$BuildMode = "both",

    # 版本名，例如 0.5.0。不传时读取 apps/echoclip/pubspec.yaml。
    [string]$VersionName,

    # Android versionCode，必须是正整数。不传时读取 apps/echoclip/pubspec.yaml。
    [int]$VersionCode = 0,

    # 输出目录。默认写到仓库 dist/android/<version>/。
    [string]$OutputRoot,

    # 指定 changelog 起点。不传时优先使用最近的 git tag，否则取最近 30 条提交。
    [string]$ChangelogSince,

    # 跳过 flutter pub get。只有确认依赖已经准备好时才建议使用。
    [switch]$SkipPubGet,

    # 跳过 APK 版本及原生库 ABI/ELF 校验。正常发布不建议使用。
    [switch]$SkipApkValidation
)

$ErrorActionPreference = "Stop"
$androidTargetPlatform = "android-arm64"
$androidAbi = "arm64-v8a"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Utf8NoBomLines {
    param(
        [string]$Path,
        [string[]]$Lines
    )

    # PowerShell 5.1 的 Set-Content -Encoding UTF8 会写 BOM。
    # Gradle 读取 local.properties 时会把 BOM 当成 key 的一部分，
    # 因此这里统一使用 .NET 写无 BOM UTF-8。
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($Path, $Lines, $encoding)
}

function Resolve-RepoRoot {
    # 脚本位于 scripts/ 下，仓库根目录就是脚本目录的上一级。
    return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Read-PubspecVersion {
    param([string]$PubspecPath)

    # Flutter 的 version 字段格式为 versionName+versionCode，例如 0.4.0+5。
    $line = Get-Content -LiteralPath $PubspecPath -Encoding UTF8 |
        Where-Object { $_ -match "^\s*version\s*:" } |
        Select-Object -First 1
    if (-not $line -or $line -notmatch "^\s*version\s*:\s*([^\+]+)\+(\d+)\s*$") {
        throw "无法从 pubspec.yaml 读取 version，期望格式：version: 0.5.0+6"
    }

    return @{
        VersionName = $Matches[1].Trim()
        VersionCode = [int]$Matches[2]
    }
}

function Assert-Version {
    param(
        [string]$Name,
        [int]$Code
    )

    # 这里允许 0.5.0、0.5.0-beta1、0.5.0-rc.1 这类常见版本名。
    if ($Name -notmatch "^\d+\.\d+\.\d+([-.][0-9A-Za-z.-]+)?$") {
        throw "VersionName '$Name' 不符合预期格式，例如 0.5.0 或 0.5.0-beta1。"
    }
    if ($Code -le 0) {
        throw "VersionCode 必须是正整数。"
    }
}

function Update-PubspecVersion {
    param(
        [string]$PubspecPath,
        [string]$Name,
        [int]$Code
    )

    # pubspec.yaml 是源码版本来源，必须跟本次构建保持一致。
    $content = Get-Content -LiteralPath $PubspecPath -Encoding UTF8
    $updated = $content | ForEach-Object {
        if ($_ -match "^\s*version\s*:") {
            "version: $Name+$Code"
        } else {
            $_
        }
    }
    Write-Utf8NoBomLines -Path $PubspecPath -Lines ([string[]]$updated)
}

function Read-LocalProperties {
    param([string]$Path)

    # local.properties 不进 git，但 Flutter Gradle 插件会读取它。
    $map = [ordered]@{}
    if (Test-Path -LiteralPath $Path) {
        foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
            if ($line -match "^\s*#" -or $line.Trim().Length -eq 0) {
                continue
            }
            $index = $line.IndexOf("=")
            if ($index -gt 0) {
                $key = $line.Substring(0, $index).Trim()
                $value = $line.Substring($index + 1).Trim()
                $map[$key] = $value
            }
        }
    }
    return $map
}

function Write-LocalProperties {
    param(
        [string]$Path,
        [hashtable]$Values
    )

    # Windows 路径里的反斜杠在 properties 文件里保持原样即可。
    $lines = foreach ($key in $Values.Keys) {
        # Java Properties 会把反斜杠当作转义符，因此 Windows 路径必须写成双反斜杠。
        $value = "$($Values[$key])".Replace("\", "\\")
        "$key=$value"
    }
    Write-Utf8NoBomLines -Path $Path -Lines ([string[]]$lines)
}

function Resolve-FlutterSdk {
    param([hashtable]$LocalProperties)

    # 优先使用 local.properties，其次使用环境变量，最后兼容本机常用路径。
    $candidates = @(
        $LocalProperties["flutter.sdk"],
        $env:FLUTTER_ROOT,
        $env:Flutter_SDK,
        "D:\Flutter_SDK\flutter"
    ) | Where-Object { $_ -and $_.Trim().Length -gt 0 }

    foreach ($candidate in $candidates) {
        $flutterBat = Join-Path $candidate "bin\flutter.bat"
        if (Test-Path -LiteralPath $flutterBat) {
            return (Resolve-Path $candidate).Path
        }
    }

    throw "未找到 Flutter SDK。请在 android/local.properties 设置 flutter.sdk，或设置 FLUTTER_ROOT。"
}

function Resolve-AndroidSdk {
    param([hashtable]$LocalProperties)

    # Android SDK 用于寻找 aapt，也用于 Gradle 构建。
    $candidates = @(
        $LocalProperties["sdk.dir"],
        $env:ANDROID_HOME,
        $env:ANDROID_SDK_ROOT,
        (Join-Path $env:LOCALAPPDATA "Android\sdk")
    ) | Where-Object { $_ -and $_.Trim().Length -gt 0 }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $candidate "build-tools")) {
            return (Resolve-Path $candidate).Path
        }
    }

    throw "未找到 Android SDK。请确认 Android Studio/cmdline-tools 已安装。"
}

function Resolve-JavaHome {
    # Gradle 9 需要 Java 17+。当前 PATH 可能仍指向 Java 8，所以这里显式寻找可用 JDK。
    $candidates = @(
        $env:JAVA_HOME,
        "C:\Program Files\Java\jdk-17",
        "C:\Program Files\Java\jdk-21",
        "C:\Program Files\Android\Android Studio\jbr"
    ) | Where-Object { $_ -and $_.Trim().Length -gt 0 }

    foreach ($candidate in $candidates) {
        $javaExe = Join-Path $candidate "bin\java.exe"
        if (-not (Test-Path -LiteralPath $javaExe)) {
            continue
        }
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            # java -version 按惯例会把版本信息输出到 stderr，这不是失败。
            $versionText = & $javaExe -version 2>&1 | Out-String
        }
        finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
        if ($versionText -match 'version "(\d+)') {
            if ([int]$Matches[1] -ge 17) {
                return (Resolve-Path $candidate).Path
            }
        } elseif ($versionText -match 'version "1\.(\d+)') {
            if ([int]$Matches[1] -ge 17) {
                return (Resolve-Path $candidate).Path
            }
        }
    }

    throw "未找到 Java 17+。请安装 JDK 17 或设置 JAVA_HOME。"
}

function Resolve-GradleBat {
    param([string]$AndroidDir)

    # 优先复用已经解压的 Gradle wrapper 缓存，避免 wrapper 因坏 zip 或网络证书问题重新下载。
    $distributionPath = Join-Path $env:USERPROFILE ".gradle\wrapper\dists\gradle-9.1.0-all"
    if (Test-Path -LiteralPath $distributionPath) {
        $existing = Get-ChildItem -LiteralPath $distributionPath -Recurse -Filter "gradle.bat" -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match "\\gradle-9\.1\.0\\bin\\gradle\.bat$" } |
            Select-Object -First 1
        if ($existing) {
            return $existing.FullName
        }
    }

    # 如果本机没有已解压 Gradle，则退回项目 wrapper。
    $wrapper = Join-Path $AndroidDir "gradlew.bat"
    if (Test-Path -LiteralPath $wrapper) {
        return $wrapper
    }

    throw "未找到 Gradle。请先运行 Android Studio 同步项目，或修复 Gradle wrapper。"
}

function Resolve-Aapt {
    param([string]$AndroidSdk)

    # aapt 用于读取 APK 内部 manifest 的版本号。
    $aapt = Get-ChildItem -LiteralPath (Join-Path $AndroidSdk "build-tools") -Recurse -Filter "aapt.exe" |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if (-not $aapt) {
        throw "未找到 aapt.exe，无法校验 APK 版本。"
    }
    return $aapt.FullName
}

function Invoke-Checked {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$WorkingDirectory
    )

    Push-Location $WorkingDirectory
    try {
        & $FilePath @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "命令失败：$FilePath $($Arguments -join ' ')"
        }
    }
    finally {
        Pop-Location
    }
}

function Test-ApkVersion {
    param(
        [string]$Aapt,
        [string]$ApkPath,
        [string]$ExpectedName,
        [int]$ExpectedCode
    )

    # aapt dump badging 第一行包含 package、versionCode、versionName。
    $badging = & $Aapt dump badging $ApkPath
    $packageLine = $badging | Where-Object { $_ -match "^package:" } | Select-Object -First 1
    if (-not $packageLine) {
        throw "无法读取 APK badging：$ApkPath"
    }
    if ($packageLine -notmatch "versionCode='(\d+)'" -or [int]$Matches[1] -ne $ExpectedCode) {
        throw "APK versionCode 校验失败：期望 $ExpectedCode，实际信息：$packageLine"
    }
    if ($packageLine -notmatch "versionName='([^']+)'" -or $Matches[1] -ne $ExpectedName) {
        throw "APK versionName 校验失败：期望 $ExpectedName，实际信息：$packageLine"
    }
}

function Test-ApkNativeLibraries {
    param(
        [string]$ApkPath,
        [string]$ExpectedAbi
    )

    # APK 是 ZIP 容器。直接读取每个 lib/<abi>/*.so 的 ELF 头，既能避免
    # 依赖额外的 readelf 工具，也能在复制发布产物前拦截混合 ABI 包。
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($ApkPath)
    try {
        $nativeEntries = @(
            $archive.Entries |
                Where-Object { $_.FullName -match '^lib/([^/]+)/[^/]+\.so$' }
        )
        if ($nativeEntries.Count -eq 0) {
            throw "APK 内未找到任何原生库：$ApkPath"
        }

        $abis = @(
            $nativeEntries |
                ForEach-Object {
                    if ($_.FullName -match '^lib/([^/]+)/') {
                        $Matches[1]
                    }
                } |
                Sort-Object -Unique
        )
        if ($abis.Count -ne 1 -or $abis[0] -ne $ExpectedAbi) {
            throw "APK ABI 校验失败：期望仅包含 $ExpectedAbi，实际包含 $($abis -join ', ')。"
        }

        $entryNames = @($nativeEntries | ForEach-Object { $_.FullName })
        $requiredLibraries = @(
            "libapp.so",
            "libflutter.so",
            "libechoclip_android_jni.so",
            "libffmpeg.so"
        )
        foreach ($library in $requiredLibraries) {
            $requiredPath = "lib/$ExpectedAbi/$library"
            if ($entryNames -notcontains $requiredPath) {
                throw "APK 缺少必需原生库：$requiredPath"
            }
        }

        foreach ($entry in $nativeEntries) {
            $stream = $entry.Open()
            try {
                # ELF e_machine 位于偏移 18；读取 20 字节即可同时校验魔数、
                # ELF class、endianness 和目标机器类型。
                $header = New-Object byte[] 20
                $bytesRead = 0
                while ($bytesRead -lt $header.Length) {
                    $read = $stream.Read($header, $bytesRead, $header.Length - $bytesRead)
                    if ($read -le 0) {
                        break
                    }
                    $bytesRead += $read
                }
            }
            finally {
                $stream.Dispose()
            }

            if ($bytesRead -lt 20) {
                throw "原生库 ELF 头不完整：$($entry.FullName)"
            }
            if ($header[0] -ne 0x7f -or
                $header[1] -ne [byte][char]'E' -or
                $header[2] -ne [byte][char]'L' -or
                $header[3] -ne [byte][char]'F') {
                throw "原生库不是 ELF 文件：$($entry.FullName)"
            }
            if ($header[4] -ne 2) {
                throw "原生库不是 ELF64：$($entry.FullName)"
            }
            if ($header[5] -ne 1) {
                throw "原生库不是 Android AArch64 所需的小端 ELF：$($entry.FullName)"
            }

            $machine = [int]$header[18] -bor ([int]$header[19] -shl 8)
            if ($machine -ne 183) {
                throw "原生库不是 AArch64 ELF（e_machine=$machine）：$($entry.FullName)"
            }
        }
    }
    finally {
        $archive.Dispose()
    }
}

function New-ChangelogDraft {
    param(
        [string]$RepoRoot,
        [string]$OutPath,
        [string]$Name,
        [int]$Code,
        [string[]]$Modes,
        [string]$Since
    )

    # 如果没有指定起点，优先使用最近 tag；没有 tag 时取最近 30 条提交。
    $range = $null
    if ($Since) {
        $range = "$Since..HEAD"
    } else {
        $latestTag = git -C $RepoRoot describe --tags --abbrev=0 2>$null
        if ($LASTEXITCODE -eq 0 -and $latestTag) {
            $range = "$latestTag..HEAD"
        }
    }

    $commits = if ($range) {
        git -C $RepoRoot log --pretty=format:"- %s (%h)" $range
    } else {
        git -C $RepoRoot log -30 --pretty=format:"- %s (%h)"
    }

    $date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $content = @(
        "# EchoClip $Name Changelog Draft",
        "",
        "- VersionName: $Name",
        "- VersionCode: $Code",
        "- Build modes: $($Modes -join ', ')",
        "- Generated at: $date",
        "",
        "## Changes",
        "",
        ($commits -join [Environment]::NewLine),
        "",
        "## Release Notes To Fill",
        "",
        "- Highlights:",
        "- Known issues:",
        "- Test devices:",
        ""
    )
    Write-Utf8NoBomLines -Path $OutPath -Lines ([string[]]$content)
}

$repoRoot = Resolve-RepoRoot
$appDir = Join-Path $repoRoot "apps\echoclip"
$androidDir = Join-Path $appDir "android"
$pubspecPath = Join-Path $appDir "pubspec.yaml"
$localPropertiesPath = Join-Path $androidDir "local.properties"

if (-not $OutputRoot) {
    $OutputRoot = Join-Path $repoRoot "dist\android"
}

$currentVersion = Read-PubspecVersion $pubspecPath
if (-not $VersionName) {
    $VersionName = $currentVersion.VersionName
}
if ($VersionCode -le 0) {
    $VersionCode = $currentVersion.VersionCode
}
Assert-Version -Name $VersionName -Code $VersionCode

Write-Step "准备构建 EchoClip Android $VersionName+$VersionCode ($BuildMode, $androidAbi)"

$localProperties = Read-LocalProperties $localPropertiesPath
$flutterSdk = Resolve-FlutterSdk $localProperties
$androidSdk = Resolve-AndroidSdk $localProperties
$javaHome = Resolve-JavaHome
$gradleBat = Resolve-GradleBat $androidDir
$aapt = Resolve-Aapt $androidSdk

Write-Host "Flutter SDK: $flutterSdk"
Write-Host "Android SDK: $androidSdk"
Write-Host "Java Home:   $javaHome"
Write-Host "Gradle:      $gradleBat"
Write-Host "aapt:        $aapt"
Write-Host "Target:      $androidTargetPlatform ($androidAbi)"

Write-Step "同步版本配置"
Update-PubspecVersion -PubspecPath $pubspecPath -Name $VersionName -Code $VersionCode

$localProperties["flutter.sdk"] = $flutterSdk
$localProperties["sdk.dir"] = $androidSdk
$localProperties["flutter.versionName"] = $VersionName
$localProperties["flutter.versionCode"] = "$VersionCode"

# 将 Dart/Flutter 工具状态放到仓库内已忽略目录，避免分析/构建时写入用户 Roaming 目录失败。
$toolHome = Join-Path $repoRoot ".dart-tool-home"
New-Item -ItemType Directory -Force -Path $toolHome | Out-Null
$env:APPDATA = $toolHome
$env:LOCALAPPDATA = $toolHome
$env:DART_SUPPRESS_ANALYTICS = "true"
$env:FLUTTER_SUPPRESS_ANALYTICS = "true"
$env:JAVA_HOME = $javaHome
$env:ANDROID_HOME = $androidSdk
$env:ANDROID_SDK_ROOT = $androidSdk
$env:PATH = (Join-Path $javaHome "bin") + ";" + $env:PATH

if (-not $SkipPubGet) {
    Write-Step "执行 flutter pub get"
    Invoke-Checked `
        -FilePath (Join-Path $flutterSdk "bin\flutter.bat") `
        -Arguments @("pub", "get") `
        -WorkingDirectory $appDir
}

$modes = if ($BuildMode -eq "both") { @("debug", "release") } else { @($BuildMode) }
$outputDir = Join-Path $OutputRoot $VersionName
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

foreach ($mode in $modes) {
    $task = if ($mode -eq "debug") { "assembleDebug" } else { "assembleRelease" }
    $sourceApk = Join-Path $appDir "build\app\outputs\apk\$mode\app-$mode.apk"
    $targetApk = Join-Path $outputDir "EchoClip-$VersionName+$VersionCode-$androidAbi-$mode.apk"

    Write-Step "构建 $mode APK"
    $localProperties["flutter.buildMode"] = $mode
    Write-LocalProperties -Path $localPropertiesPath -Values $localProperties

    Invoke-Checked `
        -FilePath $gradleBat `
        -Arguments @($task, "-Ptarget-platform=$androidTargetPlatform") `
        -WorkingDirectory $androidDir

    if (-not (Test-Path -LiteralPath $sourceApk)) {
        throw "构建完成但未找到 APK：$sourceApk"
    }

    if (-not $SkipApkValidation) {
        Write-Step "校验 $mode APK 版本与 $androidAbi 原生库"
        Test-ApkVersion `
            -Aapt $aapt `
            -ApkPath $sourceApk `
            -ExpectedName $VersionName `
            -ExpectedCode $VersionCode
        Test-ApkNativeLibraries `
            -ApkPath $sourceApk `
            -ExpectedAbi $androidAbi
    }

    Copy-Item -LiteralPath $sourceApk -Destination $targetApk -Force
    Write-Host "输出 APK: $targetApk"
}

Write-Step "生成 changelog 草稿"
$changelogPath = Join-Path $outputDir "CHANGELOG_DRAFT.md"
New-ChangelogDraft `
    -RepoRoot $repoRoot `
    -OutPath $changelogPath `
    -Name $VersionName `
    -Code $VersionCode `
    -Modes $modes `
    -Since $ChangelogSince
Write-Host "Changelog 草稿: $changelogPath"

Write-Step "构建完成"
Get-ChildItem -LiteralPath $outputDir | Select-Object FullName, Length, LastWriteTime




