package com.echoclip.echoclip

import android.content.Context
import android.net.Uri
import android.util.Base64
import java.util.UUID

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

data class SyncSettings(
    val enabled: Boolean,
    val serverHost: String,
    val uploadPort: Int,
    val deviceId: String,
    val keyConfigured: Boolean,
) {
    val serverUrl: String
        get() {
            if (!isValidSyncHost(serverHost) || uploadPort !in 1..65_535) return ""
            val authority = if (serverHost.contains(':')) "[$serverHost]" else serverHost
            return "http://$authority:$uploadPort"
        }

    fun toMap(): Map<String, Any> = mapOf(
        "enabled" to enabled,
        "serverHost" to serverHost,
        "uploadPort" to uploadPort,
        "serverUrl" to serverUrl,
        "deviceId" to deviceId,
        "keyConfigured" to keyConfigured,
    )
}

private fun isValidSyncHost(value: String): Boolean {
    val host = value.trim()
    return host.isNotEmpty() &&
        !host.contains("://") &&
        !host.any(Char::isWhitespace) &&
        !host.contains('/') &&
        !host.contains('?') &&
        !host.contains('#')
}
object RecordingStorage {
    fun getAudioGains(context: Context): Map<String, Int> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return mapOf("microphone" to prefs.getInt("microphone_gain", 100).coerceIn(0, 300), "system" to prefs.getInt("system_gain", 100).coerceIn(0, 300))
    }
    fun setAudioGains(context: Context, microphone: Int?, system: Int?): Map<String, Int> {
        val current = getAudioGains(context)
        val mic = (microphone ?: current.getValue("microphone")).coerceIn(0, 300)
        val sys = (system ?: current.getValue("system")).coerceIn(0, 300)
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit().putInt("microphone_gain", mic).putInt("system_gain", sys).apply()
        ReplayForegroundService.activeService?.microphoneGainPercent = mic
        return mapOf("microphone" to mic, "system" to sys)
    }

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
    private const val KEY_SYNC_ENABLED = "sync_enabled"
    private const val KEY_SYNC_SERVER_URL = "sync_server_url"
    private const val KEY_SYNC_SERVER_HOST = "sync_server_host"
    private const val KEY_SYNC_UPLOAD_PORT = "sync_upload_port"
    private const val KEY_SYNC_DEVICE_ID = "sync_device_id"
    private const val KEY_SYNC_BUFFER_SECONDS = "sync_buffer_seconds"
    private const val DEFAULT_SAMPLE_RATE = 16_000
    private const val DEFAULT_BUFFER_SECONDS = 1_800
    private const val DEFAULT_EXPORT_FORMAT = "mp3"
    private const val DEFAULT_MP3_BITRATE_KBPS = 128
    private const val DEFAULT_UI_LANGUAGE_MODE = "system"
    private const val DEFAULT_RECORDING_MODE = "standard"
    private const val DEFAULT_LOCK_RECORDING_TRIGGER = "screen_off"
    private val SAMPLE_RATE_OPTIONS = setOf(8_000, 16_000, 24_000, 44_100, 48_000)
    private const val MIN_BUFFER_SECONDS = 5 * 60
    private const val MAX_BUFFER_SECONDS = 24 * 60 * 60
    private val EXPORT_FORMAT_OPTIONS = setOf("wav", "mp3", "flac", "ogg", "m4a", "aac")
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

    fun getSyncSettings(context: Context): SyncSettings {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        var deviceId = prefs.getString(KEY_SYNC_DEVICE_ID, null).orEmpty()
        if (deviceId.isBlank()) {
            deviceId = UUID.randomUUID().toString()
            prefs.edit().putString(KEY_SYNC_DEVICE_ID, deviceId).commit()
        }
        var serverHost = prefs.getString(KEY_SYNC_SERVER_HOST, "").orEmpty().trim()
        var uploadPort = prefs.getInt(KEY_SYNC_UPLOAD_PORT, 32_581)
        val legacyUrl = prefs.getString(KEY_SYNC_SERVER_URL, "").orEmpty().trim()
        if (serverHost.isBlank() && legacyUrl.isNotBlank()) {
            val legacyUri = Uri.parse(legacyUrl)
            serverHost = legacyUri.host.orEmpty()
            uploadPort = if (legacyUri.port in 1..65_535) legacyUri.port else 32_581
        }
        if (uploadPort !in 1..65_535) uploadPort = 32_581
        if (legacyUrl.isNotBlank() || !prefs.contains(KEY_SYNC_SERVER_HOST)) {
            prefs.edit()
                .putString(KEY_SYNC_SERVER_HOST, serverHost)
                .putInt(KEY_SYNC_UPLOAD_PORT, uploadPort)
                .remove(KEY_SYNC_SERVER_URL)
                .remove(KEY_SYNC_BUFFER_SECONDS)
                .commit()
        }
        val keyConfigured = UploadKeyStorage.load(context)?.isNotBlank() == true
        return SyncSettings(
            enabled = prefs.getBoolean(KEY_SYNC_ENABLED, false) &&
                isValidSyncHost(serverHost) && keyConfigured,
            serverHost = serverHost,
            uploadPort = uploadPort,
            deviceId = deviceId,
            keyConfigured = keyConfigured,
        )
    }

    fun setSyncSettings(
        context: Context,
        enabled: Boolean,
        serverHost: String,
        uploadPort: Int,
        uploadKeyBase64: String?,
        clearKey: Boolean,
    ): SyncSettings {
        if (clearKey) {
            UploadKeyStorage.clear(context)
        } else if (!uploadKeyBase64.isNullOrBlank()) {
            val decoded = Base64.decode(uploadKeyBase64.trim(), Base64.DEFAULT)
            require(decoded.size == 32) { "upload key must decode to 32 bytes" }
            decoded.fill(0)
            UploadKeyStorage.store(context, uploadKeyBase64)
        }
        val normalizedHost = serverHost.trim().removeSurrounding("[", "]")
        require(uploadPort in 1..65_535) { "upload port must be between 1 and 65535" }
        if (enabled) require(isValidSyncHost(normalizedHost)) { "invalid server host" }
        val keyConfigured = UploadKeyStorage.load(context)?.isNotBlank() == true
        val appliedEnabled = enabled && isValidSyncHost(normalizedHost) && keyConfigured
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_SYNC_ENABLED, appliedEnabled)
            .putString(KEY_SYNC_SERVER_HOST, normalizedHost)
            .putInt(KEY_SYNC_UPLOAD_PORT, uploadPort)
            .remove(KEY_SYNC_SERVER_URL)
            .remove(KEY_SYNC_BUFFER_SECONDS)
            .commit()
        return getSyncSettings(context)
    }
    fun getSyncUploadKey(context: Context): String? = UploadKeyStorage.load(context)

    private fun sanitizeSampleRate(value: Int): Int {
        return if (value in SAMPLE_RATE_OPTIONS) value else DEFAULT_SAMPLE_RATE
    }

    private fun sanitizeBufferSeconds(value: Int): Int {
        return value.coerceIn(MIN_BUFFER_SECONDS, MAX_BUFFER_SECONDS)
    }

    fun sanitizeExportFormat(value: String): String {
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
