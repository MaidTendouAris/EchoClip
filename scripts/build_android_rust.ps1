$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ndkRoot = Join-Path $env:LOCALAPPDATA "Android\sdk\ndk\28.2.13676358"
$clang = Join-Path $ndkRoot "toolchains\llvm\prebuilt\windows-x86_64\bin\aarch64-linux-android35-clang.cmd"

if (-not (Test-Path $clang)) {
    throw "Android NDK linker not found: $clang"
}

$env:CC_aarch64_linux_android = $clang
$env:CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER = $clang

Push-Location $repoRoot
try {
    cargo build -p echoclip_android_jni --target aarch64-linux-android --release
    $jniLibDir = Join-Path $repoRoot "apps\echoclip\android\app\src\main\jniLibs\arm64-v8a"
    New-Item -ItemType Directory -Force -Path $jniLibDir | Out-Null
    Copy-Item `
        -Path (Join-Path $repoRoot "target\aarch64-linux-android\release\libechoclip_android_jni.so") `
        -Destination (Join-Path $jniLibDir "libechoclip_android_jni.so") `
        -Force
}
finally {
    Pop-Location
}
