use std::ffi::c_void;
use std::mem::transmute;
use std::ptr;
use std::sync::Mutex;

use echoclip_core::{AudioConfig, RingBuffer};

type JInt = i32;
type JLong = i64;
type JShortArray = *mut c_void;
type JObject = *mut c_void;
type JNIEnv = *mut c_void;

type SharedBuffer = Mutex<RingBuffer>;

const GET_ARRAY_LENGTH_SLOT: usize = 171;
const NEW_SHORT_ARRAY_SLOT: usize = 178;
const GET_SHORT_ARRAY_REGION_SLOT: usize = 202;
const SET_SHORT_ARRAY_REGION_SLOT: usize = 210;

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_echoclip_echoclip_RustAudioCore_nativeCreate(
    _env: JNIEnv,
    _this: JObject,
    sample_rate: JInt,
    channels: JInt,
    capacity_seconds: JInt,
) -> JLong {
    let config = AudioConfig {
        sample_rate: sample_rate.max(1) as u32,
        channels: channels.max(1) as u16,
    };
    let buffer = RingBuffer::new(config, capacity_seconds.max(1) as f32);
    Box::into_raw(Box::new(Mutex::new(buffer))) as JLong
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_echoclip_echoclip_RustAudioCore_nativeDestroy(
    _env: JNIEnv,
    _this: JObject,
    handle: JLong,
) {
    if handle == 0 {
        return;
    }

    unsafe {
        let _ = Box::from_raw(handle as *mut SharedBuffer);
    }
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_echoclip_echoclip_RustAudioCore_nativePush(
    env: JNIEnv,
    _this: JObject,
    handle: JLong,
    samples: JShortArray,
    count: JInt,
) {
    if handle == 0 || samples.is_null() || count <= 0 {
        return;
    }

    let available = unsafe { get_array_length(env, samples) }.min(count);
    if available <= 0 {
        return;
    }

    let mut input = vec![0_i16; available as usize];
    unsafe {
        get_short_array_region(env, samples, 0, available, input.as_mut_ptr());
    }

    let buffer = unsafe { &*(handle as *mut SharedBuffer) };
    if let Ok(mut buffer) = buffer.lock() {
        buffer.push_samples(&input);
    }
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_echoclip_echoclip_RustAudioCore_nativeAvailableSeconds(
    _env: JNIEnv,
    _this: JObject,
    handle: JLong,
) -> JInt {
    if handle == 0 {
        return 0;
    }

    let buffer = unsafe { &*(handle as *mut SharedBuffer) };
    buffer
        .lock()
        .map(|buffer| buffer.available_seconds().floor() as JInt)
        .unwrap_or(0)
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_echoclip_echoclip_RustAudioCore_nativeLatest(
    env: JNIEnv,
    _this: JObject,
    handle: JLong,
    seconds: JInt,
) -> JShortArray {
    if handle == 0 || seconds <= 0 {
        return unsafe { new_short_array(env, 0) };
    }

    let buffer = unsafe { &*(handle as *mut SharedBuffer) };
    let samples = match buffer.lock() {
        Ok(buffer) => buffer.latest(seconds as f32).samples,
        Err(_) => return unsafe { new_short_array(env, 0) },
    };

    let output = unsafe { new_short_array(env, samples.len() as JInt) };
    if output.is_null() {
        return ptr::null_mut();
    }

    unsafe {
        set_short_array_region(env, output, 0, samples.len() as JInt, samples.as_ptr());
    }
    output
}

unsafe fn table(env: JNIEnv) -> *const *const c_void {
    unsafe { *(env as *mut *const *const c_void) }
}

unsafe fn table_fn(env: JNIEnv, slot: usize) -> *const c_void {
    unsafe { *table(env).add(slot) }
}

unsafe fn get_array_length(env: JNIEnv, array: JShortArray) -> JInt {
    let function: extern "system" fn(JNIEnv, JShortArray) -> JInt =
        unsafe { transmute(table_fn(env, GET_ARRAY_LENGTH_SLOT)) };
    function(env, array)
}

unsafe fn new_short_array(env: JNIEnv, len: JInt) -> JShortArray {
    let function: extern "system" fn(JNIEnv, JInt) -> JShortArray =
        unsafe { transmute(table_fn(env, NEW_SHORT_ARRAY_SLOT)) };
    function(env, len)
}

unsafe fn get_short_array_region(
    env: JNIEnv,
    array: JShortArray,
    start: JInt,
    len: JInt,
    output: *mut i16,
) {
    let function: extern "system" fn(JNIEnv, JShortArray, JInt, JInt, *mut i16) =
        unsafe { transmute(table_fn(env, GET_SHORT_ARRAY_REGION_SLOT)) };
    function(env, array, start, len, output);
}

unsafe fn set_short_array_region(
    env: JNIEnv,
    array: JShortArray,
    start: JInt,
    len: JInt,
    input: *const i16,
) {
    let function: extern "system" fn(JNIEnv, JShortArray, JInt, JInt, *const i16) =
        unsafe { transmute(table_fn(env, SET_SHORT_ARRAY_REGION_SLOT)) };
    function(env, array, start, len, input);
}
