package com.echoclip.echoclip

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.drawable.Icon
import android.net.Uri
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import android.content.pm.ServiceInfo
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.ArrayDeque
import java.util.Locale
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.sqrt

class ReplayForegroundService : Service() {
    private var rustBufferHandle: Long = 0
    private var sampleRate: Int = 16_000
    private var bufferSeconds: Int = 1_800
    private var recordingMode: String = MODE_STANDARD
    private var lockRecordingTrigger: String = TRIGGER_SCREEN_OFF
    @Volatile
    private var evidenceState: String = EVIDENCE_OFF
    @Volatile
    private var evidenceLastStopReason: String? = null
    private var audioRecord: AudioRecord? = null
    private lateinit var runtimeDir: File
    private var captureThread: Thread? = null
    private var screenReceiver: BroadcastReceiver? = null
    private val saveJobs get() = ClipSaveJobs.jobs
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
    private var syncConfigurationError: String? = null
    @Volatile
    private var shouldCapture = false
    @Volatile
    private var schedulerArmed = false
    @Volatile
    private var stopRequested = false
    @Volatile
    private var scheduledExecutionInFlight = false
    @Volatile
    private var sessionStartedUnixMillis: Long = 0L

    override fun onCreate() {
        super.onCreate()
        activeService = this
        val settings = RecordingStorage.getAudioSettings(this)
        val modeSettings = RecordingStorage.getRecordingModeSettings(this)
        sampleRate = settings.sampleRate
        bufferSeconds = settings.bufferSeconds
        recordingMode = modeSettings.mode
        lockRecordingTrigger = modeSettings.trigger
        runtimeDir = File(filesDir, "echoclip-runtime").apply { mkdirs() }
        cleanupStaleCacheExports()
        if (filesDir.usableSpace < MIN_INTERNAL_FREE_BYTES) {
            captureError = "storage_low:${filesDir.usableSpace}"
        }
        val recorder = ClipSaveJobs.acquireRecorder(this)
        rustBufferHandle = recorder.handle
        sampleRate = recorder.settings.sampleRate
        bufferSeconds = recorder.settings.bufferSeconds
        if (rustBufferHandle == 0L) {
            captureError = "rust_recorder_start_failed"
        } else {
            applySyncSettings()
        }
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        stopRequested = false
        if (intent?.action == ACTION_STOP) {
            stopManualCapture()
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_SAVE_30) {
            saveLatestClip(30)
            return START_STICKY
        }
        if (intent?.action == ACTION_SCHEDULE_ARM) {
            schedulerArmed = true
            startAsForeground(buildNotification())
            updateNotification()
            return START_STICKY
        }
        if (intent?.action == ACTION_SCHEDULE_TICK) {
            schedulerArmed = true
            startAsForeground(buildNotification())
            val executions = intent.getStringExtra(EXTRA_SCHEDULE_EXECUTIONS).orEmpty()
            if (executions.isNotBlank()) {
                executeScheduledExecutions(executions)
            }
            return START_STICKY
        }

        val modeSettings = RecordingStorage.getRecordingModeSettings(this)
        recordingMode = intent?.getStringExtra(EXTRA_RECORDING_MODE)?.takeIf {
            it == MODE_STANDARD || it == MODE_LOCKSCREEN
        } ?: modeSettings.mode
        lockRecordingTrigger = intent?.getStringExtra(EXTRA_LOCK_RECORDING_TRIGGER)?.takeIf {
            it == TRIGGER_SCREEN_OFF || it == TRIGGER_KEYGUARD_LOCKED
        } ?: modeSettings.trigger

        val notification = buildNotification()
        startAsForeground(notification)

        if (recordingMode == MODE_LOCKSCREEN) {
            enterEvidenceArmed()
        } else {
            leaveEvidenceMode()
            startCapture()
        }

        return START_STICKY
    }

    private fun startAsForeground(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    override fun onDestroy() {
        stopCapture()
        unregisterScreenReceiver()
        if (rustBufferHandle != 0L) {
            RecordingStorage.setLastAvailableMillis(
                this,
                RustAudioCore.availableMillis(rustBufferHandle),
            )
            ClipSaveJobs.releaseRecorder(rustBufferHandle)
            rustBufferHandle = 0
        }
        isRunning = false
        evidenceState = EVIDENCE_OFF
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
            "EchoClip replay",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "EchoClip keeps a rolling audio replay buffer."
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
            .setContentTitle(notificationTitle())
            .setContentText(notificationText())
            .setContentIntent(openPendingIntent)
            .setOngoing(true)
            .addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(this, android.R.drawable.ic_menu_save),
                    "Save 30s",
                    savePendingIntent,
                ).build(),
            )
            .addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(this, android.R.drawable.ic_media_pause),
                    "Stop",
                    stopPendingIntent,
                ).build(),
            )
            .build()
    }

    private fun notificationTitle(): String {
        return if (recordingMode == MODE_LOCKSCREEN) {
            "EchoClip lock recording"
        } else {
            "EchoClip replay buffer"
        }
    }

    private fun notificationText(): String {
        return when {
            schedulerArmed && !isRunning ->
                "Scheduled tasks are armed. Recording starts only when a task is due."
            recordingMode != MODE_LOCKSCREEN ->
                "Standard recording mode is writing to the replay cache."
            evidenceState == EVIDENCE_RECORDING ->
                "Screen state triggered recording. Audio is being cached."
            evidenceLastStopReason == STOP_REASON_SCREEN_ON ->
                "Recording stopped when the screen turned on. Waiting for the next trigger."
            evidenceLastStopReason == STOP_REASON_USER_PRESENT ->
                "Recording stopped after unlock. Waiting for the next trigger."
            else ->
                "Lock recording mode is armed and will use the microphone after trigger."
        }
    }

    private fun updateNotification() {
        val manager = getSystemService(NotificationManager::class.java) ?: return
        manager.notify(NOTIFICATION_ID, buildNotification())
    }

    private fun enterEvidenceArmed() {
        if (isRunning) {
            stopCapture()
        }
        evidenceState = EVIDENCE_ARMED
        evidenceLastStopReason = null
        registerScreenReceiver()
        updateNotification()
    }

    private fun leaveEvidenceMode() {
        unregisterScreenReceiver()
        evidenceState = EVIDENCE_OFF
        evidenceLastStopReason = null
    }

    private fun registerScreenReceiver() {
        if (screenReceiver != null) {
            return
        }
        screenReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    Intent.ACTION_SCREEN_OFF -> handleScreenOff()
                    Intent.ACTION_SCREEN_ON -> stopEvidenceCapture(STOP_REASON_SCREEN_ON)
                    Intent.ACTION_USER_PRESENT -> stopEvidenceCapture(STOP_REASON_USER_PRESENT)
                }
            }
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        registerReceiver(screenReceiver, filter)
    }

    private fun unregisterScreenReceiver() {
        screenReceiver?.let {
            runCatching { unregisterReceiver(it) }
        }
        screenReceiver = null
    }

    private fun handleScreenOff() {
        if (recordingMode != MODE_LOCKSCREEN || evidenceState != EVIDENCE_ARMED) {
            return
        }
        if (lockRecordingTrigger == TRIGGER_KEYGUARD_LOCKED && !isKeyguardLocked()) {
            return
        }
        evidenceLastStopReason = null
        startEvidenceCapture()
    }

    private fun isKeyguardLocked(): Boolean {
        val manager = getSystemService(KeyguardManager::class.java)
        return manager?.isKeyguardLocked == true
    }

    private fun startEvidenceCapture() {
        if (isRunning) {
            return
        }
        evidenceState = EVIDENCE_RECORDING
        startCapture()
        updateNotification()
    }

    private fun stopEvidenceCapture(reason: String) {
        if (recordingMode != MODE_LOCKSCREEN || !isRunning) {
            return
        }
        stopCapture()
        evidenceState = EVIDENCE_ARMED
        evidenceLastStopReason = reason
        updateNotification()
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
            isRunning = false
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
            isRunning = false
            return
        }
        audioRecord = record
        shouldCapture = true
        isRunning = true
        sessionStartedUnixMillis = System.currentTimeMillis()
        RecordingStorage.setLastSessionStartedUnixMillis(this, sessionStartedUnixMillis)
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
        // Unblock AudioRecord.read before waiting for its thread to finish.
        runCatching { audioRecord?.stop() }
        captureThread?.join(500)
        captureThread = null
        audioRecord = null
        isRunning = false
        if (rustBufferHandle != 0L) {
            RecordingStorage.setLastAvailableMillis(
                this,
                RustAudioCore.availableMillis(rustBufferHandle),
            )
        }
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

    fun setSchedulerArmed(armed: Boolean) {
        schedulerArmed = armed
        releaseIfIdle()
    }

    private fun releaseIfIdle() {
        stopRequested = !schedulerArmed && !isRunning &&
            !scheduledExecutionInFlight && evidenceState == EVIDENCE_OFF
        if (stopRequested) {
            stopSelf()
        } else {
            updateNotification()
        }
    }

    fun applyRecordingMode(settings: RecordingModeSettings): Map<String, Any?> {
        if (recordingMode != settings.mode) {
            // A mode switch starts a paused session. Remove the old screen
            // listener before stopping capture so it cannot restart recording.
            leaveEvidenceMode()
            stopCapture()
        }
        recordingMode = settings.mode
        lockRecordingTrigger = settings.trigger
        releaseIfIdle()
        return recordingControlStatus()
    }

    fun stopManualCapture(): Map<String, Any?> {
        val wasActive = isRunning || evidenceState != EVIDENCE_OFF
        leaveEvidenceMode()
        stopCapture()
        releaseIfIdle()
        return recordingControlStatus() + mapOf("stopped" to wasActive)
    }

    internal fun recordingControlStatus(): Map<String, Any?> = mapOf(
        "running" to isRunning,
        "serviceActive" to !stopRequested,
        "serviceState" to serviceState(),
        "recordingMode" to recordingMode,
        "lockRecordingTrigger" to lockRecordingTrigger,
        "evidenceState" to evidenceState,
        "evidenceLastStopReason" to evidenceLastStopReason,
        "schedulerArmed" to schedulerArmed,
    )

    private fun executeScheduledExecutions(executionsJson: String) {
        scheduledExecutionInFlight = true
        Thread {
            try {
                val executions = runCatching { JSONArray(executionsJson) }.getOrNull()
                    ?: return@Thread
                for (executionIndex in 0 until executions.length()) {
                    val execution = executions.optJSONObject(executionIndex) ?: continue
                    val executionId = execution.optString("executionId")
                    val actions = execution.optJSONArray("actions") ?: JSONArray()
                    val results = JSONArray()
                    for (actionPosition in 0 until actions.length()) {
                        val due = actions.optJSONObject(actionPosition) ?: continue
                        val actionIndex = due.optInt("actionIndex")
                        val action = due.optJSONObject("action") ?: JSONObject()
                        results.put(executeScheduledAction(actionIndex, action))
                    }
                    ScheduleCoordinator.complete(this, executionId, results)
                }
            } finally {
                scheduledExecutionInFlight = false
                ScheduleCoordinator.reschedule(this)
                updateNotification()
            }
        }.apply {
            name = "EchoClipScheduledExecution"
            isDaemon = true
            start()
        }
    }

    private fun executeScheduledAction(
        actionIndex: Int,
        action: JSONObject,
    ): JSONObject {
        return when (action.optString("type")) {
            "set_upload_enabled" -> executeScheduledUpload(
                actionIndex,
                action.optBoolean("enabled"),
            )
            "start_recording" -> {
                if (isRunning) {
                    scheduledResult(actionIndex, "no_op")
                } else {
                    captureError = null
                    startCapture()
                    if (isRunning) {
                        scheduledResult(actionIndex, "succeeded")
                    } else {
                        scheduledResult(
                            actionIndex,
                            "platform_blocked",
                            captureError ?: "PLATFORM_MICROPHONE_BLOCKED",
                        )
                    }
                }
            }
            "stop_recording" -> {
                if (!isRunning) {
                    scheduledResult(actionIndex, "no_op")
                } else {
                    stopCapture()
                    scheduledResult(actionIndex, "succeeded")
                }
            }
            "save_recent" -> executeScheduledSave(
                actionIndex = actionIndex,
                seconds = action.optInt("seconds", 30).coerceIn(1, 86_400),
                format = action.optString("format", "mp3"),
                bitrate = action.optInt("mp3BitrateKbps", 128),
                allowPartial = action.optBoolean("allowPartial", true),
            )
            else -> scheduledResult(actionIndex, "failed", "UNKNOWN_SCHEDULED_ACTION")
        }
    }

    private fun executeScheduledUpload(
        actionIndex: Int,
        enabled: Boolean,
    ): JSONObject {
        val before = RecordingStorage.getSyncSettings(this)
        if (before.enabled == enabled) {
            return scheduledResult(actionIndex, "no_op")
        }
        if (enabled && !before.keyConfigured) {
            return scheduledResult(actionIndex, "failed", "UPLOAD_NOT_CONFIGURED")
        }
        val settings = runCatching {
            RecordingStorage.setSyncSettings(
                context = this,
                enabled = enabled,
                serverHost = before.serverHost,
                uploadPort = before.uploadPort,
                uploadKeyBase64 = null,
                clearKey = false,
            )
        }.getOrElse {
            return scheduledResult(
                actionIndex,
                "failed",
                "UPLOAD_CONFIGURATION_FAILED:${it.javaClass.simpleName}",
            )
        }
        val applied = applySyncSettings()["applied"] == true
        return if (applied || !settings.enabled) {
            scheduledResult(actionIndex, "succeeded")
        } else {
            scheduledResult(actionIndex, "failed", "UPLOAD_APPLY_FAILED")
        }
    }

    private fun executeScheduledSave(
        actionIndex: Int,
        seconds: Int,
        format: String,
        bitrate: Int,
        allowPartial: Boolean,
    ): JSONObject {
        val availableBefore = RustAudioCore.availableMillis(rustBufferHandle)
        if (availableBefore <= 0L) {
            return scheduledResult(actionIndex, "failed", "EXPORT_BUFFER_EMPTY")
        }
        if (!allowPartial && availableBefore < seconds * 1_000L) {
            return scheduledResult(actionIndex, "failed", "EXPORT_RANGE_UNAVAILABLE")
        }
        val response = saveLatestClipInternal(seconds, format, bitrate)
        if (response["saved"] != true) {
            return scheduledResult(
                actionIndex,
                "failed",
                response["error"]?.toString() ?: "EXPORT_FAILED",
            )
        }
        val jobId = (response["jobId"] as? Number)?.toLong()
            ?: return scheduledResult(actionIndex, "failed", "EXPORT_JOB_NOT_FOUND")
        val started = SystemClock.elapsedRealtime()
        while (SystemClock.elapsedRealtime() - started < EXPORT_WAIT_TIMEOUT_MILLIS) {
            val job = saveJobs[jobId]
                ?: return scheduledResult(actionIndex, "failed", "EXPORT_JOB_NOT_FOUND")
            when (job.state) {
                "Finished" -> {
                    val actualMillis = job.durationSeconds * 1_000L
                    val partial = actualMillis < seconds * 1_000L
                    return scheduledResult(
                        actionIndex,
                        if (partial) "partial" else "succeeded",
                        if (partial) "EXPORT_PARTIAL_DURATION" else null,
                        job.uri,
                        actualMillis,
                    )
                }
                "Failed", "Canceled" -> return scheduledResult(
                    actionIndex,
                    "failed",
                    job.error ?: "EXPORT_FAILED",
                )
            }
            Thread.sleep(EXPORT_POLL_INTERVAL_MILLIS)
        }
        return scheduledResult(actionIndex, "failed", "EXPORT_TIMEOUT")
    }

    private fun scheduledResult(
        actionIndex: Int,
        state: String,
        errorCode: String? = null,
        outputUri: String? = null,
        actualDurationMillis: Long? = null,
    ): JSONObject = JSONObject()
        .put("actionIndex", actionIndex)
        .put("state", state)
        .put("errorCode", errorCode ?: JSONObject.NULL)
        .put("outputUri", outputUri ?: JSONObject.NULL)
        .put("actualDurationMillis", actualDurationMillis ?: JSONObject.NULL)
    fun saveLatestClip(seconds: Int): Map<String, Any?> {
        return try {
            saveLatestClipInternal(seconds, null, null)
        } catch (error: Exception) {
            mapOf(
                "saved" to false,
                "error" to "exception:${error.javaClass.simpleName}:${error.message}",
            )
        }
    }

    private fun saveLatestClipInternal(
        seconds: Int,
        formatOverride: String?,
        bitrateOverride: Int?,
    ): Map<String, Any?> {
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

        return ClipSaveJobs.start(this, seconds, rustBufferHandle, formatOverride,
            bitrateOverride)
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
            "serviceActive" to !stopRequested,
            "serviceState" to serviceState(),
            "statusCode" to serviceState(),
            "recordingMode" to recordingMode,
            "lockRecordingTrigger" to lockRecordingTrigger,
            "evidenceState" to evidenceState,
            "evidenceLastStopReason" to evidenceLastStopReason,
            "availableSeconds" to (rustStatus.availableMillis / 1_000L).toInt(),
            "availableMillis" to rustStatus.availableMillis,
            "sessionStartedUnixMillis" to if (isRunning) sessionStartedUnixMillis else 0L,
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
            "syncConfigured" to rustStatus.syncConfigured,
            "syncStatus" to rustStatus.sync?.toMap(),
            "syncConfigurationError" to syncConfigurationError,
        )
    }

    fun applySyncSettings(): Map<String, Any?> {
        val settings = RecordingStorage.getSyncSettings(this)
        val uploadKey = if (settings.enabled) RecordingStorage.getSyncUploadKey(this) else ""
        val applied = if (rustBufferHandle == 0L) {
            !settings.enabled
        } else {
            RustAudioCore.configureSync(
                handle = rustBufferHandle,
                enabled = settings.enabled,
                serverUrl = settings.serverUrl,
                uploadKeyBase64 = uploadKey.orEmpty(),
                deviceId = settings.deviceId,
            )
        }
        syncConfigurationError = if (applied) null else "sync_native_config_failed"
        return settings.toMap() + mapOf(
            "applied" to applied,
            "error" to syncConfigurationError,
        )
    }

    fun cancelSaveJob(jobId: Long): Map<String, Any?> = ClipSaveJobs.cancel(jobId)


    fun meterStatus(): Map<String, Any?> {
        val clockMs = SystemClock.elapsedRealtime()
        val levels = synchronized(levelLock) {
            val latest = levelFrames.lastOrNull()
            if (latest == null || clockMs - latest.timestampMs > LEVEL_STALE_MILLIS) {
                0.0f to 0.0f
            } else {
                latest.level to latest.peak
            }
        }
        return mapOf(
            "running" to isRunning,
            "serviceActive" to !stopRequested,
            "serviceState" to serviceState(),
            "statusCode" to serviceState(),
            "recordingMode" to recordingMode,
            "lockRecordingTrigger" to lockRecordingTrigger,
            "evidenceState" to evidenceState,
            "evidenceLastStopReason" to evidenceLastStopReason,
            "availableMillis" to availableMillis(),
            "sessionStartedUnixMillis" to if (isRunning) sessionStartedUnixMillis else 0L,
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

    private fun serviceState(): String {
        if (recordingMode != MODE_LOCKSCREEN) {
            return if (isRunning) STATE_STANDARD_RECORDING else STATE_STANDARD_PAUSED
        }
        return when {
            evidenceState == EVIDENCE_RECORDING -> STATE_LOCKSCREEN_RECORDING
            evidenceLastStopReason == STOP_REASON_SCREEN_ON -> STATE_LOCKSCREEN_STOPPED_SCREEN_ON
            evidenceLastStopReason == STOP_REASON_USER_PRESENT -> STATE_LOCKSCREEN_STOPPED_USER_PRESENT
            evidenceState == EVIDENCE_ARMED -> STATE_LOCKSCREEN_ARMED
            else -> STATE_STOPPED
        }
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
                    val rms = sqrt(levelSquareSum / levelSampleCount) / 32768.0
                    val peakLevel = levelPeak.toDouble() / 32768.0
                    appendLevelFrame(rms.toFloat(), peakLevel.toFloat())
                    levelSquareSum = 0.0
                    levelPeak = 0
                    levelSampleCount = 0
                }
            }
        }
    }

    private fun appendLevelFrame(level: Float, peak: Float) {
        if (levelFrames.size >= MAX_LEVEL_FRAMES) {
            levelFrames.removeFirst()
        }
        // Keep physical amplitudes intact; Flutter owns display ballistics.
        levelFrames.addLast(LevelFrame(level, peak, SystemClock.elapsedRealtime()))
    }

    private fun cleanupStaleCacheExports() {
        cacheDir.listFiles()
            ?.filter { it.name.startsWith("echoclip-export-") &&
                System.currentTimeMillis() - it.lastModified() > 24 * 60 * 60 * 1_000L }
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

    companion object {
        const val ACTION_STOP = "com.echoclip.echoclip.STOP_REPLAY"
        const val ACTION_SAVE_30 = "com.echoclip.echoclip.SAVE_30"
        const val ACTION_SCHEDULE_ARM = "com.echoclip.echoclip.SCHEDULE_ARM"
        const val ACTION_SCHEDULE_TICK = "com.echoclip.echoclip.SCHEDULE_TICK"
        const val EXTRA_SCHEDULE_EXECUTIONS = "schedule_executions"
        const val EXTRA_RECORDING_MODE = "recording_mode"
        const val EXTRA_LOCK_RECORDING_TRIGGER = "lock_recording_trigger"
        const val MODE_STANDARD = "standard"
        const val MODE_LOCKSCREEN = "lockscreen"
        const val TRIGGER_SCREEN_OFF = "screen_off"
        const val TRIGGER_KEYGUARD_LOCKED = "keyguard_locked"
        const val EVIDENCE_OFF = "off"
        const val EVIDENCE_ARMED = "armed"
        const val EVIDENCE_RECORDING = "recording"
        const val STOP_REASON_SCREEN_ON = "screen_on"
        const val STOP_REASON_USER_PRESENT = "user_present"
        const val STATE_STOPPED = "stopped"
        const val STATE_STANDARD_RECORDING = "standard_recording"
        const val STATE_STANDARD_PAUSED = "standard_paused"
        const val STATE_LOCKSCREEN_ARMED = "lockscreen_armed"
        const val STATE_LOCKSCREEN_RECORDING = "lockscreen_recording"
        const val STATE_LOCKSCREEN_STOPPED_SCREEN_ON = "lockscreen_stopped_screen_on"
        const val STATE_LOCKSCREEN_STOPPED_USER_PRESENT = "lockscreen_stopped_user_present"
        private const val CHANNEL_ID = "echoclip_replay"
        private const val NOTIFICATION_ID = 4102
        private const val CHANNELS = 1
        private const val BYTES_PER_SAMPLE = 2
        private const val SEGMENT_SECONDS = 60
        private const val QUEUE_CAPACITY_CHUNKS = 32
        private const val LEVEL_FRAME_MILLIS = 50
        private const val LEVEL_STALE_MILLIS = 300
        private const val MAX_LEVEL_FRAMES = 160
        private const val EXPORT_POLL_INTERVAL_MILLIS = 100L
        private const val EXPORT_WAIT_TIMEOUT_MILLIS = 10 * 60 * 1_000L
        private const val MIN_INTERNAL_FREE_BYTES = 256L * 1024L * 1024L
        private const val MAX_SAVE_JOB_HISTORY = 32

        @Volatile
        var isRunning: Boolean = false

        @Volatile
        var activeService: ReplayForegroundService? = null
    }
}

private data class LevelFrame(
    val level: Float,
    val peak: Float,
    val timestampMs: Long,
)
