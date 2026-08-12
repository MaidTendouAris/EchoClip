# EchoClip Rust Core

This document records the Rust backend boundary for EchoClip. The shared
Flutter UI and platform permission/lifecycle adapters call into this core
instead of owning audio retention and export logic. On Windows, the Rust FFI
also owns native capture, source selection, and mixing.

## Goals

- Detect the current platform and choose the correct capture route.
- Keep replay audio on disk as rolling raw PCM segments.
- Rotate segment files every 60 seconds by default.
- Keep up to 24 hours of replay audio by default.
- Merge retained segments into a saved audio file when the user saves a replay.
- Keep Android microphone capture in Kotlin `AudioRecord`; Rust receives PCM
  from JNI and owns buffering/export.
- Keep Windows x64 microphone capture, input-device selection, default-output
  loopback, resampling, and source mixing inside the Rust/CPAL adapter.

## Platform Plan

Use `CapturePlan::current()`:

```rust
use echoclip_core::{CapturePlan, CaptureRoute};

let plan = CapturePlan::current();
match plan.route {
    CaptureRoute::ExternalPcm => {
        // Android: Kotlin AudioRecord captures microphone PCM, then JNI pushes
        // i16 little-endian mono samples into Rust.
    }
    CaptureRoute::NativeMicrophone => {
        // Native desktop adapter. On Windows, Rust/CPAL can open the selected
        // microphone, the default output loopback endpoint, or both, then feed
        // one mixed PCM timeline into RecorderWorker.
    }
    CaptureRoute::Unsupported => {
        // Show a clear unsupported-platform error.
    }
}
```

Current route mapping:

| Platform | Route |
| --- | --- |
| Android | `ExternalPcm` |
| Windows x64 | `NativeMicrophone`; Rust/CPAL WASAPI microphone and output loopback |
| Linux | `NativeMicrophone` |
| macOS | `NativeMicrophone` |
| iOS | `Unsupported` for now |

The Android decision is intentional: Android permission prompts, foreground
services, and `AudioRecord` lifecycle remain native Kotlin responsibilities.
Rust handles PCM once it has already been captured.

`NativeMicrophone` is the historical name of the native desktop route. The
Windows adapter also supports WASAPI output loopback; it does not imply that
Windows is limited to microphone-only recording.

## Windows x64 Capture And Packaging

Windows and Android use the same Flutter widgets and settings page. The Dart
service boundary reports platform capabilities instead of branching into a
second Windows UI implementation:

- `systemAudioSupported` controls whether the system-audio checkbox is enabled;
- `inputDeviceSelectionSupported` controls whether the microphone endpoint
  selector and refresh action are enabled;
- disabling microphone capture also disables its endpoint controls;
- both the Flutter state and Rust FFI reject a configuration with no enabled
  source.

Android currently reports system-audio capture and input-device selection as
unsupported, so those controls remain visible but disabled. Its existing
Kotlin `AudioRecord` -> JNI -> Rust path is unchanged.

### Native capture topology

The Windows path is owned by `echoclip_windows_ffi`:

```text
shared Flutter settings
        |
        v
WindowsReplayService -> Dart FFI -> echoclip_windows_ffi
                                      |          |
                           CPAL/WASAPI mic   default output loopback
                                      |          |
                                      +----+-----+
                                           v
                                fixed-timeline Rust mixer
                                           |
                                           v
                                    RecorderWorker
                                           |
                                           v
                                  60-second PCM segments
```

CPAL enumerates active input endpoints and exposes their Windows endpoint IDs.
The UI treats these IDs as opaque stable identifiers; display names are not
unique and are never persistence keys. A concrete ID selects that endpoint.
A null `microphoneDeviceId` is the separate "system default" selection: Rust
resolves the current default input endpoint when capture starts, so a later
recording can follow a changed Windows default without rewriting settings.

System audio is captured by opening CPAL's current default output endpoint as
an input stream. CPAL's WASAPI backend applies loopback mode for that render
endpoint. The stream uses the endpoint's native `default_output_config()` mix
format, then Rust downmixes and resamples it to the configured recorder rate.
The current UI does not select a non-default output endpoint.

The source modes are microphone only, system audio only, and microphone plus
system audio. Capture callbacks never push two independent streams directly to
`RecorderWorker`. Each callback converts its source to mono PCM at the recorder
rate and appends it to a bounded source queue. A single mixer emits frames on a
10 ms wall-clock timeline, after a short prebuffer:

- a temporarily empty source contributes silence instead of stopping time;
- a bounded queue prevents callback jitter or device-clock differences from
  growing memory and latency without limit;
- dual-source samples are averaged to retain 6 dB of headroom;
- the resulting single PCM stream reuses the same Rust segmentation, retention,
  and save logic as the Android-pushed PCM path.

This fixed timeline is important for output loopback because a silent render
endpoint may provide no useful audio frames. System-only capture still advances
the replay duration and records silence until playback resumes.

### Segments, save, and FFmpeg

The recorder default remains 60-second signed 16-bit PCM segments. Saving a
recent replay flushes the active segment, snapshots the required sample range,
and joins data across segment boundaries without making the Flutter frontend
manage platform-specific files.

The Windows capture/save path itself does not depend on an installed FFmpeg.
Recent replay saves currently use the Rust WAV exporter. The audio-processing
page uses the bundled `ffmpeg.exe` for gain processing and MP3/WAV output.

`scripts/build_windows_ffmpeg.ps1` builds an x86-64 audio-focused FFmpeg and
LAME from the pinned source tree and writes:

```text
third_party/ffmpeg/out/windows/x64/ffmpeg.exe
```

The Flutter Windows CMake build requires this executable and copies it, its
notice, and the FFmpeg/LAME licenses into the release bundle.
`scripts/build_windows_package.ps1` builds the x86-64 Rust DLL and Flutter
release, verifies the application, DLL, and FFmpeg are x64 PE files, then emits
both a portable ZIP and an Inno Setup installer. A user installation therefore
does not rely on `ffmpeg.exe` from `PATH`.

### Current MVP limits

- Changing the Windows default endpoint or unplugging an active endpoint is not
  transparently rerouted. Stop and restart recording to resolve the new device.
  A missing concrete microphone ID fails explicitly rather than silently
  falling back to the default.
- Dual-source alignment currently uses bounded FIFO queues and the 10 ms wall
  clock. It does not place packets by the WASAPI/QPC capture timestamps, so it
  is not a high-precision multi-device synchronization implementation.
- Nominal-rate resampling plus bounded drop/silence correction keeps the
  timeline finite, but long-running microphone-plus-system capture must still
  be tested on real devices for clock drift, underruns, dropped samples, and
  audible discontinuities across 44.1/48 kHz endpoint combinations.

## Configuration

Use `CoreConfig` to configure the recorder:

```rust
use echoclip_core::{AudioConfig, CoreConfig, DEFAULT_MAX_REPLAY_SECONDS};

let mut config = CoreConfig::new("D:/EchoClipRecordings");
config.audio = AudioConfig::mono_48k();
config.segment_seconds = 60;
config.max_replay_seconds = DEFAULT_MAX_REPLAY_SECONDS; // 24h

println!("estimated PCM bytes: {}", config.estimated_pcm_bytes());
```

Default PCM estimate for 48 kHz, mono, 16-bit PCM, 24 hours:

```text
48000 samples/s * 1 channel * 2 bytes * 86400 s = 8,294,400,000 bytes
```

That is about 7.7 GiB / 8.3 GB before filesystem overhead.

## Temporary File Layout

`SegmentedRecorder::start(config)` or `RecorderWorker::start(config)` creates:

```text
<work_dir>/
  .echoclip/
    temp/
      session-<unix-ms>/
        manifest.json
        segment-000000.pcm
        segment-000001.pcm
```

Segment files are raw signed 16-bit little-endian PCM. The manifest records:

- audio sample rate and channels;
- segment duration;
- max replay duration;
- total samples written;
- each segment file name, start sample, sample count, and completion state.

## Android Push Flow

Kotlin should keep using `AudioRecord`. JNI should push `ShortArray` chunks into
Rust. Android should use `RecorderWorker`, not call `SegmentedRecorder`
directly from the capture thread:

```rust
use echoclip_core::{CoreConfig, RecorderWorker};

let config = CoreConfig::new("/data/user/0/com.echoclip.echoclip/files/echoclip-runtime");
let worker = RecorderWorker::start(config)?;

// Called repeatedly by JNI from Kotlin AudioRecord chunks.
worker.push_samples(&pcm_i16_samples)?;
```

`RecorderWorker` owns a bounded queue and writer thread:

```text
AudioRecord thread -> bounded Rust queue -> Rust writer thread -> raw PCM segments
```

If the queue is full, the push call returns `QueueFull` and the Android service
should surface dropped chunk information in status.

Android temporary replay cache must use a real filesystem path, not the SAF
`content://` tree URI. Use app internal storage for temporary segments:

```text
context.filesDir/echoclip-runtime/.echoclip/temp/...
```

When the user saves a replay, Rust exports a temporary file to app cache/internal
storage, then Kotlin copies that file into the user-selected SAF folder using
`ContentResolver`. MP3 is the default export format. WAV remains available as an
explicit compatibility option.

## Export Flow

Save the latest replay window as MP3:

```rust
use echoclip_core::ExportOptions;

let options = ExportOptions::mp3(
    "/data/app/.../lib/arm64/libffmpeg.so",
    128,
);
let job_id = worker.save_latest_async(30, "/cache/echoclip-export.mp3", options)?;
let status = worker.export_status(job_id);
```

The writer thread flushes the active segment, takes a snapshot, then spawns an
export worker. Recording can continue while the export worker reads the snapshot
segments and writes the exported file.

For MP3 export, Rust does not create an intermediate WAV. It streams retained raw
PCM bytes directly into FFmpeg stdin:

```text
ffmpeg -hide_banner -loglevel error \
  -f s16le -ar <sample_rate> -ac <channels> -i pipe:0 \
  -vn -codec:a libmp3lame -b:a <bitrate> -y <output.mp3>
```

This avoids the standard WAV 4 GiB container limit for long replay saves.

Android packages FFmpeg as a PIE executable named `libffmpeg.so`:

```text
apps/echoclip/android/app/src/main/jniLibs/arm64-v8a/libffmpeg.so
```

The Android Gradle config enables legacy JNI packaging so this file is extracted
to `applicationInfo.nativeLibraryDir`. `ReplayForegroundService` passes that
absolute executable path into Rust. If FFmpeg is missing, Rust returns
`FfmpegUnavailable` instead of silently falling back to WAV.

The Android FFmpeg build is audio-only, not full FFmpeg. It keeps MP3, WAV, AAC,
FLAC, raw PCM, and core audio filters such as volume, loudness normalization,
compression, limiting, high/low-pass, tempo, and resampling. Build scripts live
under `scripts/build_android_ffmpeg.ps1` and `third_party/ffmpeg/`.

WAV export remains available:

```rust
let job_id = worker.save_latest_wav_async(30, "/cache/echoclip-export.wav")?;
```

On Android, `ReplayForegroundService.saveLatestClip()` starts a background save
task and returns immediately with a local save job id. The task runs these
states:

```text
Queued -> Exporting -> CopyingToSaf -> Finished
            |              \-> Failed
            \-> Canceled
```

Rust export jobs and Android save jobs are both exposed through service status.
Android save jobs expose copy progress through `copyBytesWritten`,
`copyTotalBytes`, and `progress`.

Canceling a save job cancels the Rust export if it is still running and deletes
only the temporary exported file in app cache. It must never delete raw PCM
replay segment files. Replay segment retention is still owned only by the
recorder trim logic.

Low-level code can still export a snapshot by absolute sample range:

```rust
let snapshot = recorder.snapshot()?;
snapshot.save_range_wav_by_sample(start_sample, end_sample, "range.wav")?;
```

The WAV exporter writes standard RIFF/WAV. Standard WAV cannot safely store more
than roughly 4 GiB of PCM data. A full 24-hour 48 kHz mono export is larger than
that, so the core returns `EchoCoreError::ExportTooLargeForWav` when the
requested WAV output is too large. Use MP3 export for long single-file saves.

## Retention

After samples are pushed, the recorder trims segment files that fall completely
outside `max_replay_seconds`. A segment that partially overlaps the retention
window is kept, and export starts from the retained sample boundary. Export
snapshots pin their segment file names with reference counts, so unrelated
expired segments can still be trimmed while export is active and overlapping
exports cannot release each other's segment pins. When export finishes or is
canceled, the worker releases the snapshot pins and triggers a trim pass.

## Recovery And Cleanup

Startup uses `SegmentedRecorder::recover_latest_or_start`:

- pick the latest temp session;
- read `manifest.json` with `serde_json`;
- if manifest is missing or corrupt, rebuild from `segment-*.pcm` files;
- delete incomplete segments;
- repair segment `sample_count` from actual file size;
- delete stale sessions outside the active one.

Recovery details are exposed through status as `recovered` and
`recovery_warning`.

Android also deletes stale `echoclip-export-*` files from app cache on service
startup.

## Status Surface

`RecorderWorkerStatus` intentionally exposes more information than the current
UI needs:

- `available_millis`;
- `oldest_retained_millis`;
- `latest_sample_millis`;
- `total_samples_written`;
- `retained_start_sample`;
- `segment_count`;
- `temp_bytes`;
- `estimated_max_pcm_bytes`;
- `queue_capacity_chunks`;
- `queued_chunks`;
- `dropped_chunks`;
- `active_exports`;
- `export_jobs`;
- `writer_last_flush_unix_millis`;
- `recovered`;
- `recovery_warning`;
- `last_error`.

Android service status adds app storage information such as internal usable and
total bytes, Android-side save job states, export format, MP3 bitrate, and
whether an executable FFmpeg path was found.

This avoids rewriting segment files during normal recording.

## Existing In-Memory Buffer

`RingBuffer` remains available for short-lived UI needs such as level meters or
small previews. It is not the 24-hour replay store. Long replay retention should
use `SegmentedRecorder`.

## Error Handling

Public backend errors use `EchoCoreError`:

- `InvalidConfig`: invalid sample rate, channel count, segment duration, or
  retention duration;
- `Io`: filesystem errors;
- `EmptyRange`: export request has no retained audio;
- `ExportTooLargeForWav`: WAV request exceeds standard WAV limits;
- `FfmpegUnavailable`: MP3 export cannot start because FFmpeg is missing or not
  executable;
- `FfmpegFailed`: FFmpeg started but returned a non-zero exit status or stdin
  failed;
- `QueueFull`: bounded PCM queue is full and a capture chunk was dropped;
- `QueueClosed` / `WorkerStopped` / `Worker`: lifecycle and background worker
  errors.

JNI/Flutter should map these to explicit user-facing errors instead of a generic
`error`.

## JNI Surface

Android JNI exports are intentionally thin:

```text
nativeStartRecorder(tempDir, sampleRate, channels, segmentSeconds, maxReplaySeconds, queueCapacity)
nativePushPcm(handle, samples, count)
nativeAvailableMillis(handle)
nativeSaveLatestToCache(handle, seconds, outputPath, format, mp3BitrateKbps, ffmpegPath)
nativeExportStatusJson(handle, jobId)
nativeCancelExport(handle, jobId)
nativeStatusJson(handle)
nativeStopRecorder(handle)
nativeDestroy(handle)
```

All JNI entry points are wrapped in `catch_unwind`. The JNI crate is used instead
of manually indexing JNI vtable slots.

`nativePushPcm` returns structured status codes:

| Code | Meaning |
| --- | --- |
| 0 | ok |
| 1 | queue full |
| 2 | worker stopped |
| 3 | invalid handle |
| 4 | panic caught |
| 5 | queue closed |
| 6 | other error |
