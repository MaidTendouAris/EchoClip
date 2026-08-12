[CmdletBinding()]
param(
    [string]$FfmpegVersion = "8.1.2",
    [string]$LameVersion = "3.100",
    [int]$Jobs = 0,
    [switch]$SkipToolInstall
)

$ErrorActionPreference = "Stop"

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
            throw "Command failed: $FilePath $($Arguments -join ' ')"
        }
    }
    finally {
        Pop-Location
    }
}

function Assert-X64PeFile {
    param([string]$Path)

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $reader = New-Object System.IO.BinaryReader($stream)
        $stream.Seek(0x3c, [System.IO.SeekOrigin]::Begin) | Out-Null
        $peOffset = $reader.ReadInt32()
        $stream.Seek($peOffset + 4, [System.IO.SeekOrigin]::Begin) | Out-Null
        $machine = $reader.ReadUInt16()
        if ($machine -ne 0x8664) {
            throw "FFmpeg is not an AMD64 PE executable (machine=0x$($machine.ToString('X4'))): $Path"
        }
    }
    finally {
        $stream.Dispose()
    }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$thirdPartyRoot = Join-Path $repoRoot "third_party\ffmpeg"
$sourceRoot = Join-Path $thirdPartyRoot "src"
$ffmpegSource = Join-Path $sourceRoot "ffmpeg"
$lameSource = Join-Path $sourceRoot "lame"
$msysRoot = Join-Path $repoRoot "tools\msys64"
$bash = Join-Path $msysRoot "usr\bin\bash.exe"

if (-not (Test-Path -LiteralPath (Join-Path $ffmpegSource "configure")) -or
    -not (Test-Path -LiteralPath (Join-Path $lameSource "configure")) -or
    -not (Test-Path -LiteralPath $bash)) {
    Invoke-Checked `
        -FilePath "powershell.exe" `
        -Arguments @(
            "-ExecutionPolicy", "Bypass",
            "-File", (Join-Path $PSScriptRoot "prepare_android_ffmpeg_sources.ps1"),
            "-FfmpegVersion", $FfmpegVersion,
            "-LameVersion", $LameVersion
        ) `
        -WorkingDirectory $repoRoot
}

if ($Jobs -le 0) {
    $Jobs = [Math]::Max(1, [Environment]::ProcessorCount)
}

$env:MSYSTEM = "UCRT64"
$env:CHERE_INVOKING = "1"
$env:MSYS2_PATH_TYPE = "inherit"

$requiredBuildTools = @(
    (Join-Path $msysRoot "ucrt64\bin\gcc.exe"),
    (Join-Path $msysRoot "ucrt64\bin\ar.exe"),
    (Join-Path $msysRoot "ucrt64\bin\ld.exe"),
    (Join-Path $msysRoot "ucrt64\bin\nasm.exe"),
    (Join-Path $msysRoot "usr\bin\pkg-config.exe"),
    (Join-Path $msysRoot "usr\bin\make.exe"),
    (Join-Path $msysRoot "usr\bin\diff.exe")
)
$missingBuildTools = @($requiredBuildTools | Where-Object { -not (Test-Path -LiteralPath $_) })

if (-not $SkipToolInstall -and $missingBuildTools.Count -gt 0) {
    Invoke-Checked `
        -FilePath $bash `
        -Arguments @(
            "-lc",
            "pacman -Sy --needed --noconfirm mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-binutils mingw-w64-ucrt-x86_64-nasm make diffutils pkgconf"
        ) `
        -WorkingDirectory $repoRoot
} elseif (-not $SkipToolInstall) {
    Write-Host "MSYS2 build tools are already installed; skipping package database synchronization."
}

$buildRoot = Join-Path $thirdPartyRoot "build\windows\x64"
$lamePrefix = Join-Path $thirdPartyRoot "prebuilt\lame\windows\x64"
$ffmpegOut = Join-Path $thirdPartyRoot "out\windows\x64"
New-Item -ItemType Directory -Force -Path $buildRoot, $lamePrefix, $ffmpegOut | Out-Null

$env:FFMPEG_SOURCE = $ffmpegSource
$env:LAME_SOURCE = $lameSource
$env:BUILD_ROOT = $buildRoot
$env:LAME_PREFIX = $lamePrefix
$env:FFMPEG_OUT = $ffmpegOut
$env:JOBS = "$Jobs"

Invoke-Checked `
    -FilePath $bash `
    -Arguments @(
        "-lc",
        "third_party/ffmpeg/build-ffmpeg-windows-audio.sh"
    ) `
    -WorkingDirectory $repoRoot

$ffmpegExe = Join-Path $ffmpegOut "ffmpeg.exe"
if (-not (Test-Path -LiteralPath $ffmpegExe)) {
    throw "Windows FFmpeg build did not create: $ffmpegExe"
}
Assert-X64PeFile -Path $ffmpegExe

Write-Host "Built Windows x64 FFmpeg: $ffmpegExe"
Get-Item -LiteralPath $ffmpegExe | Select-Object FullName, Length, LastWriteTime
