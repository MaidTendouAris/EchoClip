package com.echoclip.echoclip

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

object ScheduleCoordinator {
    private const val ALARM_REQUEST_CODE = 32580

    fun dataDir(context: Context): String =
        File(context.filesDir, "echoclip-runtime").apply { mkdirs() }.absolutePath

    fun snapshot(context: Context): Map<String, Any?> = snapshotFromJson(
        context,
        RustAudioCore.scheduleSnapshot(dataDir(context)),
    )

    private fun snapshotFromJson(context: Context, json: String): Map<String, Any?> {
        val root = runCatching { JSONObject(json) }.getOrElse {
            JSONObject().put("error", "schedule_snapshot_invalid:${it.message}")
        }
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        val exact = canScheduleExact(alarmManager)
        root.put("ok", !root.has("error"))
        root.put("schedulingPrecision", if (exact) "exact" else "approximate")
        root.put("exactAlarmPermission", exact)
        root.put(
            "recordingDestinationReady",
            RecordingStorage.getRecordingFolderUri(context) != null,
        )
        root.put("ffmpegAvailable", resolveFfmpeg(context) != null)
        root.put("uploadConfigured", RecordingStorage.getSyncSettings(context).keyConfigured)
        root.put("processResident", ReplayForegroundService.activeService != null)
        return jsonObjectToMap(root)
    }

    fun upsert(context: Context, taskJson: String): Map<String, Any?> {
        val json = RustAudioCore.scheduleUpsert(dataDir(context), taskJson)
        val result = snapshotFromJson(context, json)
        if (result["ok"] == true) {
            reschedule(context, json)
        }
        return result
    }

    fun delete(context: Context, taskId: String): Map<String, Any?> {
        val json = RustAudioCore.scheduleDelete(dataDir(context), taskId)
        val result = snapshotFromJson(context, json)
        if (result["ok"] == true) {
            reschedule(context, json)
        }
        return result
    }

    fun setEnabled(
        context: Context,
        taskId: String,
        expectedRevision: Long,
        enabled: Boolean,
    ): Map<String, Any?> {
        val json = RustAudioCore.scheduleSetEnabled(
            dataDir(context),
            taskId,
            expectedRevision,
            enabled,
        )
        val result = snapshotFromJson(context, json)
        if (result["ok"] == true) {
            reschedule(context, json)
        }
        return result
    }

    fun complete(
        context: Context,
        executionId: String,
        results: JSONArray,
    ) {
        val json = RustAudioCore.scheduleComplete(
            dataDir(context),
            executionId,
            results.toString(),
        )
        reschedule(context, json)
    }

    fun reschedule(context: Context, snapshotJson: String? = null) {
        val root = runCatching {
            JSONObject(snapshotJson ?: RustAudioCore.scheduleSnapshot(dataDir(context)))
        }.getOrNull() ?: return
        if (root.has("error")) {
            return
        }
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        val pending = alarmPendingIntent(context)
        alarmManager.cancel(pending)
        val microphoneTaskArmed = containsArmedStartRecording(root.optJSONArray("tasks"))
        ReplayForegroundService.activeService?.setSchedulerArmed(microphoneTaskArmed)
        if (microphoneTaskArmed) {
            runCatching {
                ContextCompat.startForegroundService(
                    context,
                    Intent(context, ReplayForegroundService::class.java)
                        .setAction(ReplayForegroundService.ACTION_SCHEDULE_ARM),
                )
            }
        }
        val due = root.optLong("nextWakeupUtcMillis", 0L)
        if (due <= 0L) {
            return
        }
        if (canScheduleExact(alarmManager)) {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, due, pending)
        } else {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, due, pending)
        }
    }

    fun tick(context: Context) {
        val executionsJson = RustAudioCore.scheduleTick(dataDir(context))
        val executions = runCatching { JSONArray(executionsJson) }.getOrNull()
        if (executions == null || executions.length() == 0) {
            reschedule(context)
            return
        }
        val intent = Intent(context, ReplayForegroundService::class.java)
            .setAction(ReplayForegroundService.ACTION_SCHEDULE_TICK)
            .putExtra(ReplayForegroundService.EXTRA_SCHEDULE_EXECUTIONS, executionsJson)
        runCatching { ContextCompat.startForegroundService(context, intent) }
            .onFailure {
                failExecutionsAsPlatformBlocked(context, executions, it)
            }
    }

    fun resolveFfmpeg(context: Context): File? {
        val candidates = listOf(
            File(context.applicationInfo.nativeLibraryDir, "libffmpeg.so"),
            File(context.filesDir, "ffmpeg"),
            File(context.filesDir, "ffmpeg/ffmpeg"),
            File(context.applicationInfo.nativeLibraryDir, "ffmpeg"),
        )
        return candidates.firstOrNull { it.exists() && it.canExecute() }
    }

    private fun failExecutionsAsPlatformBlocked(
        context: Context,
        executions: JSONArray,
        error: Throwable,
    ) {
        for (index in 0 until executions.length()) {
            val execution = executions.optJSONObject(index) ?: continue
            val results = JSONArray()
            val actions = execution.optJSONArray("actions") ?: JSONArray()
            for (actionIndex in 0 until actions.length()) {
                val due = actions.optJSONObject(actionIndex) ?: continue
                results.put(
                    JSONObject()
                        .put("actionIndex", due.optInt("actionIndex"))
                        .put("state", "platform_blocked")
                        .put(
                            "errorCode",
                            "PLATFORM_BACKGROUND_START_BLOCKED:${error.javaClass.simpleName}",
                        ),
                )
            }
            complete(context, execution.optString("executionId"), results)
        }
    }

    private fun containsArmedStartRecording(tasks: JSONArray?): Boolean {
        if (tasks == null) return false
        for (index in 0 until tasks.length()) {
            val task = tasks.optJSONObject(index) ?: continue
            if (!task.optBoolean("enabled") || task.optString("state") != "armed") continue
            val actions = task.optJSONArray("actions") ?: continue
            for (actionIndex in 0 until actions.length()) {
                if (actions.optJSONObject(actionIndex)?.optString("type") == "start_recording") {
                    return true
                }
            }
        }
        return false
    }

    private fun canScheduleExact(alarmManager: AlarmManager): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()

    private fun alarmPendingIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        ALARM_REQUEST_CODE,
        Intent(context, ScheduleAlarmReceiver::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun jsonObjectToMap(value: JSONObject): Map<String, Any?> {
        val output = linkedMapOf<String, Any?>()
        val keys = value.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            output[key] = jsonValue(value.opt(key))
        }
        return output
    }

    private fun jsonValue(value: Any?): Any? = when (value) {
        null, JSONObject.NULL -> null
        is JSONObject -> jsonObjectToMap(value)
        is JSONArray -> List(value.length()) { index -> jsonValue(value.opt(index)) }
        else -> value
    }
}

class ScheduleAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        ScheduleCoordinator.tick(context.applicationContext)
    }
}

class ScheduleBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action == Intent.ACTION_BOOT_COMPLETED ||
            intent?.action == AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED
        ) {
            val pending = goAsync()
            Thread {
                try {
                    if (intent.action == Intent.ACTION_BOOT_COMPLETED) StartupCoordinator.onBoot(context.applicationContext)
                    ScheduleCoordinator.reschedule(context.applicationContext)
                } finally { pending.finish() }
            }.start()
        }
    }
}
