param(
    [string]$NdkRoot = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-AndroidNdk {
    param([string]$RequestedRoot)

    $candidates = @()
    if ($RequestedRoot) { $candidates += $RequestedRoot }
    if ($env:ANDROID_NDK_HOME) { $candidates += $env:ANDROID_NDK_HOME }
    if ($env:ANDROID_NDK_ROOT) { $candidates += $env:ANDROID_NDK_ROOT }
    if ($env:ANDROID_HOME) { $candidates += Join-Path $env:ANDROID_HOME "ndk" }
    if ($env:ANDROID_SDK_ROOT) { $candidates += Join-Path $env:ANDROID_SDK_ROOT "ndk" }
    if ($env:LOCALAPPDATA) { $candidates += Join-Path $env:LOCALAPPDATA "Android\sdk\ndk" }

    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate)) {
            continue
        }
        # Candidate is either the NDK root itself, or an Android SDK "ndk"
        # directory containing one or more versioned NDK directories.
        if (Test-Path -LiteralPath (Join-Path $candidate "toolchains\llvm\prebuilt\windows-x86_64")) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
        $versions = Get-ChildItem -LiteralPath $candidate -Directory -ErrorAction SilentlyContinue |
            Where-Object {
                Test-Path -LiteralPath (Join-Path $_.FullName "toolchains\llvm\prebuilt\windows-x86_64")
            } |
            Sort-Object Name -Descending
        if ($versions) {
            return $versions[0].FullName
        }
    }

    throw "Android NDK was not found. Pass -NdkRoot or set ANDROID_NDK_HOME / ANDROID_HOME."
}

$ndkRoot = Resolve-AndroidNdk -RequestedRoot $NdkRoot
$llvmBin = Join-Path $ndkRoot "toolchains\llvm\prebuilt\windows-x86_64\bin"
$clang = Get-ChildItem -LiteralPath $llvmBin -Filter "aarch64-linux-android*-clang.cmd" |
    Sort-Object Name -Descending |
    Select-Object -First 1
if (-not $clang) {
    throw "Android NDK clang wrapper was not found in: $llvmBin"
}

$env:CC_aarch64_linux_android = $clang.FullName
$env:CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER = $clang.FullName

Push-Location $repoRoot
try {
    cargo build -p echoclip_android_jni --target aarch64-linux-android --release
    if ($LASTEXITCODE -ne 0) {
        throw "Rust Android build failed with exit code $LASTEXITCODE"
    }
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
