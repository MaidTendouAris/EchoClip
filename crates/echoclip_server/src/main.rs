use std::collections::HashMap;
use std::collections::hash_map::DefaultHasher;
use std::convert::Infallible;
use std::fs::{self, OpenOptions};
use std::hash::{Hash, Hasher};
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::net::{IpAddr, SocketAddr};
use std::path::{Path as FsPath, PathBuf};
use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, RwLock};
use std::time::Duration;
use std::time::{SystemTime, UNIX_EPOCH};

use axum::body::Bytes;
use axum::extract::{ConnectInfo, Path, State};
use axum::http::HeaderMap;
use axum::http::{HeaderValue, StatusCode, header};
use axum::response::sse::{Event, KeepAlive, Sse};
use axum::response::{Html, IntoResponse, Response};
use axum::routing::{get, patch, post};
use axum::{Json, Router};
use echoclip_core::{AudioConfig, CoreConfig, SegmentedRecorder};
use echoclip_sync_protocol::{
    ChallengeRequest, ChallengeResponse, ClientMessage, ID_BYTES, ResponseStatus, ServerResponse,
    UploadKey, open_client_message, parse_envelope, seal_server_response,
};
use futures_util::StreamExt;
use ipnet::IpNet;
use rand::RngCore;
use serde::{Deserialize, Serialize};
use tokio::sync::{mpsc, watch};
use tokio_stream::wrappers::WatchStream;

type AnyError = Box<dyn std::error::Error + Send + Sync>;

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(default)]
struct ServerConfig {
    server: GeneralConfig,
    upload: UploadConfig,
    webui: WebUiConfig,
    recording: RecordingConfig,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
struct GeneralConfig {
    data_dir: PathBuf,
    log_level: String,
}

impl Default for GeneralConfig {
    fn default() -> Self {
        Self {
            // Resolved against the server executable directory in run(), so a
            // standalone ./echoclip stores rolling stream data next to the
            // binary. The WebUI asks for the saved-recording directory once.
            data_dir: PathBuf::from("."),
            log_level: "info".to_string(),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
struct UploadConfig {
    bind: String,
    key_file: PathBuf,
    max_envelope_bytes: usize,
    challenge_ttl_seconds: u64,
    epoch_idle_seconds: u64,
    max_pending_challenges: usize,
    max_connections_per_ip: usize,
    max_requests_per_minute_per_ip: u32,
    max_active_streams: usize,
    max_replay_seconds: u32,
}

impl Default for UploadConfig {
    fn default() -> Self {
        Self {
            bind: "0.0.0.0:32581".to_string(),
            key_file: PathBuf::from("upload.key"),
            max_envelope_bytes: 262_144,
            challenge_ttl_seconds: 60,
            epoch_idle_seconds: 300,
            max_pending_challenges: 1024,
            max_connections_per_ip: 8,
            max_requests_per_minute_per_ip: 3600,
            max_active_streams: 128,
            max_replay_seconds: 86_400,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
struct WebUiConfig {
    bind: String,
    allow_public: bool,
    allowed_cidrs: Vec<IpNet>,
}

impl Default for WebUiConfig {
    fn default() -> Self {
        Self {
            bind: "0.0.0.0:32580".to_string(),
            allow_public: false,
            allowed_cidrs: [
                "127.0.0.0/8",
                "::1/128",
                "10.0.0.0/8",
                "172.16.0.0/12",
                "192.168.0.0/16",
                "fc00::/7",
            ]
            .into_iter()
            .map(|value| value.parse().expect("valid built-in CIDR"))
            .collect(),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
struct RecordingConfig {
    segment_seconds: u32,
    buffer_seconds: u32,
}

impl Default for RecordingConfig {
    fn default() -> Self {
        Self {
            segment_seconds: 60,
            buffer_seconds: 86_400,
        }
    }
}

impl ServerConfig {
    fn load(path: &FsPath) -> Result<Self, AnyError> {
        let text = fs::read_to_string(path)?;
        let config: Self = toml::from_str(&text)?;
        config.validate()?;
        Ok(config)
    }

    fn validate(&self) -> Result<(), AnyError> {
        self.upload.bind.parse::<SocketAddr>()?;
        self.webui.bind.parse::<SocketAddr>()?;
        if self.recording.segment_seconds != 60 {
            return Err("recording.segment_seconds must be 60".into());
        }
        if self.recording.buffer_seconds == 0
            || self.recording.buffer_seconds > self.upload.max_replay_seconds
        {
            return Err("recording.buffer_seconds is outside the upload retention limit".into());
        }
        if self.upload.max_envelope_bytes < 1024
            || self.upload.max_envelope_bytes > 16 * 1024 * 1024
        {
            return Err("upload.max_envelope_bytes must be between 1024 and 16777216".into());
        }
        if self.upload.challenge_ttl_seconds == 0
            || self.upload.epoch_idle_seconds == 0
            || self.upload.max_pending_challenges == 0
            || self.upload.max_connections_per_ip == 0
            || self.upload.max_requests_per_minute_per_ip == 0
            || self.upload.max_active_streams == 0
        {
            return Err("upload limits must be non-zero".into());
        }
        if self.webui.allowed_cidrs.is_empty() && !self.webui.allow_public {
            return Err(
                "webui.allowed_cidrs cannot be empty unless public access is enabled".into(),
            );
        }
        Ok(())
    }
}

#[derive(Clone)]
struct UploadState {
    credentials: Arc<RwLock<UploadCredentials>>,
    config: UploadConfig,
    epochs: Arc<Mutex<EpochMap>>,
    streams: Arc<StreamManager>,
    in_flight: Arc<Mutex<HashMap<IpAddr, usize>>>,
    request_rate: Arc<Mutex<HashMap<IpAddr, RateWindow>>>,
}

#[derive(Clone)]
struct UploadCredentials {
    key: UploadKey,
    key_id: String,
    server_instance_id: [u8; ID_BYTES],
}

impl UploadCredentials {
    fn new(key: UploadKey) -> Self {
        let key_id = key.key_id();
        let mut server_instance_id = [0_u8; ID_BYTES];
        rand::rngs::OsRng.fill_bytes(&mut server_instance_id);
        Self {
            key,
            key_id,
            server_instance_id,
        }
    }
}

#[derive(Clone, Copy, Default)]
struct RateWindow {
    window_start: u64,
    count: u32,
}

struct InFlightGuard {
    map: Arc<Mutex<HashMap<IpAddr, usize>>>,
    ip: IpAddr,
}

impl Drop for InFlightGuard {
    fn drop(&mut self) {
        if let Ok(mut map) = self.map.lock() {
            let remove = if let Some(count) = map.get_mut(&self.ip) {
                *count = count.saturating_sub(1);
                *count == 0
            } else {
                false
            };
            if remove {
                map.remove(&self.ip);
            }
        }
    }
}

type EpochMap = HashMap<[u8; ID_BYTES], Arc<Mutex<EpochState>>>;

struct EpochState {
    expires_at: u64,
    last_seen: u64,
    expected_sequence: u64,
    active: bool,
    last_request: Vec<u8>,
    last_response: Vec<u8>,
}

#[derive(Clone)]
struct WebState {
    config: WebUiConfig,
    streams: Arc<StreamManager>,
    control_token: Arc<str>,
    control_sender: mpsc::UnboundedSender<ControlAction>,
    control_peer: IpAddr,
    upload_key_file: Arc<PathBuf>,
    upload_credentials: Arc<RwLock<UploadCredentials>>,
    upload_epochs: Arc<Mutex<EpochMap>>,
    shutdown: watch::Receiver<bool>,
}

const GLOBAL_CACHE_DIRECTORY: &str = "cache";
const GLOBAL_CACHE_METADATA_FILE: &str = "cache.json";
const UPLOAD_SESSIONS_FILE: &str = "upload-sessions.json";

#[derive(Debug, Clone, Serialize, Deserialize)]
struct StreamMetadata {
    cache_id: String,
    audio: AudioConfig,
    buffer_seconds: u32,
    created_unix_seconds: u64,
    #[serde(default)]
    last_device_id: String,
    #[serde(default)]
    migrated_legacy_streams: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct LegacyStreamMetadata {
    server_stream_id: String,
    client_stream_id: String,
    device_id: String,
    audio: AudioConfig,
    buffer_seconds: u32,
    #[serde(default)]
    source_start_sample: u64,
    created_unix_seconds: u64,
    closed: bool,
    incomplete: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct UploadSessionMetadata {
    server_stream_id: String,
    client_stream_id: String,
    device_id: String,
    source_start_sample: u64,
    cache_start_sample: u64,
    #[serde(default)]
    cache_end_sample: Option<u64>,
    created_unix_seconds: u64,
    #[serde(default)]
    last_upload_unix_seconds: u64,
    closed: bool,
    incomplete: bool,
}

struct StreamState {
    metadata: Mutex<StreamMetadata>,
    recorder: Mutex<SegmentedRecorder>,
    last_upload_unix_seconds: AtomicU64,
    level_bits: AtomicU32,
    peak_level_bits: AtomicU32,
}

struct StreamManager {
    data_dir: PathBuf,
    legacy_streams_dir: PathBuf,
    cache_dir: PathBuf,
    recordings_dir: RwLock<Option<PathBuf>>,
    suggested_recordings_dir: PathBuf,
    server_state: Mutex<PersistentServerState>,
    segment_seconds: u32,
    default_buffer_seconds: AtomicU32,
    max_replay_seconds: u32,
    open_lock: Mutex<()>,
    cache: RwLock<Option<Arc<StreamState>>>,
    upload_sessions: RwLock<HashMap<String, UploadSessionMetadata>>,
    client_streams: RwLock<HashMap<String, String>>,
    active_server_stream_id: Mutex<Option<String>>,
    live_sender: watch::Sender<u64>,
    live_sequence: AtomicU64,
}

#[derive(Debug, Clone, Serialize)]
struct StreamView {
    server_stream_id: String,
    client_stream_id: String,
    device_id: String,
    sample_rate: u32,
    channels: u16,
    buffer_seconds: u32,
    total_samples_written: u64,
    retained_start_sample: u64,
    available_seconds: f32,
    segment_count: usize,
    created_unix_seconds: u64,
    last_upload_unix_seconds: u64,
    closed: bool,
    incomplete: bool,
    connected: bool,
    cache_bytes: u64,
    level: f32,
    peak_level: f32,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct LiveSnapshot {
    sequence: u64,
    server_time_millis: u64,
    stream: Option<StreamView>,
}

#[derive(Debug, Clone, Serialize)]
struct RecordingView {
    name: String,
    group: Option<String>,
    bytes: u64,
    modified_unix_seconds: u64,
}

#[derive(Debug, Clone, Serialize)]
struct RecordingGroupView {
    name: String,
    modified_unix_seconds: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct PersistentServerState {
    recording_directory: Option<PathBuf>,
    buffer_seconds: Option<u32>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct ServerSettingsView {
    buffer_seconds: u32,
    buffer_minutes: u32,
    minimum_buffer_seconds: u32,
    maximum_buffer_seconds: u32,
    single_client: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct RecordingDirectoryStatus {
    configured: bool,
    directory: Option<String>,
    suggested_directory: String,
}

impl StreamManager {
    fn open(config: &ServerConfig) -> Result<Self, AnyError> {
        let legacy_streams_dir = config.server.data_dir.join("streams");
        fs::create_dir_all(&legacy_streams_dir)?;
        let cache_dir = config.server.data_dir.join(GLOBAL_CACHE_DIRECTORY);
        let suggested_recordings_dir = config.server.data_dir.join("recordings");
        let server_state = load_server_state(&config.server.data_dir, &suggested_recordings_dir)?;
        let default_buffer_seconds = server_state
            .buffer_seconds
            .unwrap_or(config.recording.buffer_seconds);
        if default_buffer_seconds < config.recording.segment_seconds
            || default_buffer_seconds > config.upload.max_replay_seconds
        {
            return Err("persisted recording buffer is outside the server limit".into());
        }
        let recordings_dir = server_state.recording_directory.clone();
        let (live_sender, _live_receiver) = watch::channel(0_u64);
        let manager = Self {
            data_dir: config.server.data_dir.clone(),
            legacy_streams_dir,
            cache_dir,
            recordings_dir: RwLock::new(recordings_dir),
            suggested_recordings_dir,
            server_state: Mutex::new(server_state),
            segment_seconds: config.recording.segment_seconds,
            default_buffer_seconds: AtomicU32::new(default_buffer_seconds),
            max_replay_seconds: config.upload.max_replay_seconds,
            open_lock: Mutex::new(()),
            cache: RwLock::new(None),
            upload_sessions: RwLock::new(HashMap::new()),
            client_streams: RwLock::new(HashMap::new()),
            active_server_stream_id: Mutex::new(None),
            live_sender,
            live_sequence: AtomicU64::new(0),
        };
        manager.load_or_migrate_cache()?;
        Ok(manager)
    }

    fn publish_live(&self) {
        let sequence = self.live_sequence.fetch_add(1, Ordering::Relaxed) + 1;
        self.live_sender.send_replace(sequence);
    }

    fn subscribe_live(&self) -> watch::Receiver<u64> {
        self.live_sender.subscribe()
    }

    fn live_snapshot(&self) -> LiveSnapshot {
        LiveSnapshot {
            sequence: self.live_sequence.load(Ordering::Relaxed),
            server_time_millis: unix_millis_now(),
            stream: self.stream_views().into_iter().next(),
        }
    }

    fn recording_directory_status(&self) -> RecordingDirectoryStatus {
        let directory = self
            .recordings_dir
            .read()
            .expect("recording directory lock")
            .as_ref()
            .map(|path| path.display().to_string());
        RecordingDirectoryStatus {
            configured: directory.is_some(),
            directory,
            suggested_directory: self.suggested_recordings_dir.display().to_string(),
        }
    }

    fn set_recording_directory(
        &self,
        raw_path: &str,
    ) -> Result<RecordingDirectoryStatus, AnyError> {
        let raw_path = raw_path.trim();
        if raw_path.is_empty() {
            return Err("recording directory cannot be empty".into());
        }
        let path = PathBuf::from(raw_path);
        if !path.is_absolute() {
            return Err("recording directory must be an absolute server path".into());
        }
        fs::create_dir_all(&path)?;
        if !path.is_dir() {
            return Err("recording directory is not a directory".into());
        }
        verify_directory_writable(&path)?;
        let path = path.canonicalize().unwrap_or(path);
        let mut state = self.server_state.lock().expect("server state lock");
        state.recording_directory = Some(path.clone());
        persist_server_state(&self.data_dir, &state)?;
        *self
            .recordings_dir
            .write()
            .expect("recording directory lock") = Some(path.clone());
        Ok(RecordingDirectoryStatus {
            configured: true,
            directory: Some(path.display().to_string()),
            suggested_directory: self.suggested_recordings_dir.display().to_string(),
        })
    }

    fn recording_directory(&self) -> Result<PathBuf, AnyError> {
        self.recordings_dir
            .read()
            .expect("recording directory lock")
            .clone()
            .ok_or_else(|| "recording directory has not been configured in the WebUI".into())
    }

    fn server_settings(&self) -> ServerSettingsView {
        let buffer_seconds = self.default_buffer_seconds.load(Ordering::Relaxed);
        ServerSettingsView {
            buffer_seconds,
            buffer_minutes: buffer_seconds / 60,
            minimum_buffer_seconds: self.segment_seconds,
            maximum_buffer_seconds: self.max_replay_seconds,
            single_client: true,
        }
    }

    fn set_buffer_seconds(&self, buffer_seconds: u32) -> Result<ServerSettingsView, AnyError> {
        if buffer_seconds < self.segment_seconds || buffer_seconds > self.max_replay_seconds {
            return Err(format!(
                "buffer seconds must be between {} and {}",
                self.segment_seconds, self.max_replay_seconds
            )
            .into());
        }
        if let Some(cache) = self.cache_state() {
            cache
                .recorder
                .lock()
                .expect("recorder lock")
                .set_max_replay_seconds(buffer_seconds)?;
            let mut metadata = cache.metadata.lock().expect("metadata lock");
            metadata.buffer_seconds = buffer_seconds;
            self.persist_cache_metadata(&metadata)?;
        }
        let mut state = self.server_state.lock().expect("server state lock");
        state.buffer_seconds = Some(buffer_seconds);
        persist_server_state(&self.data_dir, &state)?;
        self.default_buffer_seconds
            .store(buffer_seconds, Ordering::Relaxed);
        self.publish_live();
        Ok(self.server_settings())
    }

    fn load_or_migrate_cache(&self) -> Result<(), AnyError> {
        if self.cache_dir.join(GLOBAL_CACHE_METADATA_FILE).is_file() {
            return self.load_cache();
        }
        self.migrate_legacy_streams()?;
        if self.cache_dir.join(GLOBAL_CACHE_METADATA_FILE).is_file() {
            self.load_cache()?;
        }
        Ok(())
    }

    fn load_cache(&self) -> Result<(), AnyError> {
        let mut metadata: StreamMetadata = serde_json::from_str(&fs::read_to_string(
            self.cache_dir.join(GLOBAL_CACHE_METADATA_FILE),
        )?)?;
        let configured_buffer_seconds = self.default_buffer_seconds.load(Ordering::Relaxed);
        metadata.buffer_seconds = configured_buffer_seconds;
        let mut core_config = CoreConfig::new(self.cache_dir.join("core"));
        core_config.audio = metadata.audio;
        core_config.segment_seconds = self.segment_seconds;
        core_config.max_replay_seconds = configured_buffer_seconds;
        let recorder = SegmentedRecorder::recover_latest_or_start(core_config)?;
        self.persist_cache_metadata(&metadata)?;

        let sessions_path = self.cache_dir.join(UPLOAD_SESSIONS_FILE);
        let sessions: HashMap<String, UploadSessionMetadata> = if sessions_path.is_file() {
            serde_json::from_str(&fs::read_to_string(sessions_path)?)?
        } else {
            HashMap::new()
        };
        let active = sessions
            .values()
            .filter(|session| !session.closed && !session.incomplete)
            .max_by_key(|session| session.created_unix_seconds)
            .map(|session| session.server_stream_id.clone());
        let last_upload = sessions
            .values()
            .map(|session| session.last_upload_unix_seconds)
            .max()
            .unwrap_or(0);
        let client_streams = sessions
            .values()
            .map(|session| {
                (
                    client_stream_key(&session.device_id, &session.client_stream_id),
                    session.server_stream_id.clone(),
                )
            })
            .collect();
        *self.upload_sessions.write().expect("upload sessions lock") = sessions;
        *self.client_streams.write().expect("client stream map lock") = client_streams;
        *self
            .active_server_stream_id
            .lock()
            .expect("active upload lock") = active;
        *self.cache.write().expect("cache lock") = Some(Arc::new(StreamState {
            metadata: Mutex::new(metadata),
            recorder: Mutex::new(recorder),
            last_upload_unix_seconds: AtomicU64::new(last_upload),
            level_bits: AtomicU32::new(0_f32.to_bits()),
            peak_level_bits: AtomicU32::new(0_f32.to_bits()),
        }));
        self.publish_live();
        Ok(())
    }

    fn migrate_legacy_streams(&self) -> Result<(), AnyError> {
        let mut legacy = Vec::new();
        for entry in fs::read_dir(&self.legacy_streams_dir)? {
            let entry = entry?;
            if !entry.file_type()?.is_dir() {
                continue;
            }
            let metadata_path = entry.path().join("stream.json");
            if !metadata_path.is_file() {
                continue;
            }
            let metadata: LegacyStreamMetadata =
                serde_json::from_str(&fs::read_to_string(metadata_path)?)?;
            legacy.push((metadata, entry.path()));
        }
        legacy.sort_by_key(|(metadata, _)| metadata.created_unix_seconds);
        let Some(audio) = legacy.first().map(|(metadata, _)| metadata.audio) else {
            return Ok(());
        };
        legacy.retain(|(metadata, _)| metadata.audio == audio);
        if legacy.is_empty() {
            return Ok(());
        }

        let staging = self.data_dir.join(format!(
            "{GLOBAL_CACHE_DIRECTORY}.migrating-{}",
            random_hex_id()
        ));
        fs::create_dir_all(&staging)?;
        let buffer_seconds = self.default_buffer_seconds.load(Ordering::Relaxed);
        let mut core_config = CoreConfig::new(staging.join("core"));
        core_config.audio = audio;
        core_config.segment_seconds = self.segment_seconds;
        core_config.max_replay_seconds = buffer_seconds;
        let mut destination = SegmentedRecorder::recover_latest_or_start(core_config)?;
        let mut sessions = HashMap::new();
        let mut migrated = Vec::new();
        let legacy_count = legacy.len();
        let mut last_device_id = String::new();
        let created_unix_seconds = legacy
            .first()
            .map(|(metadata, _)| metadata.created_unix_seconds)
            .unwrap_or_else(unix_seconds_now);

        for (index, (metadata, directory)) in legacy.into_iter().enumerate() {
            let mut source_config = CoreConfig::new(directory.join("core"));
            source_config.audio = metadata.audio;
            source_config.segment_seconds = self.segment_seconds;
            source_config.max_replay_seconds = metadata.buffer_seconds.max(self.segment_seconds);
            let mut source = SegmentedRecorder::recover_latest_or_start(source_config)?;
            let snapshot = source.snapshot()?;
            let cache_start_sample = destination.manifest().total_samples_written;
            let mut start = snapshot.retained_start_sample;
            while start < snapshot.total_samples_written {
                let mut end = start
                    .saturating_add(128 * 1024)
                    .min(snapshot.total_samples_written);
                end -= (end - start) % metadata.audio.channels as u64;
                if end <= start {
                    break;
                }
                destination.push_samples(&snapshot.read_range_i16(start, end)?)?;
                start = end;
            }
            destination.flush()?;
            let cache_end_sample = destination.manifest().total_samples_written;
            let is_latest = index + 1 == legacy_count;
            let closed = metadata.closed || !is_latest;
            let incomplete = metadata.incomplete || (!metadata.closed && !is_latest);
            sessions.insert(
                metadata.server_stream_id.clone(),
                UploadSessionMetadata {
                    server_stream_id: metadata.server_stream_id.clone(),
                    client_stream_id: metadata.client_stream_id.clone(),
                    device_id: metadata.device_id.clone(),
                    source_start_sample: metadata.source_start_sample,
                    cache_start_sample,
                    cache_end_sample: closed.then_some(cache_end_sample),
                    created_unix_seconds: metadata.created_unix_seconds,
                    last_upload_unix_seconds: 0,
                    closed,
                    incomplete,
                },
            );
            last_device_id = metadata.device_id;
            migrated.push(metadata.server_stream_id);
        }
        destination.flush()?;
        drop(destination);
        let metadata = StreamMetadata {
            cache_id: random_hex_id(),
            audio,
            buffer_seconds,
            created_unix_seconds,
            last_device_id,
            migrated_legacy_streams: migrated,
        };
        persist_json_atomic(&staging.join(GLOBAL_CACHE_METADATA_FILE), &metadata)?;
        persist_json_atomic(&staging.join(UPLOAD_SESSIONS_FILE), &sessions)?;
        fs::rename(staging, &self.cache_dir)?;
        Ok(())
    }
    fn create_cache(
        &self,
        audio: AudioConfig,
        device_id: &str,
    ) -> Result<Arc<StreamState>, AnyError> {
        fs::create_dir_all(&self.cache_dir)?;
        let metadata = StreamMetadata {
            cache_id: random_hex_id(),
            audio,
            buffer_seconds: self.default_buffer_seconds.load(Ordering::Relaxed),
            created_unix_seconds: unix_seconds_now(),
            last_device_id: device_id.to_string(),
            migrated_legacy_streams: Vec::new(),
        };
        self.persist_cache_metadata(&metadata)?;
        let mut core_config = CoreConfig::new(self.cache_dir.join("core"));
        core_config.audio = audio;
        core_config.segment_seconds = self.segment_seconds;
        core_config.max_replay_seconds = metadata.buffer_seconds;
        let recorder = SegmentedRecorder::recover_latest_or_start(core_config)?;
        let cache = Arc::new(StreamState {
            metadata: Mutex::new(metadata),
            recorder: Mutex::new(recorder),
            last_upload_unix_seconds: AtomicU64::new(0),
            level_bits: AtomicU32::new(0_f32.to_bits()),
            peak_level_bits: AtomicU32::new(0_f32.to_bits()),
        });
        *self.cache.write().expect("cache lock") = Some(Arc::clone(&cache));
        self.publish_live();
        Ok(cache)
    }

    fn cache_state(&self) -> Option<Arc<StreamState>> {
        self.cache.read().expect("cache lock").clone()
    }

    fn persist_cache_metadata(&self, metadata: &StreamMetadata) -> Result<(), AnyError> {
        persist_json_atomic(&self.cache_dir.join(GLOBAL_CACHE_METADATA_FILE), metadata)
    }

    fn persist_upload_sessions(&self) -> Result<(), AnyError> {
        let sessions = self
            .upload_sessions
            .read()
            .expect("upload sessions lock")
            .clone();
        persist_json_atomic(&self.cache_dir.join(UPLOAD_SESSIONS_FILE), &sessions)
    }

    fn handle(&self, message: ClientMessage) -> ServerResponse {
        match message {
            ClientMessage::Probe => ServerResponse::ok(String::new(), 0, 0),
            ClientMessage::OpenOrResume {
                device_id,
                client_stream_id,
                sample_rate,
                channels,
                sample_format,
                source_start_sample,
            } => self.open_or_resume(
                device_id,
                client_stream_id,
                sample_rate,
                channels,
                sample_format,
                source_start_sample,
            ),
            ClientMessage::Pcm {
                server_stream_id,
                start_sample,
                samples,
            } => self.push_pcm(server_stream_id, start_sample, samples),
            ClientMessage::Close {
                server_stream_id,
                final_sample,
            } => self.close_stream(server_stream_id, final_sample),
            ClientMessage::MarkIncomplete { server_stream_id } => {
                self.mark_incomplete(&server_stream_id)
            }
        }
    }

    #[allow(clippy::too_many_arguments)]
    fn open_or_resume(
        &self,
        device_id: String,
        client_stream_id: String,
        sample_rate: u32,
        channels: u16,
        sample_format: String,
        source_start_sample: u64,
    ) -> ServerResponse {
        if device_id.is_empty()
            || device_id.len() > 256
            || client_stream_id.is_empty()
            || client_stream_id.len() > 256
            || !(8_000..=192_000).contains(&sample_rate)
            || !(1..=8).contains(&channels)
            || !source_start_sample.is_multiple_of(u64::from(channels))
            || sample_format != echoclip_sync_protocol::SAMPLE_FORMAT_PCM_S16LE
        {
            return ServerResponse::rejected("invalid_stream_config");
        }

        let _open_guard = self.open_lock.lock().expect("open lock");
        let client_key = client_stream_key(&device_id, &client_stream_id);
        if let Some(server_id) = self
            .client_streams
            .read()
            .expect("client stream map lock")
            .get(&client_key)
            .cloned()
            && let Some(session) = self
                .upload_sessions
                .read()
                .expect("upload sessions lock")
                .get(&server_id)
                .cloned()
        {
            let Some(cache) = self.cache_state() else {
                return ServerResponse::rejected("cache_missing");
            };
            let metadata = cache.metadata.lock().expect("metadata lock");
            if metadata.audio.sample_rate != sample_rate || metadata.audio.channels != channels {
                return ServerResponse::rejected("stream_format_changed");
            }
            if session.source_start_sample != source_start_sample {
                return ServerResponse::rejected("stream_source_changed");
            }
            if session.incomplete {
                return ServerResponse::rejected("stream_incomplete");
            }
            drop(metadata);
            let total_samples = cache
                .recorder
                .lock()
                .expect("recorder lock")
                .manifest()
                .total_samples_written;
            let cache_end_sample = session.cache_end_sample.unwrap_or(total_samples);
            let received_samples = cache_end_sample.saturating_sub(session.cache_start_sample);
            self.publish_live();
            return ServerResponse::ok(
                server_id,
                source_start_sample.saturating_add(received_samples),
                0,
            );
        }

        let audio = AudioConfig {
            sample_rate,
            channels,
        };
        let cache = match self.cache_state() {
            Some(cache) => cache,
            None => match self.create_cache(audio, &device_id) {
                Ok(cache) => cache,
                Err(error) => {
                    return ServerResponse::rejected(format!("core_start_failed:{error}"));
                }
            },
        };
        {
            let metadata = cache.metadata.lock().expect("metadata lock");
            if metadata.audio != audio {
                return ServerResponse::rejected("cache_format_changed");
            }
        }

        let cache_start_sample = cache
            .recorder
            .lock()
            .expect("recorder lock")
            .manifest()
            .total_samples_written;
        if let Some(previous_id) = self
            .active_server_stream_id
            .lock()
            .expect("active stream lock")
            .take()
            && let Some(previous) = self
                .upload_sessions
                .write()
                .expect("upload sessions lock")
                .get_mut(&previous_id)
        {
            previous.closed = true;
            previous.incomplete = true;
            previous.cache_end_sample = Some(cache_start_sample);
        }

        let server_stream_id = random_hex_id();
        let now = unix_seconds_now();
        let session = UploadSessionMetadata {
            server_stream_id: server_stream_id.clone(),
            client_stream_id,
            device_id: device_id.clone(),
            source_start_sample,
            cache_start_sample,
            cache_end_sample: None,
            created_unix_seconds: now,
            last_upload_unix_seconds: 0,
            closed: false,
            incomplete: false,
        };
        self.upload_sessions
            .write()
            .expect("upload sessions lock")
            .insert(server_stream_id.clone(), session.clone());
        self.client_streams
            .write()
            .expect("client stream map lock")
            .insert(client_key, server_stream_id.clone());
        *self
            .active_server_stream_id
            .lock()
            .expect("active stream lock") = Some(server_stream_id.clone());
        {
            let mut metadata = cache.metadata.lock().expect("metadata lock");
            metadata.last_device_id = device_id;
            if let Err(error) = self.persist_cache_metadata(&metadata) {
                return ServerResponse::rejected(format!("metadata_write_failed:{error}"));
            }
        }
        if let Err(error) = self.persist_upload_sessions() {
            return ServerResponse::rejected(format!("metadata_write_failed:{error}"));
        }
        self.publish_live();
        ServerResponse::ok(server_stream_id, source_start_sample, 0)
    }

    fn push_pcm(
        &self,
        server_stream_id: String,
        start_sample: u64,
        samples: Vec<i16>,
    ) -> ServerResponse {
        let _open_guard = self.open_lock.lock().expect("open lock");
        let active = self
            .active_server_stream_id
            .lock()
            .expect("active stream lock")
            .clone();
        if active.as_deref() != Some(server_stream_id.as_str()) {
            return ServerResponse::rejected("stream_not_active");
        }
        let Some(session) = self
            .upload_sessions
            .read()
            .expect("upload sessions lock")
            .get(&server_stream_id)
            .cloned()
        else {
            return ServerResponse::rejected("stream_not_found");
        };
        if session.closed || session.incomplete {
            return ServerResponse::rejected("stream_closed");
        }
        let Some(cache) = self.cache_state() else {
            return ServerResponse::rejected("cache_missing");
        };
        let audio = cache.metadata.lock().expect("metadata lock").audio;
        if samples.is_empty() || !samples.len().is_multiple_of(usize::from(audio.channels)) {
            return ServerResponse::rejected("invalid_pcm_alignment");
        }

        let mut recorder = cache.recorder.lock().expect("recorder lock");
        let cache_total = recorder.manifest().total_samples_written;
        let expected_sample = session
            .source_start_sample
            .saturating_add(cache_total.saturating_sub(session.cache_start_sample));
        if start_sample != expected_sample {
            return ServerResponse {
                status: ResponseStatus::Gap,
                server_stream_id,
                next_sample: expected_sample,
                accepted_sample_count: 0,
                error_code: "sample_gap".to_string(),
            };
        }
        let (level, peak_level) = pcm_levels(&samples);
        if let Err(error) = recorder
            .push_samples(&samples)
            .and_then(|()| recorder.flush())
        {
            return ServerResponse::rejected(format!("storage_write_failed:{error}"));
        }
        let cache_total = recorder.manifest().total_samples_written;
        drop(recorder);
        let next_sample = session
            .source_start_sample
            .saturating_add(cache_total.saturating_sub(session.cache_start_sample));
        let now = unix_seconds_now();
        cache.last_upload_unix_seconds.store(now, Ordering::Relaxed);
        cache.level_bits.store(level.to_bits(), Ordering::Relaxed);
        cache
            .peak_level_bits
            .store(peak_level.to_bits(), Ordering::Relaxed);
        if let Some(current) = self
            .upload_sessions
            .write()
            .expect("upload sessions lock")
            .get_mut(&server_stream_id)
        {
            current.last_upload_unix_seconds = now;
        }
        self.publish_live();
        ServerResponse::ok(server_stream_id, next_sample, samples.len() as u64)
    }
    fn close_stream(&self, server_stream_id: String, final_sample: u64) -> ServerResponse {
        let _open_guard = self.open_lock.lock().expect("open lock");
        let Some(session) = self
            .upload_sessions
            .read()
            .expect("upload sessions lock")
            .get(&server_stream_id)
            .cloned()
        else {
            return ServerResponse::rejected("stream_not_found");
        };
        let Some(cache) = self.cache_state() else {
            return ServerResponse::rejected("cache_missing");
        };
        let mut recorder = cache.recorder.lock().expect("recorder lock");
        let cache_total = recorder.manifest().total_samples_written;
        let next_sample = session
            .source_start_sample
            .saturating_add(cache_total.saturating_sub(session.cache_start_sample));
        if final_sample != next_sample {
            return ServerResponse {
                status: ResponseStatus::Gap,
                server_stream_id,
                next_sample,
                accepted_sample_count: 0,
                error_code: "final_sample_mismatch".to_string(),
            };
        }
        if let Err(error) = recorder.flush() {
            return ServerResponse::rejected(format!("core_flush_failed:{error}"));
        }
        drop(recorder);
        if let Some(current) = self
            .upload_sessions
            .write()
            .expect("upload sessions lock")
            .get_mut(&server_stream_id)
        {
            current.closed = true;
            current.cache_end_sample = Some(cache_total);
        }
        let mut active = self
            .active_server_stream_id
            .lock()
            .expect("active stream lock");
        if active.as_deref() == Some(server_stream_id.as_str()) {
            *active = None;
        }
        drop(active);
        if let Err(error) = self.persist_upload_sessions() {
            return ServerResponse::rejected(format!("metadata_write_failed:{error}"));
        }
        self.publish_live();
        ServerResponse::ok(server_stream_id, next_sample, 0)
    }

    fn next_sample_for(&self, message: &ClientMessage) -> Option<(String, u64)> {
        let server_stream_id = match message {
            ClientMessage::Pcm {
                server_stream_id, ..
            }
            | ClientMessage::Close {
                server_stream_id, ..
            }
            | ClientMessage::MarkIncomplete { server_stream_id } => server_stream_id.clone(),
            ClientMessage::Probe | ClientMessage::OpenOrResume { .. } => return None,
        };
        let session = self
            .upload_sessions
            .read()
            .expect("upload sessions lock")
            .get(&server_stream_id)?
            .clone();
        let cache_total = self
            .cache_state()?
            .recorder
            .lock()
            .expect("recorder lock")
            .manifest()
            .total_samples_written;
        let cache_end_sample = session.cache_end_sample.unwrap_or(cache_total);
        Some((
            server_stream_id,
            session
                .source_start_sample
                .saturating_add(cache_end_sample.saturating_sub(session.cache_start_sample)),
        ))
    }

    fn mark_incomplete(&self, server_stream_id: &str) -> ServerResponse {
        let _open_guard = self.open_lock.lock().expect("open lock");
        let Some(session) = self
            .upload_sessions
            .read()
            .expect("upload sessions lock")
            .get(server_stream_id)
            .cloned()
        else {
            return ServerResponse::rejected("stream_not_found");
        };
        let Some(cache) = self.cache_state() else {
            return ServerResponse::rejected("cache_missing");
        };
        let cache_total = cache
            .recorder
            .lock()
            .expect("recorder lock")
            .manifest()
            .total_samples_written;
        let next_sample = session
            .source_start_sample
            .saturating_add(cache_total.saturating_sub(session.cache_start_sample));
        if let Some(current) = self
            .upload_sessions
            .write()
            .expect("upload sessions lock")
            .get_mut(server_stream_id)
        {
            current.incomplete = true;
            current.closed = true;
            current.cache_end_sample = Some(cache_total);
        }
        let mut active = self
            .active_server_stream_id
            .lock()
            .expect("active stream lock");
        if active.as_deref() == Some(server_stream_id) {
            *active = None;
        }
        drop(active);
        if let Err(error) = self.persist_upload_sessions() {
            return ServerResponse::rejected(format!("metadata_write_failed:{error}"));
        }
        self.publish_live();
        ServerResponse::ok(server_stream_id.to_string(), next_sample, 0)
    }

    fn stream_views(&self) -> Vec<StreamView> {
        let Some(cache) = self.cache_state() else {
            return Vec::new();
        };
        let metadata = cache.metadata.lock().expect("metadata lock").clone();
        let recorder = cache.recorder.lock().expect("recorder lock");
        let manifest = recorder.manifest();
        let active_id = self
            .active_server_stream_id
            .lock()
            .expect("active stream lock")
            .clone();
        let active_session = active_id.as_ref().and_then(|id| {
            self.upload_sessions
                .read()
                .expect("upload sessions lock")
                .get(id)
                .cloned()
        });
        let latest_session = active_session.or_else(|| {
            self.upload_sessions
                .read()
                .expect("upload sessions lock")
                .values()
                .max_by_key(|session| session.created_unix_seconds)
                .cloned()
        });
        let connected = latest_session
            .as_ref()
            .is_some_and(|session| !session.closed && !session.incomplete);
        let retained_start_sample = manifest
            .segments
            .first()
            .map(|segment| segment.start_sample)
            .unwrap_or(manifest.total_samples_written);
        vec![StreamView {
            server_stream_id: metadata.cache_id,
            client_stream_id: latest_session
                .as_ref()
                .map(|session| session.client_stream_id.clone())
                .unwrap_or_default(),
            device_id: latest_session
                .as_ref()
                .map(|session| session.device_id.clone())
                .unwrap_or(metadata.last_device_id),
            sample_rate: metadata.audio.sample_rate,
            channels: metadata.audio.channels,
            buffer_seconds: metadata.buffer_seconds,
            total_samples_written: manifest.total_samples_written,
            retained_start_sample,
            available_seconds: recorder.available_seconds(),
            segment_count: manifest.segments.len(),
            created_unix_seconds: metadata.created_unix_seconds,
            last_upload_unix_seconds: cache.last_upload_unix_seconds.load(Ordering::Relaxed),
            closed: !connected,
            incomplete: latest_session
                .as_ref()
                .is_some_and(|session| session.incomplete),
            connected,
            cache_bytes: manifest
                .segments
                .iter()
                .map(|segment| segment.sample_count.saturating_mul(2))
                .sum(),
            level: f32::from_bits(cache.level_bits.load(Ordering::Relaxed)),
            peak_level: f32::from_bits(cache.peak_level_bits.load(Ordering::Relaxed)),
        }]
    }

    fn save_latest(&self, _stream_id: &str, seconds: u32) -> Result<RecordingView, AnyError> {
        if seconds == 0 || seconds > self.max_replay_seconds {
            return Err("requested save duration is outside the configured limit".into());
        }
        let cache = self.cache_state().ok_or("cache is empty")?;
        let snapshot = cache.recorder.lock().expect("recorder lock").snapshot()?;
        let name = format!(
            "echoclip-{}-{}s-{}.wav",
            unix_seconds_now(),
            seconds,
            &random_hex_id()[..8]
        );
        let recordings_dir = self.recording_directory()?;
        let path = recordings_dir.join(&name);
        snapshot.save_latest_wav(seconds, &path)?;
        recording_view(&path)
    }

    fn save_range(
        &self,
        _stream_id: &str,
        start_seconds_ago: u64,
        end_seconds_ago: u64,
    ) -> Result<RecordingView, AnyError> {
        if start_seconds_ago == 0
            || start_seconds_ago <= end_seconds_ago
            || start_seconds_ago > self.max_replay_seconds as u64
        {
            return Err("requested save range is outside the configured limit".into());
        }
        let cache = self.cache_state().ok_or("cache is empty")?;
        let snapshot = cache.recorder.lock().expect("recorder lock").snapshot()?;
        let samples_per_second = snapshot.audio.sample_rate as u64 * snapshot.audio.channels as u64;
        let start_sample = snapshot
            .total_samples_written
            .saturating_sub(start_seconds_ago.saturating_mul(samples_per_second))
            .max(snapshot.retained_start_sample);
        let end_sample = snapshot
            .total_samples_written
            .saturating_sub(end_seconds_ago.saturating_mul(samples_per_second))
            .min(snapshot.total_samples_written);
        if end_sample <= start_sample {
            return Err("requested range is empty or outside the retained audio".into());
        }
        let name = format!(
            "echoclip-{}-{}s-{}s-{}.wav",
            unix_seconds_now(),
            start_seconds_ago,
            end_seconds_ago,
            &random_hex_id()[..8]
        );
        let recordings_dir = self.recording_directory()?;
        let path = recordings_dir.join(&name);
        snapshot.save_range_wav_by_sample(start_sample, end_sample, &path)?;
        recording_view(&path)
    }

    fn recordings(&self) -> Result<Vec<RecordingView>, AnyError> {
        let recordings_dir = self.recording_directory()?;
        let mut result = Vec::new();
        for entry in fs::read_dir(recordings_dir)? {
            let entry = entry?;
            if entry.file_type()?.is_file()
                && entry.path().extension().and_then(|value| value.to_str()) == Some("wav")
            {
                result.push(recording_view(&entry.path())?);
            }
        }
        result.sort_by_key(|recording| std::cmp::Reverse(recording.modified_unix_seconds));
        Ok(result)
    }

    fn recording_path(&self, name: &str) -> Result<PathBuf, AnyError> {
        validate_recording_name(name)?;
        let recordings_dir = self.recording_directory()?;
        let path = recordings_dir.join(name);
        if !path.is_file() {
            return Err("recording not found".into());
        }
        Ok(path)
    }

    fn rename_recording(&self, old_name: &str, new_name: &str) -> Result<RecordingView, AnyError> {
        let old_path = self.recording_path(old_name)?;
        validate_recording_name(new_name)?;
        let recordings_dir = self.recording_directory()?;
        let new_path = recordings_dir.join(new_name);
        if new_path.exists() {
            return Err("recording already exists".into());
        }
        fs::rename(old_path, &new_path)?;
        recording_view(&new_path)
    }

    fn recording_groups(&self) -> Result<Vec<RecordingGroupView>, AnyError> {
        let recordings_dir = self.recording_directory()?;
        let mut groups = Vec::new();
        for entry in fs::read_dir(recordings_dir)? {
            let entry = entry?;
            let name = entry
                .file_name()
                .to_str()
                .ok_or("recording group name is not UTF-8")?
                .to_string();
            if entry.file_type()?.is_dir() && !name.starts_with('.') {
                let modified_unix_seconds = entry
                    .metadata()?
                    .modified()
                    .ok()
                    .and_then(|value| value.duration_since(UNIX_EPOCH).ok())
                    .map(|value| value.as_secs())
                    .unwrap_or(0);
                groups.push(RecordingGroupView {
                    name,
                    modified_unix_seconds,
                });
            }
        }
        groups.sort_by_key(|group| group.name.to_lowercase());
        Ok(groups)
    }

    fn group_path(&self, name: &str) -> Result<PathBuf, AnyError> {
        validate_group_name(name)?;
        let path = self.recording_directory()?.join(name);
        let metadata = fs::symlink_metadata(&path)?;
        if metadata.file_type().is_symlink() || !metadata.is_dir() {
            return Err("recording group not found".into());
        }
        Ok(path)
    }

    fn create_group(&self, name: &str) -> Result<RecordingGroupView, AnyError> {
        validate_group_name(name)?;
        let path = self.recording_directory()?.join(name);
        if path.exists() {
            return Err("recording group already exists".into());
        }
        fs::create_dir(&path)?;
        Ok(RecordingGroupView {
            name: name.to_string(),
            modified_unix_seconds: unix_seconds_now(),
        })
    }

    fn rename_group(&self, old_name: &str, new_name: &str) -> Result<RecordingGroupView, AnyError> {
        let old_path = self.group_path(old_name)?;
        validate_group_name(new_name)?;
        let new_path = self.recording_directory()?.join(new_name);
        if new_path.exists() {
            return Err("recording group already exists".into());
        }
        fs::rename(old_path, &new_path)?;
        Ok(RecordingGroupView {
            name: new_name.to_string(),
            modified_unix_seconds: unix_seconds_now(),
        })
    }

    fn delete_group(&self, name: &str) -> Result<(), AnyError> {
        fs::remove_dir_all(self.group_path(name)?)?;
        Ok(())
    }

    fn library_recording_path(&self, group: Option<&str>, name: &str) -> Result<PathBuf, AnyError> {
        validate_recording_name(name)?;
        let directory = match group {
            Some(group) => self.group_path(group)?,
            None => self.recording_directory()?,
        };
        let path = directory.join(name);
        if !path.is_file() {
            return Err("recording not found".into());
        }
        Ok(path)
    }

    fn library_recordings(&self) -> Result<Vec<RecordingView>, AnyError> {
        let recordings_dir = self.recording_directory()?;
        let mut recordings = Vec::new();
        for entry in fs::read_dir(&recordings_dir)? {
            let entry = entry?;
            let file_type = entry.file_type()?;
            if file_type.is_file()
                && entry.path().extension().and_then(|value| value.to_str()) == Some("wav")
            {
                recordings.push(recording_view(&entry.path())?);
                continue;
            }
            if !file_type.is_dir() {
                continue;
            }
            let group = entry
                .file_name()
                .to_str()
                .ok_or("recording group name is not UTF-8")?
                .to_string();
            if group.starts_with('.') {
                continue;
            }
            for child in fs::read_dir(entry.path())? {
                let child = child?;
                if child.file_type()?.is_file()
                    && child.path().extension().and_then(|value| value.to_str()) == Some("wav")
                {
                    let mut view = recording_view(&child.path())?;
                    view.group = Some(group.clone());
                    recordings.push(view);
                }
            }
        }
        recordings.sort_by_key(|recording| std::cmp::Reverse(recording.modified_unix_seconds));
        Ok(recordings)
    }

    fn rename_library_recording(
        &self,
        group: Option<&str>,
        old_name: &str,
        new_name: &str,
    ) -> Result<RecordingView, AnyError> {
        let old_path = self.library_recording_path(group, old_name)?;
        validate_recording_name(new_name)?;
        let directory = old_path
            .parent()
            .ok_or("recording has no parent directory")?;
        let new_path = directory.join(new_name);
        if new_path.exists() {
            return Err("recording already exists".into());
        }
        fs::rename(old_path, &new_path)?;
        let mut view = recording_view(&new_path)?;
        view.group = group.map(str::to_string);
        Ok(view)
    }

    fn move_library_recording(
        &self,
        source_group: Option<&str>,
        name: &str,
        target_group: Option<&str>,
    ) -> Result<RecordingView, AnyError> {
        let source = self.library_recording_path(source_group, name)?;
        let target_directory = match target_group {
            Some(group) => self.group_path(group)?,
            None => self.recording_directory()?,
        };
        let target = target_directory.join(name);
        if source != target && target.exists() {
            return Err("recording already exists in the target group".into());
        }
        if source != target {
            fs::rename(source, &target)?;
        }
        let mut view = recording_view(&target)?;
        view.group = target_group.map(str::to_string);
        Ok(view)
    }
}
#[derive(Debug, Deserialize)]
struct SaveRequest {
    seconds: u32,
}

#[derive(Debug, Deserialize)]
struct SaveRangeRequest {
    start_seconds_ago: u64,
    end_seconds_ago: u64,
}

#[derive(Debug, Deserialize)]
struct RenameRequest {
    name: String,
}

#[derive(Debug, Deserialize)]
struct GroupRequest {
    name: String,
}

#[derive(Debug, Deserialize)]
struct MoveRecordingRequest {
    group: Option<String>,
}

#[derive(Debug, Deserialize)]
struct RecordingDirectoryRequest {
    path: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ServerSettingsRequest {
    buffer_seconds: u32,
}

#[derive(Debug, Serialize)]
struct ApiError {
    error: String,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ResetKeyResponse {
    key: String,
    key_id: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ControlAction {
    Stop,
    Reboot,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RuntimeDescriptor {
    pid: u32,
    address: SocketAddr,
    token: String,
}

struct RuntimeDescriptorGuard {
    path: PathBuf,
    token: String,
}

impl Drop for RuntimeDescriptorGuard {
    fn drop(&mut self) {
        let matches_current = fs::read(&self.path)
            .ok()
            .and_then(|bytes| serde_json::from_slice::<RuntimeDescriptor>(&bytes).ok())
            .is_some_and(|descriptor| descriptor.token == self.token);
        if matches_current {
            let _ = fs::remove_file(&self.path);
        }
    }
}

enum CliCommand {
    Serve,
    Stop,
    Reboot,
    ResetKey,
    GenerateKey,
    Help,
    Version,
}

#[tokio::main]
async fn main() {
    if let Err(error) = run().await {
        eprintln!("echoclip: {error}");
        std::process::exit(1);
    }
}

async fn run() -> Result<(), AnyError> {
    let args: Vec<String> = std::env::args().collect();
    let executable = std::env::current_exe().unwrap_or_else(|_| PathBuf::from("echoclip"));
    let exe_dir = executable
        .parent()
        .map(FsPath::to_path_buf)
        .unwrap_or_else(|| PathBuf::from("."));
    let runtime_path = runtime_descriptor_path(&executable);

    match parse_cli_command(&args)? {
        CliCommand::Serve => run_service_loop(&args, &exe_dir, &runtime_path).await,
        CliCommand::Stop => request_control(ControlAction::Stop, &runtime_path).await,
        CliCommand::Reboot => request_control(ControlAction::Reboot, &runtime_path).await,
        CliCommand::ResetKey => request_key_reset(&runtime_path).await,
        CliCommand::GenerateKey => {
            let output =
                option_value(&args, "--output").ok_or("missing --output for key generate")?;
            let output_path = PathBuf::from(output);
            let output_path = if output_path.is_absolute() {
                output_path
            } else {
                exe_dir.join(output_path)
            };
            let key = generate_key(&output_path)?;
            print_upload_key(&key);
            Ok(())
        }
        CliCommand::Help => {
            print_help();
            Ok(())
        }
        CliCommand::Version => {
            println!("echoclip {}", env!("CARGO_PKG_VERSION"));
            Ok(())
        }
    }
}

fn parse_cli_command(args: &[String]) -> Result<CliCommand, AnyError> {
    match args.get(1).map(String::as_str) {
        None | Some("serve") => Ok(CliCommand::Serve),
        Some("stop") => Ok(CliCommand::Stop),
        Some("reboot") => Ok(CliCommand::Reboot),
        Some("reset") if args.get(2).map(String::as_str) == Some("key") => Ok(CliCommand::ResetKey),
        Some("key") if args.get(2).map(String::as_str) == Some("generate") => {
            Ok(CliCommand::GenerateKey)
        }
        Some("-h" | "--help" | "help") => Ok(CliCommand::Help),
        Some("-V" | "--version" | "version") => Ok(CliCommand::Version),
        Some(value) if value.starts_with('-') => Ok(CliCommand::Serve),
        Some(value) => Err(format!("unknown command: {value}; run 'echoclip --help'").into()),
    }
}

fn print_help() {
    println!(
        "EchoClip Server {version}

Usage:
  echoclip [serve] [--config PATH]
  echoclip stop
  echoclip reboot
  echoclip reset key
  echoclip key generate --output PATH

Commands:
  serve      Start the upload service and WebUI (default)
  stop       Gracefully stop the globally running EchoClip instance
  reboot     Gracefully restart it and reload server.toml
  reset key  Replace the running server's upload key after typing yes
",
        version = env!("CARGO_PKG_VERSION")
    );
}

async fn run_service_loop(
    args: &[String],
    exe_dir: &FsPath,
    runtime_path: &FsPath,
) -> Result<(), AnyError> {
    loop {
        let (config, config_path) = load_server_config(args, exe_dir)?;
        match serve_once(config, &config_path, runtime_path).await? {
            ControlAction::Stop => return Ok(()),
            ControlAction::Reboot => eprintln!("Reboot requested; reloading configuration"),
        }
    }
}

fn load_server_config(
    args: &[String],
    exe_dir: &FsPath,
) -> Result<(ServerConfig, PathBuf), AnyError> {
    let explicit_config = option_value(args, "--config")
        .map(PathBuf::from)
        .or_else(|| {
            std::env::var_os("ECHOCLIP_CONFIG")
                .filter(|value| !value.is_empty())
                .map(PathBuf::from)
        });
    let adjacent_config = exe_dir.join("server.toml");
    #[cfg(unix)]
    let default_config = if adjacent_config.is_file() {
        adjacent_config
    } else {
        let system_config = PathBuf::from("/etc/echoclip/server.toml");
        if system_config.is_file() {
            system_config
        } else {
            adjacent_config
        }
    };
    #[cfg(not(unix))]
    let default_config = adjacent_config;

    let config_path = explicit_config.clone().unwrap_or(default_config);
    let mut config = if config_path.is_file() {
        ServerConfig::load(&config_path)?
    } else if explicit_config.is_none() {
        eprintln!(
            "server.toml not found at {}; using defaults next to the executable",
            config_path.display()
        );
        ServerConfig::default()
    } else {
        return Err(format!("config file not found: {}", config_path.display()).into());
    };

    if config.server.data_dir.is_relative() {
        config.server.data_dir = exe_dir.join(&config.server.data_dir);
    }
    if config.upload.key_file.is_relative() {
        config.upload.key_file = exe_dir.join(&config.upload.key_file);
    }
    config.validate()?;
    Ok((config, config_path))
}

async fn serve_once(
    config: ServerConfig,
    config_path: &FsPath,
    runtime_path: &FsPath,
) -> Result<ControlAction, AnyError> {
    eprintln!("Config: {}", config_path.display());
    eprintln!("Data dir: {}", config.server.data_dir.display());
    eprintln!("Upload key file: {}", config.upload.key_file.display());

    if !config.upload.key_file.is_file() {
        eprintln!("Upload key does not exist; generating it now");
        let key = generate_key(&config.upload.key_file)?;
        print_upload_key(&key);
    }
    let key = load_key(&config.upload.key_file)?;
    let upload_credentials = Arc::new(RwLock::new(UploadCredentials::new(key)));
    let key_id = upload_credentials
        .read()
        .expect("upload credentials lock")
        .key_id
        .clone();
    let upload_epochs = Arc::new(Mutex::new(HashMap::new()));
    let streams = Arc::new(StreamManager::open(&config)?);
    let (control_sender, mut control_receiver) = mpsc::unbounded_channel();
    let (shutdown_sender, shutdown_receiver) = watch::channel(false);
    let control_token: Arc<str> = format!("{}{}", random_hex_id(), random_hex_id()).into();

    let upload_state = UploadState {
        credentials: Arc::clone(&upload_credentials),
        config: config.upload.clone(),
        epochs: Arc::clone(&upload_epochs),
        streams: Arc::clone(&streams),
        in_flight: Arc::new(Mutex::new(HashMap::new())),
        request_rate: Arc::new(Mutex::new(HashMap::new())),
    };
    let upload_address: SocketAddr = config.upload.bind.parse()?;
    let web_address: SocketAddr = config.webui.bind.parse()?;
    let web_state = WebState {
        config: config.webui.clone(),
        streams,
        control_token: Arc::clone(&control_token),
        control_sender,
        control_peer: local_control_address(web_address).ip(),
        upload_key_file: Arc::new(config.upload.key_file.clone()),
        upload_credentials,
        upload_epochs,
        shutdown: shutdown_receiver.clone(),
    };
    let upload_listener = tokio::net::TcpListener::bind(upload_address).await?;
    let web_listener = tokio::net::TcpListener::bind(web_address).await?;
    let actual_upload_address = upload_listener.local_addr()?;
    let actual_web_address = web_listener.local_addr()?;

    if config.webui.allow_public {
        eprintln!(
            "WARNING: WebUI public access is enabled. EchoClip does not encrypt or authenticate WebUI HTTP traffic."
        );
    }
    eprintln!("EchoClip upload key id: {key_id}");
    eprintln!("Encrypted App upload listening on http://{actual_upload_address}");
    eprintln!("WebUI listening on http://{actual_web_address}");
    eprintln!("Log level: {}", config.server.log_level);

    let upload_app = Router::new()
        .route("/healthz", get(health))
        .route("/upload/v1/challenge", post(challenge))
        .route("/upload/v1/envelope", post(envelope))
        .with_state(upload_state);
    let web_app = Router::new()
        .route("/", get(web_index))
        .route("/api/status", get(web_status))
        .route("/api/events", get(web_events))
        .route("/api/settings", get(web_settings).put(web_update_settings))
        .route(
            "/api/setup/recording-directory",
            post(web_set_recording_directory),
        )
        .route("/api/streams", get(web_streams))
        .route("/api/streams/{id}/save", post(web_save))
        .route("/api/streams/{id}/save_range", post(web_save_range))
        .route("/api/recordings", get(web_recordings))
        .route(
            "/api/library/groups",
            get(web_groups).post(web_create_group),
        )
        .route(
            "/api/library/groups/{name}",
            patch(web_rename_group).delete(web_delete_group),
        )
        .route("/api/library/recordings", get(web_library_recordings))
        .route(
            "/api/library/recordings/{group}/{name}",
            get(web_library_download)
                .patch(web_library_rename)
                .delete(web_library_delete),
        )
        .route(
            "/api/library/recordings/{group}/{name}/move",
            post(web_library_move),
        )
        .route("/api/control/{action}", post(web_control))
        .route(
            "/api/recordings/{name}",
            get(web_download).patch(web_rename).delete(web_delete),
        )
        .with_state(web_state);

    let descriptor = RuntimeDescriptor {
        pid: std::process::id(),
        address: local_control_address(actual_web_address),
        token: control_token.to_string(),
    };
    let runtime_guard = persist_runtime_descriptor(runtime_path, &descriptor)?;
    let upload_shutdown = shutdown_receiver.clone();
    let web_shutdown = shutdown_receiver;
    let servers = async move {
        tokio::try_join!(
            axum::serve(
                upload_listener,
                upload_app.into_make_service_with_connect_info::<SocketAddr>(),
            )
            .with_graceful_shutdown(wait_for_shutdown(upload_shutdown)),
            axum::serve(
                web_listener,
                web_app.into_make_service_with_connect_info::<SocketAddr>(),
            )
            .with_graceful_shutdown(wait_for_shutdown(web_shutdown)),
        )?;
        Ok::<(), std::io::Error>(())
    };
    tokio::pin!(servers);

    let action = tokio::select! {
        result = &mut servers => {
            result?;
            return Err("EchoClip listeners stopped unexpectedly".into());
        }
        action = control_receiver.recv() => {
            action.ok_or("control channel closed unexpectedly")?
        }
        _ = tokio::signal::ctrl_c() => {
            eprintln!("Shutdown requested");
            ControlAction::Stop
        }
    };

    let _ = shutdown_sender.send(true);
    servers.await?;
    drop(runtime_guard);
    Ok(action)
}

async fn wait_for_shutdown(mut receiver: watch::Receiver<bool>) {
    while !*receiver.borrow() {
        if receiver.changed().await.is_err() {
            break;
        }
    }
}

async fn request_control(action: ControlAction, runtime_path: &FsPath) -> Result<(), AnyError> {
    let descriptor = read_running_descriptor(runtime_path)?;
    let action_name = match action {
        ControlAction::Stop => "stop",
        ControlAction::Reboot => "reboot",
    };
    let response = send_control_request(&descriptor, action_name).await?;
    if !response.starts_with(b"HTTP/1.1 202 ") {
        return Err(format!(
            "server rejected {action_name}: {}",
            http_status_line(&response)
        )
        .into());
    }
    let deadline = tokio::time::Instant::now() + Duration::from_secs(15);
    loop {
        match read_runtime_descriptor(runtime_path) {
            Err(_) if action == ControlAction::Stop => {
                println!("EchoClip stopped.");
                return Ok(());
            }
            Ok(current)
                if action == ControlAction::Reboot
                    && !constant_time_eq(current.token.as_bytes(), descriptor.token.as_bytes()) =>
            {
                println!("EchoClip rebooted.");
                return Ok(());
            }
            Ok(current)
                if action == ControlAction::Stop
                    && !constant_time_eq(current.token.as_bytes(), descriptor.token.as_bytes()) =>
            {
                return Err("another EchoClip instance started while stop was pending".into());
            }
            _ if tokio::time::Instant::now() >= deadline => {
                return Err(format!("timed out waiting for EchoClip to {action_name}").into());
            }
            _ => tokio::time::sleep(Duration::from_millis(50)).await,
        }
    }
}

async fn request_key_reset(runtime_path: &FsPath) -> Result<(), AnyError> {
    let descriptor = read_running_descriptor(runtime_path)?;
    println!("WARNING: resetting the upload key immediately invalidates the current key.");
    print!("Type yes to continue: ");
    io::stdout().flush()?;
    let mut confirmation = String::new();
    io::stdin().read_line(&mut confirmation)?;
    if !reset_key_confirmed(&confirmation) {
        println!("EchoClip upload key reset cancelled.");
        return Ok(());
    }

    let response = send_control_request(&descriptor, "reset-key").await?;
    if !response.starts_with(b"HTTP/1.1 200 ") {
        return Err(format!("server rejected reset-key: {}", http_status_line(&response)).into());
    }
    let reset: ResetKeyResponse = serde_json::from_slice(http_response_body(&response)?)?;
    println!("EchoClip upload key reset.");
    println!("EchoClip upload key: {}", reset.key);
    println!("Upload key id: {}", reset.key_id);
    Ok(())
}

fn reset_key_confirmed(value: &str) -> bool {
    value.trim() == "yes"
}

fn read_running_descriptor(runtime_path: &FsPath) -> Result<RuntimeDescriptor, AnyError> {
    read_runtime_descriptor(runtime_path).map_err(|error| {
        format!(
            "EchoClip is not running or its runtime descriptor is unavailable ({}): {error}",
            runtime_path.display()
        )
        .into()
    })
}

async fn send_control_request(
    descriptor: &RuntimeDescriptor,
    action_name: &str,
) -> Result<Vec<u8>, AnyError> {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    let mut stream = tokio::net::TcpStream::connect(descriptor.address).await?;
    let request = format!(
        concat!(
            "POST /api/control/{} HTTP/1.1\r\n",
            "Host: {}\r\n",
            "x-echoclip-control-token: {}\r\n",
            "Content-Length: 0\r\n",
            "Connection: close\r\n",
            "\r\n"
        ),
        action_name, descriptor.address, descriptor.token
    );
    stream.write_all(request.as_bytes()).await?;
    let mut response = Vec::new();
    stream.read_to_end(&mut response).await?;
    Ok(response)
}

fn http_status_line(response: &[u8]) -> String {
    String::from_utf8_lossy(
        response
            .split(|byte| *byte == b'\n')
            .next()
            .unwrap_or(response),
    )
    .trim()
    .to_string()
}

fn http_response_body(response: &[u8]) -> Result<&[u8], AnyError> {
    response
        .windows(4)
        .position(|window| window == b"\r\n\r\n")
        .map(|position| &response[position + 4..])
        .ok_or_else(|| "invalid HTTP response from EchoClip".into())
}
fn runtime_descriptor_path(executable: &FsPath) -> PathBuf {
    let mut hasher = DefaultHasher::new();
    executable.to_string_lossy().hash(&mut hasher);
    std::env::temp_dir().join(format!("echoclip-{:016x}.control.json", hasher.finish()))
}

fn local_control_address(address: SocketAddr) -> SocketAddr {
    match address {
        SocketAddr::V4(address) if address.ip().is_unspecified() => {
            SocketAddr::from(([127, 0, 0, 1], address.port()))
        }
        SocketAddr::V6(address) if address.ip().is_unspecified() => {
            SocketAddr::from(([0, 0, 0, 0, 0, 0, 0, 1], address.port()))
        }
        address => address,
    }
}

fn persist_runtime_descriptor(
    path: &FsPath,
    descriptor: &RuntimeDescriptor,
) -> Result<RuntimeDescriptorGuard, AnyError> {
    let temporary = path.with_extension(format!("{}.tmp", descriptor.token));
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let mut file = options.open(&temporary)?;
    file.write_all(&serde_json::to_vec(descriptor)?)?;
    file.flush()?;
    drop(file);
    #[cfg(windows)]
    if path.exists() {
        let metadata = fs::symlink_metadata(path)?;
        if metadata.file_type().is_symlink() || !metadata.is_file() {
            let _ = fs::remove_file(&temporary);
            return Err("unsafe EchoClip runtime descriptor path".into());
        }
        fs::remove_file(path)?;
    }
    fs::rename(&temporary, path)?;
    Ok(RuntimeDescriptorGuard {
        path: path.to_path_buf(),
        token: descriptor.token.clone(),
    })
}

fn read_runtime_descriptor(path: &FsPath) -> Result<RuntimeDescriptor, AnyError> {
    let descriptor: RuntimeDescriptor = serde_json::from_slice(&fs::read(path)?)?;
    if descriptor.token.len() != 64
        || !descriptor
            .token
            .bytes()
            .all(|byte| byte.is_ascii_hexdigit())
    {
        return Err("invalid EchoClip runtime descriptor".into());
    }
    Ok(descriptor)
}

fn constant_time_eq(left: &[u8], right: &[u8]) -> bool {
    if left.len() != right.len() {
        return false;
    }
    left.iter()
        .zip(right)
        .fold(0_u8, |difference, (left, right)| {
            difference | (left ^ right)
        })
        == 0
}
async fn health() -> &'static str {
    "ok"
}

fn enter_upload_request(state: &UploadState, ip: IpAddr) -> Result<InFlightGuard, StatusCode> {
    let now = unix_seconds_now();
    {
        let mut rates = state.request_rate.lock().expect("request rate lock");
        rates.retain(|_, window| now.saturating_sub(window.window_start) < 60);
        let window = rates.entry(ip).or_insert(RateWindow {
            window_start: now,
            count: 0,
        });
        if now.saturating_sub(window.window_start) >= 60 {
            window.window_start = now;
            window.count = 1;
        } else {
            window.count = window.count.saturating_add(1);
        }
        if window.count > state.config.max_requests_per_minute_per_ip {
            return Err(StatusCode::TOO_MANY_REQUESTS);
        }
    }
    {
        let mut in_flight = state.in_flight.lock().expect("in-flight lock");
        let count = in_flight.entry(ip).or_insert(0);
        *count = count.saturating_add(1);
        if *count > state.config.max_connections_per_ip {
            *count = count.saturating_sub(1);
            let remove = *count == 0;
            if remove {
                in_flight.remove(&ip);
            }
            return Err(StatusCode::TOO_MANY_REQUESTS);
        }
    }
    Ok(InFlightGuard {
        map: Arc::clone(&state.in_flight),
        ip,
    })
}

fn log_security_event(category: &str, peer: IpAddr, key_id: &str) {
    eprintln!(
        "security_event unix_seconds={} category={} peer={} key_id={}",
        unix_seconds_now(),
        category,
        peer,
        key_id
    );
}

#[derive(Debug)]
struct EnvelopeRejection {
    status: StatusCode,
    body: Vec<u8>,
}

impl EnvelopeRejection {
    fn plain(status: StatusCode) -> Self {
        Self {
            status,
            body: Vec::new(),
        }
    }
}

async fn challenge(
    State(state): State<UploadState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    body: Bytes,
) -> Response {
    let _guard = match enter_upload_request(&state, peer.ip()) {
        Ok(guard) => guard,
        Err(status) => return generic_upload_error(status),
    };
    if body.len() > 4096 {
        return generic_upload_error(StatusCode::PAYLOAD_TOO_LARGE);
    }
    let request: ChallengeRequest = match serde_json::from_slice(body.as_ref()) {
        Ok(request) => request,
        Err(_) => return generic_upload_error(StatusCode::BAD_REQUEST),
    };
    let credentials = state.credentials.read().expect("upload credentials lock");
    if request.key_id != credentials.key_id {
        log_security_event("challenge_unknown_key_id", peer.ip(), &request.key_id);
        return generic_upload_error(StatusCode::UNAUTHORIZED);
    }
    let now = unix_seconds_now();
    let mut epochs = state.epochs.lock().expect("epoch map lock");
    epochs.retain(|_, epoch| {
        let epoch = epoch.lock().expect("epoch lock");
        if epoch.active {
            epoch
                .last_seen
                .saturating_add(state.config.epoch_idle_seconds)
                >= now
        } else {
            epoch.expires_at >= now
        }
    });
    if epochs.len() >= state.config.max_pending_challenges {
        return generic_upload_error(StatusCode::TOO_MANY_REQUESTS);
    }
    let epoch_id = loop {
        let mut candidate = [0_u8; ID_BYTES];
        rand::rngs::OsRng.fill_bytes(&mut candidate);
        if !epochs.contains_key(&candidate) {
            break candidate;
        }
    };
    let expires_at = now.saturating_add(state.config.challenge_ttl_seconds);
    epochs.insert(
        epoch_id,
        Arc::new(Mutex::new(EpochState {
            expires_at,
            last_seen: now,
            expected_sequence: 0,
            active: false,
            last_request: Vec::new(),
            last_response: Vec::new(),
        })),
    );
    Json(ChallengeResponse::new(
        credentials.server_instance_id,
        epoch_id,
        expires_at,
    ))
    .into_response()
}

async fn envelope(
    State(state): State<UploadState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    body: Bytes,
) -> Response {
    let _guard = match enter_upload_request(&state, peer.ip()) {
        Ok(guard) => guard,
        Err(status) => return generic_upload_error(status),
    };
    if body.len() > state.config.max_envelope_bytes {
        return generic_upload_error(StatusCode::PAYLOAD_TOO_LARGE);
    }
    match tokio::task::spawn_blocking(move || process_envelope(&state, body.to_vec(), peer.ip()))
        .await
    {
        Ok(Ok(response)) => binary_response(StatusCode::OK, response),
        Ok(Err(rejection)) => {
            if rejection.body.is_empty() {
                generic_upload_error(rejection.status)
            } else {
                binary_response(rejection.status, rejection.body)
            }
        }
        Err(_) => generic_upload_error(StatusCode::INTERNAL_SERVER_ERROR),
    }
}

fn process_envelope(
    state: &UploadState,
    body: Vec<u8>,
    peer: IpAddr,
) -> Result<Vec<u8>, EnvelopeRejection> {
    let parsed =
        parse_envelope(&body).map_err(|_| EnvelopeRejection::plain(StatusCode::BAD_REQUEST))?;
    let credentials = state.credentials.read().expect("upload credentials lock");
    if parsed.header.key_id != credentials.key_id {
        log_security_event("upload_unknown_key_id", peer, &parsed.header.key_id);
        return Err(EnvelopeRejection::plain(StatusCode::UNAUTHORIZED));
    }
    let epoch = state
        .epochs
        .lock()
        .expect("epoch map lock")
        .get(&parsed.header.epoch_id)
        .cloned()
        .ok_or_else(|| {
            log_security_event("upload_unknown_epoch", peer, &credentials.key_id);
            EnvelopeRejection::plain(StatusCode::UNAUTHORIZED)
        })?;
    let mut epoch = epoch.lock().expect("epoch lock");
    let now = unix_seconds_now();
    if (!epoch.active && epoch.expires_at < now)
        || (epoch.active
            && epoch
                .last_seen
                .saturating_add(state.config.epoch_idle_seconds)
                < now)
    {
        log_security_event("upload_expired_epoch", peer, &credentials.key_id);
        return Err(EnvelopeRejection::plain(StatusCode::UNAUTHORIZED));
    }
    if parsed.header.sequence < epoch.expected_sequence
        && body == epoch.last_request
        && !epoch.last_response.is_empty()
    {
        epoch.last_seen = now;
        return Ok(epoch.last_response.clone());
    }
    if parsed.header.sequence < epoch.expected_sequence {
        log_security_event(
            "upload_duplicate_sequence_mismatch",
            peer,
            &credentials.key_id,
        );
        return Err(EnvelopeRejection::plain(StatusCode::CONFLICT));
    }
    let keys = credentials
        .key
        .derive_session(credentials.server_instance_id, parsed.header.epoch_id)
        .map_err(|_| {
            log_security_event("upload_key_derivation_failed", peer, &credentials.key_id);
            EnvelopeRejection::plain(StatusCode::UNAUTHORIZED)
        })?;
    if parsed.header.sequence > epoch.expected_sequence {
        let (header, message) = open_client_message(&keys, &body).map_err(|_| {
            log_security_event("upload_auth_failed", peer, &credentials.key_id);
            EnvelopeRejection::plain(StatusCode::UNAUTHORIZED)
        })?;
        log_security_event("upload_sequence_gap", peer, &credentials.key_id);
        let (server_stream_id, next_sample) = state
            .streams
            .next_sample_for(&message)
            .unwrap_or_else(|| (String::new(), 0));
        let response = ServerResponse {
            status: ResponseStatus::Gap,
            server_stream_id,
            next_sample,
            accepted_sample_count: 0,
            error_code: "sequence_gap".to_string(),
        };
        let encrypted = seal_server_response(
            &keys,
            &credentials.key_id,
            header.epoch_id,
            header.sequence,
            &response,
        )
        .map_err(|_| EnvelopeRejection::plain(StatusCode::INTERNAL_SERVER_ERROR))?;
        return Err(EnvelopeRejection {
            status: StatusCode::CONFLICT,
            body: encrypted,
        });
    }
    let (header, message) = open_client_message(&keys, &body).map_err(|_| {
        log_security_event("upload_auth_failed", peer, &credentials.key_id);
        EnvelopeRejection::plain(StatusCode::UNAUTHORIZED)
    })?;
    let response = state.streams.handle(message);
    let encrypted = seal_server_response(
        &keys,
        &credentials.key_id,
        header.epoch_id,
        header.sequence,
        &response,
    )
    .map_err(|_| EnvelopeRejection::plain(StatusCode::INTERNAL_SERVER_ERROR))?;
    epoch.active = true;
    epoch.last_seen = now;
    epoch.expected_sequence = epoch.expected_sequence.saturating_add(1);
    epoch.last_request = body;
    epoch.last_response = encrypted.clone();
    Ok(encrypted)
}
async fn web_index(
    State(state): State<WebState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
) -> Response {
    if !web_allowed(&state.config, peer.ip()) {
        return StatusCode::FORBIDDEN.into_response();
    }
    Html(WEB_UI).into_response()
}

async fn web_status(
    State(state): State<WebState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
) -> Response {
    if !web_allowed(&state.config, peer.ip()) {
        return StatusCode::FORBIDDEN.into_response();
    }
    let recording = state.streams.recording_directory_status();
    let settings = state.streams.server_settings();
    Json(serde_json::json!({
        "ok": true,
        "webuiPublic": state.config.allow_public,
        "serverTime": unix_seconds_now(),
        "recordingDirectoryConfigured": recording.configured,
        "recordingDirectory": recording.directory,
        "suggestedRecordingDirectory": recording.suggested_directory,
        "bufferSeconds": settings.buffer_seconds,
        "bufferMinutes": settings.buffer_minutes,
        "maximumBufferSeconds": settings.maximum_buffer_seconds,
        "singleClient": settings.single_client,
    }))
    .into_response()
}

async fn web_events(
    State(state): State<WebState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
) -> Response {
    if !web_allowed(&state.config, peer.ip()) {
        return StatusCode::FORBIDDEN.into_response();
    }
    let streams = Arc::clone(&state.streams);
    let shutdown = wait_for_shutdown(state.shutdown.clone());
    let events = WatchStream::new(streams.subscribe_live()).map(move |_| {
        let snapshot = streams.live_snapshot();
        let event = Event::default()
            .event("live")
            .id(snapshot.sequence.to_string())
            .json_data(snapshot)
            .expect("live snapshot is serializable");
        Ok::<Event, Infallible>(event)
    });
    Sse::new(events.take_until(shutdown))
        .keep_alive(
            KeepAlive::new()
                .interval(Duration::from_secs(15))
                .text("keep-alive"),
        )
        .into_response()
}

async fn web_settings(
    State(state): State<WebState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
) -> Response {
    if !web_allowed(&state.config, peer.ip()) {
        return StatusCode::FORBIDDEN.into_response();
    }
    Json(state.streams.server_settings()).into_response()
}

async fn web_update_settings(
    State(state): State<WebState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    Json(request): Json<ServerSettingsRequest>,
) -> Response {
    if !web_allowed(&state.config, peer.ip()) {
        return StatusCode::FORBIDDEN.into_response();
    }
    let streams = Arc::clone(&state.streams);
    match tokio::task::spawn_blocking(move || streams.set_buffer_seconds(request.buffer_seconds))
        .await
    {
        Ok(Ok(settings)) => Json(settings).into_response(),
        Ok(Err(error)) => api_error(StatusCode::BAD_REQUEST, error.to_string()),
        Err(error) => api_error(StatusCode::INTERNAL_SERVER_ERROR, error.to_string()),
    }
}
async fn web_set_recording_directory(
    State(state): State<WebState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    Json(request): Json<RecordingDirectoryRequest>,
) -> Response {
    if !web_allowed(&state.config, peer.ip()) {
        return StatusCode::FORBIDDEN.into_response();
    }
    let streams = Arc::clone(&state.streams);
    match tokio::task::spawn_blocking(move || streams.set_recording_directory(&request.path)).await
    {
        Ok(Ok(status)) => (StatusCode::CREATED, Json(status)).into_response(),
        Ok(Err(error)) => api_error(StatusCode::BAD_REQUEST, error.to_string()),
        Err(error) => api_error(StatusCode::INTERNAL_SERVER_ERROR, error.to_string()),
    }
}

async fn web_streams(
    State(state): State<WebState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
) -> Response {
    if !web_allowed(&state.config, peer.ip()) {
        return StatusCode::FORBIDDEN.into_response();
    }
    Json(state.streams.stream_views()).into_response()
}

async fn web_save(
    State(state): State<WebState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    Path(id): Path<String>,
    Json(request): Json<SaveRequest>,
) -> Response {
    if !web_allowed(&state.config, peer.ip()) {
        return StatusCode::FORBIDDEN.into_response();
    }
    let streams = Arc::clone(&state.streams);
    match tokio::task::spawn_blocking(move || streams.save_latest(&id, request.seconds)).await {
        Ok(Ok(recording)) => (StatusCode::CREATED, Json(recording)).into_response(),
        Ok(Err(error)) => api_error(StatusCode::BAD_REQUEST, error.to_string()),
        Err(error) => api_error(StatusCode::INTERNAL_SERVER_ERROR, error.to_string()),
    }
}

async fn web_save_range(
    State(state): State<WebState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    Path(id): Path<String>,
    Json(request): Json<SaveRangeRequest>,
) -> Response {
    if !web_allowed(&state.config, peer.ip()) {
        return StatusCode::FORBIDDEN.into_response();
    }
    let streams = Arc::clone(&state.streams);
    match tokio::task::spawn_blocking(move || {
        streams.save_range(&id, request.start_seconds_ago, request.end_seconds_ago)
    })
    .await
    {
        Ok(Ok(recording)) => (StatusCode::CREATED, Json(recording)).into_response(),
        Ok(Err(error)) => api_error(StatusCode::BAD_REQUEST, error.to_string()),
        Err(error) => api_error(StatusCode::INTERNAL_SERVER_ERROR, error.to_string()),
    }
}

async fn web_recordings(
    State(state): State<WebState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
) -> Response {
    if !web_allowed(&state.config, peer.ip()) {
        return StatusCode::FORBIDDEN.into_response();
    }
    match state.streams.recordings() {
        Ok(recordings) => Json(recordings).into_response(),
        Err(error) => api_error(StatusCode::INTERNAL_SERVER_ERROR, error.to_string()),
    }
}

fn decode_library_group(value: &str) -> Result<Option<&str>, AnyError> {
    if value == "__ungrouped__" {
        Ok(None)
    } else {
        validate_group_name(value)?;
        Ok(Some(value))
    }
}

async fn web_groups(
    State(state): State<WebState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
) -> Response {
    if !web_allowed(&state.config, peer.ip()) {
        return StatusCode::FORBIDDEN.into_response();
    }
    match state.streams.recording_groups() {
        Ok(groups) => Json(groups).into_response(),
        Err(error) => api_error(StatusCode::INTERNAL_SERVER_ERROR, error.to_string()),
    }
}

async fn web_create_group(
    State(state): State<WebState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    Json(request): Json<GroupRequest>,
) -> Response {
    if !web_allowed(&state.config, peer.ip()) {
        return StatusCode::FORBIDDEN.into_response();
    }
    match state.streams.create_group(request.name.trim()) {
        Ok(group) => (StatusCode::CREATED, Json(group)).into_response(),
        Err(error) => api_error(StatusCode::BAD_REQUEST, error.to_string()),
    }
}

async fn web_rename_group(
    State(state): State<WebState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    Path(name): Path<String>,
    Json(request): Json<GroupRequest>,
) -> Response {
    if !web_allowed(&state.config, peer.ip()) {
        return StatusCode::FORBIDDEN.into_response();
    }
    match state.streams.rename_group(&name, request.name.trim()) {
        Ok(group) => Json(group).into_response(),
        Err(error) => api_error(StatusCode::BAD_REQUEST, error.to_string()),
    }
}

async fn web_delete_group(
    State(state): State<WebState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    Path(name): Path<String>,
) -> Response {
    if !web_allowed(&state.config, peer.ip()) {
        return StatusCode::FORBIDDEN.into_response();
    }
    match state.streams.delete_group(&name) {
        Ok(()) => StatusCode::NO_CONTENT.into_response(),
        Err(error) => api_error(StatusCode::BAD_REQUEST, error.to_string()),
    }
}

async fn web_library_recordings(
    State(state): State<WebState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
) -> Response {
    if !web_allowed(&state.config, peer.ip()) {
        return StatusCode::FORBIDDEN.into_response();
    }
    match state.streams.library_recordings() {
        Ok(recordings) => Json(recordings).into_response(),
        Err(error) => api_error(StatusCode::INTERNAL_SERVER_ERROR, error.to_string()),
    }
}

async fn web_library_download(
    State(state): State<WebState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Path((group, name)): Path<(String, String)>,
) -> Response {
    if !web_allowed(&state.config, peer.ip()) {
        return StatusCode::FORBIDDEN.into_response();
    }
    let group = match decode_library_group(&group) {
        Ok(group) => group,
        Err(error) => return api_error(StatusCode::BAD_REQUEST, error.to_string()),
    };
    let path = match state.streams.library_recording_path(group, &name) {
        Ok(path) => path,
        Err(error) => return api_error(StatusCode::NOT_FOUND, error.to_string()),
    };
    match audio_file_response(&path, &name, &headers) {
        Ok(response) => response,
        Err(error) => api_error(StatusCode::INTERNAL_SERVER_ERROR, error.to_string()),
    }
}

async fn web_library_rename(
    State(state): State<WebState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    Path((group, name)): Path<(String, String)>,
    Json(request): Json<RenameRequest>,
) -> Response {
    if !web_allowed(&state.config, peer.ip()) {
        return StatusCode::FORBIDDEN.into_response();
    }
    let group = match decode_library_group(&group) {
        Ok(group) => group,
        Err(error) => return api_error(StatusCode::BAD_REQUEST, error.to_string()),
    };
    match state
        .streams
        .rename_library_recording(group, &name, request.name.trim())
    {
        Ok(recording) => Json(recording).into_response(),
        Err(error) => api_error(StatusCode::BAD_REQUEST, error.to_string()),
    }
}

async fn web_library_delete(
    State(state): State<WebState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    Path((group, name)): Path<(String, String)>,
) -> Response {
    if !web_allowed(&state.config, peer.ip()) {
        return StatusCode::FORBIDDEN.into_response();
    }
    let group = match decode_library_group(&group) {
        Ok(group) => group,
        Err(error) => return api_error(StatusCode::BAD_REQUEST, error.to_string()),
    };
    let path = match state.streams.library_recording_path(group, &name) {
        Ok(path) => path,
        Err(error) => return api_error(StatusCode::NOT_FOUND, error.to_string()),
    };
    match fs::remove_file(path) {
        Ok(()) => StatusCode::NO_CONTENT.into_response(),
        Err(error) => api_error(StatusCode::INTERNAL_SERVER_ERROR, error.to_string()),
    }
}

async fn web_library_move(
    State(state): State<WebState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    Path((group, name)): Path<(String, String)>,
    Json(request): Json<MoveRecordingRequest>,
) -> Response {
    if !web_allowed(&state.config, peer.ip()) {
        return StatusCode::FORBIDDEN.into_response();
    }
    let source_group = match decode_library_group(&group) {
        Ok(group) => group,
        Err(error) => return api_error(StatusCode::BAD_REQUEST, error.to_string()),
    };
    let target_group = request
        .group
        .as_deref()
        .map(str::trim)
        .filter(|name| !name.is_empty());
    match state
        .streams
        .move_library_recording(source_group, &name, target_group)
    {
        Ok(recording) => Json(recording).into_response(),
        Err(error) => api_error(StatusCode::BAD_REQUEST, error.to_string()),
    }
}
async fn web_download(
    State(state): State<WebState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Path(name): Path<String>,
) -> Response {
    if !web_allowed(&state.config, peer.ip()) {
        return StatusCode::FORBIDDEN.into_response();
    }
    let path = match state.streams.recording_path(&name) {
        Ok(path) => path,
        Err(error) => return api_error(StatusCode::NOT_FOUND, error.to_string()),
    };
    match audio_file_response(&path, &name, &headers) {
        Ok(response) => response,
        Err(error) => api_error(StatusCode::INTERNAL_SERVER_ERROR, error.to_string()),
    }
}

async fn web_delete(
    State(state): State<WebState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    Path(name): Path<String>,
) -> Response {
    if !web_allowed(&state.config, peer.ip()) {
        return StatusCode::FORBIDDEN.into_response();
    }
    let path = match state.streams.recording_path(&name) {
        Ok(path) => path,
        Err(error) => return api_error(StatusCode::NOT_FOUND, error.to_string()),
    };
    match fs::remove_file(path) {
        Ok(()) => StatusCode::NO_CONTENT.into_response(),
        Err(error) => api_error(StatusCode::INTERNAL_SERVER_ERROR, error.to_string()),
    }
}

async fn web_rename(
    State(state): State<WebState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    Path(name): Path<String>,
    Json(request): Json<RenameRequest>,
) -> Response {
    if !web_allowed(&state.config, peer.ip()) {
        return StatusCode::FORBIDDEN.into_response();
    }
    match state.streams.rename_recording(&name, request.name.trim()) {
        Ok(recording) => Json(recording).into_response(),
        Err(error) => api_error(StatusCode::BAD_REQUEST, error.to_string()),
    }
}

async fn web_control(
    State(state): State<WebState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    Path(action): Path<String>,
    headers: HeaderMap,
) -> Response {
    let allowed_peer = if state.control_peer.is_loopback() {
        peer.ip().is_loopback()
    } else {
        peer.ip() == state.control_peer
    };
    if !allowed_peer {
        return StatusCode::FORBIDDEN.into_response();
    }
    let Some(token) = headers
        .get("x-echoclip-control-token")
        .and_then(|value| value.to_str().ok())
    else {
        return StatusCode::UNAUTHORIZED.into_response();
    };
    if !constant_time_eq(token.as_bytes(), state.control_token.as_bytes()) {
        return StatusCode::UNAUTHORIZED.into_response();
    }
    if action == "reset-key" {
        let key_file = Arc::clone(&state.upload_key_file);
        let credentials = Arc::clone(&state.upload_credentials);
        let epochs = Arc::clone(&state.upload_epochs);
        return match tokio::task::spawn_blocking(move || {
            reset_upload_key(&key_file, &credentials, &epochs)
        })
        .await
        {
            Ok(Ok(response)) => Json(response).into_response(),
            Ok(Err(error)) => api_error(StatusCode::INTERNAL_SERVER_ERROR, error.to_string()),
            Err(error) => api_error(StatusCode::INTERNAL_SERVER_ERROR, error.to_string()),
        };
    }
    let action = match action.as_str() {
        "stop" => ControlAction::Stop,
        "reboot" => ControlAction::Reboot,
        _ => return StatusCode::NOT_FOUND.into_response(),
    };
    if state.control_sender.send(action).is_err() {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    }
    StatusCode::ACCEPTED.into_response()
}

fn web_allowed(config: &WebUiConfig, peer: IpAddr) -> bool {
    config.allow_public
        || config
            .allowed_cidrs
            .iter()
            .any(|network| network.contains(&peer))
}

fn audio_file_response(
    path: &FsPath,
    name: &str,
    request_headers: &HeaderMap,
) -> Result<Response, AnyError> {
    let total = fs::metadata(path)?.len();
    let requested = request_headers
        .get(header::RANGE)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| parse_byte_range(value, total));
    let (status, start, end) = requested
        .map(|(start, end)| (StatusCode::PARTIAL_CONTENT, start, end))
        .unwrap_or_else(|| (StatusCode::OK, 0, total.saturating_sub(1)));
    let byte_count = if total == 0 {
        0
    } else {
        end.saturating_sub(start) + 1
    };
    let mut file = fs::File::open(path)?;
    file.seek(SeekFrom::Start(start))?;
    let mut bytes = vec![0_u8; usize::try_from(byte_count)?];
    file.read_exact(&mut bytes)?;
    let mut response = (status, bytes).into_response();
    response
        .headers_mut()
        .insert(header::CONTENT_TYPE, HeaderValue::from_static("audio/wav"));
    response
        .headers_mut()
        .insert(header::ACCEPT_RANGES, HeaderValue::from_static("bytes"));
    if status == StatusCode::PARTIAL_CONTENT
        && let Ok(value) = HeaderValue::from_str(&format!("bytes {start}-{end}/{total}"))
    {
        response.headers_mut().insert(header::CONTENT_RANGE, value);
    }
    if let Ok(value) = HeaderValue::from_str(&format!("inline; filename=\"{name}\"")) {
        response
            .headers_mut()
            .insert(header::CONTENT_DISPOSITION, value);
    }
    Ok(response)
}

fn parse_byte_range(value: &str, total: u64) -> Option<(u64, u64)> {
    if total == 0 || !value.starts_with("bytes=") || value.contains(',') {
        return None;
    }
    let (start, end) = value[6..].split_once('-')?;
    if start.is_empty() {
        let suffix = end.parse::<u64>().ok()?.min(total);
        return (suffix > 0).then(|| (total - suffix, total - 1));
    }
    let start = start.parse::<u64>().ok()?;
    if start >= total {
        return None;
    }
    let end = if end.is_empty() {
        total - 1
    } else {
        end.parse::<u64>().ok()?.min(total - 1)
    };
    (end >= start).then_some((start, end))
}
fn binary_response(status: StatusCode, bytes: Vec<u8>) -> Response {
    let mut response = (status, bytes).into_response();
    response.headers_mut().insert(
        header::CONTENT_TYPE,
        HeaderValue::from_static("application/octet-stream"),
    );
    response
}

fn generic_upload_error(status: StatusCode) -> Response {
    (status, "request rejected").into_response()
}

fn api_error(status: StatusCode, error: String) -> Response {
    (status, Json(ApiError { error })).into_response()
}

fn load_server_state(
    data_dir: &FsPath,
    suggested_directory: &FsPath,
) -> Result<PersistentServerState, AnyError> {
    fs::create_dir_all(data_dir)?;
    let state_path = data_dir.join("server-state.json");
    let mut state = if state_path.is_file() {
        serde_json::from_slice::<PersistentServerState>(&fs::read(&state_path)?)?
    } else {
        PersistentServerState::default()
    };
    if let Some(directory) = state.recording_directory.take() {
        if !directory.is_absolute() {
            return Err(format!(
                "recording directory in {} must be absolute",
                state_path.display()
            )
            .into());
        }
        fs::create_dir_all(&directory)?;
        if !directory.is_dir() {
            return Err("configured recording directory is not a directory".into());
        }
        verify_directory_writable(&directory)?;
        state.recording_directory = Some(directory.canonicalize().unwrap_or(directory));
        return Ok(state);
    }

    // Migrate installations that ran the earlier server preview, which always
    // created data_dir/recordings before the WebUI setup flow existed.
    if suggested_directory.is_dir() {
        let directory = suggested_directory
            .canonicalize()
            .unwrap_or_else(|_| suggested_directory.to_path_buf());
        verify_directory_writable(&directory)?;
        state.recording_directory = Some(directory);
        persist_server_state(data_dir, &state)?;
    }
    Ok(state)
}
fn persist_server_state(data_dir: &FsPath, state: &PersistentServerState) -> Result<(), AnyError> {
    let path = data_dir.join("server-state.json");
    let temporary = data_dir.join(format!("server-state-{}.tmp", random_hex_id()));
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let mut file = options.open(&temporary)?;
    file.write_all(&serde_json::to_vec_pretty(state)?)?;
    file.write_all(b"\n")?;
    file.flush()?;
    drop(file);
    #[cfg(windows)]
    if path.exists() {
        fs::remove_file(&path)?;
    }
    fs::rename(&temporary, &path)?;
    Ok(())
}

fn verify_directory_writable(directory: &FsPath) -> Result<(), AnyError> {
    let probe = directory.join(format!(".echoclip-write-test-{}", random_hex_id()));
    let result = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&probe)
        .and_then(|mut file| file.write_all(b"echoclip"));
    let _ = fs::remove_file(&probe);
    result.map_err(|error| {
        format!(
            "recording directory is not writable ({}): {error}",
            directory.display()
        )
        .into()
    })
}

fn validate_recording_name(name: &str) -> Result<(), AnyError> {
    if name.is_empty()
        || name.len() > 255
        || name.contains('/')
        || name.contains('\\')
        || name == ".wav"
        || !name.to_ascii_lowercase().ends_with(".wav")
    {
        return Err("invalid recording name".into());
    }
    Ok(())
}

fn validate_group_name(name: &str) -> Result<(), AnyError> {
    if name.is_empty()
        || name.len() > 255
        || name.starts_with('.')
        || name.contains('/')
        || name.contains('\\')
        || name == "__ungrouped__"
    {
        return Err("invalid recording group name".into());
    }
    Ok(())
}
fn option_value<'a>(args: &'a [String], name: &str) -> Option<&'a str> {
    args.windows(2)
        .find(|pair| pair[0] == name)
        .map(|pair| pair[1].as_str())
}

fn generate_key(path: &FsPath) -> Result<UploadKey, AnyError> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let key = UploadKey::generate();
    write_new_key_file(path, &key)?;
    eprintln!("Generated EchoClip upload key at {}", path.display());
    eprintln!("Upload key id: {}", key.key_id());
    Ok(key)
}

fn print_upload_key(key: &UploadKey) {
    println!("EchoClip upload key: {}", key.to_base64());
}

fn reset_upload_key(
    path: &FsPath,
    credentials: &RwLock<UploadCredentials>,
    epochs: &Mutex<EpochMap>,
) -> Result<ResetKeyResponse, AnyError> {
    let key = UploadKey::generate();
    let key_id = key.key_id();
    let encoded = key.to_base64();
    let replacement = path.with_extension(format!("{}.tmp", random_hex_id()));
    write_new_key_file(&replacement, &key)?;

    let mut credentials = match credentials.write() {
        Ok(credentials) => credentials,
        Err(_) => {
            let _ = fs::remove_file(&replacement);
            return Err("upload credentials lock poisoned".into());
        }
    };
    let mut epochs = match epochs.lock() {
        Ok(epochs) => epochs,
        Err(_) => {
            let _ = fs::remove_file(&replacement);
            return Err("upload epoch lock poisoned".into());
        }
    };
    if let Err(error) = replace_key_file(path, &replacement) {
        let _ = fs::remove_file(&replacement);
        return Err(error);
    }
    *credentials = UploadCredentials::new(key);
    epochs.clear();
    drop(epochs);
    drop(credentials);

    eprintln!("EchoClip upload key reset; new key id: {key_id}");
    Ok(ResetKeyResponse {
        key: encoded,
        key_id,
    })
}

fn write_new_key_file(path: &FsPath, key: &UploadKey) -> Result<(), AnyError> {
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let mut file = options.open(path)?;
    file.write_all(key.to_base64().as_bytes())?;
    file.write_all(b"\n")?;
    file.flush()?;
    file.sync_all()?;
    Ok(())
}

fn replace_key_file(path: &FsPath, replacement: &FsPath) -> Result<(), AnyError> {
    #[cfg(unix)]
    {
        fs::rename(replacement, path)?;
    }
    #[cfg(windows)]
    {
        if path.exists() {
            let metadata = fs::symlink_metadata(path)?;
            if metadata.file_type().is_symlink() || !metadata.is_file() {
                return Err("unsafe upload key path".into());
            }
            fs::remove_file(path)?;
        }
        fs::rename(replacement, path)?;
    }
    #[cfg(not(any(unix, windows)))]
    {
        if path.exists() {
            fs::remove_file(path)?;
        }
        fs::rename(replacement, path)?;
    }
    Ok(())
}
fn load_key(path: &FsPath) -> Result<UploadKey, AnyError> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mode = fs::metadata(path)?.permissions().mode() & 0o777;
        if mode & 0o077 != 0 {
            return Err(format!(
                "upload key permissions are too broad ({mode:o}); expected 0600 or stricter"
            )
            .into());
        }
    }
    let bytes = fs::read(path)?;
    if bytes.len() == 32 {
        return Ok(UploadKey::from_bytes(
            bytes.try_into().expect("checked key length"),
        ));
    }
    let text = std::str::from_utf8(&bytes)?;
    Ok(UploadKey::from_base64(text)?)
}

fn persist_json_atomic<T: Serialize>(path: &FsPath, value: &T) -> Result<(), AnyError> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let file_name = path
        .file_name()
        .and_then(|value| value.to_str())
        .ok_or("metadata path is not UTF-8")?;
    let temporary = path.with_file_name(format!("{file_name}.tmp"));
    fs::write(&temporary, serde_json::to_vec_pretty(value)?)?;
    if path.exists() {
        fs::remove_file(path)?;
    }
    fs::rename(temporary, path)?;
    Ok(())
}

fn pcm_levels(samples: &[i16]) -> (f32, f32) {
    let mut sum_squares = 0_f64;
    let mut peak = 0_u32;
    for sample in samples {
        peak = peak.max(i32::from(*sample).unsigned_abs());
        let normalized = f64::from(*sample) / f64::from(i16::MAX);
        sum_squares += normalized * normalized;
    }
    let rms = (sum_squares / samples.len() as f64).sqrt() as f32;
    let peak = peak as f32 / i16::MAX as f32;
    (rms.clamp(0.0, 1.0), peak.clamp(0.0, 1.0))
}

fn recording_view(path: &FsPath) -> Result<RecordingView, AnyError> {
    let metadata = fs::metadata(path)?;
    Ok(RecordingView {
        name: path
            .file_name()
            .and_then(|value| value.to_str())
            .ok_or("recording name is not UTF-8")?
            .to_string(),
        group: None,
        bytes: metadata.len(),
        modified_unix_seconds: metadata
            .modified()
            .ok()
            .and_then(|value| value.duration_since(UNIX_EPOCH).ok())
            .map(|value| value.as_secs())
            .unwrap_or(0),
    })
}

fn client_stream_key(device_id: &str, client_stream_id: &str) -> String {
    format!("{device_id}\0{client_stream_id}")
}

fn random_hex_id() -> String {
    let mut bytes = [0_u8; 16];
    rand::rngs::OsRng.fill_bytes(&mut bytes);
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn unix_seconds_now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

fn unix_millis_now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
        .try_into()
        .unwrap_or(u64::MAX)
}

const WEB_UI: &str = include_str!("webui.html");
#[cfg(test)]
mod tests {
    use super::*;
    use echoclip_sync_protocol::{open_server_response, seal_client_message};

    #[test]
    fn default_webui_rejects_public_addresses() {
        let config = WebUiConfig::default();
        assert!(web_allowed(&config, "127.0.0.1".parse().unwrap()));
        assert!(web_allowed(&config, "192.168.1.10".parse().unwrap()));
        assert!(!web_allowed(&config, "8.8.8.8".parse().unwrap()));
    }

    #[test]
    fn default_upload_limit_allows_paced_realtime_and_retries() {
        let requests_per_minute = ServerConfig::default()
            .upload
            .max_requests_per_minute_per_ip;
        // The client sends at most four PCM ticks per second and may retry each
        // envelope once, so normal recovery must remain well below the limit.
        assert!(requests_per_minute >= 8 * 60);
        assert_eq!(requests_per_minute, 3_600);
    }

    #[test]
    fn public_webui_setting_is_explicit() {
        let config = WebUiConfig {
            allow_public: true,
            ..WebUiConfig::default()
        };
        assert!(web_allowed(&config, "8.8.8.8".parse().unwrap()));
    }

    #[test]
    fn first_webui_visit_requires_and_persists_an_absolute_recording_directory() {
        let temporary = std::env::temp_dir().join(format!(
            "echoclip-recording-setup-test-{}-{}",
            unix_seconds_now(),
            random_hex_id()
        ));
        let mut config = ServerConfig::default();
        config.server.data_dir = temporary.join("data");
        let manager = StreamManager::open(&config).unwrap();

        assert!(!manager.recording_directory_status().configured);
        assert!(manager.set_recording_directory("relative/path").is_err());

        let selected = temporary.join("saved-recordings");
        let status = manager
            .set_recording_directory(selected.to_str().unwrap())
            .unwrap();
        assert!(status.configured);
        assert!(selected.is_dir());
        assert!(config.server.data_dir.join("server-state.json").is_file());
        let changed = temporary.join("changed-recordings");
        manager
            .set_recording_directory(changed.to_str().unwrap())
            .unwrap();
        drop(manager);

        let reopened = StreamManager::open(&config).unwrap();
        assert!(reopened.recording_directory_status().configured);
        assert_eq!(
            reopened.recording_directory().unwrap(),
            changed.canonicalize().unwrap()
        );
        drop(reopened);
        let _ = fs::remove_dir_all(temporary);
    }

    #[test]
    fn live_updates_are_coalesced_and_expose_the_latest_cache_state() {
        let temporary = std::env::temp_dir().join(format!(
            "echoclip-live-updates-test-{}-{}",
            unix_seconds_now(),
            random_hex_id()
        ));
        let mut config = ServerConfig::default();
        config.server.data_dir = temporary.clone();
        let manager = StreamManager::open(&config).unwrap();
        let mut updates = manager.subscribe_live();
        assert_eq!(*updates.borrow(), 0);

        let opened = manager.open_or_resume(
            "device-1".to_string(),
            "client-stream-1".to_string(),
            48_000,
            1,
            echoclip_sync_protocol::SAMPLE_FORMAT_PCM_S16LE.to_string(),
            0,
        );
        assert_eq!(opened.status, ResponseStatus::Ok);
        assert!(updates.has_changed().unwrap());
        let after_open = *updates.borrow_and_update();
        assert!(after_open >= 2);

        let pushed = manager.push_pcm(opened.server_stream_id, 0, vec![1_000, -2_000, 500, 0]);
        assert_eq!(pushed.status, ResponseStatus::Ok);
        assert!(updates.has_changed().unwrap());
        let after_pcm = *updates.borrow_and_update();
        assert!(after_pcm > after_open);

        let snapshot = manager.live_snapshot();
        assert_eq!(snapshot.sequence, after_pcm);
        assert!(snapshot.server_time_millis >= unix_seconds_now().saturating_mul(1_000));
        let stream = snapshot.stream.unwrap();
        assert_eq!(stream.total_samples_written, 4);
        assert!(stream.connected);
        assert!(stream.peak_level > 0.0);

        drop(updates);
        drop(manager);
        let _ = fs::remove_dir_all(temporary);
    }

    #[test]
    fn webui_buffer_setting_is_server_owned_and_persistent() {
        let temporary = std::env::temp_dir().join(format!(
            "echoclip-server-settings-test-{}-{}",
            unix_seconds_now(),
            random_hex_id()
        ));
        let mut config = ServerConfig::default();
        config.server.data_dir = temporary.clone();
        config.recording.buffer_seconds = 600;
        let manager = StreamManager::open(&config).unwrap();

        assert_eq!(manager.server_settings().buffer_seconds, 600);
        assert!(manager.set_buffer_seconds(30).is_err());
        assert!(manager.set_buffer_seconds(86_401).is_err());
        let updated = manager.set_buffer_seconds(3_600).unwrap();
        assert_eq!(updated.buffer_minutes, 60);
        drop(manager);

        let reopened = StreamManager::open(&config).unwrap();
        assert_eq!(reopened.server_settings().buffer_seconds, 3_600);
        drop(reopened);
        let _ = fs::remove_dir_all(temporary);
    }
    #[test]
    fn cli_exposes_global_lifecycle_commands() {
        let args = |command: &str| vec!["echoclip".to_string(), command.to_string()];
        assert!(matches!(
            parse_cli_command(&args("stop")).unwrap(),
            CliCommand::Stop
        ));
        assert!(matches!(
            parse_cli_command(&args("reboot")).unwrap(),
            CliCommand::Reboot
        ));
        assert!(matches!(
            parse_cli_command(&[
                "echoclip".to_string(),
                "reset".to_string(),
                "key".to_string(),
            ])
            .unwrap(),
            CliCommand::ResetKey
        ));
        assert!(reset_key_confirmed("yes"));
        assert!(reset_key_confirmed(" yes\n"));
        assert!(!reset_key_confirmed("YES"));
        assert!(!reset_key_confirmed("no"));
        assert!(matches!(
            parse_cli_command(&["echoclip".to_string()]).unwrap(),
            CliCommand::Serve
        ));
    }

    #[test]
    fn upload_key_reset_replaces_file_credentials_and_epochs() {
        let temporary = std::env::temp_dir().join(format!(
            "echoclip-server-key-reset-test-{}-{}",
            unix_seconds_now(),
            random_hex_id()
        ));
        fs::create_dir_all(&temporary).unwrap();
        let key_path = temporary.join("upload.key");
        let original = UploadKey::from_bytes([23; 32]);
        let original_id = original.key_id();
        write_new_key_file(&key_path, &original).unwrap();

        let credentials = RwLock::new(UploadCredentials::new(original));
        let mut epoch_map = HashMap::new();
        epoch_map.insert(
            [17; ID_BYTES],
            Arc::new(Mutex::new(EpochState {
                expires_at: u64::MAX,
                last_seen: unix_seconds_now(),
                expected_sequence: 0,
                active: false,
                last_request: Vec::new(),
                last_response: Vec::new(),
            })),
        );
        let epochs = Mutex::new(epoch_map);

        let reset = reset_upload_key(&key_path, &credentials, &epochs).unwrap();
        assert_ne!(reset.key_id, original_id);
        assert_eq!(
            UploadKey::from_base64(&reset.key).unwrap().key_id(),
            reset.key_id
        );
        assert_eq!(load_key(&key_path).unwrap().key_id(), reset.key_id);
        assert_eq!(
            credentials.read().expect("upload credentials lock").key_id,
            reset.key_id
        );
        assert!(epochs.lock().expect("epoch map lock").is_empty());

        let _ = fs::remove_dir_all(temporary);
    }

    #[test]
    fn control_address_uses_loopback_for_wildcard_listener() {
        let address = local_control_address("0.0.0.0:32580".parse().unwrap());
        assert_eq!(address, "127.0.0.1:32580".parse().unwrap());
        assert!(constant_time_eq(b"same-token", b"same-token"));
        assert!(!constant_time_eq(b"same-token", b"other-token"));
    }

    #[test]
    fn recording_name_cannot_escape_storage_directory() {
        let mut config = ServerConfig::default();
        let temporary =
            std::env::temp_dir().join(format!("echoclip-server-path-test-{}", unix_seconds_now()));
        config.server.data_dir = temporary.clone();
        let manager = StreamManager::open(&config).unwrap();
        assert!(manager.recording_path("../secret.wav").is_err());
        assert!(manager.recording_path("a\\b.wav").is_err());
        let _ = fs::remove_dir_all(temporary);
    }

    #[test]
    fn audio_byte_ranges_support_seek_and_suffix_requests() {
        assert_eq!(parse_byte_range("bytes=10-19", 100), Some((10, 19)));
        assert_eq!(parse_byte_range("bytes=90-", 100), Some((90, 99)));
        assert_eq!(parse_byte_range("bytes=-10", 100), Some((90, 99)));
        assert_eq!(parse_byte_range("bytes=100-", 100), None);
        assert_eq!(parse_byte_range("items=0-1", 100), None);
    }

    #[test]
    fn recording_groups_move_files_without_flattening_the_library() {
        let temporary = std::env::temp_dir().join(format!(
            "echoclip-recording-groups-test-{}-{}",
            unix_seconds_now(),
            random_hex_id()
        ));
        let mut config = ServerConfig::default();
        config.server.data_dir = temporary.join("data");
        let manager = StreamManager::open(&config).unwrap();
        let recordings = temporary.join("recordings");
        manager
            .set_recording_directory(recordings.to_str().unwrap())
            .unwrap();
        fs::write(recordings.join("clip.wav"), b"RIFF").unwrap();

        manager.create_group("interviews").unwrap();
        let moved = manager
            .move_library_recording(None, "clip.wav", Some("interviews"))
            .unwrap();
        assert_eq!(moved.group.as_deref(), Some("interviews"));
        assert_eq!(manager.library_recordings().unwrap().len(), 1);
        manager.rename_group("interviews", "meetings").unwrap();
        assert!(
            manager
                .library_recording_path(Some("meetings"), "clip.wav")
                .is_ok()
        );
        manager.delete_group("meetings").unwrap();
        assert!(manager.library_recordings().unwrap().is_empty());

        drop(manager);
        let _ = fs::remove_dir_all(temporary);
    }
    #[test]
    fn connection_probe_does_not_create_a_cache_or_upload_session() {
        let temporary = std::env::temp_dir().join(format!(
            "echoclip-server-probe-test-{}-{}",
            unix_seconds_now(),
            random_hex_id()
        ));
        let mut config = ServerConfig::default();
        config.server.data_dir = temporary.clone();
        let manager = StreamManager::open(&config).unwrap();

        let response = manager.handle(ClientMessage::Probe);

        assert_eq!(response.status, ResponseStatus::Ok);
        assert!(response.server_stream_id.is_empty());
        assert!(manager.cache_state().is_none());
        assert!(manager.stream_views().is_empty());
        drop(manager);
        let _ = fs::remove_dir_all(temporary);
    }

    #[test]
    fn authenticated_upload_uses_shared_core_segments_and_retries_are_idempotent() {
        let temporary = std::env::temp_dir().join(format!(
            "echoclip-server-upload-test-{}-{}",
            unix_seconds_now(),
            random_hex_id()
        ));
        let mut config = ServerConfig::default();
        config.server.data_dir = temporary.clone();
        config.recording.buffer_seconds = 600;
        let key = UploadKey::from_bytes([42; 32]);
        let key_id = key.key_id();
        let server_instance_id = [7; ID_BYTES];
        let epoch_id = [8; ID_BYTES];
        let streams = Arc::new(StreamManager::open(&config).unwrap());
        let state = UploadState {
            credentials: Arc::new(RwLock::new(UploadCredentials {
                key: key.clone(),
                key_id: key_id.clone(),
                server_instance_id,
            })),
            config: config.upload.clone(),
            epochs: Arc::new(Mutex::new(HashMap::from([(
                epoch_id,
                Arc::new(Mutex::new(EpochState {
                    expires_at: unix_seconds_now() + 60,
                    last_seen: unix_seconds_now(),
                    expected_sequence: 0,
                    active: false,
                    last_request: Vec::new(),
                    last_response: Vec::new(),
                })),
            )]))),
            streams: Arc::clone(&streams),
            in_flight: Arc::new(Mutex::new(HashMap::new())),
            request_rate: Arc::new(Mutex::new(HashMap::new())),
        };
        let keys = key.derive_session(server_instance_id, epoch_id).unwrap();
        // The production lower bound rejects sample rates below 8 kHz, so use
        // 8 kHz and enough PCM to cross the shared core's 60 second boundary.
        let open = seal_client_message(
            &keys,
            &key_id,
            epoch_id,
            0,
            &ClientMessage::OpenOrResume {
                device_id: "test-device".to_string(),
                client_stream_id: "test-session".to_string(),
                sample_rate: 8_000,
                channels: 1,
                sample_format: echoclip_sync_protocol::SAMPLE_FORMAT_PCM_S16LE.to_string(),
                source_start_sample: 0,
            },
        )
        .unwrap();
        let open_response = process_envelope(&state, open, "127.0.0.1".parse().unwrap()).unwrap();
        let (_, open_response) = open_server_response(&keys, &open_response).unwrap();
        let server_stream_id = open_response.server_stream_id;

        let samples = vec![123_i16; 8_000 * 61];
        // Protocol frames are intentionally bounded, so upload the 61 seconds
        // in several messages while preserving exact sample positions.
        let mut start = 0_u64;
        for (sequence, chunk) in
            (1_u64..).zip(samples.chunks(echoclip_sync_protocol::MAX_PCM_SAMPLES))
        {
            let request = seal_client_message(
                &keys,
                &key_id,
                epoch_id,
                sequence,
                &ClientMessage::Pcm {
                    server_stream_id: server_stream_id.clone(),
                    start_sample: start,
                    samples: chunk.to_vec(),
                },
            )
            .unwrap();
            let response =
                process_envelope(&state, request.clone(), "127.0.0.1".parse().unwrap()).unwrap();
            let duplicate =
                process_envelope(&state, request, "127.0.0.1".parse().unwrap()).unwrap();
            assert_eq!(response, duplicate);
            start += chunk.len() as u64;
        }
        let view = streams.stream_views().pop().unwrap();
        assert_eq!(view.total_samples_written, 8_000 * 61);
        assert_eq!(view.segment_count, 2);

        let _ = fs::remove_dir_all(temporary);
    }

    #[test]
    fn separate_upload_activations_append_to_one_global_cache() {
        let temporary = std::env::temp_dir().join(format!(
            "echoclip-global-cache-test-{}-{}",
            unix_seconds_now(),
            random_hex_id()
        ));
        let mut config = ServerConfig::default();
        config.server.data_dir = temporary.clone();
        config.recording.buffer_seconds = 600;
        let manager = StreamManager::open(&config).unwrap();

        let first = manager.handle(ClientMessage::OpenOrResume {
            device_id: "device".to_string(),
            client_stream_id: "first-activation".to_string(),
            sample_rate: 8_000,
            channels: 1,
            sample_format: echoclip_sync_protocol::SAMPLE_FORMAT_PCM_S16LE.to_string(),
            source_start_sample: 0,
        });
        assert_eq!(first.status, ResponseStatus::Ok);
        assert_eq!(
            manager
                .handle(ClientMessage::Pcm {
                    server_stream_id: first.server_stream_id.clone(),
                    start_sample: 0,
                    samples: vec![11, 12, 13, 14],
                })
                .accepted_sample_count,
            4
        );
        assert_eq!(
            manager
                .handle(ClientMessage::Close {
                    server_stream_id: first.server_stream_id,
                    final_sample: 4,
                })
                .status,
            ResponseStatus::Ok
        );

        let second = manager.handle(ClientMessage::OpenOrResume {
            device_id: "device".to_string(),
            client_stream_id: "second-activation".to_string(),
            sample_rate: 8_000,
            channels: 1,
            sample_format: echoclip_sync_protocol::SAMPLE_FORMAT_PCM_S16LE.to_string(),
            source_start_sample: 1_000,
        });
        assert_eq!(second.status, ResponseStatus::Ok);
        assert_ne!(second.server_stream_id, "");
        assert_eq!(
            manager
                .handle(ClientMessage::Pcm {
                    server_stream_id: second.server_stream_id,
                    start_sample: 1_000,
                    samples: vec![21, 22, 23],
                })
                .status,
            ResponseStatus::Ok
        );

        let views = manager.stream_views();
        assert_eq!(views.len(), 1);
        assert_eq!(views[0].total_samples_written, 7);
        let cache = manager.cache_state().unwrap();
        let snapshot = cache
            .recorder
            .lock()
            .expect("recorder lock")
            .snapshot()
            .unwrap();
        assert_eq!(
            snapshot.read_range_i16(0, 7).unwrap(),
            vec![11, 12, 13, 14, 21, 22, 23]
        );
        drop(snapshot);
        drop(cache);
        drop(manager);

        let reopened = StreamManager::open(&config).unwrap();
        assert_eq!(reopened.stream_views()[0].total_samples_written, 7);
        drop(reopened);
        let _ = fs::remove_dir_all(temporary);
    }

    #[test]
    fn legacy_per_upload_streams_migrate_in_order_without_deletion() {
        let temporary = std::env::temp_dir().join(format!(
            "echoclip-cache-migration-test-{}-{}",
            unix_seconds_now(),
            random_hex_id()
        ));
        let mut config = ServerConfig::default();
        config.server.data_dir = temporary.clone();
        config.recording.buffer_seconds = 600;
        let audio = AudioConfig {
            sample_rate: 8_000,
            channels: 1,
        };
        for (index, samples) in [vec![1, 2, 3], vec![4, 5]].into_iter().enumerate() {
            let id = format!("legacy-{index}");
            let directory = temporary.join("streams").join(&id);
            let mut core_config = CoreConfig::new(directory.join("core"));
            core_config.audio = audio;
            core_config.segment_seconds = config.recording.segment_seconds;
            core_config.max_replay_seconds = config.recording.buffer_seconds;
            let mut recorder = SegmentedRecorder::recover_latest_or_start(core_config).unwrap();
            recorder.push_samples(&samples).unwrap();
            recorder.flush().unwrap();
            drop(recorder);
            persist_json_atomic(
                &directory.join("stream.json"),
                &LegacyStreamMetadata {
                    server_stream_id: id.clone(),
                    client_stream_id: format!("client-{index}"),
                    device_id: "legacy-device".to_string(),
                    audio,
                    buffer_seconds: 600,
                    source_start_sample: index as u64 * 1_000,
                    created_unix_seconds: 100 + index as u64,
                    closed: index == 0,
                    incomplete: false,
                },
            )
            .unwrap();
        }

        let manager = StreamManager::open(&config).unwrap();
        let cache = manager.cache_state().unwrap();
        let snapshot = cache
            .recorder
            .lock()
            .expect("recorder lock")
            .snapshot()
            .unwrap();
        assert_eq!(snapshot.read_range_i16(0, 5).unwrap(), vec![1, 2, 3, 4, 5]);
        assert!(temporary.join("streams/legacy-0").is_dir());
        assert!(temporary.join("streams/legacy-1").is_dir());
        assert!(temporary.join("cache/cache.json").is_file());
        assert_eq!(manager.stream_views().len(), 1);
        drop(snapshot);
        drop(cache);
        drop(manager);
        let _ = fs::remove_dir_all(temporary);
    }
    #[test]
    fn tampered_pcm_is_rejected_before_shared_core_write() {
        let temporary = std::env::temp_dir().join(format!(
            "echoclip-server-tamper-test-{}-{}",
            unix_seconds_now(),
            random_hex_id()
        ));
        let mut config = ServerConfig::default();
        config.server.data_dir = temporary.clone();
        let key = UploadKey::from_bytes([17; 32]);
        let key_id = key.key_id();
        let server_instance_id = [18; ID_BYTES];
        let epoch_id = [19; ID_BYTES];
        let streams = Arc::new(StreamManager::open(&config).unwrap());
        let state = UploadState {
            credentials: Arc::new(RwLock::new(UploadCredentials {
                key: key.clone(),
                key_id: key_id.clone(),
                server_instance_id,
            })),
            config: config.upload.clone(),
            epochs: Arc::new(Mutex::new(HashMap::from([(
                epoch_id,
                Arc::new(Mutex::new(EpochState {
                    expires_at: unix_seconds_now() + 60,
                    last_seen: unix_seconds_now(),
                    expected_sequence: 0,
                    active: false,
                    last_request: Vec::new(),
                    last_response: Vec::new(),
                })),
            )]))),
            streams: Arc::clone(&streams),
            in_flight: Arc::new(Mutex::new(HashMap::new())),
            request_rate: Arc::new(Mutex::new(HashMap::new())),
        };
        let keys = key.derive_session(server_instance_id, epoch_id).unwrap();
        let mut open = seal_client_message(
            &keys,
            &key_id,
            epoch_id,
            0,
            &ClientMessage::OpenOrResume {
                device_id: "tamper-device".to_string(),
                client_stream_id: "tamper-session".to_string(),
                sample_rate: 16_000,
                channels: 1,
                sample_format: echoclip_sync_protocol::SAMPLE_FORMAT_PCM_S16LE.to_string(),
                source_start_sample: 0,
            },
        )
        .unwrap();
        let last = open.len() - 1;
        open[last] ^= 1;
        assert_eq!(
            process_envelope(&state, open, "127.0.0.1".parse().unwrap())
                .unwrap_err()
                .status,
            StatusCode::UNAUTHORIZED
        );
        assert!(streams.stream_views().is_empty());
        let _ = fs::remove_dir_all(temporary);
    }
}
