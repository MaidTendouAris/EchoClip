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

object RecordingStorage {
    private const val PREFS_NAME = "echoclip_recording_storage"
    private const val KEY_FOLDER_URI = "folder_uri"
    private const val KEY_SAMPLE_RATE = "sample_rate"
    private const val KEY_BUFFER_SECONDS = "buffer_seconds"
    private const val DEFAULT_SAMPLE_RATE = 16_000
    private const val DEFAULT_BUFFER_SECONDS = 1_800
    private val SAMPLE_RATE_OPTIONS = setOf(8_000, 16_000, 24_000, 48_000)
    private val BUFFER_SECONDS_OPTIONS = setOf(600, 1_800, 3_600, 7_200, 18_000)

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

    private fun sanitizeSampleRate(value: Int): Int {
        return if (value in SAMPLE_RATE_OPTIONS) value else DEFAULT_SAMPLE_RATE
    }

    private fun sanitizeBufferSeconds(value: Int): Int {
        return if (value in BUFFER_SECONDS_OPTIONS) value else DEFAULT_BUFFER_SECONDS
    }
}
