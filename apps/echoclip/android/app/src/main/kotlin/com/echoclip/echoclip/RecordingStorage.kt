package com.echoclip.echoclip

import android.content.Context
import android.net.Uri

data class AudioSettings(
    val sampleRate: Int,
    val bufferSeconds: Int,
) {
    fun toMap(): Map<String, Any> = mapOf(
        "sampleRate" to sampleRate,
        "bufferSeconds" to bufferSeconds,
    )
}

data class ExportSettings(
    val format: String,
    val mp3BitrateKbps: Int,
) {
    fun toMap(): Map<String, Any> = mapOf(
        "format" to format,
        "mp3BitrateKbps" to mp3BitrateKbps,
    )
}

data class RecordingModeSettings(
    val mode: String,
    val trigger: String,
) {
    fun toMap(): Map<String, Any> = mapOf(
        "mode" to mode,
        "trigger" to trigger,
    )
}

object RecordingStorage {
    private const val PREFS_NAME = "echoclip_recording_storage"
    private const val KEY_FOLDER_URI = "folder_uri"
    private const val KEY_SAMPLE_RATE = "sample_rate"
    private const val KEY_BUFFER_SECONDS = "buffer_seconds"
    private const val KEY_EXPORT_FORMAT = "export_format"
    private const val KEY_MP3_BITRATE_KBPS = "mp3_bitrate_kbps"
    private const val KEY_UI_LANGUAGE_MODE = "ui_language_mode"
    private const val KEY_RECORDING_MODE = "recording_mode"
    private const val KEY_LOCK_RECORDING_TRIGGER = "lock_recording_trigger"
    private const val KEY_LAST_SESSION_STARTED_UNIX_MILLIS = "last_session_started_unix_millis"
    private const val KEY_LAST_AVAILABLE_MILLIS = "last_available_millis"
    private const val DEFAULT_SAMPLE_RATE = 16_000
    private const val DEFAULT_BUFFER_SECONDS = 1_800
    private const val DEFAULT_EXPORT_FORMAT = "mp3"
    private const val DEFAULT_MP3_BITRATE_KBPS = 128
    private const val DEFAULT_UI_LANGUAGE_MODE = "system"
    private const val DEFAULT_RECORDING_MODE = "standard"
    private const val DEFAULT_LOCK_RECORDING_TRIGGER = "screen_off"
    private val SAMPLE_RATE_OPTIONS = setOf(8_000, 16_000, 24_000, 48_000)
    private const val MIN_BUFFER_SECONDS = 60
    private const val MAX_BUFFER_SECONDS = 24 * 60 * 60
    private val EXPORT_FORMAT_OPTIONS = setOf("mp3", "wav")
    private val MP3_BITRATE_OPTIONS = setOf(32, 48, 64, 96, 128, 160, 192, 256, 320)
    private val UI_LANGUAGE_MODE_OPTIONS = setOf("system", "en", "zh")
    private val RECORDING_MODE_OPTIONS = setOf("standard", "lockscreen")
    private val LOCK_RECORDING_TRIGGER_OPTIONS = setOf("screen_off", "keyguard_locked")

    fun setRecordingFolderUri(context: Context, uri: Uri) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_FOLDER_URI, uri.toString())
            .apply()
    }

    fun getRecordingFolderUri(context: Context): Uri? {
        val raw = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_FOLDER_URI, null)
        return raw?.let(Uri::parse)
    }

    fun getAudioSettings(context: Context): AudioSettings {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val sampleRate = sanitizeSampleRate(
            prefs.getInt(KEY_SAMPLE_RATE, DEFAULT_SAMPLE_RATE),
        )
        val bufferSeconds = sanitizeBufferSeconds(
            prefs.getInt(KEY_BUFFER_SECONDS, DEFAULT_BUFFER_SECONDS),
        )
        return AudioSettings(sampleRate, bufferSeconds)
    }

    fun setAudioSettings(
        context: Context,
        sampleRate: Int,
        bufferSeconds: Int,
    ): AudioSettings {
        val settings = AudioSettings(
            sanitizeSampleRate(sampleRate),
            sanitizeBufferSeconds(bufferSeconds),
        )
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putInt(KEY_SAMPLE_RATE, settings.sampleRate)
            .putInt(KEY_BUFFER_SECONDS, settings.bufferSeconds)
            .apply()
        return settings
    }

    fun getExportSettings(context: Context): ExportSettings {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return ExportSettings(
            sanitizeExportFormat(
                prefs.getString(KEY_EXPORT_FORMAT, DEFAULT_EXPORT_FORMAT) ?: DEFAULT_EXPORT_FORMAT,
            ),
            sanitizeMp3Bitrate(
                prefs.getInt(KEY_MP3_BITRATE_KBPS, DEFAULT_MP3_BITRATE_KBPS),
            ),
        )
    }

    fun setExportSettings(
        context: Context,
        format: String,
        mp3BitrateKbps: Int,
    ): ExportSettings {
        val settings = ExportSettings(
            sanitizeExportFormat(format),
            sanitizeMp3Bitrate(mp3BitrateKbps),
        )
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_EXPORT_FORMAT, settings.format)
            .putInt(KEY_MP3_BITRATE_KBPS, settings.mp3BitrateKbps)
            .apply()
        return settings
    }

    fun getUiLanguageMode(context: Context): String {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return sanitizeUiLanguageMode(
            prefs.getString(KEY_UI_LANGUAGE_MODE, DEFAULT_UI_LANGUAGE_MODE)
                ?: DEFAULT_UI_LANGUAGE_MODE,
        )
    }

    fun setUiLanguageMode(context: Context, mode: String): String {
        val sanitized = sanitizeUiLanguageMode(mode)
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_UI_LANGUAGE_MODE, sanitized)
            .apply()
        return sanitized
    }

    fun getRecordingModeSettings(context: Context): RecordingModeSettings {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return RecordingModeSettings(
            sanitizeRecordingMode(
                prefs.getString(KEY_RECORDING_MODE, DEFAULT_RECORDING_MODE)
                    ?: DEFAULT_RECORDING_MODE,
            ),
            sanitizeLockRecordingTrigger(
                prefs.getString(KEY_LOCK_RECORDING_TRIGGER, DEFAULT_LOCK_RECORDING_TRIGGER)
                    ?: DEFAULT_LOCK_RECORDING_TRIGGER,
            ),
        )
    }

    fun setRecordingModeSettings(
        context: Context,
        mode: String,
        trigger: String,
    ): RecordingModeSettings {
        val settings = RecordingModeSettings(
            sanitizeRecordingMode(mode),
            sanitizeLockRecordingTrigger(trigger),
        )
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_RECORDING_MODE, settings.mode)
            .putString(KEY_LOCK_RECORDING_TRIGGER, settings.trigger)
            .apply()
        return settings
    }

    fun getLastSessionStartedUnixMillis(context: Context): Long {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getLong(KEY_LAST_SESSION_STARTED_UNIX_MILLIS, 0L)
    }

    fun setLastSessionStartedUnixMillis(context: Context, value: Long) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putLong(KEY_LAST_SESSION_STARTED_UNIX_MILLIS, value.coerceAtLeast(0L))
            .apply()
    }

    fun getLastAvailableMillis(context: Context): Long {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getLong(KEY_LAST_AVAILABLE_MILLIS, 0L).coerceAtLeast(0L)
    }

    fun setLastAvailableMillis(context: Context, value: Long) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putLong(KEY_LAST_AVAILABLE_MILLIS, value.coerceAtLeast(0L))
            .apply()
    }

    private fun sanitizeSampleRate(value: Int): Int {
        return if (value in SAMPLE_RATE_OPTIONS) value else DEFAULT_SAMPLE_RATE
    }

    private fun sanitizeBufferSeconds(value: Int): Int {
        return value.coerceIn(MIN_BUFFER_SECONDS, MAX_BUFFER_SECONDS)
    }

    private fun sanitizeExportFormat(value: String): String {
        val normalized = value.lowercase()
        return if (normalized in EXPORT_FORMAT_OPTIONS) normalized else DEFAULT_EXPORT_FORMAT
    }

    private fun sanitizeMp3Bitrate(value: Int): Int {
        return if (value in MP3_BITRATE_OPTIONS) value else DEFAULT_MP3_BITRATE_KBPS
    }

    private fun sanitizeUiLanguageMode(value: String): String {
        val normalized = value.lowercase()
        return if (normalized in UI_LANGUAGE_MODE_OPTIONS) normalized else DEFAULT_UI_LANGUAGE_MODE
    }

    private fun sanitizeRecordingMode(value: String): String {
        val normalized = value.lowercase()
        return if (normalized in RECORDING_MODE_OPTIONS) normalized else DEFAULT_RECORDING_MODE
    }

    private fun sanitizeLockRecordingTrigger(value: String): String {
        val normalized = value.lowercase()
        return if (normalized in LOCK_RECORDING_TRIGGER_OPTIONS) {
            normalized
        } else {
            DEFAULT_LOCK_RECORDING_TRIGGER
        }
    }
}
