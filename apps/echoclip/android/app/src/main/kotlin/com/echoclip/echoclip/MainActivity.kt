package com.echoclip.echoclip

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaPlayer
import android.media.PlaybackParams
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.echoclip/replay_service"
    private var pendingStartResult: MethodChannel.Result? = null
    private var pendingFolderResult: MethodChannel.Result? = null
    private var mediaPlayer: MediaPlayer? = null
    private var playingUri: String? = null
    private var playbackSpeed = 1.0f

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                    "getRecordingFolder" -> {
                        val uri = RecordingStorage.getRecordingFolderUri(this)
                        result.success(
                            mapOf(
                                "selected" to (uri != null),
                                "uri" to uri?.toString(),
                            ),
                        )
                    }
                    "getAudioSettings" -> {
                        result.success(RecordingStorage.getAudioSettings(this).toMap())
                    }
                    "setAudioSettings" -> {
                        val current = RecordingStorage.getAudioSettings(this)
                        val sampleRate = call.argument<Int>("sampleRate") ?: current.sampleRate
                        val bufferSeconds = call.argument<Int>("bufferSeconds") ?: current.bufferSeconds
                        val settings = RecordingStorage.setAudioSettings(
                            this,
                            sampleRate,
                            bufferSeconds,
                        )
                        result.success(
                            settings.toMap() + mapOf(
                                "applied" to (ReplayForegroundService.activeService == null),
                            ),
                        )
                    }
                    "chooseRecordingFolder" -> chooseRecordingFolder(result)
                    "listRecordings" -> result.success(listRecordings())
                    "listGroups" -> result.success(listGroups())
                    "createGroup" -> {
                        val name = call.argument<String>("name")
                        result.success(createGroup(name))
                    }
                    "renameGroup" -> {
                        val uri = call.argument<String>("uri")
                        val name = call.argument<String>("name")
                        result.success(renameDocument(uri, name, allowWavExtension = false))
                    }
                    "deleteGroup" -> {
                        val uri = call.argument<String>("uri")
                        result.success(deleteDocument(uri))
                    }
                    "renameRecording" -> {
                        val uri = call.argument<String>("uri")
                        val name = call.argument<String>("name")
                        result.success(renameDocument(uri, name, allowWavExtension = true))
                    }
                    "deleteRecording" -> {
                        val uri = call.argument<String>("uri")
                        result.success(deleteDocument(uri))
                    }
                    "moveRecording" -> {
                        val uri = call.argument<String>("uri")
                        val parentUri = call.argument<String>("parentUri")
                        val groupUri = call.argument<String>("groupUri")
                        result.success(moveRecording(uri, parentUri, groupUri))
                    }
                    "playRecording" -> {
                        val uri = call.argument<String>("uri")
                        if (uri == null) {
                            result.success(mapOf("playing" to false, "error" to "missing_uri"))
                        } else {
                            val speed = call.argument<Double>("speed")?.toFloat() ?: playbackSpeed
                            result.success(playRecording(uri, speed))
                        }
                    }
                    "pausePreview" -> result.success(pausePreview())
                    "resumePreview" -> result.success(resumePreview())
                    "stopPreview" -> {
                        stopPreview()
                        result.success(playbackStatus())
                    }
                    "seekPreview" -> {
                        val positionMs = call.argument<Int>("positionMs") ?: 0
                        result.success(seekPreview(positionMs))
                    }
                    "setPlaybackSpeed" -> {
                        val speed = call.argument<Double>("speed")?.toFloat() ?: 1.0f
                        result.success(setPlaybackSpeed(speed))
                    }
                    "getPlaybackStatus" -> result.success(playbackStatus())
                    "startReplay" -> startReplay(result)
                        "saveReplayClip" -> {
                            val seconds = call.argument<Int>("seconds") ?: 30
                            val service = ReplayForegroundService.activeService
                            if (service == null) {
                                result.success(
                                    mapOf(
                                        "saved" to false,
                                        "error" to "service_not_running",
                                    ),
                                )
                            } else {
                                result.success(service.saveLatestClip(seconds))
                            }
                        }
                        "stopReplay" -> {
                            stopService(Intent(this, ReplayForegroundService::class.java))
                            result.success(mapOf("running" to false))
                        }
                        "getReplayStatus" -> {
                            val service = ReplayForegroundService.activeService
                            result.success(
                                service?.status() ?: mapOf(
                                    "running" to false,
                                    "availableSeconds" to 0,
                                    "availableMillis" to 0L,
                                    "levelFrames" to emptyList<Map<String, Any>>(),
                                    "levelClockMs" to SystemClock.elapsedRealtime(),
                                    "backend" to RustAudioCore.backendName(),
                                ),
                            )
                        }
                        "getMeterStatus" -> {
                            val service = ReplayForegroundService.activeService
                            result.success(
                                service?.meterStatus() ?: mapOf(
                                    "running" to false,
                                    "availableMillis" to 0L,
                                    "level" to 0.0,
                                    "peakLevel" to 0.0,
                                ),
                            )
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.success(
                        when (call.method) {
                            "saveReplayClip" -> mapOf(
                                "saved" to false,
                                "error" to "exception:${error.javaClass.simpleName}:${error.message}",
                            )
                            "startReplay", "stopReplay", "getReplayStatus" -> mapOf(
                                "running" to false,
                                "error" to "exception:${error.javaClass.simpleName}:${error.message}",
                            )
                            "getMeterStatus" -> mapOf(
                                "running" to false,
                                "availableMillis" to 0L,
                                "level" to 0.0,
                                "peakLevel" to 0.0,
                                "error" to "exception:${error.javaClass.simpleName}:${error.message}",
                            )
                            "chooseRecordingFolder", "getRecordingFolder" -> mapOf(
                                "selected" to false,
                                "error" to "exception:${error.javaClass.simpleName}:${error.message}",
                            )
                            "getAudioSettings", "setAudioSettings" -> mapOf(
                                "sampleRate" to 16_000,
                                "bufferSeconds" to 1_800,
                                "error" to "exception:${error.javaClass.simpleName}:${error.message}",
                            )
                            "playRecording", "pausePreview", "resumePreview",
                            "stopPreview", "seekPreview", "setPlaybackSpeed",
                            "getPlaybackStatus" -> mapOf(
                                "playing" to false,
                                "error" to "exception:${error.javaClass.simpleName}:${error.message}",
                            )
                            "listGroups" -> emptyList<Map<String, Any?>>()
                            "createGroup", "renameGroup", "deleteGroup",
                            "renameRecording", "deleteRecording", "moveRecording" -> mapOf(
                                "ok" to false,
                                "error" to "exception:${error.javaClass.simpleName}:${error.message}",
                            )
                            else -> mapOf(
                                "error" to "exception:${error.javaClass.simpleName}:${error.message}",
                            )
                        },
                    )
                }
            }
    }

    private fun chooseRecordingFolder(result: MethodChannel.Result) {
        if (pendingFolderResult != null) {
            result.success(mapOf("selected" to false, "error" to "folder_request_active"))
            return
        }

        pendingFolderResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
        }
        startActivityForResult(intent, REQUEST_RECORDING_FOLDER)
    }

    private fun startReplay(result: MethodChannel.Result) {
        val missingPermissions = requiredPermissions().filter {
            checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }

        if (missingPermissions.isNotEmpty()) {
            pendingStartResult = result
            requestPermissions(missingPermissions.toTypedArray(), REQUEST_REPLAY_PERMISSIONS)
            return
        }

        startReplayService()
        result.success(mapOf("running" to true))
    }

    private fun startReplayService() {
        val intent = Intent(this, ReplayForegroundService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_REPLAY_PERMISSIONS) {
            return
        }

        val granted = grantResults.isNotEmpty() && grantResults.all {
            it == PackageManager.PERMISSION_GRANTED
        }
        val result = pendingStartResult ?: return
        pendingStartResult = null

        if (granted) {
            startReplayService()
            result.success(mapOf("running" to true))
        } else {
            result.success(
                mapOf(
                    "running" to false,
                    "error" to "microphone_permission_denied",
                ),
            )
        }
    }

    @Deprecated("Deprecated in Android API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_RECORDING_FOLDER) {
            return
        }

        val result = pendingFolderResult ?: return
        pendingFolderResult = null

        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.success(mapOf("selected" to false, "error" to "folder_not_selected"))
            return
        }

        val flags = data.flags and (
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        contentResolver.takePersistableUriPermission(uri, flags)

        if (!isFolderEmpty(uri)) {
            result.success(mapOf("selected" to false, "error" to "folder_not_empty"))
            return
        }

        RecordingStorage.setRecordingFolderUri(this, uri)
        result.success(mapOf("selected" to true, "uri" to uri.toString()))
    }

    override fun onDestroy() {
        stopPreview()
        super.onDestroy()
    }

    private fun isFolderEmpty(folderUri: Uri): Boolean {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            folderUri,
            DocumentsContract.getTreeDocumentId(folderUri),
        )
        contentResolver.query(
            childrenUri,
            arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID),
            null,
            null,
            null,
        )?.use { cursor ->
            return !cursor.moveToFirst()
        }
        return true
    }

    private fun listRecordings(): List<Map<String, Any?>> {
        val folderUri = RecordingStorage.getRecordingFolderUri(this) ?: return emptyList()
        val rootDocumentUri = rootDocumentUri(folderUri)
        val recordings = mutableListOf<Map<String, Any?>>()
        queryRecordingsInFolder(
            treeUri = folderUri,
            folderDocumentUri = rootDocumentUri,
            groupName = null,
            groupUri = null,
            output = recordings,
        )

        for (group in listGroups()) {
            val groupUri = group["uri"]?.toString() ?: continue
            queryRecordingsInFolder(
                treeUri = folderUri,
                folderDocumentUri = Uri.parse(groupUri),
                groupName = group["name"]?.toString(),
                groupUri = groupUri,
                output = recordings,
            )
        }

        return recordings.sortedByDescending { it["modified"] as? Long ?: 0L }
    }

    private fun queryRecordingsInFolder(
        treeUri: Uri,
        folderDocumentUri: Uri,
        groupName: String?,
        groupUri: String?,
        output: MutableList<Map<String, Any?>>,
    ) {
        val parentDocumentId = DocumentsContract.getDocumentId(folderDocumentUri)
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri,
            parentDocumentId,
        )
        contentResolver.query(
            childrenUri,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_SIZE,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            ),
            null,
            null,
            "${DocumentsContract.Document.COLUMN_LAST_MODIFIED} DESC",
        )?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
            val sizeIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_SIZE)
            val modifiedIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_LAST_MODIFIED)

            while (cursor.moveToNext()) {
                val name = cursor.getString(nameIndex) ?: continue
                val mime = cursor.getString(mimeIndex) ?: ""
                if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                    continue
                }
                if (!name.endsWith(".wav", ignoreCase = true) && mime != "audio/wav") {
                    continue
                }

                val documentUri = DocumentsContract.buildDocumentUriUsingTree(
                    treeUri,
                    cursor.getString(idIndex),
                )
                output += mapOf(
                    "name" to name,
                    "uri" to documentUri.toString(),
                    "parentUri" to folderDocumentUri.toString(),
                    "groupName" to groupName,
                    "groupUri" to groupUri,
                    "size" to cursor.getLong(sizeIndex),
                    "modified" to cursor.getLong(modifiedIndex),
                )
            }
        }
    }

    private fun listGroups(): List<Map<String, Any?>> {
        val folderUri = RecordingStorage.getRecordingFolderUri(this) ?: return emptyList()
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            folderUri,
            DocumentsContract.getTreeDocumentId(folderUri),
        )
        val groups = mutableListOf<Map<String, Any?>>()
        contentResolver.query(
            childrenUri,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            ),
            null,
            null,
            "${DocumentsContract.Document.COLUMN_DISPLAY_NAME} ASC",
        )?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
            val modifiedIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_LAST_MODIFIED)

            while (cursor.moveToNext()) {
                if (cursor.getString(mimeIndex) != DocumentsContract.Document.MIME_TYPE_DIR) {
                    continue
                }
                val name = cursor.getString(nameIndex) ?: continue
                val documentUri = DocumentsContract.buildDocumentUriUsingTree(
                    folderUri,
                    cursor.getString(idIndex),
                )
                groups += mapOf(
                    "name" to name,
                    "uri" to documentUri.toString(),
                    "modified" to cursor.getLong(modifiedIndex),
                )
            }
        }
        return groups
    }

    private fun createGroup(name: String?): Map<String, Any?> {
        val cleanName = sanitizeDocumentName(name, allowWavExtension = false)
            ?: return mapOf("ok" to false, "error" to "invalid_name")
        val folderUri = RecordingStorage.getRecordingFolderUri(this)
            ?: return mapOf("ok" to false, "error" to "recording_folder_not_selected")
        val created = DocumentsContract.createDocument(
            contentResolver,
            rootDocumentUri(folderUri),
            DocumentsContract.Document.MIME_TYPE_DIR,
            cleanName,
        ) ?: return mapOf("ok" to false, "error" to "create_group_failed")
        return mapOf("ok" to true, "name" to cleanName, "uri" to created.toString())
    }

    private fun renameDocument(
        uriString: String?,
        name: String?,
        allowWavExtension: Boolean,
    ): Map<String, Any?> {
        val cleanName = sanitizeDocumentName(name, allowWavExtension)
            ?: return mapOf("ok" to false, "error" to "invalid_name")
        val uri = uriString?.let(Uri::parse)
            ?: return mapOf("ok" to false, "error" to "missing_uri")
        val renamed = DocumentsContract.renameDocument(contentResolver, uri, cleanName)
            ?: return mapOf("ok" to false, "error" to "rename_failed")
        return mapOf("ok" to true, "name" to cleanName, "uri" to renamed.toString())
    }

    private fun deleteDocument(uriString: String?): Map<String, Any?> {
        val uri = uriString?.let(Uri::parse)
            ?: return mapOf("ok" to false, "error" to "missing_uri")
        val deleted = DocumentsContract.deleteDocument(contentResolver, uri)
        return mapOf("ok" to deleted)
    }

    private fun moveRecording(
        uriString: String?,
        parentUriString: String?,
        groupUriString: String?,
    ): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            return mapOf("ok" to false, "error" to "move_requires_android_n")
        }
        val folderUri = RecordingStorage.getRecordingFolderUri(this)
            ?: return mapOf("ok" to false, "error" to "recording_folder_not_selected")
        val documentUri = uriString?.let(Uri::parse)
            ?: return mapOf("ok" to false, "error" to "missing_uri")
        val sourceParentUri = parentUriString?.let(Uri::parse)
            ?: return mapOf("ok" to false, "error" to "missing_parent_uri")
        val targetParentUri = groupUriString?.let(Uri::parse) ?: rootDocumentUri(folderUri)
        val moved = DocumentsContract.moveDocument(
            contentResolver,
            documentUri,
            sourceParentUri,
            targetParentUri,
        ) ?: return mapOf("ok" to false, "error" to "move_failed")
        return mapOf("ok" to true, "uri" to moved.toString())
    }

    private fun rootDocumentUri(treeUri: Uri): Uri {
        return DocumentsContract.buildDocumentUriUsingTree(
            treeUri,
            DocumentsContract.getTreeDocumentId(treeUri),
        )
    }

    private fun sanitizeDocumentName(name: String?, allowWavExtension: Boolean): String? {
        val cleaned = name
            ?.trim()
            ?.replace(Regex("[\\\\/:*?\"<>|]"), "_")
            ?.take(80)
        if (cleaned.isNullOrBlank() || cleaned == "." || cleaned == "..") {
            return null
        }
        return if (allowWavExtension && !cleaned.endsWith(".wav", ignoreCase = true)) {
            "$cleaned.wav"
        } else {
            cleaned
        }
    }

    private fun playRecording(uriString: String, speed: Float): Map<String, Any?> {
        stopPreview()
        return try {
            playbackSpeed = speed.coerceIn(MIN_PLAYBACK_SPEED, MAX_PLAYBACK_SPEED)
            mediaPlayer = MediaPlayer().apply {
                setDataSource(this@MainActivity, Uri.parse(uriString))
                setOnCompletionListener {
                    stopPreview()
                }
                prepare()
                applyPlaybackSpeed(this, playbackSpeed)
                start()
            }
            playingUri = uriString
            playbackStatus()
        } catch (error: Exception) {
            stopPreview()
            mapOf("playing" to false, "error" to (error.message ?: "playback_failed"))
        }
    }

    private fun pausePreview(): Map<String, Any?> {
        mediaPlayer?.runCatching {
            if (isPlaying) {
                pause()
            }
        }
        return playbackStatus()
    }

    private fun resumePreview(): Map<String, Any?> {
        mediaPlayer?.runCatching {
            applyPlaybackSpeed(this, playbackSpeed)
            start()
        }
        return playbackStatus()
    }

    private fun seekPreview(positionMs: Int): Map<String, Any?> {
        mediaPlayer?.runCatching {
            val target = positionMs.coerceIn(0, duration.coerceAtLeast(0))
            seekTo(target)
        }
        return playbackStatus()
    }

    private fun setPlaybackSpeed(speed: Float): Map<String, Any?> {
        playbackSpeed = speed.coerceIn(MIN_PLAYBACK_SPEED, MAX_PLAYBACK_SPEED)
        mediaPlayer?.runCatching {
            applyPlaybackSpeed(this, playbackSpeed)
        }
        return playbackStatus()
    }

    private fun playbackStatus(): Map<String, Any?> {
        val player = mediaPlayer ?: return mapOf(
            "playing" to false,
            "paused" to false,
            "uri" to null,
            "positionMs" to 0,
            "durationMs" to 0,
            "speed" to playbackSpeed.toDouble(),
        )

        return try {
            mapOf(
                "playing" to player.isPlaying,
                "paused" to !player.isPlaying,
                "uri" to playingUri,
                "positionMs" to player.currentPosition,
                "durationMs" to player.duration,
                "speed" to playbackSpeed.toDouble(),
            )
        } catch (error: Exception) {
            stopPreview()
            mapOf(
                "playing" to false,
                "paused" to false,
                "uri" to null,
                "positionMs" to 0,
                "durationMs" to 0,
                "speed" to playbackSpeed.toDouble(),
                "error" to (error.message ?: "playback_status_failed"),
            )
        }
    }

    private fun applyPlaybackSpeed(player: MediaPlayer, speed: Float) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            player.playbackParams = (player.playbackParams ?: PlaybackParams())
                .setSpeed(speed)
        }
    }

    private fun stopPreview() {
        mediaPlayer?.runCatching {
            if (isPlaying) {
                stop()
            }
            release()
        }
        mediaPlayer = null
        playingUri = null
    }

    private fun requiredPermissions(): List<String> {
        val permissions = mutableListOf(Manifest.permission.RECORD_AUDIO)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissions += Manifest.permission.POST_NOTIFICATIONS
        }
        return permissions
    }

    companion object {
        private const val REQUEST_REPLAY_PERMISSIONS = 4102
        private const val REQUEST_RECORDING_FOLDER = 4103
        private const val MIN_PLAYBACK_SPEED = 0.1f
        private const val MAX_PLAYBACK_SPEED = 16.0f
    }
}
