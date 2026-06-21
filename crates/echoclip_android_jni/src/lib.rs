use std::io;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::path::PathBuf;

use echoclip_core::{AudioConfig, CoreConfig, ExportFormat, ExportOptions, RecorderWorker};
use jni::JNIEnv;
use jni::objects::{JObject, JShortArray, JString};
use jni::sys::{jint, jlong, jstring};

type WorkerHandle = RecorderWorker;

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
        Ok(Box::into_raw(Box::new(worker)) as jlong)
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
            worker.stop();
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
        match worker.push_samples(&input) {
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
        Ok(worker.status().available_millis as jlong)
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
        Ok(worker.save_latest_async(seconds.max(1) as u32, output_path, options)? as jlong)
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
        Ok(serde_json::to_string(&worker.status())?)
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
        match worker.export_status(job_id as u64) {
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
        Ok(if worker.cancel_export(job_id as u64) {
            0
        } else {
            1
        })
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
    if value.eq_ignore_ascii_case("wav") {
        ExportFormat::Wav
    } else {
        ExportFormat::Mp3
    }
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
