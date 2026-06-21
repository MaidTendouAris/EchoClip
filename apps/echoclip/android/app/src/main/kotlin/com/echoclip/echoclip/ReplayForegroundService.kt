package com.echoclip.echoclip

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import android.content.pm.ServiceInfo
import android.provider.DocumentsContract
import java.io.File
import java.io.FileInputStream
import java.util.ArrayDeque
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.sqrt

class ReplayForegroundService : Service() {
    private var rustBufferHandle: Long = 0
    private var sampleRate: Int = 16_000
    private var bufferSeconds: Int = 1_800
    private var audioRecord: AudioRecord? = null
    private lateinit var runtimeDir: File
    private var captureThread: Thread? = null
    private val saveJobs = ConcurrentHashMap<Long, SaveJobState>()
    private val nextSaveJobId = AtomicLong(1)
    private val levelLock = Any()
    private val levelFrames = ArrayDeque<LevelFrame>(MAX_LEVEL_FRAMES)
    private var levelSquareSum = 0.0
    private var levelPeak = 0
    private var levelSampleCount = 0
    @Volatile
    private var capturedSampleCount: Long = 0
    @Volatile
    private var captureError: String? = null
    @Volatile
    private var shouldCapture = false

    override fun onCreate() {
        super.onCreate()
        activeService = this
        val settings = RecordingStorage.getAudioSettings(this)
        sampleRate = settings.sampleRate
        bufferSeconds = settings.bufferSeconds
        runtimeDir = File(filesDir, "echoclip-runtime").apply { mkdirs() }
        cleanupStaleCacheExports()
        if (filesDir.usableSpace < MIN_INTERNAL_FREE_BYTES) {
            captureError = "storage_low:${filesDir.usableSpace}"
        }
        rustBufferHandle = RustAudioCore.startRecorder(
            tempDir = runtimeDir.absolutePath,
            sampleRate = sampleRate,
            channels = CHANNELS,
            segmentSeconds = SEGMENT_SECONDS,
            maxReplaySeconds = bufferSeconds,
            queueCapacityChunks = QUEUE_CAPACITY_CHUNKS,
        )
        if (rustBufferHandle == 0L) {
            captureError = "rust_recorder_start_failed"
        }
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_SAVE_30) {
            saveLatestClip(30)
            return START_STICKY
        }

        isRunning = true
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        startCapture()
        return START_STICKY
    }

    override fun onDestroy() {
        stopCapture()
        if (rustBufferHandle != 0L) {
            RustAudioCore.stopRecorder(rustBufferHandle)
            RustAudioCore.destroy(rustBufferHandle)
            rustBufferHandle = 0
        }
        isRunning = false
        activeService = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val channel = NotificationChannel(
            CHANNEL_ID,
            "EchoClip 即时回放",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "EchoClip 正在保留最近的音频缓冲"
        }

        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val openIntent = packageManager.getLaunchIntentForPackage(packageName)
        val openPendingIntent = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stopPendingIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, ReplayForegroundService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val savePendingIntent = PendingIntent.getService(
            this,
            2,
            Intent(this, ReplayForegroundService::class.java).setAction(ACTION_SAVE_30),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("EchoClip 正在缓冲")
            .setContentText("即时回放模式已启动，正在保留最近的麦克风音频。")
            .setContentIntent(openPendingIntent)
            .setOngoing(true)
            .addAction(android.R.drawable.ic_menu_save, "保存 30 秒", savePendingIntent)
            .addAction(android.R.drawable.ic_media_pause, "停止", stopPendingIntent)
            .build()
    }

    private fun startCapture() {
        if (shouldCapture) {
            return
        }

        val minBufferSize = AudioRecord.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        if (minBufferSize <= 0) {
            captureError = "invalid_min_buffer:$minBufferSize"
            return
        }

        val record = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            minBufferSize * 2,
        )
        if (record.state != AudioRecord.STATE_INITIALIZED) {
            captureError = "audio_record_not_initialized"
            record.release()
            return
        }
        audioRecord = record
        shouldCapture = true
        captureError = null

        captureThread = Thread {
            val chunk = ShortArray(minBufferSize / BYTES_PER_SAMPLE)
            try {
                record.startRecording()
                while (shouldCapture) {
                    val read = record.read(chunk, 0, chunk.size)
                    if (read > 0) {
                        pushSamples(chunk, read)
                        updateLevels(chunk, read)
                    }
                }
            } catch (_: SecurityException) {
                captureError = "microphone_permission_lost"
                shouldCapture = false
            } catch (error: Exception) {
                captureError = "capture_exception:${error.javaClass.simpleName}:${error.message}"
                shouldCapture = false
            } finally {
                runCatching { record.stop() }
                record.release()
            }
        }.apply {
            name = "EchoClipAudioCapture"
            isDaemon = true
            start()
        }
    }

    private fun stopCapture() {
        shouldCapture = false
        captureThread?.join(500)
        captureThread = null
        audioRecord = null
    }

    private fun pushSamples(samples: ShortArray, count: Int) {
        if (rustBufferHandle != 0L) {
            when (RustAudioCore.pushPcm(rustBufferHandle, samples, count)) {
                PushCode.OK -> capturedSampleCount += count.toLong()
                PushCode.QUEUE_FULL -> captureError = "pcm_queue_full"
                PushCode.WORKER_STOPPED -> captureError = "pcm_worker_stopped"
                PushCode.INVALID_HANDLE -> captureError = "pcm_invalid_handle"
                PushCode.PANIC_CAUGHT -> captureError = "pcm_panic_caught"
                PushCode.QUEUE_CLOSED -> captureError = "pcm_queue_closed"
                PushCode.OTHER_ERROR -> captureError = "pcm_push_failed"
                else -> captureError = "pcm_unknown_push_code"
            }
        }
    }

    fun saveLatestClip(seconds: Int): Map<String, Any?> {
        return try {
            saveLatestClipInternal(seconds)
        } catch (error: Exception) {
            mapOf(
                "saved" to false,
                "error" to "exception:${error.javaClass.simpleName}:${error.message}",
            )
        }
    }

    private fun saveLatestClipInternal(seconds: Int): Map<String, Any?> {
        if (rustBufferHandle == 0L) {
            return mapOf(
                "saved" to false,
                "error" to "rust_buffer_unavailable",
            )
        }

        if (RustAudioCore.availableMillis(rustBufferHandle) <= 0L) {
            return mapOf(
                "saved" to false,
                "error" to "buffer_empty",
            )
        }

        val folderUri = RecordingStorage.getRecordingFolderUri(this)
            ?: return mapOf(
                "saved" to false,
                "error" to "recording_folder_not_selected",
            )
        val exportSettings = RecordingStorage.getExportSettings(this)

        cleanupFinishedSaveJobs()
        val saveJobId = nextSaveJobId.getAndIncrement()
        val timestamp = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())
        val state = SaveJobState(
            id = saveJobId,
            requestedSeconds = seconds,
            state = "Queued",
            createdMs = SystemClock.elapsedRealtime(),
        )
        saveJobs[saveJobId] = state
        Thread {
            runSaveJob(state, seconds, folderUri, timestamp, exportSettings)
        }.apply {
            name = "EchoClipSaveJob-$saveJobId"
            isDaemon = true
            start()
        }

        return mapOf(
            "saved" to true,
            "pending" to true,
            "jobId" to saveJobId,
            "state" to state.state,
            "format" to exportSettings.format,
        )
    }

    fun status(): Map<String, Any?> {
        val clockMs = SystemClock.elapsedRealtime()
        val framesCopy = synchronized(levelLock) {
            levelFrames.map {
                mapOf(
                    "level" to it.level.toDouble(),
                    "timestampMs" to it.timestampMs,
                )
            }
        }
        val rustStatus = if (rustBufferHandle == 0L) {
            RustRecorderStatus(lastError = captureError)
        } else {
            RustAudioCore.status(rustBufferHandle)
        }
        val exportSettings = RecordingStorage.getExportSettings(this)
        val ffmpegPath = resolveFfmpegPath()
        return mapOf(
            "running" to isRunning,
            "availableSeconds" to (rustStatus.availableMillis / 1_000L).toInt(),
            "availableMillis" to rustStatus.availableMillis,
            "levelFrames" to framesCopy,
            "levelClockMs" to clockMs,
            "captureError" to (captureError ?: rustStatus.lastError),
            "backend" to RustAudioCore.backendName(),
            "sampleRate" to sampleRate,
            "bufferSeconds" to bufferSeconds,
            "segmentCount" to rustStatus.segmentCount,
            "queuedChunks" to rustStatus.queuedChunks,
            "droppedChunks" to rustStatus.droppedChunks,
            "activeExports" to rustStatus.activeExports,
            "rustExportJobs" to rustStatus.exportJobs.map { it.toMap() },
            "saveJobs" to saveJobs.values.sortedByDescending { it.id }.take(MAX_SAVE_JOB_HISTORY)
                .map { it.toMap() },
            "tempBytes" to rustStatus.tempBytes,
            "estimatedMaxPcmBytes" to rustStatus.estimatedMaxPcmBytes,
            "internalUsableBytes" to filesDir.usableSpace,
            "internalTotalBytes" to filesDir.totalSpace,
            "oldestRetainedMillis" to rustStatus.oldestRetainedMillis,
            "latestSampleMillis" to rustStatus.latestSampleMillis,
            "writerLastFlushUnixMillis" to rustStatus.writerLastFlushUnixMillis,
            "recovered" to rustStatus.recovered,
            "recoveryWarning" to rustStatus.recoveryWarning,
            "exportFormat" to exportSettings.format,
            "mp3BitrateKbps" to exportSettings.mp3BitrateKbps,
            "ffmpegAvailable" to (ffmpegPath != null),
            "ffmpegPath" to ffmpegPath,
        )
    }

    fun cancelSaveJob(jobId: Long): Map<String, Any?> {
        val job = saveJobs[jobId] ?: return mapOf(
            "canceled" to false,
            "error" to "save_job_not_found",
        )
        job.cancelRequested = true
        if (job.rustJobId != 0L) {
            RustAudioCore.cancelExport(rustBufferHandle, job.rustJobId)
        }
        if (job.state == "Queued" || job.state == "Exporting" || job.state == "CopyingToSaf") {
            job.state = "Canceling"
        }
        return mapOf(
            "canceled" to true,
            "jobId" to jobId,
            "state" to job.state,
        )
    }

    fun meterStatus(): Map<String, Any?> {
        val clockMs = SystemClock.elapsedRealtime()
        val levels = synchronized(levelLock) {
            val latest = levelFrames.lastOrNull()
            var peak = 0.0f
            for (frame in levelFrames.descendingIterator()) {
                if (clockMs - frame.timestampMs > PEAK_HOLD_MILLIS) {
                    break
                }
                peak = maxOf(peak, frame.level)
            }
            val level = if (latest == null || clockMs - latest.timestampMs > LEVEL_STALE_MILLIS) {
                0.0f
            } else {
                latest.level
            }
            level to peak
        }
        return mapOf(
            "running" to isRunning,
            "availableMillis" to availableMillis(),
            "level" to levels.first.toDouble(),
            "peakLevel" to levels.second.toDouble(),
            "captureError" to captureError,
        )
    }

    private fun availableMillis(): Long {
        if (rustBufferHandle != 0L) {
            return RustAudioCore.availableMillis(rustBufferHandle)
        }
        return 0L
    }

    private fun updateLevels(samples: ShortArray, count: Int) {
        if (count <= 0) {
            return
        }

        val usable = min(count, samples.size)
        synchronized(levelLock) {
            val frameSamples = maxOf(1, sampleRate * LEVEL_FRAME_MILLIS / 1_000)
            for (index in 0 until usable) {
                val value = abs(samples[index].toInt())
                levelPeak = maxOf(levelPeak, value)
                levelSquareSum += value.toDouble() * value.toDouble()
                levelSampleCount += 1

                if (levelSampleCount >= frameSamples) {
                    val rms = sqrt(levelSquareSum / levelSampleCount) / Short.MAX_VALUE
                    val peakLevel = levelPeak.toDouble() / Short.MAX_VALUE
                    val next = sqrt(((rms * 0.82) + (peakLevel * 0.18)).coerceIn(0.0, 1.0)).toFloat()
                    appendLevelFrame(next)
                    levelSquareSum = 0.0
                    levelPeak = 0
                    levelSampleCount = 0
                }
            }
        }
    }

    private fun appendLevelFrame(level: Float) {
        if (levelFrames.size >= MAX_LEVEL_FRAMES) {
            levelFrames.removeFirst()
        }
        val smoothed = if (levelFrames.isEmpty()) {
            level
        } else {
            levelFrames.last.level * 0.25f + level * 0.75f
        }
        levelFrames.addLast(LevelFrame(smoothed, SystemClock.elapsedRealtime()))
    }

    private fun waitForExport(job: SaveJobState, jobId: Long): RustExportStatus {
        var last = RustAudioCore.exportStatus(rustBufferHandle, jobId)
        val start = SystemClock.elapsedRealtime()
        while (last.state == "Pending" || last.state == "Running") {
            if (job.cancelRequested) {
                RustAudioCore.cancelExport(rustBufferHandle, jobId)
                return last.copy(state = "Canceled", error = "canceled")
            }
            if (SystemClock.elapsedRealtime() - start > EXPORT_WAIT_TIMEOUT_MILLIS) {
                return last.copy(state = "Failed", error = "export_timeout")
            }
            Thread.sleep(EXPORT_POLL_INTERVAL_MILLIS)
            last = RustAudioCore.exportStatus(rustBufferHandle, jobId)
        }
        return last
    }

    private fun runSaveJob(
        state: SaveJobState,
        seconds: Int,
        folderUri: Uri,
        timestamp: String,
        exportSettings: ExportSettings,
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
            cacheFile = File(cacheDir, "echoclip-export-$timestamp-${seconds}s.$extension")
            val rustJobId = RustAudioCore.saveLatestToCache(
                rustBufferHandle,
                seconds,
                cacheFile.absolutePath,
                exportSettings.format,
                exportSettings.mp3BitrateKbps,
                resolveFfmpegPath(),
            )
            state.rustJobId = rustJobId
            if (rustJobId == 0L) {
                state.fail("export_job_start_failed")
                return
            }
            if (state.cancelRequested) {
                RustAudioCore.cancelExport(rustBufferHandle, rustJobId)
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
                contentResolver,
                parentDocumentUri,
                mimeTypeForExport(exportSettings.format),
                displayName,
            ) ?: run {
                state.fail("create_document_failed")
                return
            }

            try {
                copyFileToDocument(contentResolver, outputUri, cacheFile, state)
            } catch (error: Exception) {
                runCatching { DocumentsContract.deleteDocument(contentResolver, outputUri) }
                if (state.cancelRequested) {
                    state.cancel()
                    return
                }
                state.fail("write_failed:${error.javaClass.simpleName}:${error.message}")
                return
            }

            state.uri = outputUri.toString()
            state.state = "Finished"
            state.finishedMs = SystemClock.elapsedRealtime()
        } catch (error: Exception) {
            state.fail("exception:${error.javaClass.simpleName}:${error.message}")
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
                val buffer = ByteArray(COPY_BUFFER_BYTES)
                while (true) {
                    if (state.cancelRequested) {
                        throw InterruptedException("copy_canceled")
                    }
                    val read = input.read(buffer)
                    if (read < 0) {
                        break
                    }
                    destination.write(buffer, 0, read)
                    state.copyBytesWritten += read.toLong()
                }
            }
        }
    }

    private fun cleanupStaleCacheExports() {
        cacheDir.listFiles()
            ?.filter { it.name.startsWith("echoclip-export-") }
            ?.forEach { it.delete() }
    }

    private fun resolveFfmpegPath(): String? {
        val candidates = listOf(
            File(applicationInfo.nativeLibraryDir, "libffmpeg.so"),
            File(filesDir, "ffmpeg"),
            File(filesDir, "ffmpeg/ffmpeg"),
            File(applicationInfo.nativeLibraryDir, "ffmpeg"),
        )
        return candidates.firstOrNull { it.exists() && it.canExecute() }?.absolutePath
    }

    private fun mimeTypeForExport(format: String): String {
        return when (format.lowercase(Locale.US)) {
            "wav" -> "audio/wav"
            else -> "audio/mpeg"
        }
    }

    private fun cleanupFinishedSaveJobs() {
        val finished = saveJobs.values
            .filter { it.state == "Finished" || it.state == "Failed" || it.state == "Canceled" }
            .sortedByDescending { it.finishedMs ?: it.createdMs }
            .drop(MAX_SAVE_JOB_HISTORY)
        for (job in finished) {
            saveJobs.remove(job.id)
        }
    }

    companion object {
        const val ACTION_STOP = "com.echoclip.echoclip.STOP_REPLAY"
        const val ACTION_SAVE_30 = "com.echoclip.echoclip.SAVE_30"
        private const val CHANNEL_ID = "echoclip_replay"
        private const val NOTIFICATION_ID = 4102
        private const val CHANNELS = 1
        private const val BYTES_PER_SAMPLE = 2
        private const val SEGMENT_SECONDS = 60
        private const val QUEUE_CAPACITY_CHUNKS = 32
        private const val LEVEL_FRAME_MILLIS = 50
        private const val LEVEL_STALE_MILLIS = 300
        private const val PEAK_HOLD_MILLIS = 1_600
        private const val MAX_LEVEL_FRAMES = 160
        private const val EXPORT_POLL_INTERVAL_MILLIS = 100L
        private const val EXPORT_WAIT_TIMEOUT_MILLIS = 10 * 60 * 1_000L
        private const val MIN_INTERNAL_FREE_BYTES = 256L * 1024L * 1024L
        private const val MAX_SAVE_JOB_HISTORY = 32
        private const val COPY_BUFFER_BYTES = 256 * 1024

        @Volatile
        var isRunning: Boolean = false

        @Volatile
        var activeService: ReplayForegroundService? = null
    }
}

private data class LevelFrame(
    val level: Float,
    val timestampMs: Long,
)

private class SaveJobState(
    val id: Long,
    val requestedSeconds: Int,
    @Volatile var state: String,
    val createdMs: Long,
) {
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
