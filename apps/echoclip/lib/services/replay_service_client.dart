part of '../main.dart';

class ReplayServiceClient {
  const ReplayServiceClient();

  static const MethodChannel _channel = MethodChannel(
    'com.echoclip/replay_service',
  );

  static bool get _usesWindowsBackend =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

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

  Future<OperationResult> processRecording({
    required ClipItem clip,
    required double gainDb,
    required String format,
    required int mp3BitrateKbps,
  }) async {
    return OperationResult.fromNative(
      await _map('processRecording', {
        'uri': clip.uri,
        'parentUri': clip.parentUri,
        'gainDb': gainDb,
        'format': format,
        'mp3BitrateKbps': mp3BitrateKbps,
      }),
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
  });

  factory SaveClipResult.fromNative(Map<dynamic, dynamic> value) {
    return SaveClipResult(
      saved: value['saved'] == true,
      pending: value['pending'] == true,
      error: value['error']?.toString(),
    );
  }

  final bool saved;
  final bool pending;
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
