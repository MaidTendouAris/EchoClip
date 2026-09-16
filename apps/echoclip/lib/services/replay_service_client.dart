part of '../main.dart';

class ReplayServiceClient {
  const ReplayServiceClient();

  static const MethodChannel _channel = MethodChannel(
    'com.echoclip/replay_service',
  );

  static bool get _usesWindowsBackend =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Future<Map<dynamic, dynamic>> getAppVersion() async =>
      await const MethodChannel(
        'com.echoclip/app_info',
      ).invokeMapMethod<dynamic, dynamic>('getAppVersion') ??
      const {};

  Future<String> getExportFormat() async {
    final value = (await _map('getExportSettings'))['format'];
    return recordingExportFormats.contains(value) ? value as String : 'mp3';
  }

  Future<String> setExportFormat(String format) async {
    final response = await _map('setExportSettings', {'format': format});
    if (response['ok'] == false || response['error'] != null) {
      throw PlatformException(
        code: response['error']?.toString() ?? 'export_settings_failed',
      );
    }
    return response['format']?.toString() ?? format;
  }

  Future<ScheduleSnapshot> setStartupSilent(bool silent) async =>
      ScheduleSnapshot.fromNative(
        await _map('setStartupSilent', {'silent': silent}),
      );

  Future<Map<dynamic, dynamic>> getAudioGains() => _map('getAudioGains');
  Future<Map<dynamic, dynamic>> setAudioGain(String source, int percent) =>
      _map('setAudioGains', {source: percent});
  Future<BufferWindow> getBufferWindow() async =>
      BufferWindow.fromNative(await _map('getBufferWindow'));
  Future<SaveClipResult> saveBufferRange(BufferSelection range) async =>
      SaveClipResult.fromNative(
        await _map('saveBufferRange', {
          'range': range.toMap(),
          'seconds': range.duration.ceil(),
        }),
      );
  Future<ScheduleSnapshot> getStartupSettings() async =>
      ScheduleSnapshot.fromNative(await _map('getStartupSettings'));
  Future<ScheduleSnapshot> setStartupEnabled(bool enabled) async =>
      ScheduleSnapshot.fromNative(
        await _map('setStartupEnabled', {'enabled': enabled}),
      );
  Future<ScheduleSnapshot> consumeStartupTasks() async =>
      ScheduleSnapshot.fromNative(await _map('consumeStartupTasks'));

  Future<UiLanguageMode> getUiLanguageMode() async {
    final response = await _map('getUiLanguageMode');
    return UiLanguageMode.fromStorageValue(response['mode']?.toString());
  }

  Future<UiLanguageMode> setUiLanguageMode(UiLanguageMode mode) async {
    final response = await _map('setUiLanguageMode', {
      'mode': mode.storageValue,
    });
    return UiLanguageMode.fromStorageValue(response['mode']?.toString());
  }

  Future<AudioSettings> getAudioSettings() async {
    return AudioSettings.fromNative(await _map('getAudioSettings'));
  }

  Future<AudioSettingsUpdate> setAudioSettings({
    required int sampleRate,
    required int bufferSeconds,
  }) async {
    return AudioSettingsUpdate.fromNative(
      await _map('setAudioSettings', {
        'sampleRate': sampleRate,
        'bufferSeconds': bufferSeconds,
      }),
    );
  }

  /// Lists microphone/input endpoints exposed by the native capture backend.
  ///
  /// Android currently lets the platform choose its input route, so it reports
  /// no selectable endpoints while still using the same settings UI.
  Future<List<AudioInputDevice>> listAudioInputDevices() async {
    if (!_usesWindowsBackend) {
      return const <AudioInputDevice>[];
    }
    final response = await _list('listAudioInputDevices');
    return response.whereType<Map>().map(AudioInputDevice.fromNative).toList();
  }

  Future<AudioSourceSettings> getAudioSourceSettings() async {
    if (!_usesWindowsBackend) {
      return AudioSourceSettings.androidDefault;
    }
    return AudioSourceSettings.fromNative(await _map('getAudioSourceSettings'));
  }

  Future<AudioSourceSettingsUpdate> setAudioSourceSettings({
    required bool microphoneEnabled,
    required bool systemAudioEnabled,
    // null means "follow the current system-default input device".
    String? microphoneDeviceId,
  }) async {
    if (!_usesWindowsBackend) {
      return AudioSourceSettingsUpdate.fromSettings(
        AudioSourceSettings.androidDefault,
        applied: microphoneEnabled && !systemAudioEnabled,
      );
    }
    return AudioSourceSettingsUpdate.fromNative(
      await _map('setAudioSourceSettings', {
        'microphoneEnabled': microphoneEnabled,
        'systemAudioEnabled': systemAudioEnabled,
        'microphoneDeviceId': microphoneDeviceId,
      }),
    );
  }

  Future<ServerSyncSettings> getServerSyncSettings() async {
    return ServerSyncSettings.fromNative(await _map('getServerSyncSettings'));
  }

  Future<ServerSyncSettingsUpdate> setServerSyncEnabled(bool enabled) async {
    return ServerSyncSettingsUpdate.fromNative(
      await _map('setServerSyncEnabled', {'enabled': enabled}),
    );
  }

  Future<ServerSyncSettingsUpdate> setServerSyncSettings({
    required String serverHost,
    required int uploadPort,
    String? uploadKey,
    bool clearKey = false,
  }) async {
    return ServerSyncSettingsUpdate.fromNative(
      await _map('setServerSyncSettings', {
        'serverHost': serverHost,
        'uploadPort': uploadPort,
        'uploadKey': uploadKey,
        'clearKey': clearKey,
      }),
    );
  }

  Future<ServerConnectionTestResult> testServerConnection({
    String? serverHost,
    int? uploadPort,
    String? uploadKey,
  }) async {
    return ServerConnectionTestResult.fromNative(
      await _map('testServerConnection', {
        'serverHost': serverHost,
        'uploadPort': uploadPort,
        'uploadKey': uploadKey,
      }),
    );
  }

  Future<RecordingModeSettings> getRecordingModeSettings() async {
    return RecordingModeSettings.fromNative(
      await _map('getRecordingModeSettings'),
    );
  }

  Future<ReplayCommandResult> setRecordingModeSettings({
    required RecordingMode mode,
    required LockRecordingTrigger trigger,
  }) async {
    return ReplayCommandResult.fromNative(
      await _map('setRecordingModeSettings', {
        'mode': mode.storageValue,
        'trigger': trigger.storageValue,
      }),
    );
  }

  Future<FolderStatus> getRecordingFolder() async {
    return FolderStatus.fromNative(await _map('getRecordingFolder'));
  }

  Future<FolderStatus> chooseRecordingFolder() async {
    return FolderStatus.fromNative(await _map('chooseRecordingFolder'));
  }

  Future<ReplayStatus> getReplayStatus() async {
    return ReplayStatus.fromNative(await _map('getReplayStatus'));
  }

  Future<MeterStatus> getMeterStatus() async {
    return MeterStatus.fromNative(await _map('getMeterStatus'));
  }

  Future<ReplayCommandResult> startReplay({
    required RecordingMode mode,
    required LockRecordingTrigger trigger,
  }) async {
    return ReplayCommandResult.fromNative(
      await _map('startReplay', {
        'mode': mode.storageValue,
        'trigger': trigger.storageValue,
      }),
    );
  }

  Future<ReplayCommandResult> stopReplay() async {
    return ReplayCommandResult.fromNative(await _map('stopReplay'));
  }

  Future<SaveClipResult> saveReplayClip(int seconds) async {
    return SaveClipResult.fromNative(
      await _map('saveReplayClip', {'seconds': seconds}),
    );
  }

  Future<Map<dynamic, dynamic>> getSaveJob(int jobId) =>
      _map('getSaveJob', {'jobId': jobId});

  Future<void> cancelSaveJob(int jobId) async {
    await _map('cancelSaveJob', {'jobId': jobId});
  }

  Future<OperationResult> shareRecording(ClipItem clip, String title) async =>
      OperationResult.fromNative(
        await _map('shareRecording', {
          'uri': clip.uri,
          'name': clip.name,
          'title': title,
        }),
      );

  Future<List<RecordingGroup>> listGroups() async {
    final response = await _list('listGroups');
    return response.whereType<Map>().map(RecordingGroup.fromNative).toList();
  }

  Future<List<ClipItem>> listRecordings() async {
    final response = await _list('listRecordings');
    return response.whereType<Map>().map(ClipItem.fromNative).toList();
  }

  Future<PlaybackSnapshot> playRecording({
    required String uri,
    required double speed,
    required PlaybackSnapshot fallback,
  }) async {
    return PlaybackSnapshot.fromNative(
      await _map('playRecording', {'uri': uri, 'speed': speed}),
      fallback: fallback,
    );
  }

  Future<PlaybackSnapshot> pausePreview(PlaybackSnapshot fallback) async {
    return PlaybackSnapshot.fromNative(
      await _map('pausePreview'),
      fallback: fallback,
    );
  }

  Future<PlaybackSnapshot> resumePreview(PlaybackSnapshot fallback) async {
    return PlaybackSnapshot.fromNative(
      await _map('resumePreview'),
      fallback: fallback,
    );
  }

  Future<PlaybackSnapshot> stopPreview(PlaybackSnapshot fallback) async {
    return PlaybackSnapshot.fromNative(
      await _map('stopPreview'),
      fallback: fallback,
    );
  }

  Future<PlaybackSnapshot> seekPreview({
    required int positionMs,
    required PlaybackSnapshot fallback,
  }) async {
    return PlaybackSnapshot.fromNative(
      await _map('seekPreview', {'positionMs': positionMs}),
      fallback: fallback,
    );
  }

  Future<PlaybackSnapshot> setPlaybackSpeed({
    required double speed,
    required PlaybackSnapshot fallback,
  }) async {
    return PlaybackSnapshot.fromNative(
      await _map('setPlaybackSpeed', {'speed': speed}),
      fallback: fallback.copyWith(speed: speed),
    );
  }

  Future<OperationResult> runLibraryMutation(
    String method,
    Map<String, Object?> arguments,
  ) async {
    return OperationResult.fromNative(await _map(method, arguments));
  }

  Future<OperationResult> convertWavToMp3({
    required ClipItem clip,
    int mp3BitrateKbps = 128,
  }) async {
    return OperationResult.fromNative(
      await _map('convertWavToMp3', {
        'uri': clip.uri,
        'parentUri': clip.parentUri,
        'mp3BitrateKbps': mp3BitrateKbps,
      }),
    );
  }

  Future<ScheduleSnapshot> getScheduleSnapshot() async {
    return ScheduleSnapshot.fromNative(await _map('getScheduleSnapshot'));
  }

  Future<ScheduleSnapshot> upsertScheduledTask(
    Map<String, Object?> task,
  ) async {
    return ScheduleSnapshot.fromNative(
      await _map('upsertScheduledTask', {'task': task}),
    );
  }

  Future<ScheduleSnapshot> deleteScheduledTask(String taskId) async {
    return ScheduleSnapshot.fromNative(
      await _map('deleteScheduledTask', {'taskId': taskId}),
    );
  }

  Future<ScheduleSnapshot> setScheduledTaskEnabled({
    required String taskId,
    required int expectedRevision,
    required bool enabled,
  }) async {
    return ScheduleSnapshot.fromNative(
      await _map('setScheduledTaskEnabled', {
        'taskId': taskId,
        'expectedRevision': expectedRevision,
        'enabled': enabled,
      }),
    );
  }

  Future<ScheduleSnapshot> requestExactAlarmPermission() async {
    return ScheduleSnapshot.fromNative(
      await _map('requestExactAlarmPermission'),
    );
  }

  Future<CacheClearResult> clearCache() async {
    return CacheClearResult.fromNative(await _map('clearCache'));
  }

  Future<CacheStatus> getCacheStatus() async {
    return CacheStatus.fromNative(await _map('getCacheStatus'));
  }

  Future<void> openUrl(String url) async {
    await _map('openUrl', {'url': url});
  }

  Future<Map<String, Object?>> _map(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    if (_usesWindowsBackend) {
      final response = await WindowsReplayService.instance.invoke(
        method,
        arguments,
      );
      if (response is Map) {
        return Map<String, Object?>.from(response);
      }
      return const <String, Object?>{};
    }
    final response = await _channel.invokeMapMethod<String, Object?>(
      method,
      arguments,
    );
    return Map<String, Object?>.from(response ?? const {});
  }

  Future<List<Object?>> _list(String method) async {
    if (_usesWindowsBackend) {
      final response = await WindowsReplayService.instance.invoke(method);
      return response is List
          ? List<Object?>.from(response)
          : const <Object?>[];
    }
    return await _channel.invokeListMethod<Object?>(method) ??
        const <Object?>[];
  }
}

class ScheduleSnapshot {
  const ScheduleSnapshot({
    required this.ok,
    required this.tasks,
    this.presets = const [],
    this.startupEnabled = false,
    this.startupSupported = true,
    this.startupSilent = false,
    this.startupRecordingEnabled = false,
    this.startupUploadEnabled = false,
    this.startupTasks = const [],
    required this.history,
    required this.nextWakeup,
    required this.schedulingPrecision,
    required this.exactAlarmPermission,
    required this.recordingDestinationReady,
    required this.ffmpegAvailable,
    required this.uploadConfigured,
    required this.processResident,
    this.error,
  });

  factory ScheduleSnapshot.fromNative(Map<dynamic, dynamic> value) {
    final taskValues = value['tasks'];
    final presetValues = value['presets'];
    final historyValues = value['history'];
    final nextWakeup = value['nextWakeupUtcMillis'];
    return ScheduleSnapshot(
      ok: value['ok'] != false && value['error'] == null,
      startupEnabled: value['startupEnabled'] == true,
      startupSupported: value['startupSupported'] != false,
      startupSilent: value['startupSilent'] == true,
      startupRecordingEnabled:
          (value['startupActions'] as Map?)?['recordingEnabled'] == true,
      startupUploadEnabled:
          (value['startupActions'] as Map?)?['uploadEnabled'] == true,
      startupTasks: (value['startupTasks'] as List? ?? [])
          .whereType<Map>()
          .map(SchedulePresetModel.fromNative)
          .toList(),
      tasks: taskValues is List
          ? taskValues
                .whereType<Map>()
                .map(ScheduledTaskModel.fromNative)
                .toList()
          : const [],
      presets: presetValues is List
          ? presetValues
                .whereType<Map>()
                .map(SchedulePresetModel.fromNative)
                .toList()
          : const [],
      history: historyValues is List
          ? historyValues
                .whereType<Map>()
                .map(ScheduledExecutionModel.fromNative)
                .toList()
          : const [],
      nextWakeup: nextWakeup is num && nextWakeup.toInt() > 0
          ? DateTime.fromMillisecondsSinceEpoch(
              nextWakeup.toInt(),
              isUtc: true,
            ).toLocal()
          : null,
      schedulingPrecision:
          value['schedulingPrecision']?.toString() ?? 'unavailable',
      exactAlarmPermission: value['exactAlarmPermission'] == true,
      recordingDestinationReady: value['recordingDestinationReady'] == true,
      ffmpegAvailable: value['ffmpegAvailable'] == true,
      uploadConfigured: value['uploadConfigured'] == true,
      processResident: value['processResident'] == true,
      error: value['error']?.toString(),
    );
  }

  final bool ok;
  final List<ScheduledTaskModel> tasks;
  final List<SchedulePresetModel> presets;
  final bool startupEnabled;
  final bool startupSupported;
  final bool startupSilent;
  final bool startupRecordingEnabled;
  final bool startupUploadEnabled;
  final List<SchedulePresetModel> startupTasks;
  final List<ScheduledExecutionModel> history;
  final DateTime? nextWakeup;
  final String schedulingPrecision;
  final bool exactAlarmPermission;
  final bool recordingDestinationReady;
  final bool ffmpegAvailable;
  final bool uploadConfigured;
  final bool processResident;
  final String? error;
}

class SchedulePresetModel {
  const SchedulePresetModel({
    required this.id,
    required this.name,
    required this.enabled,
    required this.trigger,
    required this.actions,
  });
  factory SchedulePresetModel.fromNative(Map<dynamic, dynamic> value) {
    return SchedulePresetModel(
      id: value['id']?.toString() ?? '',
      name: value['name']?.toString() ?? '',
      enabled: value['enabled'] == true,
      trigger: Map<String, Object?>.from(value['trigger'] as Map? ?? const {}),
      actions: (value['actions'] as List? ?? const [])
          .whereType<Map>()
          .map((a) => Map<String, Object?>.from(a))
          .toList(),
    );
  }
  final String id;
  final String name;
  final bool enabled;
  final Map<String, Object?> trigger;
  final List<Map<String, Object?>> actions;
}

class ScheduledTaskModel {
  const ScheduledTaskModel({
    required this.id,
    required this.revision,
    required this.name,
    required this.enabled,
    required this.state,
    required this.trigger,
    required this.actions,
    required this.nextDue,
  });

  factory ScheduledTaskModel.fromNative(Map<dynamic, dynamic> value) {
    final triggerValue = value['trigger'];
    final actionValues = value['actions'];
    final nextDue = value['nextDueUtcMillis'];
    return ScheduledTaskModel(
      id: value['id']?.toString() ?? '',
      revision: value['revision'] is num
          ? (value['revision'] as num).toInt()
          : 0,
      name: value['name']?.toString() ?? '',
      enabled: value['enabled'] == true,
      state: value['state']?.toString() ?? 'disabled',
      trigger: triggerValue is Map
          ? Map<String, Object?>.from(triggerValue)
          : const {},
      actions: actionValues is List
          ? actionValues
                .whereType<Map>()
                .map((action) => Map<String, Object?>.from(action))
                .toList()
          : const [],
      nextDue: nextDue is num && nextDue.toInt() > 0
          ? DateTime.fromMillisecondsSinceEpoch(
              nextDue.toInt(),
              isUtc: true,
            ).toLocal()
          : null,
    );
  }

  final String id;
  final int revision;
  final String name;
  final bool enabled;
  final String state;
  final Map<String, Object?> trigger;
  final List<Map<String, Object?>> actions;
  final DateTime? nextDue;
}

class ScheduledExecutionModel {
  const ScheduledExecutionModel({
    required this.executionId,
    required this.taskName,
    required this.result,
    required this.scheduledFor,
    required this.startedAt,
    required this.lateByMillis,
    required this.actionResults,
  });

  factory ScheduledExecutionModel.fromNative(Map<dynamic, dynamic> value) {
    DateTime? parseTime(Object? raw) => raw is num
        ? DateTime.fromMillisecondsSinceEpoch(
            raw.toInt(),
            isUtc: true,
          ).toLocal()
        : null;
    final actionValues = value['actionResults'];
    return ScheduledExecutionModel(
      executionId: value['executionId']?.toString() ?? '',
      taskName: value['taskName']?.toString() ?? '',
      result: value['result']?.toString() ?? 'failed',
      scheduledFor: parseTime(value['scheduledForUtcMillis']),
      startedAt: parseTime(value['startedAtUtcMillis']),
      lateByMillis: value['lateByMillis'] is num
          ? (value['lateByMillis'] as num).toInt()
          : 0,
      actionResults: actionValues is List
          ? actionValues
                .whereType<Map>()
                .map((item) => Map<String, Object?>.from(item))
                .toList()
          : const [],
    );
  }

  final String executionId;
  final String taskName;
  final String result;
  final DateTime? scheduledFor;
  final DateTime? startedAt;
  final int lateByMillis;
  final List<Map<String, Object?>> actionResults;
}

class AudioSettings {
  const AudioSettings({required this.sampleRate, required this.bufferSeconds});

  factory AudioSettings.fromNative(Map<dynamic, dynamic> value) {
    return AudioSettings(
      sampleRate: value['sampleRate'] is int
          ? value['sampleRate'] as int
          : 16000,
      bufferSeconds: value['bufferSeconds'] is int
          ? value['bufferSeconds'] as int
          : 1800,
    );
  }

  final int sampleRate;
  final int bufferSeconds;
}

class AudioSettingsUpdate extends AudioSettings {
  const AudioSettingsUpdate({
    required super.sampleRate,
    required super.bufferSeconds,
    required this.applied,
  });

  factory AudioSettingsUpdate.fromNative(Map<dynamic, dynamic> value) {
    final settings = AudioSettings.fromNative(value);
    return AudioSettingsUpdate(
      sampleRate: settings.sampleRate,
      bufferSeconds: settings.bufferSeconds,
      applied: value['applied'] == true,
    );
  }

  final bool applied;
}

class AudioInputDevice {
  const AudioInputDevice({
    required this.id,
    required this.name,
    required this.isDefault,
  });

  factory AudioInputDevice.fromNative(Map<dynamic, dynamic> value) {
    return AudioInputDevice(
      id: value['id']?.toString() ?? '',
      name:
          value['name']?.toString() ??
          value['label']?.toString() ??
          value['id']?.toString() ??
          '',
      isDefault: value['isDefault'] == true,
    );
  }

  final String id;
  final String name;
  final bool isDefault;
}

class AudioSourceSettings {
  const AudioSourceSettings({
    required this.microphoneEnabled,
    required this.systemAudioEnabled,
    required this.systemAudioSupported,
    required this.inputDeviceSelectionSupported,
    this.microphoneDeviceId,
  });

  static const androidDefault = AudioSourceSettings(
    microphoneEnabled: true,
    systemAudioEnabled: false,
    systemAudioSupported: false,
    inputDeviceSelectionSupported: false,
  );

  factory AudioSourceSettings.fromNative(Map<dynamic, dynamic> value) {
    return AudioSourceSettings(
      microphoneEnabled: value['microphoneEnabled'] != false,
      systemAudioEnabled: value['systemAudioEnabled'] == true,
      microphoneDeviceId: value['microphoneDeviceId']?.toString(),
      systemAudioSupported: value['systemAudioSupported'] == true,
      inputDeviceSelectionSupported:
          value['inputDeviceSelectionSupported'] == true,
    );
  }

  final bool microphoneEnabled;
  final bool systemAudioEnabled;

  /// null keeps device routing attached to the Windows system default.
  final String? microphoneDeviceId;
  final bool systemAudioSupported;
  final bool inputDeviceSelectionSupported;
}

class AudioSourceSettingsUpdate extends AudioSourceSettings {
  const AudioSourceSettingsUpdate({
    required super.microphoneEnabled,
    required super.systemAudioEnabled,
    required super.systemAudioSupported,
    required super.inputDeviceSelectionSupported,
    required this.applied,
    super.microphoneDeviceId,
  });

  factory AudioSourceSettingsUpdate.fromNative(Map<dynamic, dynamic> value) {
    return AudioSourceSettingsUpdate.fromSettings(
      AudioSourceSettings.fromNative(value),
      applied: value['applied'] == true,
    );
  }

  factory AudioSourceSettingsUpdate.fromSettings(
    AudioSourceSettings settings, {
    required bool applied,
  }) {
    return AudioSourceSettingsUpdate(
      microphoneEnabled: settings.microphoneEnabled,
      systemAudioEnabled: settings.systemAudioEnabled,
      microphoneDeviceId: settings.microphoneDeviceId,
      systemAudioSupported: settings.systemAudioSupported,
      inputDeviceSelectionSupported: settings.inputDeviceSelectionSupported,
      applied: applied,
    );
  }

  final bool applied;
}

class ServerConnectionLog {
  const ServerConnectionLog({
    required this.unixSeconds,
    required this.event,
    required this.message,
  });

  factory ServerConnectionLog.fromNative(Map<dynamic, dynamic> value) {
    final time = value['unixSeconds'] ?? value['unix_seconds'];
    return ServerConnectionLog(
      unixSeconds: time is num ? time.toInt() : 0,
      event: value['event']?.toString() ?? 'unknown',
      message: value['message']?.toString() ?? '',
    );
  }

  final int unixSeconds;
  final String event;
  final String message;
}

class ServerConnectionTestResult {
  const ServerConnectionTestResult({
    required this.success,
    required this.testedAtUnixSeconds,
    required this.serverUrl,
    this.error,
  });

  factory ServerConnectionTestResult.fromNative(Map<dynamic, dynamic> value) {
    final testedAt =
        value['testedAtUnixSeconds'] ?? value['tested_at_unix_seconds'];
    return ServerConnectionTestResult(
      success: value['success'] == true,
      testedAtUnixSeconds: testedAt is num ? testedAt.toInt() : 0,
      serverUrl: (value['serverUrl'] ?? value['server_url'])?.toString() ?? '',
      error: value['error']?.toString(),
    );
  }

  final bool success;
  final int testedAtUnixSeconds;
  final String serverUrl;
  final String? error;
}

class ServerSyncStatus {
  const ServerSyncStatus({
    required this.running,
    required this.connected,
    required this.serverUrl,
    required this.keyId,
    required this.localTotalSamples,
    required this.remoteNextSample,
    required this.lagSamples,
    required this.lastSuccessUnixSeconds,
    required this.reconnectCount,
    required this.logs,
    this.serverStreamId,
    this.lastError,
  });

  factory ServerSyncStatus.fromNative(Map<dynamic, dynamic> value) {
    int integer(String camel, String snake) {
      final raw = value[camel] ?? value[snake];
      return raw is num ? raw.toInt() : 0;
    }

    final rawLogs = value['logs'];
    return ServerSyncStatus(
      running: value['running'] == true,
      connected: value['connected'] == true,
      serverUrl: (value['serverUrl'] ?? value['server_url'])?.toString() ?? '',
      keyId: (value['keyId'] ?? value['key_id'])?.toString() ?? '',
      serverStreamId: (value['serverStreamId'] ?? value['server_stream_id'])
          ?.toString(),
      localTotalSamples: integer('localTotalSamples', 'local_total_samples'),
      remoteNextSample: integer('remoteNextSample', 'remote_next_sample'),
      lagSamples: integer('lagSamples', 'lag_samples'),
      lastSuccessUnixSeconds: integer(
        'lastSuccessUnixSeconds',
        'last_success_unix_seconds',
      ),
      reconnectCount: integer('reconnectCount', 'reconnect_count'),
      lastError: (value['lastError'] ?? value['last_error'])?.toString(),
      logs: rawLogs is List
          ? rawLogs
                .whereType<Map>()
                .map(ServerConnectionLog.fromNative)
                .toList(growable: false)
          : const <ServerConnectionLog>[],
    );
  }

  final bool running;
  final bool connected;
  final String serverUrl;
  final String keyId;
  final String? serverStreamId;
  final int localTotalSamples;
  final int remoteNextSample;
  final int lagSamples;
  final int lastSuccessUnixSeconds;
  final int reconnectCount;
  final String? lastError;
  final List<ServerConnectionLog> logs;
}

class ServerSyncSettings {
  const ServerSyncSettings({
    required this.enabled,
    required this.serverHost,
    required this.uploadPort,
    required this.deviceId,
    required this.keyConfigured,
    this.status,
    this.configurationError,
  });

  factory ServerSyncSettings.fromNative(Map<dynamic, dynamic> value) {
    final rawStatus = value['status'] ?? value['syncStatus'];
    final legacyUrl = value['serverUrl']?.toString().trim() ?? '';
    final legacyUri = Uri.tryParse(legacyUrl);
    final serverHost = value['serverHost']?.toString().trim().isNotEmpty == true
        ? value['serverHost'].toString().trim()
        : legacyUri?.host ?? '';
    final rawPort = value['uploadPort'];
    final uploadPort = rawPort is num
        ? rawPort.toInt()
        : legacyUri?.hasPort == true
        ? legacyUri!.port
        : 32581;
    return ServerSyncSettings(
      enabled: value['enabled'] == true,
      serverHost: serverHost,
      uploadPort: uploadPort,
      deviceId: value['deviceId']?.toString() ?? '',
      keyConfigured: value['keyConfigured'] == true,
      status: rawStatus is Map ? ServerSyncStatus.fromNative(rawStatus) : null,
      configurationError: value['configurationError']?.toString(),
    );
  }

  final bool enabled;
  final String serverHost;
  final int uploadPort;
  final String deviceId;
  final bool keyConfigured;
  final ServerSyncStatus? status;
  final String? configurationError;

  bool get configured =>
      serverHost.isNotEmpty &&
      uploadPort >= 1 &&
      uploadPort <= 65535 &&
      keyConfigured;

  String get serverUrl {
    final host = serverHost.trim();
    if (host.isEmpty || uploadPort < 1 || uploadPort > 65535) {
      return '';
    }
    final unwrapped = host.startsWith('[') && host.endsWith(']')
        ? host.substring(1, host.length - 1)
        : host;
    final authority = unwrapped.contains(':') ? '[$unwrapped]' : unwrapped;
    return 'http://$authority:$uploadPort';
  }

  String get connectionLabel =>
      serverHost.isEmpty ? '' : '$serverHost:$uploadPort';
}

class ServerSyncSettingsUpdate extends ServerSyncSettings {
  const ServerSyncSettingsUpdate({
    required super.enabled,
    required super.serverHost,
    required super.uploadPort,
    required super.deviceId,
    required super.keyConfigured,
    required this.applied,
    super.status,
    super.configurationError,
  });

  factory ServerSyncSettingsUpdate.fromNative(Map<dynamic, dynamic> value) {
    final settings = ServerSyncSettings.fromNative(value);
    return ServerSyncSettingsUpdate(
      enabled: settings.enabled,
      serverHost: settings.serverHost,
      uploadPort: settings.uploadPort,
      deviceId: settings.deviceId,
      keyConfigured: settings.keyConfigured,
      status: settings.status,
      configurationError: settings.configurationError,
      applied: value['applied'] == true,
    );
  }

  final bool applied;
}

class RecordingModeSettings {
  const RecordingModeSettings({required this.mode, required this.trigger});

  factory RecordingModeSettings.fromNative(Map<dynamic, dynamic> value) {
    return RecordingModeSettings(
      mode: RecordingMode.fromStorageValue(value['mode']?.toString()),
      trigger: LockRecordingTrigger.fromStorageValue(
        value['trigger']?.toString(),
      ),
    );
  }

  final RecordingMode mode;
  final LockRecordingTrigger trigger;
}

class FolderStatus {
  const FolderStatus({required this.selected, this.uri, this.error});

  factory FolderStatus.fromNative(Map<dynamic, dynamic> value) {
    return FolderStatus(
      selected: value['selected'] == true,
      uri: value['uri']?.toString(),
      error: value['error']?.toString(),
    );
  }

  final bool selected;
  final String? uri;
  final String? error;
}

class ReplayStatus {
  const ReplayStatus({
    required this.running,
    required this.serviceActive,
    required this.recordingMode,
    required this.lockRecordingTrigger,
    required this.evidenceState,
    required this.serviceState,
    required this.availableMillis,
    required this.sessionStartedUnixMillis,
    this.evidenceLastStopReason,
    this.captureError,
    this.sampleRate,
    this.bufferSeconds,
    this.cacheBytes,
    this.syncConfigured = false,
    this.syncStatus,
    this.syncConfigurationError,
  });

  factory ReplayStatus.fromNative(Map<dynamic, dynamic> value) {
    final availableMillis = value['availableMillis'];
    final availableSeconds = value['availableSeconds'];
    return ReplayStatus(
      running: value['running'] == true,
      serviceActive: value['serviceActive'] == true,
      recordingMode: RecordingMode.fromStorageValue(
        value['recordingMode']?.toString(),
      ),
      lockRecordingTrigger: LockRecordingTrigger.fromStorageValue(
        value['lockRecordingTrigger']?.toString(),
      ),
      evidenceState: value['evidenceState']?.toString() ?? 'off',
      evidenceLastStopReason: value['evidenceLastStopReason']?.toString(),
      serviceState:
          value['serviceState']?.toString() ??
          value['statusCode']?.toString() ??
          'stopped',
      availableMillis: availableMillis is num
          ? availableMillis.toInt()
          : availableSeconds is int
          ? availableSeconds * 1000
          : 0,
      sessionStartedUnixMillis: value['sessionStartedUnixMillis'] is num
          ? (value['sessionStartedUnixMillis'] as num).toInt()
          : 0,
      captureError: value['captureError']?.toString(),
      sampleRate: value['sampleRate'] is int
          ? value['sampleRate'] as int
          : null,
      bufferSeconds: value['bufferSeconds'] is int
          ? value['bufferSeconds'] as int
          : null,
      cacheBytes: value['cacheBytes'] is int
          ? value['cacheBytes'] as int
          : null,
      syncConfigured: value['syncConfigured'] == true,
      syncStatus: value['syncStatus'] is Map
          ? ServerSyncStatus.fromNative(value['syncStatus'] as Map)
          : null,
      syncConfigurationError: value['syncConfigurationError']?.toString(),
    );
  }

  final bool running;
  final bool serviceActive;
  final RecordingMode recordingMode;
  final LockRecordingTrigger lockRecordingTrigger;
  final String evidenceState;
  final String? evidenceLastStopReason;
  final String serviceState;
  final int availableMillis;
  final int sessionStartedUnixMillis;
  final String? captureError;
  final int? sampleRate;
  final int? bufferSeconds;
  final int? cacheBytes;
  final bool syncConfigured;
  final ServerSyncStatus? syncStatus;
  final String? syncConfigurationError;
}

class MeterStatus {
  const MeterStatus({
    required this.running,
    required this.serviceActive,
    required this.recordingMode,
    required this.lockRecordingTrigger,
    required this.evidenceState,
    required this.serviceState,
    required this.availableMillis,
    required this.sessionStartedUnixMillis,
    required this.level,
    required this.peakLevel,
    this.evidenceLastStopReason,
    this.captureError,
  });

  factory MeterStatus.fromNative(Map<dynamic, dynamic> value) {
    return MeterStatus(
      running: value['running'] == true,
      serviceActive: value['serviceActive'] == true,
      recordingMode: RecordingMode.fromStorageValue(
        value['recordingMode']?.toString(),
      ),
      lockRecordingTrigger: LockRecordingTrigger.fromStorageValue(
        value['lockRecordingTrigger']?.toString(),
      ),
      evidenceState: value['evidenceState']?.toString() ?? 'off',
      evidenceLastStopReason: value['evidenceLastStopReason']?.toString(),
      serviceState:
          value['serviceState']?.toString() ??
          value['statusCode']?.toString() ??
          'stopped',
      availableMillis: value['availableMillis'] is num
          ? (value['availableMillis'] as num).toInt()
          : 0,
      sessionStartedUnixMillis: value['sessionStartedUnixMillis'] is num
          ? (value['sessionStartedUnixMillis'] as num).toInt()
          : 0,
      level: value['level'] is num ? (value['level'] as num).toDouble() : 0,
      peakLevel: value['peakLevel'] is num
          ? (value['peakLevel'] as num).toDouble()
          : 0,
      captureError: value['captureError']?.toString(),
    );
  }

  final bool running;
  final bool serviceActive;
  final RecordingMode recordingMode;
  final LockRecordingTrigger lockRecordingTrigger;
  final String evidenceState;
  final String? evidenceLastStopReason;
  final String serviceState;
  final int availableMillis;
  final int sessionStartedUnixMillis;
  final double level;
  final double peakLevel;
  final String? captureError;
}

class ReplayCommandResult {
  const ReplayCommandResult({
    required this.running,
    required this.serviceActive,
    this.recordingMode,
    this.lockRecordingTrigger,
    this.evidenceState,
    this.evidenceLastStopReason,
    this.serviceState,
    this.error,
  });

  factory ReplayCommandResult.fromNative(Map<dynamic, dynamic> value) {
    final running = value['running'] == true;
    return ReplayCommandResult(
      running: running,
      serviceActive: value.containsKey('serviceActive')
          ? value['serviceActive'] == true
          : running,
      recordingMode: value.containsKey('recordingMode')
          ? RecordingMode.fromStorageValue(value['recordingMode']?.toString())
          : null,
      lockRecordingTrigger: value.containsKey('lockRecordingTrigger')
          ? LockRecordingTrigger.fromStorageValue(
              value['lockRecordingTrigger']?.toString(),
            )
          : null,
      evidenceState: value['evidenceState']?.toString(),
      evidenceLastStopReason: value['evidenceLastStopReason']?.toString(),
      serviceState:
          value['serviceState']?.toString() ?? value['statusCode']?.toString(),
      error: value['error']?.toString(),
    );
  }

  final bool running;
  final bool serviceActive;
  final RecordingMode? recordingMode;
  final LockRecordingTrigger? lockRecordingTrigger;
  final String? evidenceState;
  final String? evidenceLastStopReason;
  final String? serviceState;
  final String? error;
}

class SaveClipResult {
  const SaveClipResult({
    required this.saved,
    required this.pending,
    this.error,
    this.jobId,
  });

  factory SaveClipResult.fromNative(Map<dynamic, dynamic> value) {
    return SaveClipResult(
      saved: value['saved'] == true,
      pending: value['pending'] == true,
      jobId: (value['jobId'] as num?)?.toInt(),
      error: value['error']?.toString(),
    );
  }

  final bool saved;
  final bool pending;
  final int? jobId;
  final String? error;
}

class OperationResult {
  const OperationResult({
    required this.ok,
    this.error,
    this.name,
    this.deletedBytes,
    this.cacheBytes,
    this.activeReplayCachePreserved = false,
  });

  factory OperationResult.fromNative(Map<dynamic, dynamic> value) {
    return OperationResult(
      ok: value['ok'] == true,
      error: value['error']?.toString(),
      name: value['name']?.toString(),
      deletedBytes: value['deletedBytes'] is int
          ? value['deletedBytes'] as int
          : null,
      cacheBytes: value['cacheBytes'] is int
          ? value['cacheBytes'] as int
          : null,
      activeReplayCachePreserved: value['activeReplayCachePreserved'] == true,
    );
  }

  final bool ok;
  final String? error;
  final String? name;
  final int? deletedBytes;
  final int? cacheBytes;
  final bool activeReplayCachePreserved;
}

class CacheClearResult extends OperationResult {
  const CacheClearResult({
    required super.ok,
    super.error,
    super.deletedBytes,
    super.cacheBytes,
    super.activeReplayCachePreserved = false,
  });

  factory CacheClearResult.fromNative(Map<dynamic, dynamic> value) {
    final result = OperationResult.fromNative(value);
    return CacheClearResult(
      ok: result.ok,
      error: result.error,
      deletedBytes: result.deletedBytes,
      cacheBytes: result.cacheBytes,
      activeReplayCachePreserved: result.activeReplayCachePreserved,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'ok': ok,
      'error': error,
      'deletedBytes': deletedBytes,
      'cacheBytes': cacheBytes,
      'activeReplayCachePreserved': activeReplayCachePreserved,
    };
  }
}

class CacheStatus {
  const CacheStatus({required this.ok, required this.cacheBytes});

  factory CacheStatus.fromNative(Map<dynamic, dynamic> value) {
    return CacheStatus(
      ok: value['ok'] == true,
      cacheBytes: value['cacheBytes'] is int ? value['cacheBytes'] as int : 0,
    );
  }

  final bool ok;
  final int cacheBytes;
}

class BufferWindow {
  const BufferWindow({
    required this.bufferId,
    required this.sampleRate,
    required this.channels,
    required this.startSample,
    required this.endSample,
  });
  factory BufferWindow.fromNative(Map<dynamic, dynamic> data) {
    final window = BufferWindow(
      bufferId: data['bufferId'] as String? ?? '',
      sampleRate: (data['sampleRate'] as num? ?? 0).toInt(),
      channels: (data['channels'] as num? ?? 0).toInt(),
      startSample: (data['startSample'] as num? ?? 0).toInt(),
      endSample: (data['endSample'] as num? ?? 0).toInt(),
    );
    if (window.bufferId.isEmpty ||
        window.sampleRate <= 0 ||
        window.channels <= 0 ||
        window.endSample < window.startSample) {
      throw const FormatException('buffer_unavailable');
    }
    return window;
  }
  final String bufferId;
  final int sampleRate, channels, startSample, endSample;
  double get duration => (endSample - startSample) / (sampleRate * channels);
  BufferSelection select(double start, double end) {
    if (!start.isFinite ||
        !end.isFinite ||
        start != start.truncateToDouble() ||
        end != end.truncateToDouble() ||
        start < 0 ||
        end > duration ||
        start >= end) {
      throw const FormatException('BUFFER_RANGE_INVALID');
    }
    final first = startSample + (start * sampleRate).round() * channels;
    final last = math.min(
      endSample,
      startSample + (end * sampleRate).round() * channels,
    );
    if (first >= last) throw const FormatException('BUFFER_RANGE_INVALID');
    return BufferSelection(window: this, startSample: first, endSample: last);
  }
}

class BufferSelection {
  const BufferSelection({
    required this.window,
    required this.startSample,
    required this.endSample,
  });
  final BufferWindow window;
  final int startSample, endSample;
  double get start =>
      (startSample - window.startSample) /
      (window.sampleRate * window.channels);
  double get end =>
      (endSample - window.startSample) / (window.sampleRate * window.channels);
  double get duration => end - start;
  Map<String, Object?> toMap() => {
    'bufferId': window.bufferId,
    'startSample': startSample,
    'endSample': endSample,
  };
}
