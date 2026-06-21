use std::collections::{HashMap, HashSet};
use std::f32::consts::PI;
use std::fs::{self, File, OpenOptions};
use std::io::{self, BufReader, BufWriter, Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};
use std::sync::mpsc::{self, Receiver, SyncSender, TrySendError};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

pub const DEFAULT_SEGMENT_SECONDS: u32 = 60;
pub const DEFAULT_MAX_REPLAY_SECONDS: u32 = 24 * 60 * 60;
pub const DEFAULT_QUEUE_CAPACITY_CHUNKS: usize = 32;
pub const DEFAULT_MANIFEST_DEBOUNCE: Duration = Duration::from_secs(5);
pub const DEFAULT_EXPORT_JOB_HISTORY: usize = 32;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EchoPlatform {
    Windows,
    Android,
    Linux,
    MacOs,
    Ios,
    Unknown,
}

impl EchoPlatform {
    pub fn current() -> Self {
        #[cfg(target_os = "windows")]
        return Self::Windows;
        #[cfg(target_os = "android")]
        return Self::Android;
        #[cfg(target_os = "linux")]
        return Self::Linux;
        #[cfg(target_os = "macos")]
        return Self::MacOs;
        #[cfg(target_os = "ios")]
        return Self::Ios;

        #[allow(unreachable_code)]
        Self::Unknown
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CaptureRoute {
    ExternalPcm,
    NativeMicrophone,
    Unsupported,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CapturePlan {
    pub platform: EchoPlatform,
    pub route: CaptureRoute,
}

impl CapturePlan {
    pub fn current() -> Self {
        Self::for_platform(EchoPlatform::current())
    }

    pub fn for_platform(platform: EchoPlatform) -> Self {
        let route = match platform {
            EchoPlatform::Android => CaptureRoute::ExternalPcm,
            EchoPlatform::Windows | EchoPlatform::Linux | EchoPlatform::MacOs => {
                CaptureRoute::NativeMicrophone
            }
            EchoPlatform::Ios | EchoPlatform::Unknown => CaptureRoute::Unsupported,
        };

        Self { platform, route }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct AudioConfig {
    pub sample_rate: u32,
    pub channels: u16,
}

impl AudioConfig {
    pub fn mono_48k() -> Self {
        Self {
            sample_rate: 48_000,
            channels: 1,
        }
    }

    fn samples_for_duration(self, seconds: f32) -> usize {
        let frames = (self.sample_rate as f32 * seconds).round().max(1.0) as usize;
        frames * self.channels as usize
    }

    fn samples_for_seconds_u64(self, seconds: u32) -> u64 {
        self.sample_rate as u64 * self.channels as u64 * seconds as u64
    }

    fn bytes_for_samples(sample_count: u64) -> u64 {
        sample_count * 2
    }
}

#[derive(Debug, Clone)]
pub struct AudioClip {
    pub config: AudioConfig,
    pub samples: Vec<i16>,
}

impl AudioClip {
    pub fn duration_seconds(&self) -> f32 {
        self.samples.len() as f32 / self.config.channels as f32 / self.config.sample_rate as f32
    }

    pub fn with_gain_db(mut self, gain_db: f32) -> Self {
        apply_gain_db(&mut self.samples, gain_db);
        self
    }

    pub fn write_wav<P: AsRef<Path>>(&self, path: P) -> io::Result<()> {
        write_wav_i16(path, self.config, &self.samples)
    }
}

#[derive(Debug, Clone)]
pub struct RingBuffer {
    config: AudioConfig,
    samples: Vec<i16>,
    write_pos: usize,
    len: usize,
}

impl RingBuffer {
    pub fn new(config: AudioConfig, capacity_seconds: f32) -> Self {
        let capacity = config.samples_for_duration(capacity_seconds);
        Self {
            config,
            samples: vec![0; capacity],
            write_pos: 0,
            len: 0,
        }
    }

    pub fn config(&self) -> AudioConfig {
        self.config
    }

    pub fn capacity_samples(&self) -> usize {
        self.samples.len()
    }

    pub fn available_samples(&self) -> usize {
        self.len
    }

    pub fn available_seconds(&self) -> f32 {
        self.len as f32 / self.config.channels as f32 / self.config.sample_rate as f32
    }

    pub fn push_samples(&mut self, input: &[i16]) {
        for &sample in input {
            self.samples[self.write_pos] = sample;
            self.write_pos = (self.write_pos + 1) % self.samples.len();
            self.len = (self.len + 1).min(self.samples.len());
        }
    }

    pub fn latest(&self, seconds: f32) -> AudioClip {
        let requested = self.config.samples_for_duration(seconds);
        let count = requested.min(self.len);
        let start = (self.write_pos + self.samples.len() - count) % self.samples.len();
        let mut out = Vec::with_capacity(count);

        for index in 0..count {
            out.push(self.samples[(start + index) % self.samples.len()]);
        }

        AudioClip {
            config: self.config,
            samples: out,
        }
    }
}

#[derive(Debug, Clone)]
pub struct CoreConfig {
    pub audio: AudioConfig,
    pub segment_seconds: u32,
    pub max_replay_seconds: u32,
    pub work_dir: PathBuf,
}

impl CoreConfig {
    pub fn new(work_dir: impl Into<PathBuf>) -> Self {
        Self {
            audio: AudioConfig::mono_48k(),
            segment_seconds: DEFAULT_SEGMENT_SECONDS,
            max_replay_seconds: DEFAULT_MAX_REPLAY_SECONDS,
            work_dir: work_dir.into(),
        }
    }

    pub fn temp_root(&self) -> PathBuf {
        self.work_dir.join(".echoclip").join("temp")
    }

    pub fn validate(&self) -> Result<(), EchoCoreError> {
        if self.audio.sample_rate == 0 {
            return Err(EchoCoreError::InvalidConfig("sample_rate must be non-zero"));
        }
        if self.audio.channels == 0 {
            return Err(EchoCoreError::InvalidConfig("channels must be non-zero"));
        }
        if self.segment_seconds == 0 {
            return Err(EchoCoreError::InvalidConfig(
                "segment_seconds must be non-zero",
            ));
        }
        if self.max_replay_seconds == 0 {
            return Err(EchoCoreError::InvalidConfig(
                "max_replay_seconds must be non-zero",
            ));
        }
        Ok(())
    }

    pub fn estimated_pcm_bytes(&self) -> u64 {
        AudioConfig::bytes_for_samples(self.audio.samples_for_seconds_u64(self.max_replay_seconds))
    }
}

#[derive(Debug)]
pub enum EchoCoreError {
    Io(io::Error),
    Serde(serde_json::Error),
    InvalidConfig(&'static str),
    ExportTooLargeForWav { bytes: u64 },
    FfmpegUnavailable(String),
    FfmpegFailed(String),
    ExportCanceled,
    EmptyRange,
    QueueClosed,
    QueueFull { dropped_chunks: u64 },
    WorkerStopped,
    Worker(String),
    JobNotFound(u64),
}

impl std::fmt::Display for EchoCoreError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Io(error) => write!(formatter, "{error}"),
            Self::Serde(error) => write!(formatter, "{error}"),
            Self::InvalidConfig(message) => write!(formatter, "invalid config: {message}"),
            Self::ExportTooLargeForWav { bytes } => {
                write!(formatter, "WAV export is larger than 4 GiB: {bytes} bytes")
            }
            Self::FfmpegUnavailable(message) => write!(formatter, "ffmpeg unavailable: {message}"),
            Self::FfmpegFailed(message) => write!(formatter, "ffmpeg failed: {message}"),
            Self::ExportCanceled => write!(formatter, "export canceled"),
            Self::EmptyRange => write!(formatter, "export range is empty"),
            Self::QueueClosed => write!(formatter, "recorder worker queue is closed"),
            Self::QueueFull { dropped_chunks } => {
                write!(
                    formatter,
                    "recorder worker queue is full; dropped chunks: {dropped_chunks}"
                )
            }
            Self::WorkerStopped => write!(formatter, "recorder worker is stopped"),
            Self::Worker(message) => write!(formatter, "recorder worker error: {message}"),
            Self::JobNotFound(id) => write!(formatter, "export job not found: {id}"),
        }
    }
}

impl std::error::Error for EchoCoreError {}

impl From<io::Error> for EchoCoreError {
    fn from(value: io::Error) -> Self {
        Self::Io(value)
    }
}

impl From<serde_json::Error> for EchoCoreError {
    fn from(value: serde_json::Error) -> Self {
        Self::Serde(value)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SegmentInfo {
    pub index: u64,
    pub file_name: String,
    pub start_sample: u64,
    pub sample_count: u64,
    pub complete: bool,
}

impl SegmentInfo {
    pub fn end_sample(&self) -> u64 {
        self.start_sample + self.sample_count
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ExportFormat {
    Wav,
    Mp3,
}

impl ExportFormat {
    pub fn extension(self) -> &'static str {
        match self {
            Self::Wav => "wav",
            Self::Mp3 => "mp3",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExportOptions {
    pub format: ExportFormat,
    pub mp3_bitrate_kbps: u32,
    pub ffmpeg_path: Option<PathBuf>,
}

impl ExportOptions {
    pub fn mp3(ffmpeg_path: impl Into<PathBuf>, bitrate_kbps: u32) -> Self {
        Self {
            format: ExportFormat::Mp3,
            mp3_bitrate_kbps: sanitize_mp3_bitrate(bitrate_kbps),
            ffmpeg_path: Some(ffmpeg_path.into()),
        }
    }

    pub fn wav() -> Self {
        Self {
            format: ExportFormat::Wav,
            mp3_bitrate_kbps: 128,
            ffmpeg_path: None,
        }
    }
}

impl Default for ExportOptions {
    fn default() -> Self {
        Self {
            format: ExportFormat::Mp3,
            mp3_bitrate_kbps: 128,
            ffmpeg_path: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecorderManifest {
    pub format_version: u32,
    pub session_id: String,
    pub created_unix_millis: u128,
    pub audio: AudioConfig,
    pub sample_format: String,
    pub segment_seconds: u32,
    pub max_replay_seconds: u32,
    pub total_samples_written: u64,
    pub segments: Vec<SegmentInfo>,
}

impl RecorderManifest {
    fn new(config: &CoreConfig, session_id: String) -> Self {
        Self {
            session_id,
            format_version: 1,
            created_unix_millis: unix_millis_now(),
            audio: config.audio,
            sample_format: "i16le".to_string(),
            segment_seconds: config.segment_seconds,
            max_replay_seconds: config.max_replay_seconds,
            total_samples_written: 0,
            segments: Vec::new(),
        }
    }

    pub fn to_json(&self) -> Result<String, EchoCoreError> {
        Ok(serde_json::to_string_pretty(self)?)
    }

    pub fn from_json(input: &str) -> Result<Self, EchoCoreError> {
        Ok(serde_json::from_str(input)?)
    }
}

#[derive(Debug)]
pub struct SegmentedRecorder {
    config: CoreConfig,
    session_dir: PathBuf,
    manifest_path: PathBuf,
    manifest: RecorderManifest,
    current_file: Option<BufWriter<File>>,
    manifest_dirty: bool,
    last_manifest_persist: Instant,
    recovered: bool,
    recovery_warning: Option<String>,
}

impl SegmentedRecorder {
    pub fn start(config: CoreConfig) -> Result<Self, EchoCoreError> {
        config.validate()?;
        fs::create_dir_all(config.temp_root())?;

        let session_id = new_session_id();
        let session_dir = config.temp_root().join(&session_id);
        fs::create_dir_all(&session_dir)?;

        let manifest_path = session_dir.join("manifest.json");
        let manifest = RecorderManifest::new(&config, session_id);
        let mut recorder = Self {
            config,
            session_dir,
            manifest_path,
            manifest,
            current_file: None,
            manifest_dirty: false,
            last_manifest_persist: Instant::now(),
            recovered: false,
            recovery_warning: None,
        };
        recorder.persist_manifest_now()?;
        Ok(recorder)
    }

    pub fn recover_latest_or_start(config: CoreConfig) -> Result<Self, EchoCoreError> {
        config.validate()?;
        let temp_root = config.temp_root();
        fs::create_dir_all(&temp_root)?;
        let mut recovery_warnings = Vec::new();

        let Some(session_dir) = latest_session_dir(&temp_root)? else {
            return Self::start(config);
        };
        let manifest_path = session_dir.join("manifest.json");
        let mut manifest = if manifest_path.exists() {
            match fs::read_to_string(&manifest_path)
                .map_err(EchoCoreError::from)
                .and_then(|json| RecorderManifest::from_json(&json))
            {
                Ok(manifest) => manifest,
                Err(error) => {
                    recovery_warnings.push(format!("manifest_reconstructed:{error}"));
                    reconstruct_manifest_from_pcm(&config, &session_dir)?
                }
            }
        } else {
            recovery_warnings.push("manifest_missing_reconstructed".to_string());
            reconstruct_manifest_from_pcm(&config, &session_dir)?
        };
        manifest.audio = config.audio;
        manifest.segment_seconds = config.segment_seconds;
        manifest.max_replay_seconds = config.max_replay_seconds;

        let mut retained_segments = Vec::with_capacity(manifest.segments.len());
        let mut retained_files = HashSet::new();
        for segment in manifest.segments.drain(..) {
            let path = session_dir.join(&segment.file_name);
            if path.exists() {
                let actual_samples = fs::metadata(&path)?.len() / 2;
                if actual_samples == 0 {
                    recovery_warnings.push(format!("empty_segment_skipped:{}", segment.file_name));
                    continue;
                }
                let mut segment = segment;
                if !segment.complete {
                    recovery_warnings.push(format!(
                        "recovered_incomplete_segment:{}",
                        segment.file_name
                    ));
                    segment.complete = true;
                }
                if segment.sample_count != actual_samples {
                    recovery_warnings.push(format!(
                        "repaired_sample_count:{}:{}->{}",
                        segment.file_name, segment.sample_count, actual_samples
                    ));
                }
                segment.sample_count = actual_samples;
                retained_files.insert(segment.file_name.clone());
                retained_segments.push(segment);
            } else {
                recovery_warnings.push(format!("missing_segment_skipped:{}", segment.file_name));
            }
        }
        recover_untracked_pcm_segments(
            &session_dir,
            &retained_files,
            &mut retained_segments,
            &mut recovery_warnings,
        )?;
        retained_segments.sort_by_key(|segment| segment.index);
        let mut next_start = 0;
        for segment in &mut retained_segments {
            segment.start_sample = next_start;
            next_start += segment.sample_count;
        }
        manifest.segments = retained_segments;
        manifest.total_samples_written = next_start;

        let mut recorder = Self {
            config,
            session_dir,
            manifest_path,
            manifest,
            current_file: None,
            manifest_dirty: true,
            last_manifest_persist: Instant::now(),
            recovered: true,
            recovery_warning: if recovery_warnings.is_empty() {
                None
            } else {
                Some(recovery_warnings.join(";"))
            },
        };
        recorder.trim_expired_segments()?;
        recorder.persist_manifest_now()?;
        cleanup_stale_sessions(&temp_root, &recorder.session_dir)?;
        Ok(recorder)
    }

    pub fn config(&self) -> &CoreConfig {
        &self.config
    }

    pub fn manifest(&self) -> &RecorderManifest {
        &self.manifest
    }

    pub fn session_dir(&self) -> &Path {
        &self.session_dir
    }

    pub fn available_seconds(&self) -> f32 {
        let samples = self.available_samples();
        samples as f32 / self.config.audio.channels as f32 / self.config.audio.sample_rate as f32
    }

    pub fn available_samples(&self) -> u64 {
        let retained_start = self.retained_start_sample();
        self.manifest
            .total_samples_written
            .saturating_sub(retained_start)
    }

    pub fn temp_bytes(&self) -> u64 {
        self.manifest
            .segments
            .iter()
            .filter_map(|segment| fs::metadata(self.session_dir.join(&segment.file_name)).ok())
            .map(|metadata| metadata.len())
            .sum()
    }

    pub fn push_samples(&mut self, samples: &[i16]) -> Result<(), EchoCoreError> {
        self.push_samples_with_trim(samples, true)
    }

    pub fn push_samples_defer_trim(&mut self, samples: &[i16]) -> Result<(), EchoCoreError> {
        self.push_samples_with_trim(samples, false)
    }

    fn push_samples_with_trim(
        &mut self,
        samples: &[i16],
        trim_expired: bool,
    ) -> Result<(), EchoCoreError> {
        let mut offset = 0;
        while offset < samples.len() {
            self.ensure_current_segment()?;
            let remaining = self.remaining_in_current_segment() as usize;
            let write_count = remaining.min(samples.len() - offset);
            self.write_samples_to_current(&samples[offset..offset + write_count])?;
            offset += write_count;

            if self.remaining_in_current_segment() == 0 {
                self.close_current_segment()?;
            }
        }

        if trim_expired {
            self.trim_expired_segments()?;
        }
        self.persist_manifest_if_due()?;
        Ok(())
    }

    pub fn flush(&mut self) -> Result<(), EchoCoreError> {
        if let Some(file) = self.current_file.as_mut() {
            file.flush()?;
        }
        self.persist_manifest_now()
    }

    pub fn save_latest_wav(
        &mut self,
        seconds: u32,
        output_path: impl AsRef<Path>,
    ) -> Result<u64, EchoCoreError> {
        self.flush()?;

        let requested = self.config.audio.samples_for_seconds_u64(seconds);
        let end = self.manifest.total_samples_written;
        let retained_start = self.retained_start_sample();
        let start = end.saturating_sub(requested).max(retained_start);
        self.save_range_wav_by_sample(start, end, output_path)
    }

    pub fn snapshot(&mut self) -> Result<RecorderSnapshot, EchoCoreError> {
        self.flush()?;
        Ok(RecorderSnapshot {
            audio: self.config.audio,
            session_dir: self.session_dir.clone(),
            total_samples_written: self.manifest.total_samples_written,
            retained_start_sample: self.retained_start_sample(),
            segments: self.manifest.segments.clone(),
        })
    }

    pub fn save_range_wav_by_sample(
        &mut self,
        start_sample: u64,
        end_sample: u64,
        output_path: impl AsRef<Path>,
    ) -> Result<u64, EchoCoreError> {
        self.flush()?;
        if end_sample <= start_sample {
            return Err(EchoCoreError::EmptyRange);
        }

        let retained_start = self.retained_start_sample();
        let start = start_sample.max(retained_start);
        let end = end_sample.min(self.manifest.total_samples_written);
        if end <= start {
            return Err(EchoCoreError::EmptyRange);
        }

        let sample_count = end - start;
        let data_bytes = AudioConfig::bytes_for_samples(sample_count);
        if data_bytes > (u32::MAX - 36) as u64 {
            return Err(EchoCoreError::ExportTooLargeForWav { bytes: data_bytes });
        }

        let mut output = BufWriter::new(File::create(output_path)?);
        write_wav_header(&mut output, self.config.audio, sample_count as u32)?;

        for segment in self.segments_overlapping(start, end) {
            let copy_start = start.max(segment.start_sample);
            let copy_end = end.min(segment.end_sample());
            let local_start = copy_start - segment.start_sample;
            let local_count = copy_end - copy_start;
            copy_segment_samples_from(
                &self.session_dir,
                segment,
                local_start,
                local_count,
                &mut output,
                None,
            )?;
        }

        output.flush()?;
        Ok(sample_count)
    }

    fn ensure_current_segment(&mut self) -> Result<(), EchoCoreError> {
        if self.current_file.is_some() {
            return Ok(());
        }

        let mut index = self
            .manifest
            .segments
            .last()
            .map(|segment| segment.index + 1)
            .unwrap_or(0);
        let (file_name, file_path) = loop {
            let file_name = format!("segment-{index:06}.pcm");
            let file_path = self.session_dir.join(&file_name);
            if !file_path.exists() {
                break (file_name, file_path);
            }
            index += 1;
        };
        let file = OpenOptions::new()
            .create_new(true)
            .write(true)
            .open(file_path)?;

        self.manifest.segments.push(SegmentInfo {
            index,
            file_name,
            start_sample: self.manifest.total_samples_written,
            sample_count: 0,
            complete: false,
        });
        self.current_file = Some(BufWriter::new(file));
        self.mark_manifest_dirty();
        Ok(())
    }

    fn write_samples_to_current(&mut self, samples: &[i16]) -> Result<(), EchoCoreError> {
        let file = self.current_file.as_mut().expect("current segment exists");
        write_i16le_samples(file, samples)?;

        let segment = self
            .manifest
            .segments
            .last_mut()
            .expect("current segment metadata exists");
        segment.sample_count += samples.len() as u64;
        self.manifest.total_samples_written += samples.len() as u64;
        self.mark_manifest_dirty();
        Ok(())
    }

    fn close_current_segment(&mut self) -> Result<(), EchoCoreError> {
        if let Some(mut file) = self.current_file.take() {
            file.flush()?;
        }
        if let Some(segment) = self.manifest.segments.last_mut() {
            segment.complete = true;
        }
        self.mark_manifest_dirty();
        self.persist_manifest_now()?;
        Ok(())
    }

    fn remaining_in_current_segment(&self) -> u64 {
        let capacity = self
            .config
            .audio
            .samples_for_seconds_u64(self.config.segment_seconds);
        let used = self
            .manifest
            .segments
            .last()
            .map(|segment| segment.sample_count)
            .unwrap_or(0);
        capacity.saturating_sub(used)
    }

    fn trim_expired_segments(&mut self) -> Result<(), EchoCoreError> {
        self.trim_expired_segments_except(&HashSet::new())
    }

    fn trim_expired_segments_except(
        &mut self,
        pinned_files: &HashSet<String>,
    ) -> Result<(), EchoCoreError> {
        let retained_start = self.retained_start_sample();
        let mut retained = Vec::with_capacity(self.manifest.segments.len());
        let mut removed_any = false;

        for segment in self.manifest.segments.drain(..) {
            if segment.end_sample() <= retained_start && !pinned_files.contains(&segment.file_name)
            {
                removed_any = true;
                let path = self.session_dir.join(&segment.file_name);
                match fs::remove_file(path) {
                    Ok(()) => {}
                    Err(error) if error.kind() == io::ErrorKind::NotFound => {}
                    Err(error) => return Err(EchoCoreError::Io(error)),
                }
            } else {
                retained.push(segment);
            }
        }

        if removed_any {
            self.mark_manifest_dirty();
        }
        self.manifest.segments = retained;
        Ok(())
    }

    fn retained_start_sample(&self) -> u64 {
        let max_samples = self
            .config
            .audio
            .samples_for_seconds_u64(self.config.max_replay_seconds);
        self.manifest
            .total_samples_written
            .saturating_sub(max_samples)
    }

    fn segments_overlapping(&self, start: u64, end: u64) -> impl Iterator<Item = &SegmentInfo> {
        self.manifest
            .segments
            .iter()
            .filter(move |segment| segment.start_sample < end && segment.end_sample() > start)
    }

    fn mark_manifest_dirty(&mut self) {
        self.manifest_dirty = true;
    }

    fn persist_manifest_if_due(&mut self) -> Result<(), EchoCoreError> {
        if self.manifest_dirty && self.last_manifest_persist.elapsed() >= DEFAULT_MANIFEST_DEBOUNCE
        {
            self.persist_manifest_now()?;
        }
        Ok(())
    }

    fn persist_manifest_now(&mut self) -> Result<(), EchoCoreError> {
        if !self.manifest_dirty && self.manifest_path.exists() {
            return Ok(());
        }
        let tmp_path = self.manifest_path.with_extension("json.tmp");
        {
            let mut file = BufWriter::new(File::create(&tmp_path)?);
            file.write_all(self.manifest.to_json()?.as_bytes())?;
            file.flush()?;
        }
        match fs::remove_file(&self.manifest_path) {
            Ok(()) => {}
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => return Err(EchoCoreError::Io(error)),
        }
        fs::rename(tmp_path, &self.manifest_path)?;
        self.manifest_dirty = false;
        self.last_manifest_persist = Instant::now();
        Ok(())
    }
}

impl Drop for SegmentedRecorder {
    fn drop(&mut self) {
        let _ = self.flush();
    }
}

#[derive(Debug, Clone)]
pub struct RecorderSnapshot {
    pub audio: AudioConfig,
    pub session_dir: PathBuf,
    pub total_samples_written: u64,
    pub retained_start_sample: u64,
    pub segments: Vec<SegmentInfo>,
}

impl RecorderSnapshot {
    pub fn available_samples(&self) -> u64 {
        self.total_samples_written
            .saturating_sub(self.retained_start_sample)
    }

    pub fn available_millis(&self) -> u64 {
        samples_to_millis(self.available_samples(), self.audio)
    }

    pub fn save_latest_wav(
        &self,
        seconds: u32,
        output_path: impl AsRef<Path>,
    ) -> Result<u64, EchoCoreError> {
        self.save_latest_wav_with_cancel(seconds, output_path, None)
    }

    pub fn save_latest_wav_with_cancel(
        &self,
        seconds: u32,
        output_path: impl AsRef<Path>,
        cancel_flag: Option<&AtomicBool>,
    ) -> Result<u64, EchoCoreError> {
        self.save_latest_with_options(seconds, output_path, &ExportOptions::wav(), cancel_flag)
    }

    pub fn save_latest_with_options(
        &self,
        seconds: u32,
        output_path: impl AsRef<Path>,
        options: &ExportOptions,
        cancel_flag: Option<&AtomicBool>,
    ) -> Result<u64, EchoCoreError> {
        let requested = self.audio.samples_for_seconds_u64(seconds);
        let end = self.total_samples_written;
        let start = end
            .saturating_sub(requested)
            .max(self.retained_start_sample);
        self.save_range_by_sample_with_options(start, end, output_path, options, cancel_flag)
    }

    pub fn save_range_wav_by_sample(
        &self,
        start_sample: u64,
        end_sample: u64,
        output_path: impl AsRef<Path>,
    ) -> Result<u64, EchoCoreError> {
        self.save_range_wav_by_sample_with_cancel(start_sample, end_sample, output_path, None)
    }

    pub fn save_range_wav_by_sample_with_cancel(
        &self,
        start_sample: u64,
        end_sample: u64,
        output_path: impl AsRef<Path>,
        cancel_flag: Option<&AtomicBool>,
    ) -> Result<u64, EchoCoreError> {
        self.save_range_by_sample_with_options(
            start_sample,
            end_sample,
            output_path,
            &ExportOptions::wav(),
            cancel_flag,
        )
    }

    pub fn save_range_by_sample_with_options(
        &self,
        start_sample: u64,
        end_sample: u64,
        output_path: impl AsRef<Path>,
        options: &ExportOptions,
        cancel_flag: Option<&AtomicBool>,
    ) -> Result<u64, EchoCoreError> {
        if end_sample <= start_sample {
            return Err(EchoCoreError::EmptyRange);
        }
        check_canceled(cancel_flag)?;

        let start = start_sample.max(self.retained_start_sample);
        let end = end_sample.min(self.total_samples_written);
        if end <= start {
            return Err(EchoCoreError::EmptyRange);
        }

        let sample_count = end - start;
        match options.format {
            ExportFormat::Wav => {
                self.export_range_wav(start, end, sample_count, output_path, cancel_flag)?
            }
            ExportFormat::Mp3 => {
                self.export_range_mp3(start, end, output_path, options, cancel_flag)?
            }
        }
        Ok(sample_count)
    }

    fn export_range_wav(
        &self,
        start: u64,
        end: u64,
        sample_count: u64,
        output_path: impl AsRef<Path>,
        cancel_flag: Option<&AtomicBool>,
    ) -> Result<(), EchoCoreError> {
        let data_bytes = AudioConfig::bytes_for_samples(sample_count);
        if data_bytes > (u32::MAX - 36) as u64 {
            return Err(EchoCoreError::ExportTooLargeForWav { bytes: data_bytes });
        }

        let mut output = BufWriter::new(File::create(output_path)?);
        write_wav_header(&mut output, self.audio, sample_count as u32)?;
        self.write_pcm_range_to(start, end, &mut output, cancel_flag)?;
        output.flush()?;
        Ok(())
    }

    fn export_range_mp3(
        &self,
        start: u64,
        end: u64,
        output_path: impl AsRef<Path>,
        options: &ExportOptions,
        cancel_flag: Option<&AtomicBool>,
    ) -> Result<(), EchoCoreError> {
        let ffmpeg_path = options.ffmpeg_path.as_ref().ok_or_else(|| {
            EchoCoreError::FfmpegUnavailable("ffmpeg_path_not_configured".to_string())
        })?;
        if !ffmpeg_path.exists() {
            return Err(EchoCoreError::FfmpegUnavailable(format!(
                "ffmpeg_not_found:{}",
                ffmpeg_path.display()
            )));
        }

        let output_path = output_path.as_ref();
        let bitrate = format!("{}k", sanitize_mp3_bitrate(options.mp3_bitrate_kbps));
        let mut child = Command::new(ffmpeg_path)
            .arg("-hide_banner")
            .arg("-loglevel")
            .arg("error")
            .arg("-f")
            .arg("s16le")
            .arg("-ar")
            .arg(self.audio.sample_rate.to_string())
            .arg("-ac")
            .arg(self.audio.channels.to_string())
            .arg("-i")
            .arg("pipe:0")
            .arg("-vn")
            .arg("-codec:a")
            .arg("libmp3lame")
            .arg("-b:a")
            .arg(bitrate)
            .arg("-y")
            .arg(output_path)
            .stdin(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|error| EchoCoreError::FfmpegUnavailable(error.to_string()))?;

        let write_result = {
            let stdin = child
                .stdin
                .as_mut()
                .ok_or_else(|| EchoCoreError::FfmpegFailed("stdin_unavailable".to_string()))?;
            self.write_pcm_range_to(start, end, stdin, cancel_flag)
        };

        drop(child.stdin.take());
        if let Err(error) = write_result {
            let _ = child.kill();
            let _ = child.wait();
            let _ = fs::remove_file(output_path);
            return Err(error);
        }

        let output = child
            .wait_with_output()
            .map_err(|error| EchoCoreError::FfmpegFailed(error.to_string()))?;
        if !output.status.success() {
            let _ = fs::remove_file(output_path);
            let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
            return Err(EchoCoreError::FfmpegFailed(if stderr.is_empty() {
                format!("exit_status:{}", output.status)
            } else {
                stderr
            }));
        }
        check_canceled(cancel_flag)?;
        Ok(())
    }

    fn write_pcm_range_to(
        &self,
        start: u64,
        end: u64,
        output: &mut impl Write,
        cancel_flag: Option<&AtomicBool>,
    ) -> Result<(), EchoCoreError> {
        for segment in self
            .segments
            .iter()
            .filter(|segment| segment.start_sample < end && segment.end_sample() > start)
        {
            check_canceled(cancel_flag)?;
            let copy_start = start.max(segment.start_sample);
            let copy_end = end.min(segment.end_sample());
            let local_start = copy_start - segment.start_sample;
            let local_count = copy_end - copy_start;
            copy_segment_samples_from(
                &self.session_dir,
                segment,
                local_start,
                local_count,
                output,
                cancel_flag,
            )?;
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ExportJobState {
    Pending,
    Running,
    Finished,
    Failed,
    Canceled,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExportJobStatus {
    pub id: u64,
    pub state: ExportJobState,
    pub requested_seconds: u32,
    pub format: ExportFormat,
    pub output_path: PathBuf,
    pub samples_written: u64,
    pub error: Option<String>,
    pub created_unix_millis: u128,
    pub finished_unix_millis: Option<u128>,
}

impl ExportJobStatus {
    fn pending(
        id: u64,
        requested_seconds: u32,
        format: ExportFormat,
        output_path: PathBuf,
    ) -> Self {
        Self {
            id,
            state: ExportJobState::Pending,
            requested_seconds,
            format,
            output_path,
            samples_written: 0,
            error: None,
            created_unix_millis: unix_millis_now(),
            finished_unix_millis: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecorderWorkerStatus {
    pub running: bool,
    pub available_millis: u64,
    pub oldest_retained_millis: u64,
    pub latest_sample_millis: u64,
    pub total_samples_written: u64,
    pub retained_start_sample: u64,
    pub segment_count: usize,
    pub temp_bytes: u64,
    pub estimated_max_pcm_bytes: u64,
    pub queue_capacity_chunks: usize,
    pub queued_chunks: usize,
    pub dropped_chunks: u64,
    pub active_exports: usize,
    pub export_jobs: Vec<ExportJobStatus>,
    pub writer_last_flush_unix_millis: u128,
    pub recovered: bool,
    pub recovery_warning: Option<String>,
    pub last_error: Option<String>,
}

#[derive(Debug, Clone)]
struct SharedWorkerStatus {
    running: bool,
    available_millis: u64,
    oldest_retained_millis: u64,
    latest_sample_millis: u64,
    total_samples_written: u64,
    retained_start_sample: u64,
    segment_count: usize,
    temp_bytes: u64,
    estimated_max_pcm_bytes: u64,
    queue_capacity_chunks: usize,
    queued_chunks: usize,
    dropped_chunks: u64,
    active_exports: usize,
    writer_last_flush_unix_millis: u128,
    recovered: bool,
    recovery_warning: Option<String>,
    last_error: Option<String>,
}

impl SharedWorkerStatus {
    fn new(queue_capacity_chunks: usize) -> Self {
        Self {
            running: true,
            available_millis: 0,
            oldest_retained_millis: 0,
            latest_sample_millis: 0,
            total_samples_written: 0,
            retained_start_sample: 0,
            segment_count: 0,
            temp_bytes: 0,
            estimated_max_pcm_bytes: 0,
            queue_capacity_chunks,
            queued_chunks: 0,
            dropped_chunks: 0,
            active_exports: 0,
            writer_last_flush_unix_millis: 0,
            recovered: false,
            recovery_warning: None,
            last_error: None,
        }
    }

    fn public(&self, export_jobs: Vec<ExportJobStatus>) -> RecorderWorkerStatus {
        RecorderWorkerStatus {
            running: self.running,
            available_millis: self.available_millis,
            oldest_retained_millis: self.oldest_retained_millis,
            latest_sample_millis: self.latest_sample_millis,
            total_samples_written: self.total_samples_written,
            retained_start_sample: self.retained_start_sample,
            segment_count: self.segment_count,
            temp_bytes: self.temp_bytes,
            estimated_max_pcm_bytes: self.estimated_max_pcm_bytes,
            queue_capacity_chunks: self.queue_capacity_chunks,
            queued_chunks: self.queued_chunks,
            dropped_chunks: self.dropped_chunks,
            active_exports: self.active_exports,
            export_jobs,
            writer_last_flush_unix_millis: self.writer_last_flush_unix_millis,
            recovered: self.recovered,
            recovery_warning: self.recovery_warning.clone(),
            last_error: self.last_error.clone(),
        }
    }
}

enum RecorderCommand {
    Push(Vec<i16>),
    SaveLatest {
        id: u64,
        seconds: u32,
        output_path: PathBuf,
        options: ExportOptions,
    },
    Trim,
    Flush(mpsc::Sender<Result<(), String>>),
    Stop,
}

pub struct RecorderWorker {
    sender: SyncSender<RecorderCommand>,
    thread: Option<JoinHandle<()>>,
    status: Arc<Mutex<SharedWorkerStatus>>,
    export_jobs: Arc<Mutex<Vec<ExportJobStatus>>>,
    cancel_flags: Arc<Mutex<HashMap<u64, Arc<AtomicBool>>>>,
    next_job_id: AtomicU64,
    queued_chunks: Arc<AtomicUsize>,
    stopped: Arc<AtomicBool>,
}

impl RecorderWorker {
    pub fn start(config: CoreConfig) -> Result<Self, EchoCoreError> {
        Self::start_with_queue(config, DEFAULT_QUEUE_CAPACITY_CHUNKS)
    }

    pub fn start_with_queue(
        config: CoreConfig,
        queue_capacity_chunks: usize,
    ) -> Result<Self, EchoCoreError> {
        let recorder = SegmentedRecorder::recover_latest_or_start(config)?;
        let (sender, receiver) = mpsc::sync_channel(queue_capacity_chunks.max(1));
        let status = Arc::new(Mutex::new(SharedWorkerStatus::new(
            queue_capacity_chunks.max(1),
        )));
        let export_jobs = Arc::new(Mutex::new(Vec::new()));
        let cancel_flags = Arc::new(Mutex::new(HashMap::new()));
        let active_exports = Arc::new(AtomicUsize::new(0));
        let pinned_segments = Arc::new(Mutex::new(HashMap::new()));
        let queued_chunks = Arc::new(AtomicUsize::new(0));
        let stopped = Arc::new(AtomicBool::new(false));

        update_worker_status(
            &status,
            &recorder,
            queued_chunks.load(Ordering::Relaxed),
            active_exports.load(Ordering::Relaxed),
            None,
        );

        let thread_status = Arc::clone(&status);
        let thread_export_jobs = Arc::clone(&export_jobs);
        let thread_cancel_flags = Arc::clone(&cancel_flags);
        let thread_active_exports = Arc::clone(&active_exports);
        let thread_pinned_segments = Arc::clone(&pinned_segments);
        let thread_queued_chunks = Arc::clone(&queued_chunks);
        let thread_stopped = Arc::clone(&stopped);
        let command_sender = sender.clone();
        let thread = thread::spawn(move || {
            recorder_worker_loop(
                recorder,
                receiver,
                command_sender,
                thread_status,
                thread_export_jobs,
                thread_cancel_flags,
                thread_active_exports,
                thread_pinned_segments,
                thread_queued_chunks,
                thread_stopped,
            );
        });

        Ok(Self {
            sender,
            thread: Some(thread),
            status,
            export_jobs,
            cancel_flags,
            next_job_id: AtomicU64::new(1),
            queued_chunks,
            stopped,
        })
    }

    pub fn push_samples(&self, samples: &[i16]) -> Result<(), EchoCoreError> {
        if self.stopped.load(Ordering::Relaxed) {
            return Err(EchoCoreError::WorkerStopped);
        }
        let chunk = samples.to_vec();
        match self.sender.try_send(RecorderCommand::Push(chunk)) {
            Ok(()) => {
                self.queued_chunks.fetch_add(1, Ordering::Relaxed);
                Ok(())
            }
            Err(TrySendError::Full(_)) => {
                let dropped = self.increment_dropped_chunks();
                Err(EchoCoreError::QueueFull {
                    dropped_chunks: dropped,
                })
            }
            Err(TrySendError::Disconnected(_)) => Err(EchoCoreError::QueueClosed),
        }
    }

    pub fn save_latest_wav_async(
        &self,
        seconds: u32,
        output_path: impl Into<PathBuf>,
    ) -> Result<u64, EchoCoreError> {
        self.save_latest_async(seconds, output_path, ExportOptions::wav())
    }

    pub fn save_latest_async(
        &self,
        seconds: u32,
        output_path: impl Into<PathBuf>,
        options: ExportOptions,
    ) -> Result<u64, EchoCoreError> {
        if self.stopped.load(Ordering::Relaxed) {
            return Err(EchoCoreError::WorkerStopped);
        }

        let id = self.next_job_id.fetch_add(1, Ordering::Relaxed);
        let output_path = output_path.into();
        let format = options.format;
        self.cancel_flags
            .lock()
            .expect("cancel flag lock")
            .insert(id, Arc::new(AtomicBool::new(false)));
        self.export_jobs
            .lock()
            .expect("export job lock")
            .push(ExportJobStatus::pending(
                id,
                seconds,
                format,
                output_path.clone(),
            ));
        self.sender
            .send(RecorderCommand::SaveLatest {
                id,
                seconds,
                output_path,
                options,
            })
            .map_err(|_| EchoCoreError::QueueClosed)?;
        Ok(id)
    }

    pub fn cancel_export(&self, id: u64) -> bool {
        let Some(flag) = self
            .cancel_flags
            .lock()
            .expect("cancel flag lock")
            .get(&id)
            .cloned()
        else {
            return false;
        };
        flag.store(true, Ordering::Relaxed);
        let mut jobs = self.export_jobs.lock().expect("export job lock");
        if let Some(job) = jobs.iter_mut().find(|job| job.id == id) {
            if matches!(job.state, ExportJobState::Pending) {
                job.state = ExportJobState::Canceled;
                job.error = Some("canceled".to_string());
                job.finished_unix_millis = Some(unix_millis_now());
            }
            return true;
        }
        false
    }

    pub fn flush(&self) -> Result<(), EchoCoreError> {
        let (sender, receiver) = mpsc::channel();
        self.sender
            .send(RecorderCommand::Flush(sender))
            .map_err(|_| EchoCoreError::QueueClosed)?;
        match receiver.recv() {
            Ok(Ok(())) => Ok(()),
            Ok(Err(error)) => Err(EchoCoreError::Worker(error)),
            Err(_) => Err(EchoCoreError::QueueClosed),
        }
    }

    pub fn status(&self) -> RecorderWorkerStatus {
        prune_export_jobs(&self.export_jobs);
        let export_jobs = self.export_jobs.lock().expect("export job lock").clone();
        self.status.lock().expect("status lock").public(export_jobs)
    }

    pub fn export_status(&self, id: u64) -> Option<ExportJobStatus> {
        self.export_jobs
            .lock()
            .expect("export job lock")
            .iter()
            .find(|job| job.id == id)
            .cloned()
    }

    pub fn stop(&mut self) {
        if self.stopped.swap(true, Ordering::Relaxed) {
            return;
        }
        let _ = self.sender.send(RecorderCommand::Stop);
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }

    fn increment_dropped_chunks(&self) -> u64 {
        let mut status = self.status.lock().expect("status lock");
        status.dropped_chunks += 1;
        status.dropped_chunks
    }
}

impl Drop for RecorderWorker {
    fn drop(&mut self) {
        self.stop();
    }
}

fn recorder_worker_loop(
    mut recorder: SegmentedRecorder,
    receiver: Receiver<RecorderCommand>,
    command_sender: SyncSender<RecorderCommand>,
    status: Arc<Mutex<SharedWorkerStatus>>,
    export_jobs: Arc<Mutex<Vec<ExportJobStatus>>>,
    cancel_flags: Arc<Mutex<HashMap<u64, Arc<AtomicBool>>>>,
    active_exports: Arc<AtomicUsize>,
    pinned_segments: Arc<Mutex<HashMap<String, usize>>>,
    queued_chunks: Arc<AtomicUsize>,
    stopped: Arc<AtomicBool>,
) {
    while let Ok(command) = receiver.recv() {
        match command {
            RecorderCommand::Push(samples) => {
                queued_chunks.fetch_sub(1, Ordering::Relaxed);
                let result = recorder.push_samples_defer_trim(&samples).and_then(|()| {
                    let pinned = pinned_file_set(&pinned_segments);
                    recorder.trim_expired_segments_except(&pinned)
                });
                let error = result.err().map(|error| error.to_string());
                update_worker_status(
                    &status,
                    &recorder,
                    queued_chunks.load(Ordering::Relaxed),
                    active_exports.load(Ordering::Relaxed),
                    error,
                );
            }
            RecorderCommand::SaveLatest {
                id,
                seconds,
                output_path,
                options,
            } => {
                let snapshot = recorder.snapshot();
                if let Ok(snapshot) = &snapshot {
                    pin_snapshot_segments(&pinned_segments, snapshot);
                }
                update_worker_status(
                    &status,
                    &recorder,
                    queued_chunks.load(Ordering::Relaxed),
                    active_exports.load(Ordering::Relaxed),
                    snapshot.as_ref().err().map(|error| error.to_string()),
                );
                match snapshot {
                    Ok(snapshot) => spawn_export_job(
                        id,
                        seconds,
                        output_path,
                        options,
                        snapshot,
                        Arc::clone(&export_jobs),
                        Arc::clone(&cancel_flags),
                        Arc::clone(&active_exports),
                        Arc::clone(&pinned_segments),
                        command_sender.clone(),
                        Arc::clone(&status),
                    ),
                    Err(error) => update_export_job(
                        &export_jobs,
                        id,
                        ExportJobState::Failed,
                        0,
                        Some(error.to_string()),
                    ),
                }
            }
            RecorderCommand::Flush(reply) => {
                let result = recorder.flush().map_err(|error| error.to_string());
                let error = result.as_ref().err().cloned();
                update_worker_status(
                    &status,
                    &recorder,
                    queued_chunks.load(Ordering::Relaxed),
                    active_exports.load(Ordering::Relaxed),
                    error,
                );
                let _ = reply.send(result);
            }
            RecorderCommand::Trim => {
                let pinned = pinned_file_set(&pinned_segments);
                let result = recorder.trim_expired_segments_except(&pinned);
                let error = result.err().map(|error| error.to_string());
                update_worker_status(
                    &status,
                    &recorder,
                    queued_chunks.load(Ordering::Relaxed),
                    active_exports.load(Ordering::Relaxed),
                    error,
                );
            }
            RecorderCommand::Stop => {
                let _ = recorder.flush();
                break;
            }
        }
    }

    stopped.store(true, Ordering::Relaxed);
    let mut status = status.lock().expect("status lock");
    status.running = false;
}

fn spawn_export_job(
    id: u64,
    seconds: u32,
    output_path: PathBuf,
    options: ExportOptions,
    snapshot: RecorderSnapshot,
    export_jobs: Arc<Mutex<Vec<ExportJobStatus>>>,
    cancel_flags: Arc<Mutex<HashMap<u64, Arc<AtomicBool>>>>,
    active_exports: Arc<AtomicUsize>,
    pinned_segments: Arc<Mutex<HashMap<String, usize>>>,
    command_sender: SyncSender<RecorderCommand>,
    status: Arc<Mutex<SharedWorkerStatus>>,
) {
    active_exports.fetch_add(1, Ordering::Relaxed);
    update_export_job(&export_jobs, id, ExportJobState::Running, 0, None);
    thread::spawn(move || {
        let pinned_file_names: Vec<String> = snapshot
            .segments
            .iter()
            .map(|segment| segment.file_name.clone())
            .collect();
        let cancel_flag = cancel_flags
            .lock()
            .expect("cancel flag lock")
            .get(&id)
            .cloned()
            .unwrap_or_else(|| Arc::new(AtomicBool::new(false)));
        let result =
            snapshot.save_latest_with_options(seconds, &output_path, &options, Some(&cancel_flag));
        let remaining_exports = active_exports
            .fetch_sub(1, Ordering::Relaxed)
            .saturating_sub(1);
        unpin_snapshot_segments(&pinned_segments, &pinned_file_names);
        cancel_flags.lock().expect("cancel flag lock").remove(&id);

        match result {
            Ok(samples) => {
                update_export_job(&export_jobs, id, ExportJobState::Finished, samples, None);
            }
            Err(EchoCoreError::ExportCanceled) => {
                let _ = fs::remove_file(&output_path);
                update_export_job(
                    &export_jobs,
                    id,
                    ExportJobState::Canceled,
                    0,
                    Some("canceled".to_string()),
                );
            }
            Err(error) => {
                let _ = fs::remove_file(&output_path);
                let message = error.to_string();
                update_export_job(
                    &export_jobs,
                    id,
                    ExportJobState::Failed,
                    0,
                    Some(message.clone()),
                );
                status.lock().expect("status lock").last_error = Some(message);
            }
        }
        status.lock().expect("status lock").active_exports = remaining_exports;
        prune_export_jobs(&export_jobs);
        let _ = command_sender.send(RecorderCommand::Trim);
    });
}

fn update_export_job(
    export_jobs: &Arc<Mutex<Vec<ExportJobStatus>>>,
    id: u64,
    state: ExportJobState,
    samples_written: u64,
    error: Option<String>,
) {
    if let Some(job) = export_jobs
        .lock()
        .expect("export job lock")
        .iter_mut()
        .find(|job| job.id == id)
    {
        job.state = state;
        job.samples_written = samples_written;
        job.error = error;
        if matches!(
            state,
            ExportJobState::Finished | ExportJobState::Failed | ExportJobState::Canceled
        ) {
            job.finished_unix_millis = Some(unix_millis_now());
        }
    }
    prune_export_jobs(export_jobs);
}

fn prune_export_jobs(export_jobs: &Arc<Mutex<Vec<ExportJobStatus>>>) {
    let mut jobs = export_jobs.lock().expect("export job lock");
    let mut finished: Vec<ExportJobStatus> = jobs
        .iter()
        .filter(|job| {
            matches!(
                job.state,
                ExportJobState::Finished | ExportJobState::Failed | ExportJobState::Canceled
            )
        })
        .cloned()
        .collect();
    finished.sort_by_key(|job| job.finished_unix_millis.unwrap_or(job.created_unix_millis));
    let keep_finished_ids: HashSet<u64> = finished
        .into_iter()
        .rev()
        .take(DEFAULT_EXPORT_JOB_HISTORY)
        .map(|job| job.id)
        .collect();
    jobs.retain(|job| {
        matches!(job.state, ExportJobState::Pending | ExportJobState::Running)
            || keep_finished_ids.contains(&job.id)
    });
}

fn pin_snapshot_segments(
    pinned_segments: &Arc<Mutex<HashMap<String, usize>>>,
    snapshot: &RecorderSnapshot,
) {
    let mut pinned = pinned_segments.lock().expect("pinned segment lock");
    for segment in &snapshot.segments {
        *pinned.entry(segment.file_name.clone()).or_insert(0) += 1;
    }
}

fn unpin_snapshot_segments(
    pinned_segments: &Arc<Mutex<HashMap<String, usize>>>,
    file_names: &[String],
) {
    let mut pinned = pinned_segments.lock().expect("pinned segment lock");
    for file_name in file_names {
        if let Some(count) = pinned.get_mut(file_name) {
            *count = count.saturating_sub(1);
            if *count == 0 {
                pinned.remove(file_name);
            }
        }
    }
}

fn pinned_file_set(pinned_segments: &Arc<Mutex<HashMap<String, usize>>>) -> HashSet<String> {
    pinned_segments
        .lock()
        .expect("pinned segment lock")
        .keys()
        .cloned()
        .collect()
}

fn update_worker_status(
    status: &Arc<Mutex<SharedWorkerStatus>>,
    recorder: &SegmentedRecorder,
    queued_chunks: usize,
    active_exports: usize,
    error: Option<String>,
) {
    let mut status = status.lock().expect("status lock");
    status.available_millis =
        samples_to_millis(recorder.available_samples(), recorder.config.audio);
    status.oldest_retained_millis =
        samples_to_millis(recorder.retained_start_sample(), recorder.config.audio);
    status.latest_sample_millis = samples_to_millis(
        recorder.manifest.total_samples_written,
        recorder.config.audio,
    );
    status.total_samples_written = recorder.manifest.total_samples_written;
    status.retained_start_sample = recorder.retained_start_sample();
    status.segment_count = recorder.manifest.segments.len();
    status.temp_bytes = recorder.temp_bytes();
    status.estimated_max_pcm_bytes = recorder.config.estimated_pcm_bytes();
    status.queued_chunks = queued_chunks;
    status.active_exports = active_exports;
    status.writer_last_flush_unix_millis = unix_millis_now();
    status.recovered = recorder.recovered;
    status.recovery_warning = recorder.recovery_warning.clone();
    if let Some(error) = error {
        status.last_error = Some(error);
    }
}

pub fn apply_gain_db(samples: &mut [i16], gain_db: f32) {
    let gain = 10.0_f32.powf(gain_db / 20.0);
    for sample in samples {
        let amplified = *sample as f32 * gain;
        *sample = amplified.clamp(i16::MIN as f32, i16::MAX as f32) as i16;
    }
}

pub fn generate_demo_audio(config: AudioConfig, seconds: f32) -> Vec<i16> {
    let frames = (config.sample_rate as f32 * seconds).round() as usize;
    let channels = config.channels as usize;
    let mut samples = Vec::with_capacity(frames * channels);

    for frame in 0..frames {
        let t = frame as f32 / config.sample_rate as f32;
        let tone = (t * 440.0 * 2.0 * PI).sin() * 0.25;
        let slow_pulse = (t * 3.0 * 2.0 * PI).sin().max(0.0) * 0.35;
        let value = ((tone + slow_pulse) * i16::MAX as f32).clamp(i16::MIN as f32, i16::MAX as f32);
        for _ in 0..channels {
            samples.push(value as i16);
        }
    }

    samples
}

pub fn write_wav_i16<P: AsRef<Path>>(
    path: P,
    config: AudioConfig,
    samples: &[i16],
) -> io::Result<()> {
    let mut file = BufWriter::new(File::create(path)?);
    write_wav_header(&mut file, config, samples.len() as u32)?;

    write_i16le_samples(&mut file, samples)?;
    file.flush()
}

fn write_wav_header(
    file: &mut impl Write,
    config: AudioConfig,
    sample_count: u32,
) -> io::Result<()> {
    let data_size = sample_count * 2;
    let byte_rate = config.sample_rate * config.channels as u32 * 2;
    let block_align = config.channels * 2;

    file.write_all(b"RIFF")?;
    file.write_all(&(36 + data_size).to_le_bytes())?;
    file.write_all(b"WAVE")?;
    file.write_all(b"fmt ")?;
    file.write_all(&16_u32.to_le_bytes())?;
    file.write_all(&1_u16.to_le_bytes())?;
    file.write_all(&config.channels.to_le_bytes())?;
    file.write_all(&config.sample_rate.to_le_bytes())?;
    file.write_all(&byte_rate.to_le_bytes())?;
    file.write_all(&block_align.to_le_bytes())?;
    file.write_all(&16_u16.to_le_bytes())?;
    file.write_all(b"data")?;
    file.write_all(&data_size.to_le_bytes())?;
    Ok(())
}

fn write_i16le_samples(output: &mut impl Write, samples: &[i16]) -> io::Result<()> {
    let mut bytes = Vec::with_capacity(samples.len() * 2);
    for sample in samples {
        bytes.extend_from_slice(&sample.to_le_bytes());
    }
    output.write_all(&bytes)
}

fn copy_segment_samples_from(
    session_dir: &Path,
    segment: &SegmentInfo,
    start: u64,
    count: u64,
    output: &mut impl Write,
    cancel_flag: Option<&AtomicBool>,
) -> Result<(), EchoCoreError> {
    let mut input = BufReader::new(File::open(session_dir.join(&segment.file_name))?);
    input.seek(SeekFrom::Start(start * 2))?;
    copy_exact_bytes(&mut input, output, count * 2, cancel_flag)?;
    Ok(())
}

fn copy_exact_bytes(
    input: &mut impl Read,
    output: &mut impl Write,
    mut remaining: u64,
    cancel_flag: Option<&AtomicBool>,
) -> Result<(), EchoCoreError> {
    let mut buffer = [0_u8; 8192];
    while remaining > 0 {
        check_canceled(cancel_flag)?;
        let read_len = remaining.min(buffer.len() as u64) as usize;
        input.read_exact(&mut buffer[..read_len])?;
        output.write_all(&buffer[..read_len])?;
        remaining -= read_len as u64;
    }
    Ok(())
}

fn check_canceled(cancel_flag: Option<&AtomicBool>) -> Result<(), EchoCoreError> {
    if cancel_flag
        .map(|flag| flag.load(Ordering::Relaxed))
        .unwrap_or(false)
    {
        return Err(EchoCoreError::ExportCanceled);
    }
    Ok(())
}

fn sanitize_mp3_bitrate(value: u32) -> u32 {
    match value {
        32 | 48 | 64 | 96 | 128 | 160 | 192 | 256 | 320 => value,
        0..=31 => 32,
        33..=47 => 48,
        49..=63 => 64,
        65..=95 => 96,
        97..=159 => 128,
        161..=191 => 160,
        193..=255 => 192,
        257..=319 => 256,
        _ => 320,
    }
}

fn new_session_id() -> String {
    format!("session-{}", unix_millis_now())
}

fn unix_millis_now() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis())
        .unwrap_or(0)
}

fn samples_to_millis(samples: u64, config: AudioConfig) -> u64 {
    if config.sample_rate == 0 || config.channels == 0 {
        return 0;
    }
    samples * 1_000 / config.sample_rate as u64 / config.channels as u64
}

fn latest_session_dir(temp_root: &Path) -> Result<Option<PathBuf>, EchoCoreError> {
    let mut latest: Option<(SystemTime, PathBuf)> = None;
    for entry in fs::read_dir(temp_root)? {
        let entry = entry?;
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }
        let modified = entry
            .metadata()
            .and_then(|metadata| metadata.modified())
            .unwrap_or(UNIX_EPOCH);
        match &latest {
            Some((latest_modified, _)) if modified <= *latest_modified => {}
            _ => latest = Some((modified, path)),
        }
    }
    Ok(latest.map(|(_, path)| path))
}

fn cleanup_stale_sessions(temp_root: &Path, active_session: &Path) -> Result<(), EchoCoreError> {
    for entry in fs::read_dir(temp_root)? {
        let entry = entry?;
        let path = entry.path();
        if path.is_dir() && path != active_session {
            match fs::remove_dir_all(path) {
                Ok(()) => {}
                Err(error) if error.kind() == io::ErrorKind::NotFound => {}
                Err(error) => return Err(EchoCoreError::Io(error)),
            }
        }
    }
    Ok(())
}

fn recover_untracked_pcm_segments(
    session_dir: &Path,
    retained_files: &HashSet<String>,
    retained_segments: &mut Vec<SegmentInfo>,
    recovery_warnings: &mut Vec<String>,
) -> Result<(), EchoCoreError> {
    for entry in fs::read_dir(session_dir)? {
        let entry = entry?;
        let path = entry.path();
        if path.extension().and_then(|value| value.to_str()) != Some("pcm") {
            continue;
        }
        let Some(file_name) = path
            .file_name()
            .and_then(|value| value.to_str())
            .map(|value| value.to_string())
        else {
            continue;
        };
        if retained_files.contains(&file_name) {
            continue;
        }
        let Some(index) = segment_index_from_name(&file_name) else {
            recovery_warnings.push(format!("untracked_pcm_ignored:{file_name}"));
            continue;
        };
        let sample_count = fs::metadata(&path)?.len() / 2;
        if sample_count == 0 {
            recovery_warnings.push(format!("empty_untracked_segment_skipped:{file_name}"));
            continue;
        }
        recovery_warnings.push(format!("recovered_untracked_segment:{file_name}"));
        retained_segments.push(SegmentInfo {
            index,
            file_name,
            start_sample: 0,
            sample_count,
            complete: true,
        });
    }
    Ok(())
}

fn reconstruct_manifest_from_pcm(
    config: &CoreConfig,
    session_dir: &Path,
) -> Result<RecorderManifest, EchoCoreError> {
    let session_id = session_dir
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or("session-recovered")
        .to_string();
    let mut pcm_files = Vec::new();
    for entry in fs::read_dir(session_dir)? {
        let entry = entry?;
        let path = entry.path();
        if path.extension().and_then(|value| value.to_str()) != Some("pcm") {
            continue;
        }
        let Some(file_name) = path
            .file_name()
            .and_then(|value| value.to_str())
            .map(|value| value.to_string())
        else {
            continue;
        };
        let index = segment_index_from_name(&file_name).unwrap_or(pcm_files.len() as u64);
        pcm_files.push((index, file_name, path));
    }
    pcm_files.sort_by_key(|(index, _, _)| *index);

    let mut manifest = RecorderManifest::new(config, session_id);
    let mut next_start = 0_u64;
    for (index, file_name, path) in pcm_files {
        let sample_count = fs::metadata(path)?.len() / 2;
        if sample_count == 0 {
            continue;
        }
        manifest.segments.push(SegmentInfo {
            index,
            file_name,
            start_sample: next_start,
            sample_count,
            complete: true,
        });
        next_start += sample_count;
    }
    manifest.total_samples_written = next_start;
    Ok(manifest)
}

fn segment_index_from_name(file_name: &str) -> Option<u64> {
    file_name
        .strip_prefix("segment-")
        .and_then(|value| value.strip_suffix(".pcm"))
        .and_then(|value| value.parse().ok())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn latest_returns_most_recent_samples() {
        let config = AudioConfig {
            sample_rate: 10,
            channels: 1,
        };
        let mut buffer = RingBuffer::new(config, 1.0);
        buffer.push_samples(&[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);

        let clip = buffer.latest(0.5);

        assert_eq!(clip.samples, vec![8, 9, 10, 11, 12]);
    }

    #[test]
    fn gain_is_clamped() {
        let mut samples = vec![20_000, -20_000];
        apply_gain_db(&mut samples, 12.0);

        assert_eq!(samples, vec![i16::MAX, i16::MIN]);
    }

    #[test]
    fn capture_plan_uses_external_pcm_on_android() {
        let plan = CapturePlan::for_platform(EchoPlatform::Android);

        assert_eq!(plan.route, CaptureRoute::ExternalPcm);
    }

    #[test]
    fn segmented_recorder_splits_segments() {
        let work_dir = test_dir("split");
        let config = test_config(&work_dir, 2, 10);
        let mut recorder = SegmentedRecorder::start(config).unwrap();

        recorder.push_samples(&[1, 2, 3, 4, 5]).unwrap();

        let segments = &recorder.manifest().segments;
        assert_eq!(segments.len(), 3);
        assert_eq!(segments[0].sample_count, 2);
        assert!(segments[0].complete);
        assert_eq!(segments[1].sample_count, 2);
        assert!(segments[1].complete);
        assert_eq!(segments[2].sample_count, 1);
        assert!(!segments[2].complete);

        let _ = fs::remove_dir_all(work_dir);
    }

    #[test]
    fn recovery_keeps_manifested_incomplete_segment() {
        let work_dir = test_dir("recover-incomplete");
        let config = test_config(&work_dir, 2, 10);
        let mut recorder = SegmentedRecorder::start(config.clone()).unwrap();

        recorder.push_samples(&[1]).unwrap();
        recorder.persist_manifest_now().unwrap();
        drop(recorder);

        let mut recovered = SegmentedRecorder::recover_latest_or_start(config).unwrap();
        assert!(
            recovered
                .recovery_warning
                .as_deref()
                .unwrap_or("")
                .contains("recovered_incomplete_segment")
        );
        assert_eq!(recovered.manifest().segments.len(), 1);
        assert_eq!(recovered.manifest().segments[0].sample_count, 1);

        recovered.push_samples(&[2]).unwrap();
        assert_eq!(recovered.available_samples(), 2);

        let _ = fs::remove_dir_all(work_dir);
    }

    #[test]
    fn recovery_keeps_untracked_debounced_segment_and_avoids_name_collision() {
        let work_dir = test_dir("recover-untracked");
        let config = test_config(&work_dir, 2, 10);
        let mut recorder = SegmentedRecorder::start(config.clone()).unwrap();

        recorder.push_samples(&[1, 2]).unwrap();
        let session_dir = recorder.session_dir().to_path_buf();
        drop(recorder);
        fs::write(session_dir.join("segment-000001.pcm"), 3_i16.to_le_bytes()).unwrap();

        let mut recovered = SegmentedRecorder::recover_latest_or_start(config).unwrap();
        assert!(
            recovered
                .recovery_warning
                .as_deref()
                .unwrap_or("")
                .contains("recovered_untracked_segment:segment-000001.pcm")
        );
        assert_eq!(recovered.manifest().segments.len(), 2);
        assert_eq!(recovered.available_samples(), 3);

        recovered.push_samples(&[4]).unwrap();
        assert_eq!(recovered.available_samples(), 4);
        assert!(recovered.session_dir().join("segment-000002.pcm").exists());

        let _ = fs::remove_dir_all(work_dir);
    }

    #[test]
    fn segmented_recorder_trims_old_segments() {
        let work_dir = test_dir("trim");
        let config = test_config(&work_dir, 2, 4);
        let mut recorder = SegmentedRecorder::start(config).unwrap();

        recorder.push_samples(&[1, 2, 3, 4, 5, 6, 7]).unwrap();

        let segments = &recorder.manifest().segments;
        assert_eq!(recorder.available_samples(), 4);
        assert_eq!(segments.first().unwrap().start_sample, 2);
        assert!(!recorder.session_dir().join("segment-000000.pcm").exists());
        assert!(recorder.session_dir().join("segment-000001.pcm").exists());

        let _ = fs::remove_dir_all(work_dir);
    }

    #[test]
    fn save_latest_wav_spans_segments() {
        let work_dir = test_dir("save");
        let config = test_config(&work_dir, 2, 10);
        let mut recorder = SegmentedRecorder::start(config).unwrap();

        recorder.push_samples(&[1, 2, 3, 4, 5, 6]).unwrap();
        let output = work_dir.join("latest.wav");
        let written = recorder.save_latest_wav(4, &output).unwrap();

        assert_eq!(written, 4);
        assert_eq!(read_wav_samples(&output), vec![3, 4, 5, 6]);

        let _ = fs::remove_dir_all(work_dir);
    }

    #[test]
    fn manifest_is_written_as_json() {
        let work_dir = test_dir("manifest");
        let config = test_config(&work_dir, 2, 10);
        let mut recorder = SegmentedRecorder::start(config).unwrap();

        recorder.push_samples(&[1, 2, 3]).unwrap();

        let manifest = fs::read_to_string(recorder.session_dir().join("manifest.json")).unwrap();
        assert!(manifest.contains("\"format_version\": 1"));
        assert!(manifest.contains("\"sample_format\": \"i16le\""));
        assert!(manifest.contains("\"segment-000000.pcm\""));

        let _ = fs::remove_dir_all(work_dir);
    }

    fn test_config(work_dir: &Path, segment_seconds: u32, max_replay_seconds: u32) -> CoreConfig {
        CoreConfig {
            audio: AudioConfig {
                sample_rate: 1,
                channels: 1,
            },
            segment_seconds,
            max_replay_seconds,
            work_dir: work_dir.to_path_buf(),
        }
    }

    fn test_dir(name: &str) -> PathBuf {
        let path = std::env::temp_dir().join(format!("echoclip-core-{name}-{}", unix_millis_now()));
        let _ = fs::remove_dir_all(&path);
        path
    }

    fn read_wav_samples(path: &Path) -> Vec<i16> {
        let bytes = fs::read(path).unwrap();
        bytes[44..]
            .chunks_exact(2)
            .map(|chunk| i16::from_le_bytes([chunk[0], chunk[1]]))
            .collect()
    }
}
