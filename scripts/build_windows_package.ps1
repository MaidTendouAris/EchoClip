<#
    Builds and packages EchoClip for 64-bit Windows.

    The script produces both a portable ZIP and, unless -SkipInstaller is used,
    a single-file Inno Setup installer.

    Examples:
      powershell -ExecutionPolicy Bypass -File scripts\build_windows_package.ps1
      powershell -ExecutionPolicy Bypass -File scripts\build_windows_package.ps1 -InstallInnoSetup
#>

[CmdletBinding()]
param(
    [string]$VersionName,
    [string]$BuildNumber,
    [string]$OutputRoot,
    [string]$InnoCompiler,
    [switch]$SkipClean,
    [switch]$SkipFfmpegBuild,
    [switch]$SkipPubGet,
    [switch]$SkipAnalyze,
    [switch]$SkipTests,
    [switch]$SkipInstaller,
    [switch]$InstallInnoSetup
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
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
            throw "Command failed: $FilePath $($Arguments -join ' ')"
        }
    }
    finally {
        Pop-Location
    }
}

function Resolve-FlutterBat {
    $flutterCommand = Get-Command flutter.bat -ErrorAction SilentlyContinue
    if ($flutterCommand) {
        return $flutterCommand.Source
    }

    $fallback = "D:\Flutter_SDK\flutter\bin\flutter.bat"
    if (Test-Path -LiteralPath $fallback) {
        return $fallback
    }

    throw "Flutter was not found on PATH."
}

function Read-PubspecVersion {
    param([string]$PubspecPath)

    $versionLine = Get-Content -LiteralPath $PubspecPath -Encoding UTF8 |
        Where-Object { $_ -match "^\s*version\s*:" } |
        Select-Object -First 1
    if (-not $versionLine -or $versionLine -notmatch "^\s*version\s*:\s*(\d+\.\d+\.\d+)(?:\+(\d+))?\s*(?:#.*)?$") {
        throw "Unable to read a version such as 0.4.0+5 from pubspec.yaml."
    }
    return [PSCustomObject]@{
        Name = $Matches[1]
        BuildNumber = if ($Matches[2]) { $Matches[2] } else { "0" }
    }
}

function Assert-X64PeFile {
    param([string]$Path)

    $stream = [System.IO.File]::OpenRead($Path)
    $reader = New-Object System.IO.BinaryReader($stream)
    try {
        if ($reader.ReadUInt16() -ne 0x5A4D) {
            throw "Not a valid PE file: $Path"
        }
        $stream.Position = 0x3C
        $peOffset = $reader.ReadInt32()
        if ($peOffset -lt 0 -or $peOffset -gt ($stream.Length - 6)) {
            throw "Invalid PE header offset in $Path"
        }
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) {
            throw "PE signature was not found in $Path"
        }
        if ($reader.ReadUInt16() -ne 0x8664) {
            throw "The built executable is not x86-64 (AMD64): $Path"
        }
    }
    finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

function Assert-ReleaseBundle {
    param([string]$ReleaseDirectory)

    $requiredPaths = @(
        "echoclip.exe",
        "echoclip_windows_ffi.dll",
        "ffmpeg.exe",
        "flutter_windows.dll",
        "licenses\FFmpeg-Windows-NOTICE.txt",
        "licenses\FFmpeg-LGPL-2.1.txt",
        "licenses\LAME-LGPL-2.0.txt",
        "data\icudtl.dat",
        "data\flutter_assets",
        "data\app.so"
    )
    foreach ($relativePath in $requiredPaths) {
        $path = Join-Path $ReleaseDirectory $relativePath
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Windows release bundle is incomplete; missing: $path"
        }
    }
}

function Resolve-InnoCompiler {
    param([string]$RequestedPath)

    $candidates = @(
        $RequestedPath,
        (Get-Command ISCC.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue),
        (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 7\ISCC.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe"),
        "C:\Program Files\Inno Setup 7\ISCC.exe",
        "C:\Program Files (x86)\Inno Setup 7\ISCC.exe",
        "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
        "C:\Program Files\Inno Setup 6\ISCC.exe"
    ) | Where-Object { $_ -and $_.Trim().Length -gt 0 }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    return $null
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$appDir = Join-Path $repoRoot "apps\echoclip"
$pubspecPath = Join-Path $appDir "pubspec.yaml"
$installerDefinition = Join-Path $repoRoot "installer\windows\EchoClip.iss"
$flutterBat = Resolve-FlutterBat

$pubspecVersion = Read-PubspecVersion -PubspecPath $pubspecPath
if (-not $VersionName) {
    $VersionName = $pubspecVersion.Name
}
if (-not $BuildNumber) {
    $BuildNumber = $pubspecVersion.BuildNumber
}
if ($VersionName -notmatch "^\d+\.\d+\.\d+$") {
    throw "VersionName '$VersionName' is invalid; use major.minor.patch with numeric components."
}
foreach ($component in $VersionName.Split(".")) {
    if ([uint64]$component -gt 65535) {
        throw "Each Windows version component must be between 0 and 65535: $VersionName"
    }
}
if ($BuildNumber -notmatch "^\d+$" -or [uint64]$BuildNumber -gt 65535) {
    throw "BuildNumber '$BuildNumber' is invalid; use an integer from 0 through 65535."
}
if (-not $OutputRoot) {
    $OutputRoot = Join-Path $repoRoot "dist\windows\$VersionName"
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)

if ($env:PROCESSOR_ARCHITECTURE -notin @("AMD64", "IA64")) {
    throw "This script must run from a 64-bit Windows process to build windows-x64."
}

$toolStateRoot = Join-Path $repoRoot ".dart-tool-home"
New-Item -ItemType Directory -Force -Path $toolStateRoot | Out-Null
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$env:DART_SUPPRESS_ANALYTICS = "true"
$env:FLUTTER_SUPPRESS_ANALYTICS = "true"

Write-Step "Preparing EchoClip $VersionName for Windows x64"
Write-Host "Flutter: $flutterBat"
Write-Host "Output:  $OutputRoot"

if (-not $SkipClean) {
    Write-Step "Cleaning previous Flutter build outputs"
    Invoke-Checked -FilePath $flutterBat -Arguments @("clean") -WorkingDirectory $appDir
}

if (-not $SkipPubGet) {
    Write-Step "Resolving Flutter dependencies"
    Invoke-Checked -FilePath $flutterBat -Arguments @("pub", "get") -WorkingDirectory $appDir
}

if (-not $SkipAnalyze) {
    Write-Step "Running Flutter analyzer"
    Invoke-Checked -FilePath $flutterBat -Arguments @("analyze", "--no-pub") -WorkingDirectory $appDir
}

if (-not $SkipTests) {
    Write-Step "Running Flutter tests"
    Invoke-Checked -FilePath $flutterBat -Arguments @("test", "--no-pub") -WorkingDirectory $appDir
}

if (-not $SkipFfmpegBuild) {
    Write-Step "Building bundled Windows x64 FFmpeg"
    Invoke-Checked `
        -FilePath "powershell.exe" `
        -Arguments @(
            "-ExecutionPolicy", "Bypass",
            "-File", (Join-Path $PSScriptRoot "build_windows_ffmpeg.ps1")
        ) `
        -WorkingDirectory $repoRoot
}

Write-Step "Building Windows x64 release bundle"
Invoke-Checked `
    -FilePath $flutterBat `
    -Arguments @(
        "build", "windows", "--release", "--no-pub",
        "--build-name", $VersionName,
        "--build-number", $BuildNumber
    ) `
    -WorkingDirectory $appDir

$releaseDir = Join-Path $appDir "build\windows\x64\runner\Release"
$releaseExe = Join-Path $releaseDir "echoclip.exe"
$releaseRustDll = Join-Path $releaseDir "echoclip_windows_ffi.dll"
$releaseFfmpeg = Join-Path $releaseDir "ffmpeg.exe"
if (-not (Test-Path -LiteralPath $releaseExe)) {
    throw "Windows build completed but echoclip.exe was not found at $releaseExe"
}
Assert-ReleaseBundle -ReleaseDirectory $releaseDir
Assert-X64PeFile -Path $releaseExe
Assert-X64PeFile -Path $releaseRustDll
Assert-X64PeFile -Path $releaseFfmpeg

$portableZip = Join-Path $OutputRoot "EchoClip-$VersionName-windows-x64-portable.zip"
if (Test-Path -LiteralPath $portableZip) {
    Remove-Item -LiteralPath $portableZip -Force
}
Write-Step "Creating portable ZIP"
Compress-Archive -Path (Join-Path $releaseDir "*") -DestinationPath $portableZip -CompressionLevel Optimal
if ((Get-Item -LiteralPath $portableZip).Length -le 0) {
    throw "Portable ZIP was created but is empty: $portableZip"
}
Write-Host "Portable package: $portableZip"

if (-not $SkipInstaller) {
    $installerPath = Join-Path $OutputRoot "EchoClip-$VersionName-x64-Setup.exe"
    if (Test-Path -LiteralPath $installerPath) {
        Remove-Item -LiteralPath $installerPath -Force
    }

    $resolvedInnoCompiler = Resolve-InnoCompiler -RequestedPath $InnoCompiler
    if (-not $resolvedInnoCompiler -and $InstallInnoSetup) {
        Write-Step "Installing Inno Setup with winget"
        Invoke-Checked `
            -FilePath "winget.exe" `
            -Arguments @(
                "install",
                "--id", "JRSoftware.InnoSetup",
                "--exact",
                "--silent",
                "--accept-package-agreements",
                "--accept-source-agreements"
            ) `
            -WorkingDirectory $repoRoot
        $resolvedInnoCompiler = Resolve-InnoCompiler
    }

    if (-not $resolvedInnoCompiler) {
        throw "Inno Setup was not found. Install version 6.3 or newer, or rerun with -InstallInnoSetup."
    }

    Write-Step "Compiling single-file installer"
    Invoke-Checked `
        -FilePath $resolvedInnoCompiler `
        -Arguments @(
            "/DAppVersion=$VersionName",
            "/DAppBuildNumber=$BuildNumber",
            "/DSourceDir=$releaseDir",
            "/DOutputDir=$OutputRoot",
            "/DRepoRoot=$repoRoot",
            $installerDefinition
        ) `
        -WorkingDirectory $repoRoot
}

if (-not $SkipInstaller -and -not (Test-Path -LiteralPath $installerPath)) {
    throw "Installer compilation completed but the expected file is missing: $installerPath"
}
if (-not $SkipInstaller -and (Get-Item -LiteralPath $installerPath).Length -le 0) {
    throw "Installer compilation completed but the installer is empty: $installerPath"
}

Write-Step "Windows package completed"
Get-ChildItem -LiteralPath $OutputRoot -File |
    Select-Object FullName, Length, LastWriteTime
