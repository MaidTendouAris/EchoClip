# EchoClip Android FFmpeg Build

EchoClip packages FFmpeg for Android as:

```text
apps/echoclip/android/app/src/main/jniLibs/arm64-v8a/libffmpeg.so
```

The file is an Android PIE executable named `libffmpeg.so`, not a JNI library.
It is placed under `jniLibs` so Android extracts it into
`applicationInfo.nativeLibraryDir`, where the Rust core can spawn it as a child
process.

## Source Layout

Do not commit FFmpeg or LAME source trees. Place local source checkouts here:

```text
third_party/ffmpeg/
  src/
    ffmpeg/
    lame/
```

Current build inputs are recorded in `versions.txt`.

FFmpeg itself only distributes source code. Binary builds must be reproducible
from the source, configure flags, and licenses documented in this directory.

## Build

From the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\prepare_android_ffmpeg_sources.ps1
powershell -ExecutionPolicy Bypass -File scripts\build_android_ffmpeg.ps1
```

The prepare script downloads portable MSYS2 into `tools/msys64`, installs the
required MSYS2 build tools, and unpacks FFmpeg/LAME source under
`third_party/ffmpeg/src`.

The build script builds:

1. static `libmp3lame.a`;
2. an audio-only Android FFmpeg command-line executable;
3. `apps/echoclip/android/app/src/main/jniLibs/arm64-v8a/libffmpeg.so`.

Git Bash, MSYS2, or WSL `bash` must be available in `PATH`.

## Audio-Only Scope

The build is intentionally broader than EchoClip's current MP3-only export path
but still avoids a full FFmpeg build.

Enabled output formats:

- MP3 through `libmp3lame`;
- WAV / PCM;
- AAC / ADTS / M4A;
- FLAC.

Enabled input formats:

- raw signed 16-bit little-endian PCM (`s16le`);
- WAV;
- MP3;
- AAC / M4A;
- FLAC.

Enabled filters:

- `volume`;
- `loudnorm`;
- `acompressor`;
- `alimiter`;
- `highpass`;
- `lowpass`;
- `atempo`;
- `aresample`.

This covers the planned lightweight audio processing features without shipping
video codecs, devices, networking, FFprobe, or FFplay.

## Licensing

EchoClip is GPL-3.0-only. FFmpeg is LGPL-2.1-or-later by default, with optional
GPL components depending on configure flags. LAME is LGPL. The checked-in build
configuration intentionally avoids `--enable-nonfree`.

When distributing APKs that include `libffmpeg.so`, keep these obligations in
release artifacts or a public source package:

- FFmpeg and LAME source versions;
- configure flags;
- any local patches;
- license texts and attribution;
- a source download link matching the shipped binary.

The app About/License screen should mention that EchoClip uses FFmpeg and LAME.
