use std::collections::{HashMap, VecDeque};
use std::ffi::{CStr, CString, c_char};
use std::path::PathBuf;
use std::ptr;
use std::slice;
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering};
use std::sync::mpsc;
use std::sync::{Arc, Mutex, OnceLock, RwLock};
use std::thread;
use std::time::{Duration, Instant};

#[cfg(target_os = "windows")]
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
#[cfg(target_os = "windows")]
use cpal::{FromSample, Sample};
use echoclip_core::{
    AudioConfig, CoreConfig, DEFAULT_SEGMENT_SECONDS, EchoCoreError, ExportJobState, ExportOptions,
    RecorderWorker,
};

pub const EC_OK: i32 = 0;
pub const EC_ERROR_INVALID_ARGUMENT: i32 = 1;
pub const EC_ERROR_CORE: i32 = 2;
pub const EC_ERROR_QUEUE_FULL: i32 = 3;
pub const EC_ERROR_STOPPED: i32 = 4;
pub const EC_ERROR_PANIC: i32 = 5;

const EMPTY_C_STRING: &[u8] = b"\0";
const MIX_INTERVAL: Duration = Duration::from_millis(10);
const MIX_PREBUFFER: Duration = Duration::from_millis(40);
const MIX_MAX_BUFFER_MILLIS: usize = 500;

#[derive(Clone, Debug, PartialEq, Eq)]
struct CaptureSelection {
    microphone_enabled: bool,
    system_audio_enabled: bool,
    microphone_device_id: Option<String>,
}

impl Default for CaptureSelection {
    fn default() -> Self {
        Self {
            microphone_enabled: true,
            system_audio_enabled: false,
            microphone_device_id: None,
        }
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
struct SourceRuntimeInfo {
    id: String,
    name: String,
    sample_rate: u32,
    channels: u32,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
struct CaptureRuntimeInfo {
    microphone: Option<SourceRuntimeInfo>,
    system_audio: Option<SourceRuntimeInfo>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum CaptureSource {
    Microphone,
    SystemAudio,
}

#[derive(Debug)]
struct SourceQueue {
    max_buffer_frames: usize,
    high_water_frames: usize,
    samples: VecDeque<i16>,
}

impl SourceQueue {
    fn new(max_buffer_frames: usize, high_water_frames: usize) -> Self {
        Self {
            max_buffer_frames,
            high_water_frames,
            samples: VecDeque::new(),
        }
    }

    fn enqueue(&mut self, samples: &[i16]) -> usize {
        self.samples.extend(samples.iter().copied());
        let dropped = self.samples.len().saturating_sub(self.max_buffer_frames);
        if dropped != 0 {
            self.samples.drain(..dropped);
        }
        dropped
    }

    fn take_for_timeline(&mut self, frame_count: usize) -> (Vec<i16>, usize, usize) {
        // Independent device clocks can differ by a few ppm. The wall-clock
        // output is authoritative; when a faster source grows beyond the
        // prebuffer plus 20 ms, consume one extra oldest frame per tick. A
        // slower source is corrected by the normal underrun-to-silence path.
        let drift_dropped = usize::from(self.samples.len() > self.high_water_frames);
        if drift_dropped != 0 {
            self.samples.pop_front();
        }
        let mut missing = 0;
        let output = (0..frame_count)
            .map(|_| {
                self.samples.pop_front().unwrap_or_else(|| {
                    missing += 1;
                    0
                })
            })
            .collect();
        (output, missing, drift_dropped)
    }
}

#[derive(Debug)]
struct AudioTimeline {
    microphone_enabled: bool,
    system_audio_enabled: bool,
    microphone: Mutex<SourceQueue>,
    system_audio: Mutex<SourceQueue>,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
struct TimelineResult {
    microphone_missing: usize,
    system_audio_missing: usize,
    microphone_drift_dropped: usize,
    system_audio_drift_dropped: usize,
}

impl AudioTimeline {
    fn new(selection: &CaptureSelection, sample_rate: u32) -> Self {
        let max_buffer_frames = ((sample_rate as usize) * MIX_MAX_BUFFER_MILLIS / 1_000).max(1);
        let high_water_frames =
            ((sample_rate as usize) * (MIX_PREBUFFER.as_millis() as usize + 20) / 1_000).max(1);
        Self {
            microphone_enabled: selection.microphone_enabled,
            system_audio_enabled: selection.system_audio_enabled,
            microphone: Mutex::new(SourceQueue::new(max_buffer_frames, high_water_frames)),
            system_audio: Mutex::new(SourceQueue::new(max_buffer_frames, high_water_frames)),
        }
    }

    /// Adds source frames without ever taking the other source's lock. Returns
    /// the number of oldest frames discarded to keep latency and memory bounded.
    fn enqueue(&self, source: CaptureSource, samples: &[i16]) -> usize {
        match source {
            CaptureSource::Microphone => lock_mutex(&self.microphone).enqueue(samples),
            CaptureSource::SystemAudio => lock_mutex(&self.system_audio).enqueue(samples),
        }
    }

    /// Produces one fixed-time-axis chunk. A source that has not delivered
    /// enough frames contributes silence; dual-source capture gives each source
    /// 6 dB of headroom so two full-scale inputs do not hard-clip.
    fn mix(&self, frame_count: usize) -> (Vec<i16>, TimelineResult) {
        let (microphone, microphone_missing, microphone_drift_dropped) = if self.microphone_enabled
        {
            lock_mutex(&self.microphone).take_for_timeline(frame_count)
        } else {
            (vec![0; frame_count], 0, 0)
        };
        let (system_audio, system_audio_missing, system_audio_drift_dropped) =
            if self.system_audio_enabled {
                lock_mutex(&self.system_audio).take_for_timeline(frame_count)
            } else {
                (vec![0; frame_count], 0, 0)
            };
        let result = TimelineResult {
            microphone_missing,
            system_audio_missing,
            microphone_drift_dropped,
            system_audio_drift_dropped,
        };
        let output = microphone
            .into_iter()
            .zip(system_audio)
            .map(|(microphone, system_audio)| {
                if self.microphone_enabled && self.system_audio_enabled {
                    ((i32::from(microphone) + i32::from(system_audio)) / 2) as i16
                } else if self.microphone_enabled {
                    microphone
                } else {
                    system_audio
                }
            })
            .collect();
        (output, result)
    }
}

#[derive(Debug)]
struct FrameClock {
    sample_rate: u32,
    fractional: u32,
}

impl FrameClock {
    fn new(sample_rate: u32) -> Self {
        Self {
            sample_rate,
            fractional: 0,
        }
    }

    fn frames_for_ticks(&mut self, ticks: u32) -> usize {
        // One tick is 10 ms, or 1/100 second. Carry the remainder so unusual
        // recorder rates still produce exactly sample_rate frames per second.
        let scaled = u64::from(self.sample_rate) * u64::from(ticks) + u64::from(self.fractional);
        self.fractional = (scaled % 100) as u32;
        (scaled / 100) as usize
    }
}

#[derive(Debug)]
struct FfiError {
    code: i32,
    message: String,
}

impl FfiError {
    fn invalid(message: impl Into<String>) -> Self {
        Self {
            code: EC_ERROR_INVALID_ARGUMENT,
            message: message.into(),
        }
    }

    fn core(error: impl std::fmt::Display) -> Self {
        Self {
            code: EC_ERROR_CORE,
            message: error.to_string(),
        }
    }
}

impl From<EchoCoreError> for FfiError {
    fn from(error: EchoCoreError) -> Self {
        let code = match error {
            EchoCoreError::QueueFull { .. } => EC_ERROR_QUEUE_FULL,
            EchoCoreError::QueueClosed | EchoCoreError::WorkerStopped => EC_ERROR_STOPPED,
            _ => EC_ERROR_CORE,
        };
        Self {
            code,
            message: error.to_string(),
        }
    }
}

struct RecorderHandle {
    config: CoreConfig,
    worker: RwLock<Option<RecorderWorker>>,
    capture: Mutex<Option<CaptureThread>>,
    capture_selection: Mutex<CaptureSelection>,
    capture_runtime: Mutex<CaptureRuntimeInfo>,
    capture_running: AtomicBool,
    capture_sample_rate: AtomicU32,
    capture_channels: AtomicU32,
    capture_device: Mutex<Option<String>>,
    input_level_rms_bits: AtomicU32,
    input_peak_bits: AtomicU32,
    microphone_level_rms_bits: AtomicU32,
    microphone_peak_bits: AtomicU32,
    system_audio_level_rms_bits: AtomicU32,
    system_audio_peak_bits: AtomicU32,
    microphone_dropped_samples: AtomicU64,
    system_audio_dropped_samples: AtomicU64,
    microphone_silence_filled_samples: AtomicU64,
    system_audio_silence_filled_samples: AtomicU64,
    capture_error: Mutex<Option<String>>,
    last_error: Mutex<CString>,
}

struct CaptureThread {
    stop_sender: mpsc::Sender<()>,
    join_handle: thread::JoinHandle<()>,
}

impl RecorderHandle {
    fn new(config: CoreConfig, worker: RecorderWorker) -> Self {
        Self {
            config,
            worker: RwLock::new(Some(worker)),
            capture: Mutex::new(None),
            capture_selection: Mutex::new(CaptureSelection::default()),
            capture_runtime: Mutex::new(CaptureRuntimeInfo::default()),
            capture_running: AtomicBool::new(false),
            capture_sample_rate: AtomicU32::new(0),
            capture_channels: AtomicU32::new(0),
            capture_device: Mutex::new(None),
            input_level_rms_bits: AtomicU32::new(0_f32.to_bits()),
            input_peak_bits: AtomicU32::new(0_f32.to_bits()),
            microphone_level_rms_bits: AtomicU32::new(0_f32.to_bits()),
            microphone_peak_bits: AtomicU32::new(0_f32.to_bits()),
            system_audio_level_rms_bits: AtomicU32::new(0_f32.to_bits()),
            system_audio_peak_bits: AtomicU32::new(0_f32.to_bits()),
            microphone_dropped_samples: AtomicU64::new(0),
            system_audio_dropped_samples: AtomicU64::new(0),
            microphone_silence_filled_samples: AtomicU64::new(0),
            system_audio_silence_filled_samples: AtomicU64::new(0),
            capture_error: Mutex::new(None),
            last_error: Mutex::new(empty_c_string()),
        }
    }

    fn set_error(&self, message: &str) {
        *lock_mutex(&self.last_error) = make_c_string(message);
    }

    fn clear_error(&self) {
        *lock_mutex(&self.last_error) = empty_c_string();
    }

    fn error_ptr(&self) -> *const c_char {
        lock_mutex(&self.last_error).as_ptr()
    }

    fn set_capture_error(&self, message: impl Into<String>) {
        *lock_mutex(&self.capture_error) = Some(message.into());
    }

    fn clear_capture_error(&self) {
        *lock_mutex(&self.capture_error) = None;
    }

    fn reset_capture_metrics(&self) {
        self.input_level_rms_bits
            .store(0_f32.to_bits(), Ordering::Relaxed);
        self.input_peak_bits
            .store(0_f32.to_bits(), Ordering::Relaxed);
        self.microphone_level_rms_bits
            .store(0_f32.to_bits(), Ordering::Relaxed);
        self.microphone_peak_bits
            .store(0_f32.to_bits(), Ordering::Relaxed);
        self.system_audio_level_rms_bits
            .store(0_f32.to_bits(), Ordering::Relaxed);
        self.system_audio_peak_bits
            .store(0_f32.to_bits(), Ordering::Relaxed);
        self.microphone_dropped_samples.store(0, Ordering::Relaxed);
        self.system_audio_dropped_samples
            .store(0, Ordering::Relaxed);
        self.microphone_silence_filled_samples
            .store(0, Ordering::Relaxed);
        self.system_audio_silence_filled_samples
            .store(0, Ordering::Relaxed);
    }
}

fn registry() -> &'static Mutex<HashMap<u64, Arc<RecorderHandle>>> {
    static REGISTRY: OnceLock<Mutex<HashMap<u64, Arc<RecorderHandle>>>> = OnceLock::new();
    REGISTRY.get_or_init(|| Mutex::new(HashMap::new()))
}

fn global_error() -> &'static Mutex<CString> {
    static GLOBAL_ERROR: OnceLock<Mutex<CString>> = OnceLock::new();
    GLOBAL_ERROR.get_or_init(|| Mutex::new(empty_c_string()))
}

static NEXT_HANDLE: AtomicU64 = AtomicU64::new(1);

#[unsafe(no_mangle)]
pub extern "C" fn ec_create(
    work_dir_utf8: *const c_char,
    sample_rate: u32,
    buffer_seconds: u32,
) -> u64 {
    match std::panic::catch_unwind(|| create_impl(work_dir_utf8, sample_rate, buffer_seconds)) {
        Ok(Ok(handle)) => {
            set_global_error("");
            handle
        }
        Ok(Err(error)) => {
            set_global_error(&error.message);
            0
        }
        Err(_) => {
            set_global_error("panic in ec_create");
            0
        }
    }
}

fn create_impl(
    work_dir_utf8: *const c_char,
    sample_rate: u32,
    buffer_seconds: u32,
) -> Result<u64, FfiError> {
    if sample_rate == 0 {
        return Err(FfiError::invalid("sample_rate must be non-zero"));
    }
    if buffer_seconds == 0 {
        return Err(FfiError::invalid("buffer_seconds must be non-zero"));
    }
    let work_dir = utf8_path(work_dir_utf8, "work_dir_utf8")?;
    if work_dir.as_os_str().is_empty() {
        return Err(FfiError::invalid("work_dir_utf8 must not be empty"));
    }

    let mut config = CoreConfig::new(work_dir);
    config.audio = AudioConfig {
        sample_rate,
        channels: 1,
    };
    config.segment_seconds = DEFAULT_SEGMENT_SECONDS;
    config.max_replay_seconds = buffer_seconds;
    let worker = RecorderWorker::start(config.clone()).map_err(FfiError::from)?;
    let handle = Arc::new(RecorderHandle::new(config, worker));

    let mut entries = lock_mutex(registry());
    loop {
        let id = NEXT_HANDLE.fetch_add(1, Ordering::Relaxed);
        if id != 0 && !entries.contains_key(&id) {
            entries.insert(id, handle);
            return Ok(id);
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn ec_destroy(handle: u64) {
    let result = std::panic::catch_unwind(|| destroy_impl(handle));
    match result {
        Ok(Ok(())) => set_global_error(""),
        Ok(Err(error)) => set_global_error(&error.message),
        Err(_) => set_global_error("panic in ec_destroy"),
    }
}

fn destroy_impl(handle: u64) -> Result<(), FfiError> {
    if handle == 0 {
        return Err(FfiError::invalid("invalid handle: 0"));
    }
    let recorder = lock_mutex(registry())
        .remove(&handle)
        .ok_or_else(|| FfiError::invalid(format!("invalid handle: {handle}")))?;
    stop_capture_thread(&recorder)?;
    let mut worker = write_lock(&recorder.worker);
    if let Some(mut worker) = worker.take() {
        worker.stop();
    }
    Ok(())
}

#[unsafe(no_mangle)]
pub extern "C" fn ec_audio_devices_json(output_utf8: *mut c_char, output_capacity: usize) -> usize {
    match std::panic::catch_unwind(|| audio_devices_json_impl(output_utf8, output_capacity)) {
        Ok(Ok(required)) => {
            set_global_error("");
            required
        }
        Ok(Err(error)) => {
            set_global_error(&error.message);
            0
        }
        Err(_) => {
            set_global_error("panic in ec_audio_devices_json");
            0
        }
    }
}

fn audio_devices_json_impl(
    output_utf8: *mut c_char,
    output_capacity: usize,
) -> Result<usize, FfiError> {
    #[cfg(not(target_os = "windows"))]
    let json = "[]".to_string();

    #[cfg(target_os = "windows")]
    let json = {
        let host = cpal::default_host();
        let default_id = host
            .default_input_device()
            .and_then(|device| device.id().ok())
            .map(|id| id.to_string());
        let devices = host.input_devices().map_err(|error| {
            FfiError::core(format!("failed to enumerate input devices: {error}"))
        })?;
        let mut entries = Vec::new();
        for device in devices {
            let Ok(id) = device.id() else {
                continue;
            };
            let id = id.to_string();
            let name = device
                .description()
                .map(|description| description.name().to_string())
                .unwrap_or_else(|_| device.to_string());
            entries.push(serde_json::json!({
                "id": id,
                "name": name,
                "isDefault": default_id.as_deref() == Some(id.as_str()),
            }));
        }
        entries.sort_by(|left, right| {
            let left_default = left["isDefault"].as_bool().unwrap_or(false);
            let right_default = right["isDefault"].as_bool().unwrap_or(false);
            right_default.cmp(&left_default).then_with(|| {
                left["name"]
                    .as_str()
                    .unwrap_or_default()
                    .to_lowercase()
                    .cmp(&right["name"].as_str().unwrap_or_default().to_lowercase())
            })
        });
        serde_json::to_string(&entries).map_err(FfiError::core)?
    };

    copy_utf8_result(&json, output_utf8, output_capacity)
}

#[unsafe(no_mangle)]
/// Configures native capture sources and the selected microphone.
///
/// A null or empty `microphone_device_id_utf8` selects the current Windows
/// default input device. If capture is active it is restarted on the new
/// sources, keeping configuration and capture lifecycle inside Rust.
///
/// # Safety
///
/// A non-null `microphone_device_id_utf8` must point to a valid NUL-terminated
/// UTF-8 string for the duration of this call.
pub unsafe extern "C" fn ec_configure_capture(
    handle: u64,
    microphone_enabled: i32,
    system_audio_enabled: i32,
    microphone_device_id_utf8: *const c_char,
) -> i32 {
    ffi_result(handle, || {
        let microphone_enabled = ffi_bool(microphone_enabled, "microphone_enabled")?;
        let system_audio_enabled = ffi_bool(system_audio_enabled, "system_audio_enabled")?;
        if !microphone_enabled && !system_audio_enabled {
            return Err(FfiError::invalid(
                "at least one capture source must be enabled",
            ));
        }
        let microphone_device_id =
            unsafe { optional_utf8(microphone_device_id_utf8, "microphone_device_id_utf8")? };
        let selection = CaptureSelection {
            microphone_enabled,
            system_audio_enabled,
            microphone_device_id,
        };
        let recorder = get_handle(handle)?;

        #[cfg(not(target_os = "windows"))]
        {
            let _ = (recorder, selection);
            return Err(FfiError::core(
                "native audio capture is only available on Windows",
            ));
        }

        #[cfg(target_os = "windows")]
        {
            validate_capture_selection(&selection)?;
            let was_started = lock_mutex(&recorder.capture).is_some();
            if *lock_mutex(&recorder.capture_selection) == selection {
                recorder.clear_error();
                return Ok(());
            }
            if was_started {
                stop_capture_thread(&recorder)?;
            }
            *lock_mutex(&recorder.capture_selection) = selection;
            if was_started {
                start_capture_for_recorder(&recorder)?;
            }
            recorder.clear_error();
            Ok(())
        }
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn ec_start_capture(handle: u64) -> i32 {
    ffi_result(handle, || start_capture_impl(handle))
}

fn start_capture_impl(handle: u64) -> Result<(), FfiError> {
    let recorder = get_handle(handle)?;

    #[cfg(not(target_os = "windows"))]
    {
        let _ = recorder;
        return Err(FfiError::core(
            "native microphone capture is only available on Windows",
        ));
    }

    #[cfg(target_os = "windows")]
    {
        start_capture_for_recorder(&recorder)
    }
}

#[cfg(target_os = "windows")]
fn start_capture_for_recorder(recorder: &Arc<RecorderHandle>) -> Result<(), FfiError> {
    let mut capture_slot = lock_mutex(&recorder.capture);
    if capture_slot.is_some() && recorder.capture_running.load(Ordering::Acquire) {
        recorder.clear_error();
        return Ok(());
    }
    if let Some(capture) = capture_slot.take() {
        stop_join_capture(recorder, capture)?;
    }

    recorder.clear_capture_error();
    recorder.reset_capture_metrics();
    let (stop_sender, stop_receiver) = mpsc::channel();
    let (init_sender, init_receiver) = mpsc::channel();
    let capture_recorder = Arc::clone(recorder);
    let join_handle = thread::Builder::new()
        .name("echoclip-wasapi-capture".to_string())
        .spawn(move || {
            capture_thread_main(capture_recorder, stop_receiver, init_sender);
        })
        .map_err(FfiError::core)?;

    match init_receiver.recv() {
        Ok(Ok(())) => {
            *capture_slot = Some(CaptureThread {
                stop_sender,
                join_handle,
            });
            recorder.clear_error();
            Ok(())
        }
        Ok(Err(message)) => {
            let _ = join_handle.join();
            recorder.set_capture_error(message.clone());
            Err(FfiError::core(message))
        }
        Err(error) => {
            let _ = join_handle.join();
            let message = format!("capture initialization channel closed: {error}");
            recorder.set_capture_error(message.clone());
            Err(FfiError::core(message))
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn ec_stop_capture(handle: u64) -> i32 {
    ffi_result(handle, || {
        let recorder = get_handle(handle)?;
        stop_capture_thread(&recorder)?;
        recorder.clear_capture_error();
        recorder.clear_error();
        Ok(())
    })
}

#[unsafe(no_mangle)]
/// Pushes test PCM directly into the recorder worker.
///
/// # Safety
///
/// When `sample_count` is non-zero, `samples` must point to at least
/// `sample_count` initialized `i16` values and remain valid for this call.
pub unsafe extern "C" fn ec_push_pcm(handle: u64, samples: *const i16, sample_count: usize) -> i32 {
    ffi_result(handle, || {
        let recorder = get_handle(handle)?;
        if sample_count == 0 {
            recorder.clear_error();
            return Ok(());
        }
        if samples.is_null() {
            return Err(FfiError::invalid(
                "samples must not be null when sample_count is non-zero",
            ));
        }
        let samples = unsafe { slice::from_raw_parts(samples, sample_count) };
        let worker = read_lock(&recorder.worker);
        let worker = worker
            .as_ref()
            .ok_or_else(|| stopped_error("recorder worker is stopped"))?;
        worker.push_samples(samples).map_err(FfiError::from)?;
        recorder.clear_error();
        Ok(())
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn ec_available_millis(handle: u64) -> u64 {
    match std::panic::catch_unwind(|| available_millis_impl(handle)) {
        Ok(Ok(value)) => value,
        Ok(Err(error)) => {
            record_error(handle, &error.message);
            0
        }
        Err(_) => {
            record_error(handle, "panic in ec_available_millis");
            0
        }
    }
}

fn available_millis_impl(handle: u64) -> Result<u64, FfiError> {
    let recorder = get_handle(handle)?;
    let worker = read_lock(&recorder.worker);
    let worker = worker
        .as_ref()
        .ok_or_else(|| stopped_error("recorder worker is stopped"))?;
    let available = worker.status().available_millis;
    recorder.clear_error();
    Ok(available)
}

#[unsafe(no_mangle)]
pub extern "C" fn ec_save_latest_wav(
    handle: u64,
    seconds: u32,
    output_path_utf8: *const c_char,
) -> i32 {
    ffi_result(handle, || {
        if seconds == 0 {
            return Err(FfiError::invalid("seconds must be non-zero"));
        }
        let output_path = utf8_path(output_path_utf8, "output_path_utf8")?;
        if output_path.as_os_str().is_empty() {
            return Err(FfiError::invalid("output_path_utf8 must not be empty"));
        }
        let recorder = get_handle(handle)?;
        let worker = read_lock(&recorder.worker);
        let worker = worker
            .as_ref()
            .ok_or_else(|| stopped_error("recorder worker is stopped"))?;
        let job_id = worker
            .save_latest_wav_async(seconds, output_path)
            .map_err(FfiError::from)?;

        loop {
            let job = worker.export_status(job_id).ok_or_else(|| {
                FfiError::core(format!(
                    "export job disappeared before completion: {job_id}"
                ))
            })?;
            match job.state {
                ExportJobState::Pending | ExportJobState::Running => {
                    thread::sleep(Duration::from_millis(5));
                }
                ExportJobState::Finished => {
                    recorder.clear_error();
                    return Ok(());
                }
                ExportJobState::Failed | ExportJobState::Canceled => {
                    return Err(FfiError::core(
                        job.error
                            .unwrap_or_else(|| format!("export job {:?}", job.state)),
                    ));
                }
            }
        }
    })
}

/// Export the most recent buffer to WAV or MP3 with an optional bitrate and
/// FFmpeg path. `format` is 0 = wav (FFmpeg is ignored) and 1 = mp3 (FFmpeg
/// must be provided). Returns when the export job finishes.
///
/// # Safety
///
/// When `format` is mp3, `ffmpeg_path_utf8` must be null or point to a valid
/// NUL-terminated UTF-8 path. `output_path_utf8` must point to a valid
/// NUL-terminated UTF-8 path.
#[unsafe(no_mangle)]
pub extern "C" fn ec_save_latest(
    handle: u64,
    seconds: u32,
    format: u32,
    bitrate_kbps: u32,
    ffmpeg_path_utf8: *const c_char,
    output_path_utf8: *const c_char,
) -> i32 {
    ffi_result(handle, || {
        if seconds == 0 {
            return Err(FfiError::invalid("seconds must be non-zero"));
        }
        let output_path = utf8_path(output_path_utf8, "output_path_utf8")?;
        if output_path.as_os_str().is_empty() {
            return Err(FfiError::invalid("output_path_utf8 must not be empty"));
        }
        let options = match format {
            0 => ExportOptions::wav(),
            1 => {
                let ffmpeg_path = utf8_path(ffmpeg_path_utf8, "ffmpeg_path_utf8")?;
                if ffmpeg_path.as_os_str().is_empty() {
                    return Err(FfiError::invalid(
                        "ffmpeg_path_utf8 must not be empty for mp3 export",
                    ));
                }
                ExportOptions::mp3(ffmpeg_path, bitrate_kbps)
            }
            other => {
                return Err(FfiError::invalid(format!(
                    "unknown export format {other} (expected 0 = wav, 1 = mp3)"
                )));
            }
        };
        let recorder = get_handle(handle)?;
        let worker = read_lock(&recorder.worker);
        let worker = worker
            .as_ref()
            .ok_or_else(|| stopped_error("recorder worker is stopped"))?;
        let job_id = worker
            .save_latest_async(seconds, output_path, options)
            .map_err(FfiError::from)?;

        loop {
            let job = worker.export_status(job_id).ok_or_else(|| {
                FfiError::core(format!(
                    "export job disappeared before completion: {job_id}"
                ))
            })?;
            match job.state {
                ExportJobState::Pending | ExportJobState::Running => {
                    thread::sleep(Duration::from_millis(5));
                }
                ExportJobState::Finished => {
                    recorder.clear_error();
                    return Ok(());
                }
                ExportJobState::Failed | ExportJobState::Canceled => {
                    return Err(FfiError::core(
                        job.error
                            .unwrap_or_else(|| format!("export job {:?}", job.state)),
                    ));
                }
            }
        }
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn ec_clear(handle: u64) -> i32 {
    ffi_result(handle, || {
        let recorder = get_handle(handle)?;
        stop_capture_thread(&recorder)?;
        let mut worker_slot = write_lock(&recorder.worker);
        if let Some(mut worker) = worker_slot.take() {
            worker.stop();
        }

        let temp_root = recorder.config.temp_root();
        let remove_result = if temp_root.exists() {
            std::fs::remove_dir_all(&temp_root).map_err(FfiError::core)
        } else {
            Ok(())
        };
        let restart_result = RecorderWorker::start(recorder.config.clone()).map_err(FfiError::from);

        match restart_result {
            Ok(worker) => {
                *worker_slot = Some(worker);
                remove_result?;
                recorder.clear_error();
                Ok(())
            }
            Err(restart_error) => match remove_result {
                Ok(()) => Err(restart_error),
                Err(remove_error) => Err(FfiError::core(format!(
                    "failed to clear cache: {}; failed to restart worker: {}",
                    remove_error.message, restart_error.message
                ))),
            },
        }
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn ec_status(handle: u64) -> i32 {
    match std::panic::catch_unwind(|| status_impl(handle)) {
        Ok(Ok(value)) => value,
        Ok(Err(error)) => {
            record_error(handle, &error.message);
            -1
        }
        Err(_) => {
            record_error(handle, "panic in ec_status");
            -1
        }
    }
}

fn status_impl(handle: u64) -> Result<i32, FfiError> {
    let recorder = get_handle(handle)?;
    let running = recorder.capture_running.load(Ordering::Acquire);
    recorder.clear_error();
    Ok(i32::from(running))
}

#[unsafe(no_mangle)]
pub extern "C" fn ec_status_json(
    handle: u64,
    output_utf8: *mut c_char,
    output_capacity: usize,
) -> usize {
    match std::panic::catch_unwind(|| status_json_impl(handle, output_utf8, output_capacity)) {
        Ok(Ok(required)) => required,
        Ok(Err(error)) => {
            record_error(handle, &error.message);
            0
        }
        Err(_) => {
            record_error(handle, "panic in ec_status_json");
            0
        }
    }
}

fn status_json_impl(
    handle: u64,
    output_utf8: *mut c_char,
    output_capacity: usize,
) -> Result<usize, FfiError> {
    let recorder = get_handle(handle)?;
    let selection = lock_mutex(&recorder.capture_selection).clone();
    let runtime = lock_mutex(&recorder.capture_runtime).clone();
    let worker = read_lock(&recorder.worker);
    let worker = worker
        .as_ref()
        .ok_or_else(|| stopped_error("recorder worker is stopped"))?;
    let mut status = serde_json::to_value(worker.status()).map_err(FfiError::core)?;
    let fields = status
        .as_object_mut()
        .ok_or_else(|| FfiError::core("core status did not serialize as an object"))?;
    fields.insert(
        "capture_running".to_string(),
        recorder.capture_running.load(Ordering::Acquire).into(),
    );
    fields.insert(
        "capture_sample_rate".to_string(),
        recorder.capture_sample_rate.load(Ordering::Relaxed).into(),
    );
    fields.insert(
        "recorder_sample_rate".to_string(),
        recorder.config.audio.sample_rate.into(),
    );
    fields.insert(
        "capture_channels".to_string(),
        recorder.capture_channels.load(Ordering::Relaxed).into(),
    );
    fields.insert(
        "capture_device".to_string(),
        lock_mutex(&recorder.capture_device).clone().into(),
    );
    let capture_mode = match (selection.microphone_enabled, selection.system_audio_enabled) {
        (true, true) => "both",
        (true, false) => "microphone",
        (false, true) => "system_audio",
        (false, false) => "none",
    };
    fields.insert("capture_mode".to_string(), capture_mode.into());
    fields.insert(
        "microphone_enabled".to_string(),
        selection.microphone_enabled.into(),
    );
    fields.insert(
        "system_audio_enabled".to_string(),
        selection.system_audio_enabled.into(),
    );
    fields.insert(
        "microphone_device_id".to_string(),
        selection.microphone_device_id.clone().into(),
    );
    fields.insert(
        "system_audio_supported".to_string(),
        cfg!(target_os = "windows").into(),
    );
    fields.insert(
        "input_device_selection_supported".to_string(),
        cfg!(target_os = "windows").into(),
    );
    insert_source_runtime(fields, "microphone", runtime.microphone.as_ref());
    insert_source_runtime(fields, "system_audio", runtime.system_audio.as_ref());
    fields.insert(
        "input_level_rms".to_string(),
        f32::from_bits(recorder.input_level_rms_bits.load(Ordering::Relaxed)).into(),
    );
    fields.insert(
        "input_peak".to_string(),
        f32::from_bits(recorder.input_peak_bits.load(Ordering::Relaxed)).into(),
    );
    fields.insert(
        "microphone_level_rms".to_string(),
        f32::from_bits(recorder.microphone_level_rms_bits.load(Ordering::Relaxed)).into(),
    );
    fields.insert(
        "microphone_peak".to_string(),
        f32::from_bits(recorder.microphone_peak_bits.load(Ordering::Relaxed)).into(),
    );
    fields.insert(
        "system_audio_level_rms".to_string(),
        f32::from_bits(recorder.system_audio_level_rms_bits.load(Ordering::Relaxed)).into(),
    );
    fields.insert(
        "system_audio_peak".to_string(),
        f32::from_bits(recorder.system_audio_peak_bits.load(Ordering::Relaxed)).into(),
    );
    fields.insert(
        "microphone_dropped_samples".to_string(),
        recorder
            .microphone_dropped_samples
            .load(Ordering::Relaxed)
            .into(),
    );
    fields.insert(
        "system_audio_dropped_samples".to_string(),
        recorder
            .system_audio_dropped_samples
            .load(Ordering::Relaxed)
            .into(),
    );
    fields.insert(
        "microphone_silence_filled_samples".to_string(),
        recorder
            .microphone_silence_filled_samples
            .load(Ordering::Relaxed)
            .into(),
    );
    fields.insert(
        "system_audio_silence_filled_samples".to_string(),
        recorder
            .system_audio_silence_filled_samples
            .load(Ordering::Relaxed)
            .into(),
    );
    fields.insert(
        "capture_error".to_string(),
        lock_mutex(&recorder.capture_error).clone().into(),
    );
    let json = serde_json::to_string(&status).map_err(FfiError::core)?;
    let required = copy_utf8_result(&json, output_utf8, output_capacity)?;
    recorder.clear_error();
    Ok(required)
}

fn insert_source_runtime(
    fields: &mut serde_json::Map<String, serde_json::Value>,
    prefix: &str,
    runtime: Option<&SourceRuntimeInfo>,
) {
    fields.insert(
        format!("{prefix}_active_device_id"),
        runtime.map(|info| info.id.clone()).into(),
    );
    fields.insert(
        format!("{prefix}_device"),
        runtime.map(|info| info.name.clone()).into(),
    );
    fields.insert(
        format!("{prefix}_sample_rate"),
        runtime.map(|info| info.sample_rate).unwrap_or(0).into(),
    );
    fields.insert(
        format!("{prefix}_channels"),
        runtime.map(|info| info.channels).unwrap_or(0).into(),
    );
}

#[unsafe(no_mangle)]
pub extern "C" fn ec_last_error(handle: u64) -> *const c_char {
    match std::panic::catch_unwind(|| {
        if handle == 0 {
            return lock_mutex(global_error()).as_ptr();
        }
        match get_handle(handle) {
            Ok(recorder) => recorder.error_ptr(),
            Err(error) => {
                set_global_error(&error.message);
                lock_mutex(global_error()).as_ptr()
            }
        }
    }) {
        Ok(pointer) => pointer,
        Err(_) => EMPTY_C_STRING.as_ptr().cast(),
    }
}

fn stop_capture_thread(recorder: &Arc<RecorderHandle>) -> Result<(), FfiError> {
    let capture = lock_mutex(&recorder.capture).take();
    if let Some(capture) = capture {
        stop_join_capture(recorder, capture)?;
    }
    recorder.capture_running.store(false, Ordering::Release);
    recorder.capture_sample_rate.store(0, Ordering::Relaxed);
    recorder.capture_channels.store(0, Ordering::Relaxed);
    *lock_mutex(&recorder.capture_device) = None;
    *lock_mutex(&recorder.capture_runtime) = CaptureRuntimeInfo::default();
    recorder.reset_capture_metrics();
    Ok(())
}

fn stop_join_capture(
    recorder: &Arc<RecorderHandle>,
    capture: CaptureThread,
) -> Result<(), FfiError> {
    let _ = capture.stop_sender.send(());
    if capture.join_handle.join().is_err() {
        recorder.capture_running.store(false, Ordering::Release);
        let message = "native capture thread panicked";
        recorder.set_capture_error(message);
        return Err(FfiError::core(message));
    }
    recorder.capture_running.store(false, Ordering::Release);
    Ok(())
}

#[cfg(target_os = "windows")]
fn capture_thread_main(
    recorder: Arc<RecorderHandle>,
    stop_receiver: mpsc::Receiver<()>,
    init_sender: mpsc::Sender<Result<(), String>>,
) {
    let result = run_native_capture(Arc::clone(&recorder), stop_receiver, &init_sender);
    recorder.capture_running.store(false, Ordering::Release);
    if let Err(message) = result {
        recorder.set_capture_error(message.clone());
        let _ = init_sender.send(Err(message));
    }
}

#[cfg(target_os = "windows")]
fn run_native_capture(
    recorder: Arc<RecorderHandle>,
    stop_receiver: mpsc::Receiver<()>,
    init_sender: &mpsc::Sender<Result<(), String>>,
) -> Result<(), String> {
    let host = cpal::default_host();
    let requested_rate = recorder.config.audio.sample_rate;
    let selection = lock_mutex(&recorder.capture_selection).clone();
    if !selection.microphone_enabled && !selection.system_audio_enabled {
        return Err("at least one capture source must be enabled".to_string());
    }

    let timeline = Arc::new(AudioTimeline::new(&selection, requested_rate));
    let (stream_error_sender, stream_error_receiver) = mpsc::channel::<String>();
    let mut streams = Vec::with_capacity(2);
    let mut runtime = CaptureRuntimeInfo::default();

    if selection.microphone_enabled {
        let device = resolve_microphone(&host, selection.microphone_device_id.as_deref())?;
        let (stream, info) = build_source_stream(
            &device,
            CaptureSource::Microphone,
            requested_rate,
            Arc::clone(&recorder),
            Arc::clone(&timeline),
            stream_error_sender.clone(),
        )?;
        streams.push(stream);
        runtime.microphone = Some(info);
    }

    if selection.system_audio_enabled {
        // On WASAPI, CPAL deliberately enables AUDCLNT_STREAMFLAGS_LOOPBACK
        // when build_input_stream is called on an eRender (output) endpoint.
        let device = host.default_output_device().ok_or_else(|| {
            "no default Windows output device is available for system audio loopback".to_string()
        })?;
        let (stream, info) = build_source_stream(
            &device,
            CaptureSource::SystemAudio,
            requested_rate,
            Arc::clone(&recorder),
            Arc::clone(&timeline),
            stream_error_sender.clone(),
        )?;
        streams.push(stream);
        runtime.system_audio = Some(info);
    }

    for stream in &streams {
        stream
            .play()
            .map_err(|error| format!("failed to start Windows capture stream: {error}"))?;
    }

    let active_sources: Vec<&SourceRuntimeInfo> =
        [runtime.microphone.as_ref(), runtime.system_audio.as_ref()]
            .into_iter()
            .flatten()
            .collect();
    let legacy_rate = if active_sources.len() == 1 {
        active_sources[0].sample_rate
    } else {
        requested_rate
    };
    let legacy_channels = if active_sources.len() == 1 {
        active_sources[0].channels
    } else {
        1
    };
    let legacy_name = active_sources
        .iter()
        .map(|info| info.name.as_str())
        .collect::<Vec<_>>()
        .join(" + ");
    recorder
        .capture_sample_rate
        .store(legacy_rate, Ordering::Relaxed);
    recorder
        .capture_channels
        .store(legacy_channels, Ordering::Relaxed);
    *lock_mutex(&recorder.capture_device) = Some(legacy_name);
    *lock_mutex(&recorder.capture_runtime) = runtime;
    recorder.capture_running.store(true, Ordering::Release);
    init_sender
        .send(Ok(()))
        .map_err(|error| format!("capture initialization receiver closed: {error}"))?;

    // RecorderWorker receives one monotonic, fixed-rate stream regardless of
    // how callbacks from independent WASAPI device clocks are chunked. A
    // bounded source queue absorbs short jitter; underrun contributes silence
    // and overflow drops oldest frames so drift can never grow without bound.
    let mut clock = FrameClock::new(requested_rate);
    let mut next_tick = Instant::now() + MIX_PREBUFFER;
    loop {
        let now = Instant::now();
        let poll_timeout = next_tick.saturating_duration_since(now).min(MIX_INTERVAL);
        match stop_receiver.recv_timeout(poll_timeout) {
            Ok(()) | Err(mpsc::RecvTimeoutError::Disconnected) => break,
            Err(mpsc::RecvTimeoutError::Timeout) => {}
        }
        if let Ok(message) = stream_error_receiver.try_recv() {
            return Err(message);
        }

        let now = Instant::now();
        if now < next_tick {
            continue;
        }
        let mut ticks = 1_u32;
        next_tick += MIX_INTERVAL;
        while next_tick <= now && ticks < 10 {
            ticks += 1;
            next_tick += MIX_INTERVAL;
        }
        if next_tick <= now {
            // Do not synthesize an arbitrarily large silent span after sleep or
            // a heavily stalled process. Resume from the current wall clock.
            next_tick = now + MIX_INTERVAL;
        }
        let frames = clock.frames_for_ticks(ticks);
        if frames == 0 {
            continue;
        }
        let (mixed, timeline_result) = timeline.mix(frames);
        recorder
            .microphone_silence_filled_samples
            .fetch_add(timeline_result.microphone_missing as u64, Ordering::Relaxed);
        recorder.system_audio_silence_filled_samples.fetch_add(
            timeline_result.system_audio_missing as u64,
            Ordering::Relaxed,
        );
        recorder.microphone_dropped_samples.fetch_add(
            timeline_result.microphone_drift_dropped as u64,
            Ordering::Relaxed,
        );
        recorder.system_audio_dropped_samples.fetch_add(
            timeline_result.system_audio_drift_dropped as u64,
            Ordering::Relaxed,
        );
        push_captured_pcm(&recorder, &mixed);
    }
    drop(streams);
    Ok(())
}

#[cfg(target_os = "windows")]
fn validate_capture_selection(selection: &CaptureSelection) -> Result<(), FfiError> {
    let host = cpal::default_host();
    if selection.microphone_enabled {
        resolve_microphone(&host, selection.microphone_device_id.as_deref())
            .map_err(FfiError::core)?;
    }
    if selection.system_audio_enabled && host.default_output_device().is_none() {
        return Err(FfiError::core(
            "no default Windows output device is available for system audio loopback",
        ));
    }
    Ok(())
}

#[cfg(target_os = "windows")]
fn resolve_microphone(host: &cpal::Host, device_id: Option<&str>) -> Result<cpal::Device, String> {
    let Some(device_id) = device_id.filter(|value| !value.is_empty()) else {
        return host
            .default_input_device()
            .ok_or_else(|| "no default Windows input device is available".to_string());
    };
    let parsed = device_id
        .parse::<cpal::DeviceId>()
        .map_err(|error| format!("invalid Windows input device id '{device_id}': {error}"))?;
    let device = host
        .device_by_id(&parsed)
        .ok_or_else(|| format!("selected Windows input device is unavailable: {device_id}"))?;
    if !device.supports_input() {
        return Err(format!(
            "selected Windows device does not support microphone input: {device_id}"
        ));
    }
    Ok(device)
}

#[cfg(target_os = "windows")]
struct SourceStreamContext {
    source: CaptureSource,
    recorder: Arc<RecorderHandle>,
    timeline: Arc<AudioTimeline>,
    channels: usize,
    input_sample_rate: u32,
    output_sample_rate: u32,
    stream_error_sender: mpsc::Sender<String>,
}

#[cfg(target_os = "windows")]
fn build_source_stream(
    device: &cpal::Device,
    source: CaptureSource,
    output_sample_rate: u32,
    recorder: Arc<RecorderHandle>,
    timeline: Arc<AudioTimeline>,
    stream_error_sender: mpsc::Sender<String>,
) -> Result<(cpal::Stream, SourceRuntimeInfo), String> {
    let supported = match source {
        CaptureSource::Microphone => {
            let range = device
                .supported_input_configs()
                .map_err(|error| format!("failed to query microphone formats: {error}"))?
                .filter(|config| !config.sample_format().is_dsd())
                .min_by_key(|config| {
                    let nearest = output_sample_rate
                        .clamp(config.min_sample_rate(), config.max_sample_rate());
                    (
                        output_sample_rate.abs_diff(nearest),
                        u8::from(config.channels() != 1),
                        sample_format_rank(config.sample_format()),
                        config.channels(),
                    )
                })
                .ok_or_else(|| {
                    "selected microphone has no supported PCM capture format".to_string()
                })?;
            let sample_rate =
                output_sample_rate.clamp(range.min_sample_rate(), range.max_sample_rate());
            range.with_sample_rate(sample_rate)
        }
        CaptureSource::SystemAudio => {
            // eRender endpoints expose output configs, not input configs, even
            // though CPAL accepts build_input_stream for WASAPI loopback.
            device
                .default_output_config()
                .map_err(|error| format!("failed to query system audio loopback format: {error}"))?
        }
    };
    let sample_format = supported.sample_format();
    let config = supported.config();
    let channels = usize::from(config.channels);
    let input_sample_rate = config.sample_rate;
    let id = device
        .id()
        .map_err(|error| format!("failed to read Windows audio device id: {error}"))?
        .to_string();
    let name = device
        .description()
        .map(|description| description.name().to_string())
        .unwrap_or_else(|_| device.to_string());
    let info = SourceRuntimeInfo {
        id,
        name,
        sample_rate: input_sample_rate,
        channels: channels as u32,
    };
    let context = SourceStreamContext {
        source,
        recorder,
        timeline,
        channels,
        input_sample_rate,
        output_sample_rate,
        stream_error_sender,
    };

    macro_rules! build {
        ($sample:ty) => {
            build_typed_source_stream::<$sample>(device, config, context)
        };
    }
    let stream = match sample_format {
        cpal::SampleFormat::I8 => build!(i8),
        cpal::SampleFormat::I16 => build!(i16),
        cpal::SampleFormat::I24 => build!(cpal::I24),
        cpal::SampleFormat::I32 => build!(i32),
        cpal::SampleFormat::I64 => build!(i64),
        cpal::SampleFormat::U8 => build!(u8),
        cpal::SampleFormat::U16 => build!(u16),
        cpal::SampleFormat::U24 => build!(cpal::U24),
        cpal::SampleFormat::U32 => build!(u32),
        cpal::SampleFormat::U64 => build!(u64),
        cpal::SampleFormat::F32 => build!(f32),
        cpal::SampleFormat::F64 => build!(f64),
        format => Err(format!("unsupported Windows PCM sample format: {format}")),
    }?;
    Ok((stream, info))
}

#[cfg(target_os = "windows")]
fn build_typed_source_stream<T>(
    device: &cpal::Device,
    config: cpal::StreamConfig,
    context: SourceStreamContext,
) -> Result<cpal::Stream, String>
where
    T: cpal::SizedSample + Sample + 'static,
    i16: FromSample<T>,
{
    let SourceStreamContext {
        source,
        recorder,
        timeline,
        channels,
        input_sample_rate,
        output_sample_rate,
        stream_error_sender,
    } = context;
    let error_recorder = Arc::clone(&recorder);
    let mut resampler = LinearResampler::new(input_sample_rate, output_sample_rate);
    let source_name = match source {
        CaptureSource::Microphone => "microphone",
        CaptureSource::SystemAudio => "system audio loopback",
    };
    device
        .build_input_stream::<T, _, _>(
            config,
            move |data, _| {
                let mono = downmix_samples(data, channels);
                let recorder_samples = resampler.process(&mono);
                update_source_levels(&recorder, source, &recorder_samples);
                let dropped = timeline.enqueue(source, &recorder_samples);
                match source {
                    CaptureSource::Microphone => {
                        recorder
                            .microphone_dropped_samples
                            .fetch_add(dropped as u64, Ordering::Relaxed);
                    }
                    CaptureSource::SystemAudio => {
                        recorder
                            .system_audio_dropped_samples
                            .fetch_add(dropped as u64, Ordering::Relaxed);
                    }
                }
            },
            move |error| {
                let message = format!("Windows {source_name} stream error: {error}");
                error_recorder.set_capture_error(message.clone());
                error_recorder
                    .capture_running
                    .store(false, Ordering::Release);
                let _ = stream_error_sender.send(message);
            },
            None,
        )
        .map_err(|error| format!("failed to build Windows {source_name} stream: {error}"))
}

#[cfg(target_os = "windows")]
fn sample_format_rank(format: cpal::SampleFormat) -> u8 {
    match format {
        cpal::SampleFormat::F32 => 0,
        cpal::SampleFormat::I16 => 1,
        cpal::SampleFormat::I24 => 2,
        cpal::SampleFormat::I32 => 3,
        cpal::SampleFormat::F64 => 4,
        _ => 5,
    }
}

#[cfg(target_os = "windows")]
fn push_captured_pcm(recorder: &Arc<RecorderHandle>, mono: &[i16]) {
    if mono.is_empty() {
        return;
    }
    update_input_levels(recorder, mono);
    let worker = read_lock(&recorder.worker);
    let Some(worker) = worker.as_ref() else {
        recorder.set_capture_error("recorder worker stopped during capture");
        recorder.capture_running.store(false, Ordering::Release);
        return;
    };
    if let Err(error) = worker.push_samples(mono) {
        recorder.set_capture_error(format!("failed to queue captured audio: {error}"));
        if matches!(
            error,
            EchoCoreError::QueueClosed | EchoCoreError::WorkerStopped
        ) {
            recorder.capture_running.store(false, Ordering::Release);
        }
    }
}

#[cfg(target_os = "windows")]
fn update_input_levels(recorder: &RecorderHandle, samples: &[i16]) {
    let (rms, peak) = audio_levels(samples);
    recorder
        .input_level_rms_bits
        .store(rms.to_bits(), Ordering::Relaxed);
    recorder
        .input_peak_bits
        .store(peak.to_bits(), Ordering::Relaxed);
}

#[cfg(target_os = "windows")]
fn update_source_levels(recorder: &RecorderHandle, source: CaptureSource, samples: &[i16]) {
    if samples.is_empty() {
        return;
    }
    let (rms, peak) = audio_levels(samples);
    match source {
        CaptureSource::Microphone => {
            recorder
                .microphone_level_rms_bits
                .store(rms.to_bits(), Ordering::Relaxed);
            recorder
                .microphone_peak_bits
                .store(peak.to_bits(), Ordering::Relaxed);
        }
        CaptureSource::SystemAudio => {
            recorder
                .system_audio_level_rms_bits
                .store(rms.to_bits(), Ordering::Relaxed);
            recorder
                .system_audio_peak_bits
                .store(peak.to_bits(), Ordering::Relaxed);
        }
    }
}

#[cfg(target_os = "windows")]
fn audio_levels(samples: &[i16]) -> (f32, f32) {
    let mut sum_squares = 0_f64;
    let mut peak = 0_f32;
    for &sample in samples {
        let normalized = sample as f32 / i16::MAX as f32;
        sum_squares += f64::from(normalized * normalized);
        peak = peak.max(normalized.abs());
    }
    let rms = (sum_squares / samples.len() as f64).sqrt() as f32;
    (rms, peak)
}

#[cfg(target_os = "windows")]
struct LinearResampler {
    source_step: f64,
    next_output_position: f64,
    input_position: u64,
    previous_sample: Option<f32>,
}

#[cfg(target_os = "windows")]
impl LinearResampler {
    fn new(input_sample_rate: u32, output_sample_rate: u32) -> Self {
        Self {
            source_step: input_sample_rate as f64 / output_sample_rate as f64,
            next_output_position: 0.0,
            input_position: 0,
            previous_sample: None,
        }
    }

    fn process(&mut self, input: &[i16]) -> Vec<i16> {
        if self.source_step == 1.0 {
            return input.to_vec();
        }

        let estimated = (input.len() as f64 / self.source_step).ceil() as usize + 1;
        let mut output = Vec::with_capacity(estimated);
        for &sample in input {
            let current = sample as f32;
            let Some(previous) = self.previous_sample else {
                self.previous_sample = Some(current);
                if self.next_output_position == 0.0 {
                    output.push(sample);
                    self.next_output_position += self.source_step;
                }
                continue;
            };

            let current_position = self.input_position + 1;
            while self.next_output_position <= current_position as f64 {
                let fraction = (self.next_output_position - self.input_position as f64) as f32;
                let interpolated = previous + ((current - previous) * fraction);
                output.push(interpolated.round().clamp(i16::MIN as f32, i16::MAX as f32) as i16);
                self.next_output_position += self.source_step;
            }
            self.previous_sample = Some(current);
            self.input_position = current_position;
        }
        output
    }
}

#[cfg(target_os = "windows")]
fn downmix_samples<T>(input: &[T], channels: usize) -> Vec<i16>
where
    T: Sample,
    i16: FromSample<T>,
{
    input
        .chunks_exact(channels)
        .map(|frame| {
            let sum = frame
                .iter()
                .copied()
                .map(i16::from_sample)
                .map(i64::from)
                .sum::<i64>();
            (sum / channels as i64) as i16
        })
        .collect()
}

fn ffi_result(action_handle: u64, action: impl FnOnce() -> Result<(), FfiError>) -> i32 {
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(action)) {
        Ok(Ok(())) => EC_OK,
        Ok(Err(error)) => {
            record_error(action_handle, &error.message);
            error.code
        }
        Err(_) => {
            record_error(action_handle, "panic in EchoClip Windows FFI");
            EC_ERROR_PANIC
        }
    }
}

fn get_handle(handle: u64) -> Result<Arc<RecorderHandle>, FfiError> {
    if handle == 0 {
        return Err(FfiError::invalid("invalid handle: 0"));
    }
    lock_mutex(registry())
        .get(&handle)
        .cloned()
        .ok_or_else(|| FfiError::invalid(format!("invalid handle: {handle}")))
}

fn utf8_path(pointer: *const c_char, name: &str) -> Result<PathBuf, FfiError> {
    if pointer.is_null() {
        return Err(FfiError::invalid(format!("{name} must not be null")));
    }
    let value = unsafe { CStr::from_ptr(pointer) }
        .to_str()
        .map_err(|_| FfiError::invalid(format!("{name} must be valid UTF-8")))?;
    Ok(PathBuf::from(value))
}

fn ffi_bool(value: i32, name: &str) -> Result<bool, FfiError> {
    match value {
        0 => Ok(false),
        1 => Ok(true),
        _ => Err(FfiError::invalid(format!("{name} must be 0 or 1"))),
    }
}

unsafe fn optional_utf8(pointer: *const c_char, name: &str) -> Result<Option<String>, FfiError> {
    if pointer.is_null() {
        return Ok(None);
    }
    let value = unsafe { CStr::from_ptr(pointer) }
        .to_str()
        .map_err(|_| FfiError::invalid(format!("{name} must be valid UTF-8")))?;
    if value.is_empty() {
        Ok(None)
    } else {
        Ok(Some(value.to_string()))
    }
}

fn copy_utf8_result(
    value: &str,
    output_utf8: *mut c_char,
    output_capacity: usize,
) -> Result<usize, FfiError> {
    let value = make_c_string(value);
    let required = value.as_bytes_with_nul().len();
    if !output_utf8.is_null() && output_capacity >= required {
        unsafe {
            ptr::copy_nonoverlapping(
                value.as_ptr().cast::<u8>(),
                output_utf8.cast::<u8>(),
                required,
            );
        }
    }
    Ok(required)
}

fn stopped_error(message: impl Into<String>) -> FfiError {
    FfiError {
        code: EC_ERROR_STOPPED,
        message: message.into(),
    }
}

fn record_error(handle: u64, message: &str) {
    if let Ok(recorder) = get_handle(handle) {
        recorder.set_error(message);
    } else {
        set_global_error(message);
    }
}

fn set_global_error(message: &str) {
    *lock_mutex(global_error()) = make_c_string(message);
}

fn make_c_string(message: &str) -> CString {
    CString::new(message.replace('\0', "\\0")).unwrap_or_else(|_| empty_c_string())
}

fn empty_c_string() -> CString {
    CString::new(Vec::new()).expect("empty CString")
}

fn lock_mutex<T>(mutex: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    mutex
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

fn read_lock<T>(lock: &RwLock<T>) -> std::sync::RwLockReadGuard<'_, T> {
    lock.read().unwrap_or_else(|poisoned| poisoned.into_inner())
}

fn write_lock<T>(lock: &RwLock<T>) -> std::sync::RwLockWriteGuard<'_, T> {
    lock.write()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn ffi_reuses_segmented_core_and_exports_across_segments() {
        let work_dir = unique_test_dir();
        let output = work_dir.join("latest.wav");
        let work_dir_c = CString::new(work_dir.to_string_lossy().as_bytes()).unwrap();
        let output_c = CString::new(output.to_string_lossy().as_bytes()).unwrap();

        let handle = ec_create(work_dir_c.as_ptr(), 4, 120);
        assert_ne!(handle, 0, "{}", last_error(handle));

        let samples: Vec<i16> = (0..244).map(|value| value as i16).collect();
        assert_eq!(
            unsafe { ec_push_pcm(handle, samples.as_ptr(), samples.len()) },
            EC_OK
        );
        assert_eq!(ec_save_latest_wav(handle, 2, output_c.as_ptr()), EC_OK);
        assert_eq!(fs::metadata(&output).unwrap().len(), 44 + (8 * 2));
        assert_eq!(ec_available_millis(handle), 61_000);

        let required = ec_status_json(handle, ptr::null_mut(), 0);
        assert!(required > 1);
        let mut status = vec![0_u8; required];
        assert_eq!(
            ec_status_json(handle, status.as_mut_ptr().cast(), status.len()),
            required
        );
        let status = CStr::from_bytes_with_nul(&status)
            .unwrap()
            .to_str()
            .unwrap();
        assert!(status.contains("\"segment_count\":2"), "{status}");

        assert_eq!(ec_clear(handle), EC_OK, "{}", last_error(handle));
        assert_eq!(ec_available_millis(handle), 0);
        assert_eq!(ec_status(handle), 0);
        ec_destroy(handle);
        let _ = fs::remove_dir_all(work_dir);
    }

    #[cfg(target_os = "windows")]
    #[test]
    fn resampler_keeps_rate_across_callback_boundaries() {
        let input: Vec<i16> = (0..480).map(|value| value as i16).collect();
        let mut resampler = LinearResampler::new(48_000, 16_000);
        let mut output = resampler.process(&input[..137]);
        output.extend(resampler.process(&input[137..]));

        assert_eq!(output.len(), 160);
        assert_eq!(output[0], 0);
        assert_eq!(output[1], 3);
        assert_eq!(output[159], 477);
    }

    #[cfg(target_os = "windows")]
    #[test]
    fn audio_device_enumeration_returns_the_public_json_schema() {
        let required = ec_audio_devices_json(ptr::null_mut(), 0);
        assert!(required > 1, "{}", last_error(0));
        let mut json = vec![0_u8; required];
        assert_eq!(
            ec_audio_devices_json(json.as_mut_ptr().cast(), json.len()),
            required
        );
        let json = CStr::from_bytes_with_nul(&json).unwrap().to_str().unwrap();
        let devices: serde_json::Value = serde_json::from_str(json).unwrap();
        let devices = devices.as_array().expect("device list must be an array");
        let mut default_count = 0_usize;
        for device in devices {
            assert!(
                device["id"].as_str().is_some_and(|value| !value.is_empty()),
                "{device}"
            );
            assert!(
                device["name"]
                    .as_str()
                    .is_some_and(|value| !value.is_empty()),
                "{device}"
            );
            assert!(device["isDefault"].is_boolean(), "{device}");
            default_count += usize::from(device["isDefault"].as_bool() == Some(true));
        }
        assert!(default_count <= 1, "only one microphone may be default");
    }

    #[test]
    fn timeline_mixes_different_callback_block_sizes_on_one_clock() {
        let selection = CaptureSelection {
            microphone_enabled: true,
            system_audio_enabled: true,
            microphone_device_id: None,
        };
        let timeline = AudioTimeline::new(&selection, 1_000);
        assert_eq!(
            timeline.enqueue(CaptureSource::Microphone, &[10, 20, 30]),
            0
        );
        assert_eq!(
            timeline.enqueue(CaptureSource::SystemAudio, &[2, 4, 6, 8, 10]),
            0
        );
        assert_eq!(timeline.enqueue(CaptureSource::Microphone, &[40, 50]), 0);

        let (first, first_result) = timeline.mix(2);
        let (second, second_result) = timeline.mix(3);
        assert_eq!(first, [6, 12]);
        assert_eq!(second, [18, 24, 30]);
        assert_eq!(first_result, TimelineResult::default());
        assert_eq!(second_result, TimelineResult::default());
    }

    #[test]
    fn timeline_delayed_or_ended_source_contributes_silence_without_stalling() {
        let selection = CaptureSelection {
            microphone_enabled: true,
            system_audio_enabled: true,
            microphone_device_id: None,
        };
        let timeline = AudioTimeline::new(&selection, 1_000);
        timeline.enqueue(CaptureSource::Microphone, &[100, 200, 300, 400]);

        let (before_system, missing) = timeline.mix(2);
        assert_eq!(before_system, [50, 100]);
        assert_eq!(missing.system_audio_missing, 2);

        timeline.enqueue(CaptureSource::SystemAudio, &[1_000, 2_000]);
        let (after_system, missing) = timeline.mix(3);
        assert_eq!(after_system, [650, 1_200, 0]);
        assert_eq!(missing.microphone_missing, 1);
        assert_eq!(missing.system_audio_missing, 1);
    }

    #[test]
    fn timeline_queue_is_bounded_and_drops_oldest_frames() {
        let selection = CaptureSelection {
            microphone_enabled: true,
            system_audio_enabled: false,
            microphone_device_id: None,
        };
        let timeline = AudioTimeline::new(&selection, 10);
        // At tiny test rates the queue still has a minimum capacity of one.
        {
            let mut microphone = lock_mutex(&timeline.microphone);
            assert_eq!(microphone.max_buffer_frames, 5);
            microphone.high_water_frames = usize::MAX;
        }
        assert_eq!(
            timeline.enqueue(CaptureSource::Microphone, &[1, 2, 3, 4, 5, 6, 7]),
            2
        );
        let (output, missing) = timeline.mix(6);
        assert_eq!(output, [3, 4, 5, 6, 7, 0]);
        assert_eq!(missing.microphone_missing, 1);
        assert_eq!(missing.system_audio_missing, 0);
    }

    #[test]
    fn dual_source_mix_has_full_scale_headroom() {
        let selection = CaptureSelection {
            microphone_enabled: true,
            system_audio_enabled: true,
            microphone_device_id: None,
        };
        let timeline = AudioTimeline::new(&selection, 1_000);
        timeline.enqueue(CaptureSource::Microphone, &[i16::MAX, i16::MIN, i16::MAX]);
        timeline.enqueue(CaptureSource::SystemAudio, &[i16::MAX, i16::MIN, i16::MIN]);
        let (mixed, _) = timeline.mix(3);
        assert_eq!(mixed, [i16::MAX, i16::MIN, 0]);
    }

    #[test]
    fn timeline_corrects_fast_source_one_frame_at_a_time() {
        let selection = CaptureSelection {
            microphone_enabled: true,
            system_audio_enabled: false,
            microphone_device_id: None,
        };
        let timeline = AudioTimeline::new(&selection, 1_000);
        let samples: Vec<i16> = (0..62).collect();
        timeline.enqueue(CaptureSource::Microphone, &samples);
        let (mixed, result) = timeline.mix(2);
        assert_eq!(mixed, [1, 2]);
        assert_eq!(result.microphone_drift_dropped, 1);
        assert_eq!(result.system_audio_drift_dropped, 0);
    }

    #[test]
    fn frame_clock_carries_fractional_frames_without_long_term_drift() {
        let mut clock = FrameClock::new(44_101);
        let total: usize = (0..100).map(|_| clock.frames_for_ticks(1)).sum();
        assert_eq!(total, 44_101);
        assert_eq!(clock.fractional, 0);
    }

    #[test]
    fn configure_capture_boolean_and_source_validation_is_strict() {
        assert!(!ffi_bool(0, "value").unwrap());
        assert!(ffi_bool(1, "value").unwrap());
        assert!(ffi_bool(-1, "value").is_err());
        assert!(ffi_bool(2, "value").is_err());
    }

    fn last_error(handle: u64) -> String {
        let pointer = ec_last_error(handle);
        if pointer.is_null() {
            return "null error pointer".to_string();
        }
        unsafe { CStr::from_ptr(pointer) }
            .to_string_lossy()
            .into_owned()
    }

    fn unique_test_dir() -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock")
            .as_nanos();
        std::env::temp_dir().join(format!(
            "echoclip-windows-ffi-{}-{nanos}",
            std::process::id()
        ))
    }
}
