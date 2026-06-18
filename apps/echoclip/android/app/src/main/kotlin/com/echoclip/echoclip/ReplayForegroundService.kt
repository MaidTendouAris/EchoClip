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
import java.io.BufferedOutputStream
import java.io.DataOutputStream
import java.util.ArrayDeque
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.sqrt

class ReplayForegroundService : Service() {
    private var rustBufferHandle: Long = 0
    private var sampleRate: Int = 16_000
    private var bufferSeconds: Int = 1_800
    private var audioRecord: AudioRecord? = null
    private var captureThread: Thread? = null
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
        rustBufferHandle = RustAudioCore.create(sampleRate, CHANNELS, bufferSeconds)
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
            RustAudioCore.push(rustBufferHandle, samples, count)
            capturedSampleCount += count.toLong()
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

        val clip = RustAudioCore.latest(rustBufferHandle, seconds)
        val sampleCount = clip.size

        if (sampleCount <= 0) {
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

        val timestamp = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())
        val displayName = "echoclip-$timestamp-${sampleCount / sampleRate}s.wav"
        val parentDocumentUri = DocumentsContract.buildDocumentUriUsingTree(
            folderUri,
            DocumentsContract.getTreeDocumentId(folderUri),
        )
        val outputUri = DocumentsContract.createDocument(
            contentResolver,
            parentDocumentUri,
            "audio/wav",
            displayName,
        ) ?: return mapOf(
            "saved" to false,
            "error" to "create_document_failed",
        )

        try {
            writeWav(contentResolver, outputUri, clip)
        } catch (error: Exception) {
            runCatching { DocumentsContract.deleteDocument(contentResolver, outputUri) }
            return mapOf(
                "saved" to false,
                "error" to "write_failed:${error.javaClass.simpleName}:${error.message}",
            )
        }

        return mapOf(
            "saved" to true,
            "name" to displayName,
            "uri" to outputUri.toString(),
            "durationSeconds" to sampleCount / sampleRate,
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
        return mapOf(
            "running" to isRunning,
            "availableSeconds" to if (rustBufferHandle == 0L) {
                0
            } else {
                RustAudioCore.availableSeconds(rustBufferHandle)
            },
            "availableMillis" to availableMillis(),
            "levelFrames" to framesCopy,
            "levelClockMs" to clockMs,
            "captureError" to captureError,
            "backend" to RustAudioCore.backendName(),
            "sampleRate" to sampleRate,
            "bufferSeconds" to bufferSeconds,
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
        val millis = if (sampleRate <= 0) {
            0L
        } else {
            capturedSampleCount * 1_000L / sampleRate
        }
        return min(millis, bufferSeconds * 1_000L)
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

    private fun writeWav(resolver: ContentResolver, outputUri: Uri, samples: ShortArray) {
        val output = resolver.openOutputStream(outputUri, "w")
            ?: throw IllegalStateException("Unable to open output document")
        DataOutputStream(BufferedOutputStream(output)).use { stream ->
            val dataSize = samples.size * BYTES_PER_SAMPLE
            stream.writeBytes("RIFF")
            stream.writeIntLe(36 + dataSize)
            stream.writeBytes("WAVE")
            stream.writeBytes("fmt ")
            stream.writeIntLe(16)
            stream.writeShortLe(1)
            stream.writeShortLe(CHANNELS)
            stream.writeIntLe(sampleRate)
            stream.writeIntLe(sampleRate * CHANNELS * BYTES_PER_SAMPLE)
            stream.writeShortLe(CHANNELS * BYTES_PER_SAMPLE)
            stream.writeShortLe(16)
            stream.writeBytes("data")
            stream.writeIntLe(dataSize)
            for (sample in samples) {
                stream.writeShortLe(sample.toInt())
            }
        }
    }

    companion object {
        const val ACTION_STOP = "com.echoclip.echoclip.STOP_REPLAY"
        const val ACTION_SAVE_30 = "com.echoclip.echoclip.SAVE_30"
        private const val CHANNEL_ID = "echoclip_replay"
        private const val NOTIFICATION_ID = 4102
        private const val CHANNELS = 1
        private const val BYTES_PER_SAMPLE = 2
        private const val LEVEL_FRAME_MILLIS = 50
        private const val LEVEL_STALE_MILLIS = 300
        private const val PEAK_HOLD_MILLIS = 1_600
        private const val MAX_LEVEL_FRAMES = 160

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

private fun DataOutputStream.writeIntLe(value: Int) {
    write(ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(value).array())
}

private fun DataOutputStream.writeShortLe(value: Int) {
    write(ByteBuffer.allocate(2).order(ByteOrder.LITTLE_ENDIAN).putShort(value.toShort()).array())
}
