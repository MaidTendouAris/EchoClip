package com.echoclip.echoclip

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import android.os.SystemClock
import android.provider.DocumentsContract
import java.io.File
import org.json.JSONObject
import java.io.InputStream
import java.io.OutputStream
import java.io.FileInputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong

/** Process-scoped exports remain queryable when the recorder service stops. */
internal object ClipSaveJobs {
    val jobs = ConcurrentHashMap<Long, SaveJobState>()
    private val nextId = AtomicLong(1)
    private val recorder = ReplayRecorderOwner { handle ->
        RustAudioCore.stopRecorder(handle)
        RustAudioCore.destroy(handle)
    }

    fun acquireRecorder(context: Context): RecorderLease {
        val settings = RecordingStorage.getAudioSettings(context)
        return recorder.acquire(settings) {
            val runtime = File(context.filesDir, "echoclip-runtime").apply { mkdirs() }
            RustAudioCore.startRecorder(runtime.absolutePath, settings.sampleRate,
                1, 60, settings.bufferSeconds, 32)
        }
    }

    fun bufferWindow(context: Context): Map<String, Any?> {
        val lease = acquireRecorder(context)
        try { return RustAudioCore.bufferWindow(lease.handle) }
        finally { if (lease.handle != 0L) recorder.release(lease.handle) }
    }

    fun start(context: Context, seconds: Int, handle: Long = 0L,
              formatOverride: String? = null, bitrateOverride: Int? = null, range: Map<String, Any?>? = null): Map<String, Any?> {
        val app = context.applicationContext
        val folder = RecordingStorage.getRecordingFolderUri(app)
            ?: return mapOf("saved" to false, "error" to "recording_folder_not_selected")
        val stored = RecordingStorage.getExportSettings(app)
        val settings = ExportSettings(
            format = formatOverride?.let { RecordingStorage.sanitizeExportFormat(it) }
                ?: stored.format,
            mp3BitrateKbps = bitrateOverride ?: stored.mp3BitrateKbps,
        )
        if (settings.format == "wav" && seconds > 14_400) {
            return mapOf("saved" to false, "error" to "wav_duration_limit_4_hours")
        }
        val job = SaveJobState(nextId.getAndIncrement(), seconds.coerceAtLeast(1), "Queued",
            SystemClock.elapsedRealtime())
        val capturedLease = if (handle != 0L) recorder.retain(handle) else null
        jobs[job.id] = job
        Thread {
            var lease = capturedLease
            try {
                if (job.cancelRequested) { job.cancel(); return@Thread }
                lease = lease ?: acquireRecorder(app)
                val nativeHandle = lease.handle
                if (nativeHandle == 0L) { job.fail("rust_buffer_unavailable"); return@Thread }
                if (RustAudioCore.availableMillis(nativeHandle) <= 0L) {
                    job.fail("buffer_empty"); return@Thread
                }
                val ffmpeg = listOf(File(app.applicationInfo.nativeLibraryDir, "libffmpeg.so"),
                    File(app.filesDir, "ffmpeg"), File(app.filesDir, "ffmpeg/ffmpeg"),
                    File(app.applicationInfo.nativeLibraryDir, "ffmpeg"))
                    .firstOrNull { it.isFile && it.canExecute() }?.absolutePath
                val timestamp = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())
                ClipSaveRunner(app, nativeHandle, lease.settings.sampleRate, ffmpeg)
                    .runSaveJob(job, job.requestedSeconds, folder, timestamp, settings, range)
            } catch (error: Exception) {
                if (job.cancelRequested) job.cancel()
                else job.fail("export_failed:${error.javaClass.simpleName}:${error.message}")
            } finally {
                lease?.let { if (it.handle != 0L) recorder.release(it.handle) }
                job.settled = true
                jobs.values.filter { it.settled }.sortedByDescending { it.id }
                    .drop(32).forEach { jobs.remove(it.id) }
            }
        }.apply { name = "EchoClipSaveJob-${job.id}"; isDaemon = true; start() }
        return mapOf("saved" to true, "pending" to true, "jobId" to job.id)
    }

    // The service releases its lease after capture stops. Exports retain theirs
    // through encoding, SAF copy, and cancellation cleanup.
    fun releaseRecorder(handle: Long) = recorder.release(handle)

    fun cancel(jobId: Long): Map<String, Any?> {
        val job = jobs[jobId] ?: return mapOf("canceled" to false, "error" to "save_job_not_found")
        return mapOf("canceled" to job.requestCancel(), "jobId" to jobId, "state" to job.state)
    }

    val hasActiveJobs: Boolean get() = jobs.values.any { !it.settled }

    fun status(jobId: Long): Map<String, Any?> {
        val job = jobs[jobId]
            ?: return mapOf("state" to "Failed", "error" to "save_job_not_found")
        val snapshot = job.toMap()
        return if (job.terminal && !job.settled) snapshot + mapOf("state" to "Finalizing")
            else snapshot
    }
}

private class ClipSaveRunner(val context: Context, val handle: Long,
                             val sampleRate: Int, val ffmpegPath: String?) {
    private val EXPORT_WAIT_TIMEOUT_MILLIS = 10 * 60 * 1_000L
    private val EXPORT_POLL_INTERVAL_MILLIS = 100L
    private fun mimeTypeForExport(format: String) = when (format) {
        "wav" -> "audio/wav"
        "flac" -> "audio/flac"
        "ogg" -> "audio/ogg"
        "m4a" -> "audio/mp4"
        "aac" -> "audio/aac"
        else -> "audio/mpeg"
    }
    private fun waitForExport(job: SaveJobState, jobId: Long): RustExportStatus {
        var last = RustAudioCore.exportStatus(handle, jobId)
        var timedOut = false
        val start = SystemClock.elapsedRealtime()
        while (last.state == "Pending" || last.state == "Running") {
            if (job.cancelRequested) {
                RustAudioCore.cancelExport(handle, jobId)
            }
            if (SystemClock.elapsedRealtime() - start > EXPORT_WAIT_TIMEOUT_MILLIS) {
                RustAudioCore.cancelExport(handle, jobId)
                timedOut = true
            }
            Thread.sleep(EXPORT_POLL_INTERVAL_MILLIS)
            last = RustAudioCore.exportStatus(handle, jobId)
        }
        return if (timedOut && !job.cancelRequested)
            last.copy(state = "Failed", error = "export_timeout") else last
    }

    fun runSaveJob(
        state: SaveJobState,
        seconds: Int,
        folderUri: Uri,
        timestamp: String,
        exportSettings: ExportSettings,
        range: Map<String, Any?>? = null,
    ) {
        var cacheFile: File? = null
        try {
            if (state.cancelRequested) {
                state.cancel()
                return
            }
            state.state = "Exporting"
            state.format = exportSettings.format
            val extension = exportSettings.format
            cacheFile = File(context.cacheDir, "echoclip-export-$timestamp-${state.id}-${seconds}s.$extension")
            if (range != null) {
                val window = RustAudioCore.bufferWindow(handle)
                require(range["bufferId"] == window["bufferId"]) { "BUFFER_RANGE_EXPIRED" }
            }
            val rustJobId = RustAudioCore.saveLatestToCache(
                handle,
                seconds,
                cacheFile.absolutePath,
                exportSettings.format,
                exportSettings.mp3BitrateKbps,
                ffmpegPath,
                range?.let { JSONObject(it).toString() },
            )
            state.rustJobId = rustJobId
            if (rustJobId == 0L) {
                state.fail("export_job_start_failed")
                return
            }
            if (state.cancelRequested) {
                RustAudioCore.cancelExport(handle, rustJobId)
            }

            val exportStatus = waitForExport(state, rustJobId)
            if (exportStatus.state == "Canceled" || state.cancelRequested) {
                state.cancel()
                return
            }
            if (exportStatus.state != "Finished") {
                state.fail("export_failed:${exportStatus.error ?: exportStatus.state}")
                return
            }

            state.samplesWritten = exportStatus.samplesWritten
            state.durationSeconds = if (sampleRate <= 0) {
                0L
            } else {
                exportStatus.samplesWritten / sampleRate
            }
            state.state = "CopyingToSaf"
            state.copyTotalBytes = cacheFile.length()
            if (state.cancelRequested) {
                state.cancel()
                return
            }

            val displayName = "echoclip-$timestamp-${state.durationSeconds}s.$extension"
            state.name = displayName
            val parentDocumentUri = DocumentsContract.buildDocumentUriUsingTree(
                folderUri,
                DocumentsContract.getTreeDocumentId(folderUri),
            )
            val outputUri = DocumentsContract.createDocument(
                context.contentResolver,
                parentDocumentUri,
                mimeTypeForExport(exportSettings.format),
                displayName,
            ) ?: run {
                state.fail("create_document_failed")
                return
            }

            try {
                copyFileToDocument(context.contentResolver, outputUri, cacheFile, state)
            } catch (error: Exception) {
                val removed = runCatching {
                    DocumentsContract.deleteDocument(context.contentResolver, outputUri)
                }.getOrDefault(false)
                if (!removed) {
                    state.fail("partial_file_cleanup_failed")
                    return
                }
                if (state.cancelRequested) {
                    state.cancel()
                    return
                }
                state.fail("write_failed:${error.javaClass.simpleName}:${error.message}")
                return
            }

            if (!state.finish(outputUri.toString())) {
                val removed = runCatching {
                    DocumentsContract.deleteDocument(context.contentResolver, outputUri)
                }.getOrDefault(false)
                if (removed) state.cancel() else state.fail("partial_file_cleanup_failed")
            }
        } catch (error: Exception) {
            if (state.cancelRequested) state.cancel()
            else state.fail("exception:${error.javaClass.simpleName}:${error.message}")
        } finally {
            cacheFile?.delete()
        }
    }

    private fun copyFileToDocument(
        resolver: ContentResolver,
        outputUri: Uri,
        source: File,
        state: SaveJobState,
    ) {
        val output = resolver.openOutputStream(outputUri, "w")
            ?: throw IllegalStateException("Unable to open output document")
        output.use { destination ->
            FileInputStream(source).use { input ->
                copyRecording(input, destination, state)
            }
        }
    }

}

internal class SaveJobState(
    val id: Long,
    val requestedSeconds: Int,
    @Volatile var state: String,
    val createdMs: Long,
) {
    @Volatile
    var settled: Boolean = false

    @Volatile
    var rustJobId: Long = 0L

    @Volatile
    var format: String = "mp3"

    @Volatile
    var name: String? = null

    @Volatile
    var uri: String? = null

    @Volatile
    var durationSeconds: Long = 0L

    @Volatile
    var samplesWritten: Long = 0L

    @Volatile
    var copyBytesWritten: Long = 0L

    @Volatile
    var copyTotalBytes: Long = 0L

    @Volatile
    var cancelRequested: Boolean = false

    @Volatile
    var error: String? = null

    @Volatile
    var finishedMs: Long? = null

    val terminal: Boolean get() = state == "Finished" || state == "Failed" || state == "Canceled"

    @Synchronized
    fun requestCancel(): Boolean {
        if (terminal) return false
        cancelRequested = true
        state = "Canceling"
        return true
    }

    @Synchronized
    fun finish(outputUri: String): Boolean {
        if (cancelRequested) return false
        uri = outputUri
        state = "Finished"
        finishedMs = SystemClock.elapsedRealtime()
        return true
    }

    fun fail(message: String) {
        error = message
        state = "Failed"
        finishedMs = SystemClock.elapsedRealtime()
    }

    fun cancel() {
        error = "canceled"
        state = "Canceled"
        finishedMs = SystemClock.elapsedRealtime()
    }

    fun toMap(): Map<String, Any?> = mapOf(
        "id" to id,
        "rustJobId" to rustJobId,
        "requestedSeconds" to requestedSeconds,
        "format" to format,
        "state" to state,
        "name" to name,
        "uri" to uri,
        "durationSeconds" to durationSeconds,
        "samplesWritten" to samplesWritten,
        "copyBytesWritten" to copyBytesWritten,
        "copyTotalBytes" to copyTotalBytes,
        "progress" to if (copyTotalBytes > 0L) {
            copyBytesWritten.toDouble() / copyTotalBytes.toDouble()
        } else {
            null
        },
        "cancelRequested" to cancelRequested,
        "error" to error,
        "createdMs" to createdMs,
        "finishedMs" to finishedMs,
    )
}

/** Check cancellation between chunks, including the last write. */
internal fun copyRecording(input: InputStream, output: OutputStream, job: SaveJobState) {
    val buffer = ByteArray(256 * 1024)
    while (true) {
        if (job.cancelRequested) throw InterruptedException("copy_canceled")
        val read = input.read(buffer)
        if (read < 0) break
        output.write(buffer, 0, read)
        job.copyBytesWritten += read.toLong()
    }
}
