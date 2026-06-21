package com.echoclip.echoclip

import org.json.JSONObject

object RustAudioCore {
    private val nativeAvailable: Boolean = runCatching {
        System.loadLibrary("echoclip_android_jni")
    }.isSuccess

    fun backendName(): String = if (nativeAvailable) {
        "rust+jni+segments"
    } else {
        "rust-native-unavailable"
    }

    fun startRecorder(
        tempDir: String,
        sampleRate: Int,
        channels: Int,
        segmentSeconds: Int,
        maxReplaySeconds: Int,
        queueCapacityChunks: Int,
    ): Long {
        if (!nativeAvailable) {
            return 0L
        }
        return runCatching {
            nativeStartRecorder(
                tempDir,
                sampleRate,
                channels,
                segmentSeconds,
                maxReplaySeconds,
                queueCapacityChunks,
            )
        }.getOrDefault(0L)
    }

    fun destroy(handle: Long) {
        if (nativeAvailable && handle != 0L) {
            runCatching { nativeDestroy(handle) }
        }
    }

    fun stopRecorder(handle: Long) {
        if (nativeAvailable && handle != 0L) {
            runCatching { nativeStopRecorder(handle) }
        }
    }

    fun pushPcm(handle: Long, samples: ShortArray, count: Int): Int {
        if (!nativeAvailable || handle == 0L) {
            return PushCode.INVALID_HANDLE
        }
        return runCatching {
            nativePushPcm(handle, samples, count)
        }.getOrDefault(PushCode.PANIC_CAUGHT)
    }

    fun availableMillis(handle: Long): Long {
        if (!nativeAvailable || handle == 0L) {
            return 0L
        }
        return runCatching {
            nativeAvailableMillis(handle)
        }.getOrDefault(0L)
    }

    fun status(handle: Long): RustRecorderStatus {
        if (!nativeAvailable || handle == 0L) {
            return RustRecorderStatus(lastError = "native_unavailable")
        }
        val json = runCatching { nativeStatusJson(handle) }.getOrNull()
        return RustRecorderStatus.fromJson(json)
    }

    fun saveLatestToCache(
        handle: Long,
        seconds: Int,
        outputPath: String,
        format: String,
        mp3BitrateKbps: Int,
        ffmpegPath: String?,
    ): Long {
        if (!nativeAvailable || handle == 0L) {
            return 0L
        }
        return runCatching {
            nativeSaveLatestToCache(
                handle,
                seconds,
                outputPath,
                format,
                mp3BitrateKbps,
                ffmpegPath.orEmpty(),
            )
        }.getOrDefault(0L)
    }

    fun exportStatus(handle: Long, jobId: Long): RustExportStatus {
        if (!nativeAvailable || handle == 0L || jobId == 0L) {
            return RustExportStatus(
                id = jobId,
                state = "Failed",
                error = "native_unavailable",
            )
        }
        val json = runCatching { nativeExportStatusJson(handle, jobId) }.getOrNull()
        return RustExportStatus.fromJson(json, jobId)
    }

    fun cancelExport(handle: Long, jobId: Long): Boolean {
        if (!nativeAvailable || handle == 0L || jobId == 0L) {
            return false
        }
        return runCatching {
            nativeCancelExport(handle, jobId) == 0
        }.getOrDefault(false)
    }

    private external fun nativeStartRecorder(
        tempDir: String,
        sampleRate: Int,
        channels: Int,
        segmentSeconds: Int,
        maxReplaySeconds: Int,
        queueCapacityChunks: Int,
    ): Long

    private external fun nativeDestroy(handle: Long)
    private external fun nativeStopRecorder(handle: Long)
    private external fun nativePushPcm(handle: Long, samples: ShortArray, count: Int): Int
    private external fun nativeAvailableMillis(handle: Long): Long
    private external fun nativeSaveLatestToCache(
        handle: Long,
        seconds: Int,
        outputPath: String,
        format: String,
        mp3BitrateKbps: Int,
        ffmpegPath: String,
    ): Long
    private external fun nativeStatusJson(handle: Long): String
    private external fun nativeExportStatusJson(handle: Long, jobId: Long): String
    private external fun nativeCancelExport(handle: Long, jobId: Long): Int
}

object PushCode {
    const val OK = 0
    const val QUEUE_FULL = 1
    const val WORKER_STOPPED = 2
    const val INVALID_HANDLE = 3
    const val PANIC_CAUGHT = 4
    const val QUEUE_CLOSED = 5
    const val OTHER_ERROR = 6
}

data class RustRecorderStatus(
    val running: Boolean = false,
    val availableMillis: Long = 0L,
    val oldestRetainedMillis: Long = 0L,
    val latestSampleMillis: Long = 0L,
    val totalSamplesWritten: Long = 0L,
    val retainedStartSample: Long = 0L,
    val segmentCount: Int = 0,
    val tempBytes: Long = 0L,
    val estimatedMaxPcmBytes: Long = 0L,
    val queueCapacityChunks: Int = 0,
    val queuedChunks: Int = 0,
    val droppedChunks: Long = 0L,
    val activeExports: Int = 0,
    val exportJobs: List<RustExportStatus> = emptyList(),
    val writerLastFlushUnixMillis: Long = 0L,
    val recovered: Boolean = false,
    val recoveryWarning: String? = null,
    val lastError: String? = null,
) {
    companion object {
        fun fromJson(json: String?): RustRecorderStatus {
            if (json.isNullOrBlank()) {
                return RustRecorderStatus(lastError = "empty_status")
            }
            return runCatching {
                val value = JSONObject(json)
                RustRecorderStatus(
                    running = value.optBoolean("running"),
                    availableMillis = value.optLong("available_millis"),
                    oldestRetainedMillis = value.optLong("oldest_retained_millis"),
                    latestSampleMillis = value.optLong("latest_sample_millis"),
                    totalSamplesWritten = value.optLong("total_samples_written"),
                    retainedStartSample = value.optLong("retained_start_sample"),
                    segmentCount = value.optInt("segment_count"),
                    tempBytes = value.optLong("temp_bytes"),
                    estimatedMaxPcmBytes = value.optLong("estimated_max_pcm_bytes"),
                    queueCapacityChunks = value.optInt("queue_capacity_chunks"),
                    queuedChunks = value.optInt("queued_chunks"),
                    droppedChunks = value.optLong("dropped_chunks"),
                    activeExports = value.optInt("active_exports"),
                    exportJobs = buildList {
                        val jobs = value.optJSONArray("export_jobs")
                        if (jobs != null) {
                            for (index in 0 until jobs.length()) {
                                add(RustExportStatus.fromJson(jobs.optJSONObject(index)?.toString(), 0L))
                            }
                        }
                    },
                    writerLastFlushUnixMillis = value.optLong("writer_last_flush_unix_millis"),
                    recovered = value.optBoolean("recovered"),
                    recoveryWarning = value.optString("recovery_warning").ifBlank { null },
                    lastError = value.optString("last_error").ifBlank { null },
                )
            }.getOrElse {
                RustRecorderStatus(lastError = "status_parse_failed:${it.message}")
            }
        }
    }
}

data class RustExportStatus(
    val id: Long,
    val state: String,
    val requestedSeconds: Int = 0,
    val outputPath: String? = null,
    val samplesWritten: Long = 0L,
    val format: String? = null,
    val error: String? = null,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "id" to id,
        "state" to state,
        "requestedSeconds" to requestedSeconds,
        "outputPath" to outputPath,
        "samplesWritten" to samplesWritten,
        "format" to format,
        "error" to error,
    )

    companion object {
        fun fromJson(json: String?, fallbackId: Long): RustExportStatus {
            if (json.isNullOrBlank()) {
                return RustExportStatus(fallbackId, "Failed", error = "empty_export_status")
            }
            return runCatching {
                val value = JSONObject(json)
                RustExportStatus(
                    id = value.optLong("id", fallbackId),
                    state = value.optString("state", "Failed"),
                    requestedSeconds = value.optInt("requested_seconds"),
                    outputPath = value.optString("output_path").ifBlank { null },
                    samplesWritten = value.optLong("samples_written"),
                    format = value.optString("format").ifBlank { null },
                    error = value.optString("error").ifBlank { null },
                )
            }.getOrElse {
                RustExportStatus(fallbackId, "Failed", error = "export_parse_failed:${it.message}")
            }
        }
    }
}
