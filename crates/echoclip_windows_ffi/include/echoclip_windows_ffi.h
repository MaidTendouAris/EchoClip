#ifndef ECHOCLIP_WINDOWS_FFI_H_
#define ECHOCLIP_WINDOWS_FFI_H_

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#define ECHOCLIP_API __declspec(dllimport)
#else
#define ECHOCLIP_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

enum EchoClipResult {
  ECHOCLIP_OK = 0,
  ECHOCLIP_ERROR_INVALID_ARGUMENT = 1,
  ECHOCLIP_ERROR_CORE = 2,
  ECHOCLIP_ERROR_QUEUE_FULL = 3,
  ECHOCLIP_ERROR_STOPPED = 4,
  ECHOCLIP_ERROR_PANIC = 5,
};

// All strings passed to this API are NUL-terminated UTF-8.
// A handle is an opaque process-local identifier; zero is always invalid.
ECHOCLIP_API uint64_t ec_create(const char *work_dir_utf8,
                                uint32_t sample_rate,
                                uint32_t buffer_seconds);
ECHOCLIP_API void ec_destroy(uint64_t handle);

// Enumerates active Windows microphone endpoints as a UTF-8 JSON array:
// [{"id":"wasapi:...","name":"...","isDefault":true}, ...].
// Returns the required byte count including the trailing NUL. Passing NULL or
// a short buffer only queries the size. Errors are read with ec_last_error(0).
ECHOCLIP_API uintptr_t ec_audio_devices_json(char *output_utf8,
                                            uintptr_t output_capacity);

// Selects microphone/system-loopback sources. microphone_device_id_utf8 may
// be NULL or empty to follow the current Windows default input device. Boolean
// arguments must be exactly 0 or 1, and at least one source must be enabled.
// If capture is already active, it is restarted inside Rust with the new
// selection. System audio always follows the current default output endpoint.
ECHOCLIP_API int32_t ec_configure_capture(
    uint64_t handle,
    int32_t microphone_enabled,
    int32_t system_audio_enabled,
    const char *microphone_device_id_utf8);

// Starts/stops native Windows capture using the configured source selection.
// Each source is resampled and mixed on one fixed-rate timeline inside the DLL
// before being fed to RecorderWorker. Stop is idempotent.
ECHOCLIP_API int32_t ec_start_capture(uint64_t handle);
ECHOCLIP_API int32_t ec_stop_capture(uint64_t handle);

// Test/diagnostic injection only. Production capture uses ec_start_capture.
// sample_count is a count of int16_t mono samples, not a byte count.
ECHOCLIP_API int32_t ec_push_pcm(uint64_t handle,
                                const int16_t *samples,
                                uintptr_t sample_count);
ECHOCLIP_API uint64_t ec_available_millis(uint64_t handle);

// Blocks until the core has joined the requested range and written the WAV.
ECHOCLIP_API int32_t ec_save_latest_wav(uint64_t handle,
                                       uint32_t seconds,
                                       const char *output_path_utf8);

// Stops/flushed the current worker, removes its segment cache, and starts a
// fresh worker with the same configuration. Concurrent pushes wait safely.
ECHOCLIP_API int32_t ec_clear(uint64_t handle);

// Returns 1 while native capture is running, 0 while stopped, or -1 on error.
ECHOCLIP_API int32_t ec_status(uint64_t handle);

// Returns the required byte count including the trailing NUL. Passing NULL or
// a short buffer only queries the size and performs no write. The core worker
// fields are augmented with capture_running, capture_mode, source selections,
// active microphone/system device details, negotiated source formats, mixed
// and per-source levels, bounded-timeline drop/silence counters, capability
// flags, and capture_error. recorder_sample_rate is the post-resampling and
// post-mix core rate.
ECHOCLIP_API uintptr_t ec_status_json(uint64_t handle,
                                     char *output_utf8,
                                     uintptr_t output_capacity);

// The returned UTF-8 string is owned by the DLL. Do not free it. It remains
// valid until the next call that changes the error for this handle, or destroy.
// Passing zero reads the process-global create/invalid-handle error.
ECHOCLIP_API const char *ec_last_error(uint64_t handle);

#ifdef __cplusplus
}
#endif

#endif  // ECHOCLIP_WINDOWS_FFI_H_
