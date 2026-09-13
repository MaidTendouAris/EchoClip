use std::fmt;
use std::io::{Read, Write};
use std::net::{Shutdown, SocketAddr, TcpStream, ToSocketAddrs};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::mpsc::Receiver;
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use echoclip_core::{PcmCommitted, RecorderSampleBounds, RecorderSyncHandle};
use echoclip_sync_protocol::{
    ChallengeRequest, ChallengeResponse, ClientMessage, MAX_PCM_SAMPLES, ResponseStatus,
    SAMPLE_FORMAT_PCM_S16LE, ServerResponse, SessionKeys, UploadKey, open_server_response,
    seal_client_message,
};
use serde::Serialize;

const WAKE_INTERVAL: Duration = Duration::from_millis(250);
const RETRY_DELAY: Duration = Duration::from_secs(1);
const DEFAULT_CONNECT_TIMEOUT: Duration = Duration::from_secs(5);
const DEFAULT_IO_TIMEOUT: Duration = Duration::from_secs(10);
const CLOSE_TIMEOUT: Duration = Duration::from_millis(500);
const MAX_HTTP_RESPONSE_BYTES: usize = 1024 * 1024;
const MAX_CONNECTION_LOGS: usize = 100;
static NEXT_UPLOAD_ACTIVATION_ID: AtomicU64 = AtomicU64::new(1);

#[derive(Debug)]
pub enum SyncError {
    InvalidConfig(String),
    Io(std::io::Error),
    Json(serde_json::Error),
    Protocol(echoclip_sync_protocol::ProtocolError),
    Core(echoclip_core::EchoCoreError),
    HttpStatus(u16),
    Http(String),
    Server(String),
}

impl fmt::Display for SyncError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidConfig(message) => write!(formatter, "invalid sync config: {message}"),
            Self::Io(error) => write!(formatter, "network I/O failed: {error}"),
            Self::Json(error) => write!(formatter, "JSON failed: {error}"),
            Self::Protocol(error) => write!(formatter, "upload protocol failed: {error}"),
            Self::Core(error) => write!(formatter, "recorder core failed: {error}"),
            Self::HttpStatus(status) => write!(formatter, "server returned HTTP {status}"),
            Self::Http(message) => write!(formatter, "invalid HTTP response: {message}"),
            Self::Server(message) => write!(formatter, "server rejected upload: {message}"),
        }
    }
}

impl std::error::Error for SyncError {}

impl From<std::io::Error> for SyncError {
    fn from(value: std::io::Error) -> Self {
        Self::Io(value)
    }
}

impl From<serde_json::Error> for SyncError {
    fn from(value: serde_json::Error) -> Self {
        Self::Json(value)
    }
}

impl From<echoclip_sync_protocol::ProtocolError> for SyncError {
    fn from(value: echoclip_sync_protocol::ProtocolError) -> Self {
        Self::Protocol(value)
    }
}

impl From<echoclip_core::EchoCoreError> for SyncError {
    fn from(value: echoclip_core::EchoCoreError) -> Self {
        Self::Core(value)
    }
}

#[derive(Clone)]
pub struct SyncClientConfig {
    pub server_url: String,
    pub upload_key: UploadKey,
    pub device_id: String,
    pub max_chunk_samples: usize,
    pub connect_timeout: Duration,
    pub io_timeout: Duration,
    cancellation: Option<Arc<UploadCancellation>>,
}

impl SyncClientConfig {
    pub fn new(
        server_url: impl Into<String>,
        upload_key: UploadKey,
        device_id: impl Into<String>,
    ) -> Self {
        Self {
            server_url: server_url.into(),
            upload_key,
            device_id: device_id.into(),
            max_chunk_samples: 32_000,
            connect_timeout: DEFAULT_CONNECT_TIMEOUT,
            io_timeout: DEFAULT_IO_TIMEOUT,
            cancellation: None,
        }
    }

    fn validate(&self) -> Result<HttpUrl, SyncError> {
        if self.device_id.trim().is_empty() || self.device_id.len() > 256 {
            return Err(SyncError::InvalidConfig("device_id".to_string()));
        }
        if self.max_chunk_samples == 0 || self.max_chunk_samples > MAX_PCM_SAMPLES {
            return Err(SyncError::InvalidConfig("max_chunk_samples".to_string()));
        }
        HttpUrl::parse(&self.server_url)
    }
}

impl fmt::Debug for SyncClientConfig {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("SyncClientConfig")
            .field("server_url", &self.server_url)
            .field("key_id", &self.upload_key.key_id())
            .field("device_id", &self.device_id)
            .field("max_chunk_samples", &self.max_chunk_samples)
            .finish_non_exhaustive()
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct UploadClientStatus {
    pub running: bool,
    pub connected: bool,
    pub server_url: String,
    pub key_id: String,
    pub server_stream_id: Option<String>,
    pub upload_start_sample: u64,
    pub local_total_samples: u64,
    pub remote_next_sample: u64,
    pub lag_samples: u64,
    pub last_success_unix_seconds: u64,
    pub reconnect_count: u64,
    pub last_error: Option<String>,
    pub logs: Vec<ConnectionLog>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ConnectionEvent {
    Started,
    Connected,
    Disconnected,
    RetentionGap,
    Stopped,
}

#[derive(Debug, Clone, Serialize)]
pub struct ConnectionLog {
    pub unix_seconds: u64,
    pub event: ConnectionEvent,
    pub message: String,
}

impl UploadClientStatus {
    fn new(config: &SyncClientConfig, upload_start_sample: u64) -> Self {
        Self {
            running: true,
            connected: false,
            server_url: config.server_url.clone(),
            key_id: config.upload_key.key_id(),
            server_stream_id: None,
            upload_start_sample,
            local_total_samples: upload_start_sample,
            remote_next_sample: upload_start_sample,
            lag_samples: 0,
            last_success_unix_seconds: 0,
            reconnect_count: 0,
            last_error: None,
            logs: vec![ConnectionLog {
                unix_seconds: unix_seconds_now(),
                event: ConnectionEvent::Started,
                message: "sync_client_started".to_string(),
            }],
        }
    }
}

struct UploadCancellation {
    stopped: Arc<AtomicBool>,
    socket: Mutex<Option<TcpStream>>,
}
impl UploadCancellation {
    fn check(&self) -> Result<(), SyncError> {
        if self.stopped.load(Ordering::Acquire) {
            return Err(
                std::io::Error::new(std::io::ErrorKind::Interrupted, "upload stopped").into(),
            );
        }
        Ok(())
    }
    fn cancel(&self) {
        self.stopped.store(true, Ordering::Release);
        if let Some(socket) = self.socket.lock().expect("upload socket lock").as_ref() {
            let _ = socket.shutdown(Shutdown::Both);
        }
    }
}

pub struct UploadClient {
    status: Arc<Mutex<UploadClientStatus>>,
    thread: Option<JoinHandle<()>>,
    cancellation: Arc<UploadCancellation>,
}

impl UploadClient {
    pub fn start(
        mut config: SyncClientConfig,
        recorder: RecorderSyncHandle,
        commits: Receiver<PcmCommitted>,
    ) -> Result<Self, SyncError> {
        let endpoint = config.validate()?;
        let activation_bounds = recorder.sample_bounds()?;
        let activation = UploadActivation {
            start_sample: activation_bounds.total_samples_written,
            id: new_upload_activation_id(
                &activation_bounds.session_id,
                activation_bounds.total_samples_written,
            ),
        };
        let stop = Arc::new(AtomicBool::new(false));
        let cancellation = Arc::new(UploadCancellation {
            stopped: Arc::clone(&stop),
            socket: Mutex::new(None),
        });
        config.cancellation = Some(Arc::clone(&cancellation));
        let status = Arc::new(Mutex::new(UploadClientStatus::new(
            &config,
            activation.start_sample,
        )));
        let thread_stop = Arc::clone(&stop);
        let thread_status = Arc::clone(&status);
        let thread = thread::Builder::new()
            .name("echoclip-sync-upload".to_string())
            .spawn(move || {
                upload_loop(
                    config,
                    endpoint,
                    recorder,
                    commits,
                    activation,
                    thread_stop,
                    thread_status,
                )
            })?;
        Ok(Self {
            status,
            thread: Some(thread),
            cancellation,
        })
    }

    pub fn status(&self) -> UploadClientStatus {
        self.status.lock().expect("upload status lock").clone()
    }

    pub fn request_stop(&self) {
        self.cancellation.cancel();
    }

    pub fn stop(&mut self) {
        self.request_stop();
        if let Some(thread) = self.thread.take() {
            // DNS and connect calls cannot be interrupted portably. They own
            // their resources and check cancellation before sending any data.
            let deadline = Instant::now() + Duration::from_millis(250);
            while !thread.is_finished() && Instant::now() < deadline {
                thread::sleep(Duration::from_millis(5));
            }
            if thread.is_finished() {
                let _ = thread.join();
            }
        } else {
            return;
        }
        let mut status = self.status.lock().expect("upload status lock");
        status.running = false;
        status.connected = false;
        push_log_locked(
            &mut status,
            ConnectionEvent::Stopped,
            "sync_client_stopped".to_string(),
        );
    }
}

impl Drop for UploadClient {
    fn drop(&mut self) {
        self.stop();
    }
}

struct UploadActivation {
    start_sample: u64,
    id: String,
}

struct UploadSession {
    keys: SessionKeys,
    key_id: String,
    epoch_id: [u8; 16],
    sequence: u64,
    server_stream_id: String,
    logical_stream_id: String,
    remote_next_sample: u64,
}

/// Performs a side-effect-free, application-layer authenticated round trip.
///
/// A successful result proves that the upload endpoint is reachable and that
/// both sides possess the configured upload key. It does not open an upload
/// stream or read any PCM from the recorder.
pub fn test_connection(config: &SyncClientConfig) -> Result<(), SyncError> {
    let endpoint = config.validate()?;
    let (keys, key_id, epoch_id) = request_challenge(config, &endpoint)?;
    let mut session = UploadSession {
        keys,
        key_id,
        epoch_id,
        sequence: 0,
        server_stream_id: String::new(),
        logical_stream_id: String::new(),
        remote_next_sample: 0,
    };
    let response = send_message(config, &endpoint, &mut session, &ClientMessage::Probe)?;
    if response.status == ResponseStatus::Ok {
        Ok(())
    } else {
        Err(SyncError::Server(response.error_code))
    }
}

fn request_challenge(
    config: &SyncClientConfig,
    endpoint: &HttpUrl,
) -> Result<(SessionKeys, String, [u8; 16]), SyncError> {
    let key_id = config.upload_key.key_id();
    let challenge_body = serde_json::to_vec(&ChallengeRequest {
        key_id: key_id.clone(),
    })?;
    let response = http_post(
        endpoint,
        "/upload/v1/challenge",
        "application/json",
        &challenge_body,
        config.connect_timeout,
        config.io_timeout,
        config.cancellation.as_deref(),
    )?;
    if response.status != 200 {
        return Err(SyncError::HttpStatus(response.status));
    }
    let challenge: ChallengeResponse = serde_json::from_slice(&response.body)?;
    if challenge.expires_at < unix_seconds_now() {
        return Err(SyncError::Server("challenge_expired".to_string()));
    }
    let (server_instance_id, epoch_id) = challenge.ids()?;
    let keys = config
        .upload_key
        .derive_session(server_instance_id, epoch_id)?;
    Ok((keys, key_id, epoch_id))
}

fn upload_loop(
    config: SyncClientConfig,
    endpoint: HttpUrl,
    recorder: RecorderSyncHandle,
    commits: Receiver<PcmCommitted>,
    activation: UploadActivation,
    stop: Arc<AtomicBool>,
    status: Arc<Mutex<UploadClientStatus>>,
) {
    let mut session: Option<UploadSession> = None;
    let mut logical_stream_suffix = 0_u64;
    while !stop.load(Ordering::Relaxed) {
        // Commit notifications are wake-up hints only. Drain them once per
        // fixed upload tick so high-frequency capture callbacks cannot turn
        // into an unbounded HTTP request rate.
        for _ in commits.try_iter() {}
        let bounds = match recorder.sample_bounds() {
            Ok(value) => value,
            Err(error) => {
                set_error(&status, error.to_string());
                break;
            }
        };
        update_local_status(&status, &bounds);

        let result = sync_available(
            &config,
            &endpoint,
            &recorder,
            &bounds,
            activation.start_sample,
            &activation.id,
            &mut session,
            &mut logical_stream_suffix,
            &status,
            &stop,
        );
        if let Err(error) = result {
            set_error(&status, error.to_string());
            session = None;
            if wait_for_stop(&stop, RETRY_DELAY) {
                break;
            }
            continue;
        }
        if wait_for_stop(&stop, WAKE_INTERVAL) {
            break;
        }
    }

    if let Some(session) = session {
        close_session_async(config, endpoint, session);
    }
    let mut current = status.lock().expect("upload status lock");
    current.running = false;
    current.connected = false;
}

fn close_session_async(
    mut config: SyncClientConfig,
    endpoint: HttpUrl,
    mut session: UploadSession,
) {
    config.cancellation = None;
    config.connect_timeout = CLOSE_TIMEOUT;
    config.io_timeout = CLOSE_TIMEOUT;
    let _ = thread::Builder::new()
        .name("echoclip-sync-close".to_string())
        .spawn(move || {
            let server_stream_id = session.server_stream_id.clone();
            let final_sample = session.remote_next_sample;
            let _ = send_message(
                &config,
                &endpoint,
                &mut session,
                &ClientMessage::Close {
                    server_stream_id,
                    final_sample,
                },
            );
        });
}

#[allow(clippy::too_many_arguments)]
fn sync_available(
    config: &SyncClientConfig,
    endpoint: &HttpUrl,
    recorder: &RecorderSyncHandle,
    bounds: &RecorderSampleBounds,
    upload_start_sample: u64,
    activation_id: &str,
    session: &mut Option<UploadSession>,
    logical_stream_suffix: &mut u64,
    status: &Arc<Mutex<UploadClientStatus>>,
    stop: &AtomicBool,
) -> Result<(), SyncError> {
    if session.is_none() {
        let source_start_sample = upload_start_sample.max(bounds.retained_start_sample);
        let logical_id = logical_stream_id(activation_id, *logical_stream_suffix);
        *session = Some(establish_session(
            config,
            endpoint,
            bounds,
            logical_id,
            source_start_sample,
        )?);
        let mut current = status.lock().expect("upload status lock");
        current.reconnect_count = current.reconnect_count.saturating_add(1);
        push_log_locked(
            &mut current,
            ConnectionEvent::Connected,
            "upload_session_established".to_string(),
        );
    }

    if stop.load(Ordering::Relaxed) {
        return Ok(());
    }
    let current_bounds = recorder.sample_bounds()?;
    let active = session.as_mut().expect("session established");
    let upload_floor = upload_start_sample.max(current_bounds.retained_start_sample);
    if active.remote_next_sample < upload_floor
        || active.remote_next_sample > current_bounds.total_samples_written
    {
        {
            let mut current = status.lock().expect("upload status lock");
            push_log_locked(
                &mut current,
                ConnectionEvent::RetentionGap,
                format!(
                    "remote_next={} upload_floor={} retained_start={}",
                    active.remote_next_sample, upload_floor, current_bounds.retained_start_sample
                ),
            );
        }
        // Best effort: tell the server that the old logical stream can
        // never be completed. The new logical stream starts at the current
        // upload floor and the WebUI shows the gap on the old one.
        if !active.server_stream_id.is_empty() {
            let _ = send_message(
                config,
                endpoint,
                active,
                &ClientMessage::MarkIncomplete {
                    server_stream_id: active.server_stream_id.clone(),
                },
            );
        }
        *logical_stream_suffix = logical_stream_suffix.saturating_add(1);
        let logical_id = logical_stream_id(activation_id, *logical_stream_suffix);
        *active = establish_session(config, endpoint, &current_bounds, logical_id, upload_floor)?;
    }
    if active.remote_next_sample == current_bounds.total_samples_written {
        let mut current = status.lock().expect("upload status lock");
        current.connected = true;
        current.server_stream_id = Some(active.server_stream_id.clone());
        current.remote_next_sample = active.remote_next_sample;
        current.lag_samples = 0;
        current.last_error = None;
        return Ok(());
    }

    let start = active.remote_next_sample;
    let channels = current_bounds.audio.channels as u64;
    let maximum = config.max_chunk_samples as u64;
    let mut end = start
        .saturating_add(maximum)
        .min(current_bounds.total_samples_written);
    let remainder = (end - start) % channels;
    end = end.saturating_sub(remainder);
    if end <= start {
        return Ok(());
    }
    let samples = recorder.read_range_i16(start, end)?;
    let response = send_message(
        config,
        endpoint,
        active,
        &ClientMessage::Pcm {
            server_stream_id: active.server_stream_id.clone(),
            start_sample: start,
            samples,
        },
    )?;
    if response.status == ResponseStatus::Gap && response.error_code == "sequence_gap" {
        // The server rejected this envelope because a previous message was
        // lost. Its authenticated Gap ACK proves the current next_sample;
        // drop the epoch and resynchronize through OpenOrResume.
        *session = None;
        return Ok(());
    }
    match response.status {
        ResponseStatus::Ok => {
            if response.next_sample <= start || response.next_sample > end {
                return Err(SyncError::Server("invalid_ack_position".to_string()));
            }
            active.remote_next_sample = response.next_sample;
        }
        ResponseStatus::Gap => {
            active.remote_next_sample = response.next_sample;
        }
        ResponseStatus::Incomplete | ResponseStatus::Rejected => {
            return Err(SyncError::Server(response.error_code));
        }
    }
    let mut current = status.lock().expect("upload status lock");
    current.connected = true;
    current.server_stream_id = Some(active.server_stream_id.clone());
    current.remote_next_sample = active.remote_next_sample;
    current.local_total_samples = current_bounds.total_samples_written;
    current.lag_samples = current_bounds
        .total_samples_written
        .saturating_sub(active.remote_next_sample);
    current.last_success_unix_seconds = unix_seconds_now();
    current.last_error = None;
    // Pace backlog recovery as well as live upload. One successful PCM
    // envelope per tick keeps retries bounded and avoids server 429s.
    Ok(())
}

fn establish_session(
    config: &SyncClientConfig,
    endpoint: &HttpUrl,
    bounds: &RecorderSampleBounds,
    logical_stream_id: String,
    source_start_sample: u64,
) -> Result<UploadSession, SyncError> {
    let (keys, key_id, epoch_id) = request_challenge(config, endpoint)?;
    let mut session = UploadSession {
        keys,
        key_id,
        epoch_id,
        sequence: 0,
        server_stream_id: String::new(),
        logical_stream_id,
        remote_next_sample: source_start_sample,
    };
    let open = ClientMessage::OpenOrResume {
        device_id: config.device_id.clone(),
        client_stream_id: session.logical_stream_id.clone(),
        sample_rate: bounds.audio.sample_rate,
        channels: bounds.audio.channels,
        sample_format: SAMPLE_FORMAT_PCM_S16LE.to_string(),
        source_start_sample,
    };
    let response = send_message(config, endpoint, &mut session, &open)?;
    if response.status != ResponseStatus::Ok || response.server_stream_id.is_empty() {
        return Err(SyncError::Server(response.error_code));
    }
    session.server_stream_id = response.server_stream_id;
    session.remote_next_sample = response.next_sample;
    Ok(session)
}

fn send_message(
    config: &SyncClientConfig,
    endpoint: &HttpUrl,
    session: &mut UploadSession,
    message: &ClientMessage,
) -> Result<ServerResponse, SyncError> {
    let sequence = session.sequence;
    let envelope = seal_client_message(
        &session.keys,
        &session.key_id,
        session.epoch_id,
        sequence,
        message,
    )?;
    let mut last_error = None;
    for _ in 0..2 {
        if let Some(cancel) = &config.cancellation {
            cancel.check()?;
        }
        match http_post(
            endpoint,
            "/upload/v1/envelope",
            "application/octet-stream",
            &envelope,
            config.connect_timeout,
            config.io_timeout,
            config.cancellation.as_deref(),
        ) {
            Ok(response) if response.status == 200 => {
                let (header, message) = open_server_response(&session.keys, &response.body)?;
                if header.sequence != sequence || header.epoch_id != session.epoch_id {
                    return Err(SyncError::Server("invalid_response_envelope".to_string()));
                }
                session.sequence = session.sequence.saturating_add(1);
                return Ok(message);
            }
            Ok(response) => {
                // A sequence gap is rejected with HTTP 409, but the body is an
                // authenticated server response encrypted with K_s2c. It proves
                // the server's current next_sample without allowing a network
                // attacker to forge a plain-text "resend from N".
                if response.status == 409
                    && let Ok((header, message)) =
                        open_server_response(&session.keys, &response.body)
                    && header.epoch_id == session.epoch_id
                {
                    if message.status == ResponseStatus::Gap {
                        return Ok(message);
                    }
                    if message.status == ResponseStatus::Rejected {
                        return Err(SyncError::Server(message.error_code));
                    }
                }
                last_error = Some(SyncError::HttpStatus(response.status));
            }
            Err(error) => last_error = Some(error),
        }
    }
    Err(last_error.unwrap_or_else(|| SyncError::Http("empty retry".to_string())))
}

fn update_local_status(status: &Arc<Mutex<UploadClientStatus>>, bounds: &RecorderSampleBounds) {
    let mut current = status.lock().expect("upload status lock");
    current.local_total_samples = bounds.total_samples_written;
    current.lag_samples = bounds
        .total_samples_written
        .saturating_sub(current.remote_next_sample);
}

fn set_error(status: &Arc<Mutex<UploadClientStatus>>, error: String) {
    let mut current = status.lock().expect("upload status lock");
    let should_log = current.last_error.as_deref() != Some(error.as_str()) || current.connected;
    current.connected = false;
    current.last_error = Some(error.clone());
    if should_log {
        push_log_locked(&mut current, ConnectionEvent::Disconnected, error);
    }
}

fn push_log_locked(status: &mut UploadClientStatus, event: ConnectionEvent, message: String) {
    status.logs.push(ConnectionLog {
        unix_seconds: unix_seconds_now(),
        event,
        message,
    });
    if status.logs.len() > MAX_CONNECTION_LOGS {
        status.logs.drain(..status.logs.len() - MAX_CONNECTION_LOGS);
    }
}

fn wait_for_stop(stop: &AtomicBool, duration: Duration) -> bool {
    let steps = (duration.as_millis() / 50).max(1);
    for _ in 0..steps {
        if stop.load(Ordering::Relaxed) {
            return true;
        }
        thread::sleep(Duration::from_millis(50));
    }
    stop.load(Ordering::Relaxed)
}

fn new_upload_activation_id(session_id: &str, upload_start_sample: u64) -> String {
    let counter = NEXT_UPLOAD_ACTIVATION_ID.fetch_add(1, Ordering::Relaxed);
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    format!("{session_id}-upload-{upload_start_sample:x}-{timestamp:x}-{counter:x}")
}

fn logical_stream_id(activation_id: &str, suffix: u64) -> String {
    if suffix == 0 {
        activation_id.to_string()
    } else {
        format!("{activation_id}-gap-{suffix}")
    }
}

#[derive(Debug, Clone)]
struct HttpUrl {
    host: String,
    host_header: String,
    port: u16,
    base_path: String,
}

impl HttpUrl {
    fn parse(value: &str) -> Result<Self, SyncError> {
        let remainder = value
            .trim()
            .strip_prefix("http://")
            .ok_or_else(|| SyncError::InvalidConfig("server_url must use http://".to_string()))?;
        let (authority, path) = remainder
            .split_once('/')
            .map(|(authority, path)| (authority, format!("/{path}")))
            .unwrap_or((remainder, String::new()));
        if authority.is_empty() || authority.contains('@') {
            return Err(SyncError::InvalidConfig("server_url authority".to_string()));
        }
        let (host, port, host_header) = if let Some(rest) = authority.strip_prefix('[') {
            let close = rest
                .find(']')
                .ok_or_else(|| SyncError::InvalidConfig("IPv6 host".to_string()))?;
            let host = &rest[..close];
            let suffix = &rest[close + 1..];
            let port = if suffix.is_empty() {
                80
            } else {
                suffix
                    .strip_prefix(':')
                    .ok_or_else(|| SyncError::InvalidConfig("IPv6 port".to_string()))?
                    .parse()
                    .map_err(|_| SyncError::InvalidConfig("port".to_string()))?
            };
            (host.to_string(), port, authority.to_string())
        } else if let Some((host, port)) = authority.rsplit_once(':') {
            let port = port
                .parse()
                .map_err(|_| SyncError::InvalidConfig("port".to_string()))?;
            (host.to_string(), port, authority.to_string())
        } else {
            (authority.to_string(), 80, authority.to_string())
        };
        if host.is_empty() || path.contains('#') {
            return Err(SyncError::InvalidConfig("server_url".to_string()));
        }
        Ok(Self {
            host,
            host_header,
            port,
            base_path: path.trim_end_matches('/').to_string(),
        })
    }

    fn path(&self, suffix: &str) -> String {
        format!("{}{}", self.base_path, suffix)
    }
}

struct HttpResponse {
    status: u16,
    body: Vec<u8>,
}

fn http_post(
    endpoint: &HttpUrl,
    path: &str,
    content_type: &str,
    body: &[u8],
    connect_timeout: Duration,
    io_timeout: Duration,
    cancellation: Option<&UploadCancellation>,
) -> Result<HttpResponse, SyncError> {
    if let Some(cancel) = cancellation {
        cancel.check()?;
    }
    let addresses: Vec<SocketAddr> = (endpoint.host.as_str(), endpoint.port)
        .to_socket_addrs()?
        .collect();
    if addresses.is_empty() {
        return Err(SyncError::Http("host resolved to no addresses".to_string()));
    }
    let mut connected = None;
    let mut last_error = None;
    for address in addresses {
        if let Some(cancel) = cancellation {
            cancel.check()?;
        }
        match TcpStream::connect_timeout(&address, connect_timeout) {
            Ok(stream) => {
                connected = Some(stream);
                break;
            }
            Err(error) => last_error = Some(error),
        }
    }
    let mut stream = connected.ok_or_else(|| {
        SyncError::Io(last_error.unwrap_or_else(|| std::io::Error::other("connect failed")))
    })?;
    if let Some(cancel) = cancellation {
        let mut slot = cancel.socket.lock().expect("upload socket lock");
        cancel.check()?;
        *slot = Some(stream.try_clone()?);
    }
    // Clearing this clone closes every completed request, including failures.
    struct ActiveSocket<'a>(Option<&'a UploadCancellation>);
    impl Drop for ActiveSocket<'_> {
        fn drop(&mut self) {
            if let Some(cancel) = self.0 {
                cancel.socket.lock().expect("upload socket lock").take();
            }
        }
    }
    let _active = ActiveSocket(cancellation);
    stream.set_read_timeout(Some(io_timeout))?;
    stream.set_write_timeout(Some(io_timeout))?;
    let request_path = endpoint.path(path);
    write!(
        stream,
        "POST {request_path} HTTP/1.1\r\nHost: {}\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nConnection: close\r\nUser-Agent: EchoClip-Sync/1\r\n\r\n",
        endpoint.host_header,
        body.len()
    )?;
    stream.write_all(body)?;
    stream.flush()?;

    let mut response = Vec::new();
    stream
        .take((MAX_HTTP_RESPONSE_BYTES + 1) as u64)
        .read_to_end(&mut response)?;
    if response.len() > MAX_HTTP_RESPONSE_BYTES {
        return Err(SyncError::Http("response too large".to_string()));
    }
    parse_http_response(response)
}

fn parse_http_response(response: Vec<u8>) -> Result<HttpResponse, SyncError> {
    let header_end = response
        .windows(4)
        .position(|window| window == b"\r\n\r\n")
        .map(|position| position + 4)
        .ok_or_else(|| SyncError::Http("missing header terminator".to_string()))?;
    let header_text = std::str::from_utf8(&response[..header_end])
        .map_err(|_| SyncError::Http("header is not UTF-8".to_string()))?;
    let mut lines = header_text.split("\r\n");
    let status_line = lines
        .next()
        .ok_or_else(|| SyncError::Http("missing status line".to_string()))?;
    let status: u16 = status_line
        .split_whitespace()
        .nth(1)
        .ok_or_else(|| SyncError::Http("missing status".to_string()))?
        .parse()
        .map_err(|_| SyncError::Http("invalid status".to_string()))?;
    let mut content_length = None;
    for line in lines {
        let Some((name, value)) = line.split_once(':') else {
            continue;
        };
        if name.eq_ignore_ascii_case("transfer-encoding")
            && value.trim().eq_ignore_ascii_case("chunked")
        {
            return Err(SyncError::Http(
                "chunked responses are not supported".to_string(),
            ));
        }
        if name.eq_ignore_ascii_case("content-length") {
            content_length = Some(
                value
                    .trim()
                    .parse::<usize>()
                    .map_err(|_| SyncError::Http("invalid content length".to_string()))?,
            );
        }
    }
    let body = response[header_end..].to_vec();
    if let Some(expected) = content_length
        && body.len() != expected
    {
        return Err(SyncError::Http("truncated response body".to_string()));
    }
    Ok(HttpResponse { status, body })
}

fn unix_seconds_now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn upload_activation_is_unique_and_status_starts_at_enable_boundary() {
        let config = SyncClientConfig::new(
            "http://127.0.0.1:32581",
            UploadKey::from_bytes([9; 32]),
            "test-device",
        );
        let status = UploadClientStatus::new(&config, 12_345);
        assert_eq!(status.upload_start_sample, 12_345);
        assert_eq!(status.local_total_samples, 12_345);
        assert_eq!(status.remote_next_sample, 12_345);
        assert_eq!(status.lag_samples, 0);

        let first = new_upload_activation_id("recorder-session", 12_345);
        let second = new_upload_activation_id("recorder-session", 12_345);
        assert_ne!(first, second);
        assert_eq!(logical_stream_id(&first, 0), first);
        assert!(logical_stream_id(&first, 1).ends_with("-gap-1"));
    }

    #[test]
    fn http_url_requires_plain_http_and_preserves_base_path() {
        let parsed = HttpUrl::parse("http://127.0.0.1:32581/base/").unwrap();
        assert_eq!(parsed.host, "127.0.0.1");
        assert_eq!(parsed.port, 32581);
        assert_eq!(
            parsed.path("/upload/v1/challenge"),
            "/base/upload/v1/challenge"
        );
        assert!(HttpUrl::parse("https://example.com").is_err());
    }

    #[test]
    fn fixed_length_http_response_is_parsed() {
        let response = parse_http_response(
            b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok".to_vec(),
        )
        .unwrap();
        assert_eq!(response.status, 200);
        assert_eq!(response.body, b"ok");
    }

    #[test]
    fn chunked_response_is_rejected_instead_of_misparsed() {
        let response = b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\nok\r\n0\r\n\r\n";
        assert!(parse_http_response(response.to_vec()).is_err());
    }
    #[test]
    fn stopping_upload_interrupts_a_server_that_never_replies() {
        use echoclip_core::{CoreConfig, RecorderWorker};
        use std::net::TcpListener;
        use std::sync::mpsc;
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let endpoint = format!("http://{}", listener.local_addr().unwrap());
        let (ready_tx, ready_rx) = mpsc::channel();
        let server = thread::spawn(move || {
            let (mut socket, _) = listener.accept().unwrap();
            socket
                .set_read_timeout(Some(Duration::from_secs(2)))
                .unwrap();
            let mut bytes = [0; 4096];
            assert!(socket.read(&mut bytes).unwrap() > 0);
            ready_tx.send(()).unwrap();
            // No response: stop must close this socket instead of waiting 10s.
            while let Ok(count) = socket.read(&mut bytes) {
                if count == 0 {
                    break;
                }
            }
        });
        let path = std::env::temp_dir().join(new_upload_activation_id("shutdown-test", 0));
        let mut recorder = RecorderWorker::start(CoreConfig::new(&path)).unwrap();
        let mut client = UploadClient::start(
            SyncClientConfig::new(endpoint, UploadKey::from_bytes([7; 32]), "shutdown-test"),
            recorder.sync_handle(),
            recorder.subscribe_commits(8),
        )
        .unwrap();
        ready_rx.recv_timeout(Duration::from_secs(2)).unwrap();
        let started = Instant::now();
        client.stop();
        let elapsed = started.elapsed();
        eprintln!("stalled upload stop: {elapsed:?}");
        assert!(elapsed < Duration::from_secs(1));
        assert!(!client.status().running);
        client.stop(); // Idempotent.
        server.join().unwrap();
        recorder.stop();
        std::fs::remove_dir_all(path).unwrap();
    }
}
