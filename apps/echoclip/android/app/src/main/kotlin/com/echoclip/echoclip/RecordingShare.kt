package com.echoclip.echoclip

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import java.util.Locale

internal object RecordingShare {
    fun share(activity: Activity, value: String?, name: String?, title: String?): Map<String, Any?> {
        if (value.isNullOrBlank()) return mapOf("ok" to false, "error" to "missing_uri")
        return try {
            val uri = Uri.parse(value)
            require(uri.scheme == "content") { "unsupported_recording_uri" }
            val resolver = activity.contentResolver
            // Check that deleted files and revoked folder grants fail here, before
            // opening a share sheet that would hand another app an unreadable URI.
            resolver.openAssetFileDescriptor(uri, "r")?.use { }
                ?: return mapOf("ok" to false, "error" to "recording_unavailable")
            val mime = when (name?.substringAfterLast('.')?.lowercase(Locale.US)) {
                "wav" -> "audio/wav"
                "mp3" -> "audio/mpeg"
                else -> resolver.getType(uri) ?: "audio/*"
            }
            val send = Intent(Intent.ACTION_SEND).apply {
                type = mime
                putExtra(Intent.EXTRA_STREAM, uri)
                putExtra(Intent.EXTRA_TITLE, name)
                clipData = ClipData.newRawUri(name ?: "EchoClip", uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            activity.startActivity(Intent.createChooser(send, title))
            mapOf("ok" to true)
        } catch (error: Exception) {
            mapOf("ok" to false, "error" to "share_failed:${error.javaClass.simpleName}")
        }
    }
}
