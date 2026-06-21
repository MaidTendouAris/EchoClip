param(
    [string] $FfmpegVersion = "8.1.2",
    [string] $LameVersion = "3.100"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$toolsRoot = Join-Path $repoRoot "tools"
$downloadsRoot = Join-Path $toolsRoot "downloads"
$thirdPartyRoot = Join-Path $repoRoot "third_party\ffmpeg"
$srcRoot = Join-Path $thirdPartyRoot "src"
$msysRoot = Join-Path $toolsRoot "msys64"

New-Item -ItemType Directory -Force -Path $downloadsRoot, $srcRoot | Out-Null

function Download-File {
    param(
        [Parameter(Mandatory = $true)][string] $Url,
        [Parameter(Mandatory = $true)][string] $OutFile
    )

    if (Test-Path $OutFile) {
        Write-Host "Already downloaded: $OutFile"
        return
    }

    Write-Host "Downloading: $Url"
    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
}

function Expand-SourceArchive {
    param(
        [Parameter(Mandatory = $true)][string] $Archive,
        [Parameter(Mandatory = $true)][string] $ExtractedName,
        [Parameter(Mandatory = $true)][string] $DestinationName
    )

    $destination = Join-Path $srcRoot $DestinationName
    if (Test-Path $destination) {
        Write-Host "Source already exists: $destination"
        return
    }

    Write-Host "Extracting: $Archive"
    tar -xf $Archive -C $srcRoot
    $extracted = Join-Path $srcRoot $ExtractedName
    if (-not (Test-Path $extracted)) {
        throw "Expected extracted directory was not found: $extracted"
    }
    Rename-Item -Path $extracted -NewName $DestinationName
}

$msysArchive = Join-Path $downloadsRoot "msys2-base-x86_64-latest.sfx.exe"
Download-File `
    -Url "https://github.com/msys2/msys2-installer/releases/latest/download/msys2-base-x86_64-latest.sfx.exe" `
    -OutFile $msysArchive

if (-not (Test-Path (Join-Path $msysRoot "usr\bin\bash.exe"))) {
    Write-Host "Extracting portable MSYS2 to: $toolsRoot"
    & $msysArchive -y "-o$toolsRoot" | Out-Host
}

$bash = Join-Path $msysRoot "usr\bin\bash.exe"
if (-not (Test-Path $bash)) {
    throw "Portable MSYS2 bash was not found: $bash"
}

Write-Host "Installing MSYS2 build tools"
& $bash -lc "pacman-key --init >/dev/null 2>&1 || true; pacman-key --populate msys2 >/dev/null 2>&1 || true; pacman -Sy --needed --noconfirm gcc make diffutils pkgconf tar gzip xz patch"

$ffmpegArchive = Join-Path $downloadsRoot "ffmpeg-$FfmpegVersion.tar.xz"
Download-File `
    -Url "https://ffmpeg.org/releases/ffmpeg-$FfmpegVersion.tar.xz" `
    -OutFile $ffmpegArchive
Expand-SourceArchive `
    -Archive $ffmpegArchive `
    -ExtractedName "ffmpeg-$FfmpegVersion" `
    -DestinationName "ffmpeg"

$lameArchive = Join-Path $downloadsRoot "lame-$LameVersion.tar.gz"
Download-File `
    -Url "https://downloads.sourceforge.net/project/lame/lame/$LameVersion/lame-$LameVersion.tar.gz" `
    -OutFile $lameArchive
Expand-SourceArchive `
    -Archive $lameArchive `
    -ExtractedName "lame-$LameVersion" `
    -DestinationName "lame"

$versionsFile = Join-Path $thirdPartyRoot "versions.local.txt"
@(
    "FFmpeg $FfmpegVersion https://ffmpeg.org/releases/ffmpeg-$FfmpegVersion.tar.xz",
    "LAME $LameVersion https://downloads.sourceforge.net/project/lame/lame/$LameVersion/lame-$LameVersion.tar.gz",
    "MSYS2 portable https://github.com/msys2/msys2-installer/releases/latest/download/msys2-base-x86_64-latest.sfx.exe"
) | Set-Content -Path $versionsFile -Encoding UTF8

Write-Host "Prepared FFmpeg Android sources and tools."
