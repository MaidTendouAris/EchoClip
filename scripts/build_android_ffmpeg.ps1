param(
    [ValidateSet("arm64-v8a")]
    [string] $Abi = "arm64-v8a",
    [int] $AndroidApi = 26,
    [string] $FfmpegSource = "",
    [string] $LameSource = "",
    [string] $NdkRoot = "",
    [int] $Jobs = 0
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$thirdPartyRoot = Join-Path $repoRoot "third_party\ffmpeg"

if ([string]::IsNullOrWhiteSpace($FfmpegSource)) {
    $FfmpegSource = Join-Path $thirdPartyRoot "src\ffmpeg"
}
if ([string]::IsNullOrWhiteSpace($LameSource)) {
    $LameSource = Join-Path $thirdPartyRoot "src\lame"
}
if ([string]::IsNullOrWhiteSpace($NdkRoot)) {
    $NdkRoot = Join-Path $env:LOCALAPPDATA "Android\sdk\ndk\28.2.13676358"
}
if ($Jobs -le 0) {
    $Jobs = [Math]::Max(1, [Environment]::ProcessorCount)
}

$bashCandidates = @(
    (Join-Path $repoRoot "tools\msys64\usr\bin\bash.exe"),
    "C:\msys64\usr\bin\bash.exe",
    "C:\Program Files\MSYS2\usr\bin\bash.exe",
    "C:\Program Files\Git\bin\bash.exe"
)
$bashPath = $bashCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($null -eq $bashPath) {
    $bashCommand = Get-Command bash -ErrorAction SilentlyContinue
    if ($null -ne $bashCommand) {
        $bashPath = $bashCommand.Source
    }
}
if ($null -eq $bashPath) {
    throw "bash was not found. Install MSYS2/Git Bash or run scripts\prepare_android_ffmpeg_sources.ps1."
}
if (-not (Test-Path (Join-Path $NdkRoot "toolchains\llvm"))) {
    throw "Android NDK was not found: $NdkRoot"
}
if (-not (Test-Path (Join-Path $FfmpegSource "configure"))) {
    throw "FFmpeg source was not found: $FfmpegSource"
}
if (-not (Test-Path (Join-Path $LameSource "configure"))) {
    throw "LAME source was not found: $LameSource"
}

$buildRoot = Join-Path $thirdPartyRoot "build\android\$Abi"
$lamePrefix = Join-Path $thirdPartyRoot "prebuilt\lame\android\$Abi"
$ffmpegOut = Join-Path $thirdPartyRoot "out\android\$Abi"
$jniLibDir = Join-Path $repoRoot "apps\echoclip\android\app\src\main\jniLibs\$Abi"

New-Item -ItemType Directory -Force -Path $buildRoot, $lamePrefix, $ffmpegOut, $jniLibDir | Out-Null

$env:ABI = $Abi
$env:ANDROID_API = "$AndroidApi"
$env:NDK_ROOT = $NdkRoot
$env:FFMPEG_SOURCE = $FfmpegSource
$env:LAME_SOURCE = $LameSource
$env:LAME_PREFIX = $lamePrefix
$env:FFMPEG_OUT = $ffmpegOut
$env:JOBS = "$Jobs"

Push-Location $repoRoot
try {
    $repoUnix = $repoRoot -replace "\\", "/"
    if ($repoUnix -match "^([A-Za-z]):/(.*)$") {
        $repoUnix = "/" + $matches[1].ToLowerInvariant() + "/" + $matches[2]
    }

    if (-not (Test-Path (Join-Path $lamePrefix "lib\libmp3lame.a"))) {
        & $bashPath -lc "cd '$repoUnix' && third_party/ffmpeg/build-lame-android.sh"
        if ($LASTEXITCODE -ne 0) {
            throw "LAME build failed with exit code $LASTEXITCODE"
        }
    }
    else {
        Write-Host "Using existing LAME build: $lamePrefix"
    }

    & $bashPath -lc "cd '$repoUnix' && third_party/ffmpeg/build-ffmpeg-android-audio.sh"
    if ($LASTEXITCODE -ne 0) {
        throw "FFmpeg build failed with exit code $LASTEXITCODE"
    }

    $ffmpegBinary = Join-Path $ffmpegOut "libffmpeg.so"
    if (-not (Test-Path $ffmpegBinary)) {
        throw "FFmpeg output was not created: $ffmpegBinary"
    }

    Copy-Item -Path $ffmpegBinary -Destination (Join-Path $jniLibDir "libffmpeg.so") -Force
    Write-Host "Packaged FFmpeg: $jniLibDir\libffmpeg.so"
}
finally {
    Pop-Location
}
