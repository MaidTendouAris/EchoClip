use std::collections::HashMap;
use std::io;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};

use echoclip_core::{
    AudioConfig, CoreConfig, ExportFormat, ExportOptions, RecorderWorker,
    scheduler::{ScheduledActionResult, Scheduler, now_utc_millis},
    transcode_wav_to_mp3,
};
use echoclip_sync_client::{SyncClientConfig, UploadClient, test_connection};
use echoclip_sync_protocol::UploadKey;
use jni::JNIEnv;
use jni::objects::{JObject, JShortArray, JString};
use jni::sys::{jint, jlong, jstring};

struct WorkerHandle {
    worker: RecorderWorker,
    sync_client: Mutex<Option<UploadClient>>,
}

impl WorkerHandle {
    fn new(worker: RecorderWorker) -> Self {
        Self {
            worker,
            sync_client: Mutex::new(None),
        }
    }

    fn stop_sync(&self) {
        if let Some(mut client) = self.sync_client.lock().expect("sync client lock").take() {
            client.stop();
        }
    }
}

impl Drop for WorkerHandle {
    fn drop(&mut self) {
        self.stop_sync();
        self.worker.stop();
    }
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_echoclip_echoclip_RustAudioCore_nativeStartRecorder(
    mut env: JNIEnv,
    _this: JObject,
    temp_dir: JString,
    sample_rate: jint,
    channels: jint,
    segment_seconds: jint,
    max_replay_seconds: jint,
    queue_capacity_chunks: jint,
) -> jlong {
    catch_jni_long(|| {
        let temp_dir = java_string(&mut env, &temp_dir)?;
        let mut config = CoreConfig::new(PathBuf::from(temp_dir));
        config.audio = AudioConfig {
            sample_rate: sample_rate.max(1) as u32,
            channels: channels.max(1) as u16,
        };
        config.segment_seconds = segment_seconds.max(1) as u32;
        config.max_replay_seconds = max_replay_seconds.max(1) as u32;

        let worker =
            RecorderWorker::start_with_queue(config, queue_capacity_chunks.max(1) as usize)?;
        Ok(Box::into_raw(Box::new(WorkerHandle::new(worker))) as jlong)
    })
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_echoclip_echoclip_RustAudioCore_nativeDestroy(
    _env: JNIEnv,
    _this: JObject,
    handle: jlong,
) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if handle != 0 {
            unsafe {
                let _ = Box::from_raw(handle as *mut WorkerHandle);
            }
        }
    }));
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_echoclip_echoclip_RustAudioCore_nativeStopRecorder(
    _env: JNIEnv,
    _this: JObject,
    handle: jlong,
) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if let Some(worker) = worker_mut(handle) {
            worker.stop_sync();
            worker.worker.stop();
        }
    }));
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_echoclip_echoclip_RustAudioCore_nativePushPcm(
    env: JNIEnv,
    _this: JObject,
    handle: jlong,
    samples: JShortArray,
    count: jint,
) -> jint {
    catch_jni_int(|| {
        if handle == 0 || count <= 0 {
            return Ok(3);
        }
        let worker = worker_ref(handle)?;
        let available = env.get_array_length(&samples)?.min(count);
        if available <= 0 {
            return Ok(0);
        }

        let mut input = vec![0_i16; available as usize];
        env.get_short_array_region(&samples, 0, &mut input)?;
        match worker.worker.push_samples(&input) {
            Ok(()) => Ok(0),
            Err(error) => {
                let text = error.to_string();
                if text.contains("queue is full") {
                    Ok(1)
                } else if text.contains("stopped") {
                    Ok(2)
                } else if text.contains("closed") {
                    Ok(5)
                } else {
                    Ok(6)
                }
            }
        }
    })
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_echoclip_echoclip_RustAudioCore_nativeAvailableMillis(
    _env: JNIEnv,
    _this: JObject,
    handle: jlong,
) -> jlong {
    catch_jni_long(|| {
        let worker = worker_ref(handle)?;
        Ok(worker.worker.status().available_millis as jlong)
    })
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_echoclip_echoclip_RustAudioCore_nativeSaveLatestToCache(
    mut env: JNIEnv,
    _this: JObject,
    handle: jlong,
    seconds: jint,
    output_path: JString,
    format: JString,
    mp3_bitrate_kbps: jint,
    ffmpeg_path: JString,
) -> jlong {
    catch_jni_long(|| {
        let worker = worker_ref(handle)?;
        let output_path = java_string(&mut env, &output_path)?;
        let format = java_string(&mut env, &format)?;
        let ffmpeg_path = java_string(&mut env, &ffmpeg_path)?;
        let options = ExportOptions {
            format: parse_export_format(&format),
            mp3_bitrate_kbps: mp3_bitrate_kbps.max(32) as u32,
            ffmpeg_path: if ffmpeg_path.trim().is_empty() {
                None
            } else {
                Some(PathBuf::from(ffmpeg_path))
            },
        };
        Ok(worker
            .worker
            .save_latest_async(seconds.max(1) as u32, output_path, options)? as jlong)
    })
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_echoclip_echoclip_RustAudioCore_nativeBufferWindowJson(
    env: JNIEnv,
    _this: JObject,
    handle: jlong,
) -> jstring {
    catch_jni_string(env, || {
        Ok(serde_json::to_string(
            &worker_ref(handle)?.worker.buffer_window(),
        )?)
    })
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_echoclip_echoclip_RustAudioCore_nativeSaveRangeToCache(
    mut env: JNIEnv,
    _this: JObject,
    handle: jlong,
    range_json: JString,
    output_path: JString,
    format: JString,
    mp3_bitrate_kbps: jint,
    ffmpeg_path: JString,
) -> jlong {
    catch_jni_long(|| {
        let worker = worker_ref(handle)?;
        let range = serde_json::from_str::<echoclip_core::ExportRange>(&java_string(
            &mut env,
            &range_json,
        )?)?;
        let output = java_string(&mut env, &output_path)?;
        let format = java_string(&mut env, &format)?;
        let ffmpeg = java_string(&mut env, &ffmpeg_path)?;
        let options = ExportOptions {
            format: parse_export_format(&format),
            mp3_bitrate_kbps: mp3_bitrate_kbps.max(32) as u32,
            ffmpeg_path: (!ffmpeg.trim().is_empty()).then(|| PathBuf::from(ffmpeg)),
        };
        Ok(worker.worker.save_range_async(range, output, options)? as jlong)
    })
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_echoclip_echoclip_RustAudioCore_nativeStatusJson(
    env: JNIEnv,
    _this: JObject,
    handle: jlong,
) -> jstring {
    catch_jni_string(env, || {
        let worker = worker_ref(handle)?;
        let mut status = serde_json::to_value(worker.worker.status())?;
        let fields = status
            .as_object_mut()
            .ok_or_else(|| io::Error::other("core status is not an object"))?;
        let sync = worker
            .sync_client
            .lock()
            .expect("sync client lock")
            .as_ref()
            .map(UploadClient::status);
        fields.insert("sync_configured".to_string(), sync.is_some().into());
        fields.insert("sync".to_string(), serde_json::to_value(sync)?);
        Ok(serde_json::to_string(&status)?)
    })
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_echoclip_echoclip_RustAudioCore_nativeExportStatusJson(
    env: JNIEnv,
    _this: JObject,
    handle: jlong,
    job_id: jlong,
) -> jstring {
    catch_jni_string(env, || {
        let worker = worker_ref(handle)?;
        match worker.worker.export_status(job_id as u64) {
            Some(status) => Ok(serde_json::to_string(&status)?),
            None => Ok(format!(
                "{{\"id\":{},\"state\":\"Failed\",\"error\":\"job_not_found\"}}",
                job_id
            )),
        }
    })
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_echoclip_echoclip_RustAudioCore_nativeCancelExport(
    _env: JNIEnv,
    _this: JObject,
    handle: jlong,
    job_id: jlong,
) -> jint {
    catch_jni_int(|| {
        let worker = worker_ref(handle)?;
        Ok(if worker.worker.cancel_export(job_id as u64) {
            0
        } else {
            1
        })
    })
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_echoclip_echoclip_RustAudioCore_nativeConfigureSync(
    mut env: JNIEnv,
    _this: JObject,
    handle: jlong,
    enabled: jint,
    server_url: JString,
    upload_key_base64: JString,
    device_id: JString,
) -> jint {
    catch_jni_int(|| {
        let recorder = worker_ref(handle)?;
        if enabled == 0 {
            recorder.stop_sync();
            return Ok(0);
        }
        if enabled != 1 {
            return Ok(3);
        }
        let server_url = java_string(&mut env, &server_url)?;
        let upload_key_base64 = java_string(&mut env, &upload_key_base64)?;
        let device_id = java_string(&mut env, &device_id)?;
        let key = UploadKey::from_base64(&upload_key_base64)?;
        let config = SyncClientConfig::new(server_url, key, device_id);
        let commits = recorder.worker.subscribe_commits(8);
        let sync_handle = recorder.worker.sync_handle();
        let client = UploadClient::start(config, sync_handle, commits)?;
        recorder.stop_sync();
        *recorder.sync_client.lock().expect("sync client lock") = Some(client);
        Ok(0)
    })
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_echoclip_echoclip_RustAudioCore_nativeTestSyncConnection(
    mut env: JNIEnv,
    _this: JObject,
    server_url: JString,
    upload_key_base64: JString,
    device_id: JString,
) -> jstring {
    let arguments = (|| {
        Ok::<_, Box<dyn std::error::Error>>((
            java_string(&mut env, &server_url)?,
            java_string(&mut env, &upload_key_base64)?,
            java_string(&mut env, &device_id)?,
        ))
    })();
    catch_jni_string(env, move || {
        let (server_url, upload_key_base64, device_id) = arguments?;
        let key = UploadKey::from_base64(&upload_key_base64)?;
        let config = SyncClientConfig::new(server_url, key, device_id);
        test_connection(&config)?;
        Ok("{\"success\":true}".to_string())
    })
}

fn scheduler_registry() -> &'static Mutex<HashMap<String, Scheduler>> {
    static REGISTRY: OnceLock<Mutex<HashMap<String, Scheduler>>> = OnceLock::new();
    REGISTRY.get_or_init(|| Mutex::new(HashMap::new()))
}

fn with_scheduler<T>(
    data_dir: String,
    action: impl FnOnce(&mut Scheduler) -> Result<T, Box<dyn std::error::Error>>,
) -> Result<T, Box<dyn std::error::Error>> {
    let mut registry = scheduler_registry()
        .lock()
        .expect("scheduler registry lock");
    if !registry.contains_key(&data_dir) {
        registry.insert(data_dir.clone(), Scheduler::open(&data_dir)?);
    }
    action(registry.get_mut(&data_dir).expect("scheduler inserted"))
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_echoclip_echoclip_RustAudioCore_nativeScheduleSnapshot(
    mut env: JNIEnv,
    _this: JObject,
    data_dir: JString,
) -> jstring {
    let data_dir = java_string(&mut env, &data_dir);
    catch_jni_string(env, move || {
        let data_dir = data_dir?;
        with_scheduler(data_dir, |scheduler| {
            Ok(scheduler.snapshot_json(now_utc_millis())?)
        })
    })
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_echoclip_echoclip_RustAudioCore_nativeScheduleUpsert(
    mut env: JNIEnv,
    _this: JObject,
    data_dir: JString,
    task_json: JString,
) -> jstring {
    let arguments = (|| {
        Ok::<_, Box<dyn std::error::Error>>((
            java_string(&mut env, &data_dir)?,
            java_string(&mut env, &task_json)?,
        ))
    })();
    catch_jni_string(env, move || {
        let (data_dir, task_json) = arguments?;
        with_scheduler(data_dir, |scheduler| {
            scheduler.editor_command_json(&task_json, now_utc_millis())?;
            Ok(scheduler.snapshot_json(now_utc_millis())?)
        })
    })
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_echoclip_echoclip_RustAudioCore_nativeScheduleDelete(
    mut env: JNIEnv,
    _this: JObject,
    data_dir: JString,
    task_id: JString,
) -> jstring {
    let arguments = (|| {
        Ok::<_, Box<dyn std::error::Error>>((
            java_string(&mut env, &data_dir)?,
            java_string(&mut env, &task_id)?,
        ))
    })();
    catch_jni_string(env, move || {
        let (data_dir, task_id) = arguments?;
        with_scheduler(data_dir, |scheduler| {
            scheduler.delete(&task_id)?;
            Ok(scheduler.snapshot_json(now_utc_millis())?)
        })
    })
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_echoclip_echoclip_RustAudioCore_nativeScheduleSetEnabled(
    mut env: JNIEnv,
    _this: JObject,
    data_dir: JString,
    task_id: JString,
    expected_revision: jlong,
    enabled: jint,
) -> jstring {
    let arguments = (|| {
        Ok::<_, Box<dyn std::error::Error>>((
            java_string(&mut env, &data_dir)?,
            java_string(&mut env, &task_id)?,
        ))
    })();
    catch_jni_string(env, move || {
        let (data_dir, task_id) = arguments?;
        with_scheduler(data_dir, |scheduler| {
            scheduler.set_enabled(
                &task_id,
                (expected_revision > 0).then_some(expected_revision as u64),
                enabled == 1,
                now_utc_millis(),
            )?;
            Ok(scheduler.snapshot_json(now_utc_millis())?)
        })
    })
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_echoclip_echoclip_RustAudioCore_nativeScheduleTick(
    mut env: JNIEnv,
    _this: JObject,
    data_dir: JString,
) -> jstring {
    let data_dir = java_string(&mut env, &data_dir);
    catch_jni_string(env, move || {
        let data_dir = data_dir?;
        with_scheduler(data_dir, |scheduler| {
            Ok(serde_json::to_string(&scheduler.tick(now_utc_millis())?)?)
        })
    })
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_echoclip_echoclip_RustAudioCore_nativeScheduleComplete(
    mut env: JNIEnv,
    _this: JObject,
    data_dir: JString,
    execution_id: JString,
    results_json: JString,
) -> jstring {
    let arguments = (|| {
        Ok::<_, Box<dyn std::error::Error>>((
            java_string(&mut env, &data_dir)?,
            java_string(&mut env, &execution_id)?,
            java_string(&mut env, &results_json)?,
        ))
    })();
    catch_jni_string(env, move || {
        let (data_dir, execution_id, results_json) = arguments?;
        let results: Vec<ScheduledActionResult> = serde_json::from_str(&results_json)?;
        with_scheduler(data_dir, |scheduler| {
            scheduler.complete_execution(&execution_id, results, now_utc_millis())?;
            Ok(scheduler.snapshot_json(now_utc_millis())?)
        })
    })
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_echoclip_echoclip_RustAudioCore_nativeTranscodeWavToMp3(
    mut env: JNIEnv,
    _this: JObject,
    input_path: JString,
    output_path: JString,
    ffmpeg_path: JString,
    bitrate_kbps: jint,
) -> jint {
    catch_jni_int(|| {
        let input_path = java_string(&mut env, &input_path)?;
        let output_path = java_string(&mut env, &output_path)?;
        let ffmpeg_path = java_string(&mut env, &ffmpeg_path)?;
        transcode_wav_to_mp3(
            input_path,
            output_path,
            ffmpeg_path,
            bitrate_kbps.max(32) as u32,
        )?;
        Ok(0)
    })
}
fn worker_ref(handle: jlong) -> Result<&'static WorkerHandle, io::Error> {
    if handle == 0 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "invalid_handle",
        ));
    }
    unsafe {
        (handle as *const WorkerHandle)
            .as_ref()
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "invalid_handle"))
    }
}

fn worker_mut(handle: jlong) -> Option<&'static mut WorkerHandle> {
    if handle == 0 {
        return None;
    }
    unsafe { (handle as *mut WorkerHandle).as_mut() }
}

fn java_string(env: &mut JNIEnv, value: &JString) -> Result<String, Box<dyn std::error::Error>> {
    Ok(env.get_string(value)?.into())
}

fn parse_export_format(value: &str) -> ExportFormat {
    ExportFormat::from_name(value).unwrap_or(ExportFormat::Mp3)
}

fn catch_jni_long(action: impl FnOnce() -> Result<jlong, Box<dyn std::error::Error>>) -> jlong {
    match catch_unwind(AssertUnwindSafe(action)) {
        Ok(Ok(value)) => value,
        Ok(Err(_)) | Err(_) => 0,
    }
}

fn catch_jni_int(action: impl FnOnce() -> Result<jint, Box<dyn std::error::Error>>) -> jint {
    match catch_unwind(AssertUnwindSafe(action)) {
        Ok(Ok(value)) => value,
        Ok(Err(_)) => 3,
        Err(_) => 4,
    }
}

fn catch_jni_string(
    env: JNIEnv,
    action: impl FnOnce() -> Result<String, Box<dyn std::error::Error>>,
) -> jstring {
    let text = match catch_unwind(AssertUnwindSafe(action)) {
        Ok(Ok(value)) => value,
        Ok(Err(error)) => format!("{{\"error\":\"{}\"}}", escape_json(&error.to_string())),
        Err(_) => "{\"error\":\"panic\"}".to_string(),
    };
    match env.new_string(text) {
        Ok(value) => value.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

fn escape_json(input: &str) -> String {
    input
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
        .replace('\t', "\\t")
}
