import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';

import 'windows_replay_ffi.dart';

/// Native Windows implementation behind [ReplayServiceClient].
///
/// Microphone capture, WASAPI system-audio loopback, mixing, and the rolling
/// one-minute segments live entirely in the Rust DLL. Dart only issues
/// lifecycle/export/scheduling commands and serves the desktop settings,
/// library, playback, and scheduled-task UI.
class WindowsReplayService {
  WindowsReplayService._() {
    _playerStateSubscription = _player.onPlayerStateChanged.listen((state) {
      _playerState = state;
    });
    _positionSubscription = _player.onPositionChanged.listen((position) {
      _playbackPositionMs = position.inMilliseconds;
    });
    _durationSubscription = _player.onDurationChanged.listen((duration) {
      _playbackDurationMs = duration.inMilliseconds;
    });
    _completeSubscription = _player.onPlayerComplete.listen((_) {
      _playerState = PlayerState.completed;
      _playbackPositionMs = _playbackDurationMs;
    });
  }

  static final WindowsReplayService instance = WindowsReplayService._();

  static const Set<int> _sampleRates = {8000, 16000, 24000, 48000};
  static const Set<String> _recordingExtensions = {
    '.aac',
    '.flac',
    '.m4a',
    '.mp3',
    '.ogg',
    '.wav',
  };

  final AudioPlayer _player = AudioPlayer();

  late final StreamSubscription<PlayerState> _playerStateSubscription;
  late final StreamSubscription<Duration> _positionSubscription;
  late final StreamSubscription<Duration> _durationSubscription;
  late final StreamSubscription<void> _completeSubscription;

  Future<void>? _initialization;
  Future<void>? _shutdown;
  bool _closing = false;
  final Set<Future<Object?>> _inFlight = {};
  Future<void> _operationTail = Future<void>.value();
  Directory? _runtimeDirectory;
  File? _settingsFile;
  WindowsReplayFfi? _ffi;
  int? _nativeHandle;

  int _sampleRate = 16000;
  int _bufferSeconds = 1800;
  bool _microphoneEnabled = true;
  bool _systemAudioEnabled = false;
  String? _microphoneDeviceId;
  String _uiLanguageMode = 'system';
  String _recordingMode = 'standard';
  String _lockRecordingTrigger = 'screen_off';
  String? _recordingFolder;
  bool _syncEnabled = false;
  String _syncServerHost = '';
  int _syncUploadPort = 32581;
  String? _syncProtectedUploadKey;
  String _syncDeviceId = '';
  Map<String, Object?>? _syncStatus;
  String? _syncConfigurationError;

  bool _running = false;
  bool _serviceActive = false;
  int _sessionStartedUnixMillis = 0;
  int _availableMillis = 0;
  int _persistedAvailableMillis = 0;
  int _nativeCacheBytes = 0;
  int? _activeSampleRate;
  String? _captureError;
  String? _statusReadError;
  int _nativeStatusFailures = 0;
  double _level = 0;
  double _peakLevel = 0;
  DateTime _lastLevelAt = DateTime.fromMillisecondsSinceEpoch(0);

  String? _playbackUri;
  double _playbackSpeed = 1;
  int _playbackPositionMs = 0;
  int _playbackDurationMs = 0;
  PlayerState _playerState = PlayerState.stopped;

  Future<Object?> invoke(String method, [Map<String, Object?>? arguments]) {
    if (_closing) {
      return Future.value(_operationError('application_shutting_down'));
    }
    final pending = _invoke(method, arguments);
    _inFlight.add(pending);
    return pending.whenComplete(() => _inFlight.remove(pending));
  }

  Future<Object?> _invoke(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    if (_closing) return _operationError('application_shutting_down');
    await _ensureInitialized();
    if (_closing) return _operationError('application_shutting_down');
    await _ensureNativeHandle();
    if (_closing) return _operationError('application_shutting_down');
    final args = arguments ?? const <String, Object?>{};
    try {
      return await Future<Object?>.value(switch (method) {
        'getUiLanguageMode' => <String, Object?>{'mode': _uiLanguageMode},
        'setUiLanguageMode' => _setUiLanguageMode(args['mode']),
        'getAudioSettings' => _audioSettingsMap(),
        'setAudioSettings' => _setAudioSettings(args),
        'listAudioInputDevices' => _listAudioInputDevices(),
        'getAudioSourceSettings' => _audioSourceSettingsMap(),
        'setAudioSourceSettings' => _setAudioSourceSettings(args),
        'getServerSyncSettings' => _serverSyncSettingsMap(),
        'setServerSyncEnabled' => _setServerSyncEnabled(args),
        'setServerSyncSettings' => _setServerSyncSettings(args),
        'testServerConnection' => _testServerConnection(args),
        'getRecordingModeSettings' => _recordingModeSettingsMap(),
        'setRecordingModeSettings' => _setRecordingModeSettings(args),
        'getRecordingFolder' => _recordingFolderMap(),
        'chooseRecordingFolder' => _chooseRecordingFolder(),
        'getReplayStatus' => _statusMap(),
        'getMeterStatus' => _meterMap(),
        'startReplay' => _runExclusive(() => _startReplay(args)),
        'stopReplay' => _runExclusive(_stopReplay),
        'saveReplayClip' => _runExclusive(
          () => _saveReplayClip(_asInt(args['seconds'], 30)),
        ),
        'listGroups' => _listGroups(),
        'listRecordings' => _listRecordings(),
        'playRecording' => _playRecording(args),
        'pausePreview' => _pausePreview(),
        'resumePreview' => _resumePreview(),
        'stopPreview' => _stopPreview(),
        'seekPreview' => _seekPreview(args),
        'setPlaybackSpeed' => _setPlaybackSpeed(args),
        'createGroup' => _createGroup(args),
        'renameGroup' => _renameGroup(args),
        'deleteGroup' => _deleteGroup(args),
        'renameRecording' => _renameRecording(args),
        'deleteRecording' => _deleteRecording(args),
        'moveRecording' => _moveRecording(args),
        'convertWavToMp3' => _convertWavToMp3(args),
        'getScheduleSnapshot' => _scheduleSnapshot(),
        'upsertScheduledTask' => _runExclusive(
          () => _upsertScheduledTask(args),
        ),
        'deleteScheduledTask' => _runExclusive(
          () => _deleteScheduledTask(args),
        ),
        'setScheduledTaskEnabled' => _runExclusive(
          () => _setScheduledTaskEnabled(args),
        ),
        'clearCache' => _runExclusive(_clearCache),
        'getCacheStatus' => _cacheStatus(),
        'openUrl' => _openUrl(args),
        _ => <String, Object?>{
          'ok': false,
          'error': 'unsupported_windows_method:$method',
        },
      });
    } catch (error) {
      if (method == 'listGroups' || method == 'listRecordings') {
        return <Object?>[];
      }
      return _failureFor(method, error);
    }
  }

  Future<void> dispose() => _shutdown ??= _shutdownBackend();

  Future<void> _shutdownBackend() async {
    // Bypass the command queue: it may be waiting for an export that shutdown
    // must cancel. Mark closed before awaiting anything so polling cannot
    // recreate the native handle during teardown.
    _closing = true;
    final handle = _nativeHandle;
    _nativeHandle = null;
    _persistedAvailableMillis = _availableMillis;
    _running = false;
    _serviceActive = false;
    await Future.wait<void>([
      if (handle != null)
        Isolate.run(() => WindowsReplayFfi.open().destroy(handle)),
      ?_initialization,
      _playerStateSubscription.cancel(),
      _positionSubscription.cancel(),
      _durationSubscription.cancel(),
      _completeSubscription.cancel(),
      _player.dispose(),
    ]);
    // Canceled exports finish their temporary-file cleanup before engine exit.
    await _operationTail;
    // Include non-queued probes/conversions: an outstanding FFI isolate would
    // otherwise hold up Flutter engine teardown after the window disappeared.
    await Future.wait(
      _inFlight.toList().map((pending) async {
        try {
          await pending;
        } catch (_) {
          /* Failed commands are already reported. */
        }
      }),
    );
    // Initialization and existing settings commands must finish before the
    // final write, especially when exiting immediately after application start.
    if (_settingsFile != null) await _persistSettings();
  }

  Future<T> _runExclusive<T>(Future<T> Function() action) {
    final previous = _operationTail;
    final release = Completer<void>();
    _operationTail = release.future;
    return previous
        .then((_) {
          if (_closing) throw StateError('application_shutting_down');
          return action();
        })
        .whenComplete(release.complete);
  }

  Future<void> _ensureInitialized() {
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    final appData =
        Platform.environment['APPDATA'] ??
        Platform.environment['LOCALAPPDATA'] ??
        Directory.current.path;
    final support = Directory(path.join(appData, 'EchoClip'));
    final runtime = Directory(path.join(support.path, 'replay-cache'));
    await support.create(recursive: true);
    await runtime.create(recursive: true);
    _runtimeDirectory = runtime;
    _nativeCacheBytes = _directorySize(runtime);
    _settingsFile = File(path.join(support.path, 'settings.json'));

    final settingsFile = _settingsFile!;
    if (!await settingsFile.exists()) {
      _syncDeviceId = _newDeviceId();
      await _persistSettings();
      return;
    }
    try {
      final decoded = jsonDecode(await settingsFile.readAsString());
      if (decoded is! Map) {
        return;
      }
      _sampleRate = _sanitizeSampleRate(decoded['sampleRate']);
      _bufferSeconds = _sanitizeBufferSeconds(decoded['bufferSeconds']);
      _microphoneEnabled = decoded['microphoneEnabled'] != false;
      _systemAudioEnabled = decoded['systemAudioEnabled'] == true;
      if (!_microphoneEnabled && !_systemAudioEnabled) {
        _microphoneEnabled = true;
      }
      final storedMicrophoneDeviceId = decoded['microphoneDeviceId']
          ?.toString()
          .trim();
      _microphoneDeviceId =
          storedMicrophoneDeviceId == null || storedMicrophoneDeviceId.isEmpty
          ? null
          : storedMicrophoneDeviceId;
      _uiLanguageMode = _sanitizeLanguage(decoded['uiLanguageMode']);
      _recordingMode = _sanitizeRecordingMode(decoded['recordingMode']);
      _lockRecordingTrigger = _sanitizeTrigger(decoded['lockRecordingTrigger']);
      final legacyUrl = decoded['syncServerUrl']?.toString().trim() ?? '';
      final legacyUri = Uri.tryParse(legacyUrl);
      _syncServerHost = decoded['syncServerHost']?.toString().trim() ?? '';
      if (_syncServerHost.isEmpty && legacyUri?.host.isNotEmpty == true) {
        _syncServerHost = legacyUri!.host;
      }
      _syncUploadPort = _sanitizeUploadPort(
        decoded['syncUploadPort'] ??
            (legacyUri?.hasPort == true ? legacyUri!.port : 32581),
      );
      _syncProtectedUploadKey = decoded['syncProtectedUploadKey']?.toString();
      _syncDeviceId = decoded['syncDeviceId']?.toString().trim() ?? '';
      _syncEnabled =
          decoded['syncEnabled'] == true &&
          _isValidSyncHost(_syncServerHost) &&
          _syncProtectedUploadKey?.isNotEmpty == true;
      final storedFolder = decoded['recordingFolder']?.toString();
      if (storedFolder != null && Directory(storedFolder).existsSync()) {
        _recordingFolder = path.normalize(path.absolute(storedFolder));
      }
      final persistedMillis = _asInt(decoded['lastAvailableMillis'], 0);
      _persistedAvailableMillis = persistedMillis > 0 ? persistedMillis : 0;
      _availableMillis = _persistedAvailableMillis;
      final persistedSessionStarted = _asInt(
        decoded['lastSessionStartedUnixMillis'],
        0,
      );
      _sessionStartedUnixMillis = persistedSessionStarted > 0
          ? persistedSessionStarted
          : 0;
    } catch (_) {
      // A malformed settings file should never prevent the recorder starting.
    }
    if (_syncDeviceId.isEmpty) {
      _syncDeviceId = _newDeviceId();
    }
    await _persistSettings();
  }

  Future<int> _ensureNativeHandle() async {
    if (_closing) throw StateError('application_shutting_down');
    final existing = _nativeHandle;
    if (existing != null) {
      _configureSchedulerRuntime(_ffi ??= WindowsReplayFfi.open(), existing);
      return existing;
    }
    final ffi = _ffi ??= WindowsReplayFfi.open();
    final handle = ffi.create(
      workDirectory: _runtimeDirectory!.path,
      sampleRate: _sampleRate,
      bufferSeconds: _bufferSeconds,
    );
    _nativeHandle = handle;
    _activeSampleRate = _sampleRate;
    _configureNativeCapture(ffi, handle);
    _applyNativeSync(ffi, handle);
    _configureSchedulerRuntime(ffi, handle);
    _refreshNativeSnapshot();
    return handle;
  }

  Future<void> _destroyNativeHandle() async {
    final handle = _nativeHandle;
    _nativeHandle = null;
    if (handle == null) {
      return;
    }
    await Isolate.run(() {
      WindowsReplayFfi.open().destroy(handle);
    });
  }

  Future<void> _recreateNativeHandle() async {
    if (_running) {
      return;
    }
    await _destroyNativeHandle();
    await _ensureNativeHandle();
  }

  void _configureSchedulerRuntime(WindowsReplayFfi ffi, int handle) {
    final code = ffi.configureSchedulerRuntimeCode(
      handle,
      recordingDirectory: _recordingFolder ?? '',
      ffmpegPath: _resolveFfmpeg() ?? '',
    );
    if (code != WindowsReplayFfi.ok) {
      throw ffi.errorFor('ec_scheduler_configure_runtime', code, handle);
    }
  }

  Future<void> _persistSettings() async {
    final settingsFile = _settingsFile;
    if (settingsFile == null) {
      return;
    }
    final temporary = File('${settingsFile.path}.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'sampleRate': _sampleRate,
        'bufferSeconds': _bufferSeconds,
        'microphoneEnabled': _microphoneEnabled,
        'systemAudioEnabled': _systemAudioEnabled,
        'microphoneDeviceId': _microphoneDeviceId,
        'uiLanguageMode': _uiLanguageMode,
        'recordingMode': _recordingMode,
        'lockRecordingTrigger': _lockRecordingTrigger,
        'recordingFolder': _recordingFolder,
        'lastAvailableMillis': _persistedAvailableMillis,
        'lastSessionStartedUnixMillis': _sessionStartedUnixMillis,
        'syncEnabled': _syncEnabled,
        'syncServerHost': _syncServerHost,
        'syncUploadPort': _syncUploadPort,
        'syncProtectedUploadKey': _syncProtectedUploadKey,
        'syncDeviceId': _syncDeviceId,
      }),
      flush: true,
    );
    if (await settingsFile.exists()) {
      await settingsFile.delete();
    }
    await temporary.rename(settingsFile.path);
  }

  Future<Map<String, Object?>> _setUiLanguageMode(Object? value) async {
    _uiLanguageMode = _sanitizeLanguage(value);
    await _persistSettings();
    return <String, Object?>{'mode': _uiLanguageMode};
  }

  Map<String, Object?> _audioSettingsMap({bool? applied}) => <String, Object?>{
    'sampleRate': _sampleRate,
    'bufferSeconds': _bufferSeconds,
    'applied': ?applied,
  };

  Future<Map<String, Object?>> _setAudioSettings(
    Map<String, Object?> args,
  ) async {
    final nextRate = _sanitizeSampleRate(args['sampleRate']);
    final nextBuffer = _sanitizeBufferSeconds(args['bufferSeconds']);
    final applied = !_running;
    final changed = _sampleRate != nextRate || _bufferSeconds != nextBuffer;
    _sampleRate = nextRate;
    _bufferSeconds = nextBuffer;
    await _persistSettings();
    if (applied && changed) {
      await _recreateNativeHandle();
    }
    return _audioSettingsMap(applied: applied);
  }

  List<Object?> _listAudioInputDevices() {
    final ffi = _ffi ??= WindowsReplayFfi.open();
    return ffi.audioInputDevicesJson();
  }

  Map<String, Object?> _audioSourceSettingsMap({bool? applied}) =>
      <String, Object?>{
        'microphoneEnabled': _microphoneEnabled,
        'systemAudioEnabled': _systemAudioEnabled,
        'microphoneDeviceId': _microphoneDeviceId,
        'systemAudioSupported': true,
        'inputDeviceSelectionSupported': true,
        'applied': ?applied,
      };

  Future<Map<String, Object?>> _setAudioSourceSettings(
    Map<String, Object?> args,
  ) async {
    final microphoneEnabled = args['microphoneEnabled'] == true;
    final systemAudioEnabled = args['systemAudioEnabled'] == true;
    if (!microphoneEnabled && !systemAudioEnabled) {
      throw ArgumentError('at_least_one_audio_source_required');
    }
    final rawDeviceId = args['microphoneDeviceId']?.toString().trim();
    _microphoneEnabled = microphoneEnabled;
    _systemAudioEnabled = systemAudioEnabled;
    _microphoneDeviceId = rawDeviceId == null || rawDeviceId.isEmpty
        ? null
        : rawDeviceId;
    final applied = !_running;
    await _persistSettings();
    final handle = _nativeHandle;
    if (applied && handle != null) {
      _configureNativeCapture(_ffi ??= WindowsReplayFfi.open(), handle);
    }
    return _audioSourceSettingsMap(applied: applied);
  }

  String get _syncServerUrl {
    if (!_isValidSyncHost(_syncServerHost)) {
      return '';
    }
    final authority = _syncServerHost.contains(':')
        ? '[$_syncServerHost]'
        : _syncServerHost;
    return 'http://$authority:$_syncUploadPort';
  }

  Map<String, Object?> _serverSyncSettingsMap({bool? applied}) {
    _refreshNativeSnapshot();
    return <String, Object?>{
      'enabled': _syncEnabled,
      'serverHost': _syncServerHost,
      'uploadPort': _syncUploadPort,
      'serverUrl': _syncServerUrl,
      'deviceId': _syncDeviceId,
      'keyConfigured': _syncProtectedUploadKey?.isNotEmpty == true,
      'status': _syncStatus,
      'configurationError': _syncConfigurationError,
      'applied': ?applied,
    };
  }

  Future<Map<String, Object?>> _setServerSyncEnabled(
    Map<String, Object?> args,
  ) async {
    final requestedEnabled = args['enabled'] == true;
    if (requestedEnabled && !_isValidSyncHost(_syncServerHost)) {
      throw ArgumentError('sync_server_host_invalid');
    }
    if (requestedEnabled && (_syncUploadPort < 1 || _syncUploadPort > 65535)) {
      throw ArgumentError('sync_upload_port_invalid');
    }
    if (requestedEnabled && _syncProtectedUploadKey?.isNotEmpty != true) {
      throw ArgumentError('sync_upload_key_required');
    }
    _syncEnabled = requestedEnabled;
    return _persistAndApplySync();
  }

  Future<Map<String, Object?>> _setServerSyncSettings(
    Map<String, Object?> args,
  ) async {
    final ffi = _ffi ??= WindowsReplayFfi.open();
    final clearKey = args['clearKey'] == true;
    final newKey = args['uploadKey']?.toString().trim();
    if (clearKey) {
      _syncProtectedUploadKey = null;
      _syncEnabled = false;
    } else if (newKey != null && newKey.isNotEmpty) {
      final decoded = base64Decode(newKey);
      if (decoded.length != 32) {
        throw ArgumentError('upload_key_must_be_32_bytes');
      }
      _syncProtectedUploadKey = ffi.protectSecret(newKey);
    }
    _syncServerHost = (args['serverHost'] ?? _syncServerHost).toString().trim();
    if (_syncServerHost.startsWith('[') && _syncServerHost.endsWith(']')) {
      _syncServerHost = _syncServerHost.substring(
        1,
        _syncServerHost.length - 1,
      );
    }
    _syncUploadPort = _asInt(args['uploadPort'], _syncUploadPort);
    if (!_isValidSyncHost(_syncServerHost)) {
      throw ArgumentError('sync_server_host_invalid');
    }
    if (_syncUploadPort < 1 || _syncUploadPort > 65535) {
      throw ArgumentError('sync_upload_port_invalid');
    }
    if (_syncEnabled && _syncProtectedUploadKey?.isNotEmpty != true) {
      throw ArgumentError('sync_upload_key_required');
    }
    return _persistAndApplySync();
  }

  Future<Map<String, Object?>> _testServerConnection(
    Map<String, Object?> args,
  ) async {
    var serverHost = (args['serverHost'] ?? _syncServerHost).toString().trim();
    if (serverHost.startsWith('[') && serverHost.endsWith(']')) {
      serverHost = serverHost.substring(1, serverHost.length - 1);
    }
    final uploadPort = _asInt(args['uploadPort'], _syncUploadPort);
    final suppliedKey = args['uploadKey']?.toString().trim();
    if (!_isValidSyncHost(serverHost)) {
      return <String, Object?>{
        'success': false,
        'error': 'sync_server_host_invalid',
      };
    }
    if (uploadPort < 1 || uploadPort > 65535) {
      return <String, Object?>{
        'success': false,
        'error': 'sync_upload_port_invalid',
      };
    }
    if (suppliedKey?.isNotEmpty == true) {
      try {
        if (base64Decode(suppliedKey!).length != 32) {
          throw const FormatException();
        }
      } on FormatException {
        return <String, Object?>{
          'success': false,
          'error': 'sync_upload_key_invalid',
        };
      }
    } else if (_syncProtectedUploadKey?.isNotEmpty != true) {
      return <String, Object?>{
        'success': false,
        'error': 'sync_upload_key_required',
      };
    }

    final authority = serverHost.contains(':') ? '[$serverHost]' : serverHost;
    final serverUrl = 'http://$authority:$uploadPort';
    final protectedKey = _syncProtectedUploadKey;
    final deviceId = _syncDeviceId;
    try {
      final outcome = await Isolate.run(() {
        final ffi = WindowsReplayFfi.open();
        final code = suppliedKey?.isNotEmpty == true
            ? ffi.testSyncConnectionCode(
                serverUrl: serverUrl,
                uploadKey: suppliedKey!,
                deviceId: deviceId,
              )
            : ffi.testSyncConnectionProtectedCode(
                serverUrl: serverUrl,
                protectedUploadKey: protectedKey!,
                deviceId: deviceId,
              );
        return <String, Object?>{
          'success': code == WindowsReplayFfi.ok,
          'error': code == WindowsReplayFfi.ok
              ? null
              : ffi.errorFor('server_connection_test', code, 0).toString(),
        };
      });
      return <String, Object?>{
        ...outcome,
        'testedAtUnixSeconds': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'serverUrl': serverUrl,
      };
    } catch (error) {
      return <String, Object?>{
        'success': false,
        'error': error.toString(),
        'testedAtUnixSeconds': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'serverUrl': serverUrl,
      };
    }
  }

  Future<Map<String, Object?>> _persistAndApplySync() async {
    final ffi = _ffi ??= WindowsReplayFfi.open();
    await _persistSettings();
    final handle = _nativeHandle;
    var applied = !_syncEnabled;
    if (handle != null) {
      applied = _applyNativeSync(ffi, handle);
    } else {
      _syncConfigurationError = null;
    }
    return _serverSyncSettingsMap(applied: applied);
  }

  bool _applyNativeSync(WindowsReplayFfi ffi, int handle) {
    final protectedKey = _syncProtectedUploadKey;
    final code = !_syncEnabled && (protectedKey == null || protectedKey.isEmpty)
        ? ffi.configureSyncCode(handle, enabled: false)
        : ffi.configureSyncProtectedCode(
            handle,
            enabled: _syncEnabled,
            serverUrl: _syncServerUrl,
            protectedUploadKey: protectedKey ?? '',
            deviceId: _syncDeviceId,
          );
    if (code == WindowsReplayFfi.ok) {
      _syncConfigurationError = null;
      return true;
    }
    _syncConfigurationError = ffi
        .errorFor('ec_configure_sync_protected', code, handle)
        .toString();
    return false;
  }

  Map<String, Object?> _recordingModeSettingsMap() => <String, Object?>{
    'mode': _recordingMode,
    'trigger': _lockRecordingTrigger,
  };

  Future<Map<String, Object?>> _setRecordingModeSettings(
    Map<String, Object?> args,
  ) async {
    _recordingMode = _sanitizeRecordingMode(args['mode']);
    _lockRecordingTrigger = _sanitizeTrigger(args['trigger']);
    await _persistSettings();
    return <String, Object?>{..._recordingModeSettingsMap(), ..._commandMap()};
  }

  Map<String, Object?> _recordingFolderMap({String? error}) {
    final folder = _recordingFolder;
    final selected = folder != null && Directory(folder).existsSync();
    return <String, Object?>{
      'selected': selected,
      'uri': selected ? folder : null,
      'error': ?error,
    };
  }

  Future<Map<String, Object?>> _chooseRecordingFolder() async {
    final selected = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose EchoClip recording folder',
      lockParentWindow: true,
    );
    if (selected == null) {
      return _recordingFolderMap(error: 'folder_selection_cancelled');
    }
    final directory = Directory(path.normalize(path.absolute(selected)));
    if (!await directory.exists()) {
      return _recordingFolderMap(error: 'folder_not_found');
    }
    _recordingFolder = directory.path;
    await _persistSettings();
    final handle = _nativeHandle;
    if (handle != null) {
      _configureSchedulerRuntime(_ffi ??= WindowsReplayFfi.open(), handle);
    }
    return _recordingFolderMap();
  }

  Future<Map<String, Object?>> _startReplay(Map<String, Object?> args) async {
    if (_running) {
      return _commandMap();
    }
    _captureError = null;
    _recordingMode = _sanitizeRecordingMode(args['mode']);
    _lockRecordingTrigger = _sanitizeTrigger(args['trigger']);
    await _persistSettings();
    if (_recordingFolder == null ||
        !Directory(_recordingFolder!).existsSync()) {
      return _commandMap(error: 'recording_folder_not_selected');
    }

    try {
      final ffi = _ffi ??= WindowsReplayFfi.open();
      final handle = await _ensureNativeHandle();
      _activeSampleRate = _sampleRate;
      _statusReadError = null;
      _nativeStatusFailures = 0;
      _level = 0;
      _peakLevel = 0;
      _configureNativeCapture(ffi, handle);
      _applyNativeSync(ffi, handle);
      _configureSchedulerRuntime(ffi, handle);
      final result = ffi.startCaptureCode(handle);
      if (result != WindowsReplayFfi.ok) {
        throw ffi.errorFor('ec_start_capture', result, handle);
      }
      _running = true;
      _serviceActive = true;
      _sessionStartedUnixMillis = DateTime.now().millisecondsSinceEpoch;
      await _persistSettings();
      _refreshNativeSnapshot();
      return _commandMap();
    } catch (error) {
      _captureError = _captureStartError(error);
      _running = false;
      _serviceActive = false;
      _activeSampleRate = null;
      return _commandMap(error: _captureError);
    }
  }

  Future<Map<String, Object?>> _stopReplay() async {
    final handle = _nativeHandle;
    _running = false;
    _serviceActive = false;
    _activeSampleRate = null;
    _statusReadError = null;
    _nativeStatusFailures = 0;
    if (handle != null) {
      try {
        final ffi = _ffi ??= WindowsReplayFfi.open();
        _persistedAvailableMillis = ffi.availableMillis(handle);
        _availableMillis = _persistedAvailableMillis;
        await _persistSettings();
      } catch (error) {
        _captureError = 'capture_stop_failed:$error';
      }

      final outcome = await Isolate.run(() {
        final ffi = WindowsReplayFfi.open();
        try {
          final result = ffi.stopCaptureCode(handle);
          return result == WindowsReplayFfi.ok
              ? null
              : ffi.errorFor('ec_stop_capture', result, handle).toString();
        } catch (error) {
          return error.toString();
        }
      });
      if (outcome != null) {
        _captureError = 'capture_stop_failed:$outcome';
      }
    }
    _level = 0;
    _peakLevel = 0;
    return _commandMap(error: _captureError);
  }

  Map<String, Object?> _commandMap({String? error}) => <String, Object?>{
    'running': _running,
    'serviceActive': _serviceActive,
    'recordingMode': _recordingMode,
    'lockRecordingTrigger': _lockRecordingTrigger,
    'evidenceState': 'off',
    'evidenceLastStopReason': null,
    'serviceState': _serviceState,
    'error': ?error,
  };

  String get _serviceState {
    if (_captureError != null && !_running) {
      return 'error';
    }
    return _running ? 'standard_recording' : 'stopped';
  }

  Map<String, Object?> _statusMap() {
    _refreshNativeSnapshot();
    return <String, Object?>{
      ..._commandMap(),
      'availableSeconds': _availableMillis ~/ 1000,
      'availableMillis': _availableMillis,
      'sessionStartedUnixMillis': _sessionStartedUnixMillis,
      'captureError': _captureError ?? _statusReadError,
      'backend': 'rust_cpal_wasapi_segmented_pcm16',
      'sampleRate': _activeSampleRate ?? _sampleRate,
      'bufferSeconds': _bufferSeconds,
      'cacheBytes': _cachedCacheBytes,
      'syncConfigured': _syncEnabled,
      'syncStatus': _syncStatus,
      'syncConfigurationError': _syncConfigurationError,
    };
  }

  Map<String, Object?> _meterMap() {
    _refreshNativeSnapshot();
    final age = DateTime.now().difference(_lastLevelAt).inMilliseconds;
    if (!_running || age > 750) {
      _level = 0;
    }
    if (age > 250) {
      _peakLevel *= math.pow(0.92, age / 250).toDouble();
    }
    return <String, Object?>{
      ..._commandMap(),
      'availableMillis': _availableMillis,
      'sessionStartedUnixMillis': _sessionStartedUnixMillis,
      'level': _level.clamp(0.0, 1.0),
      'peakLevel': _peakLevel.clamp(0.0, 1.0),
      'captureError': _captureError ?? _statusReadError,
    };
  }

  int get _cachedCacheBytes => _nativeCacheBytes;

  void _refreshNativeSnapshot() {
    if (_closing) return;
    final handle = _nativeHandle;
    if (handle == null) {
      // No live worker (stopped or fresh launch): report the last persisted
      // cache duration so the save action stays available.
      _availableMillis = _persistedAvailableMillis;
      return;
    }
    try {
      final ffi = _ffi ??= WindowsReplayFfi.open();
      final status = ffi.statusJson(handle);
      _nativeStatusFailures = 0;
      _statusReadError = null;
      _availableMillis = _nativeInt(
        status['available_millis'] ?? status['availableMillis'],
        _availableMillis,
      );
      _nativeCacheBytes = _nativeInt(
        status['temp_bytes'] ?? status['tempBytes'],
        _nativeCacheBytes,
      );
      _activeSampleRate = _nativeInt(
        status['recorder_sample_rate'] ?? status['recorderSampleRate'],
        _activeSampleRate ?? _sampleRate,
      );
      final captureRunning =
          status['capture_running'] ?? status['captureRunning'];
      final wasRunning = _running;
      _running = captureRunning == true;
      _serviceActive = _running;
      if (!wasRunning && _running) {
        _sessionStartedUnixMillis = DateTime.now().millisecondsSinceEpoch;
        unawaited(_persistSettings());
      }
      final nativeSyncEnabled = status['sync_enabled'] ?? status['syncEnabled'];
      if (nativeSyncEnabled is bool && nativeSyncEnabled != _syncEnabled) {
        _syncEnabled = nativeSyncEnabled;
        unawaited(_persistSettings());
      }
      _level = _nativeDouble(
        status['input_level_rms'] ?? status['inputLevelRms'],
        _level,
      ).clamp(0.0, 1.0);
      _peakLevel = _nativeDouble(
        status['input_peak'] ?? status['inputPeak'],
        _peakLevel,
      ).clamp(0.0, 1.0);
      if (_running) {
        _lastLevelAt = DateTime.now();
      }
      final nativeError =
          status['capture_error']?.toString() ??
          status['captureError']?.toString();
      final nativeSync = status['sync'];
      _syncStatus = nativeSync is Map
          ? Map<String, Object?>.from(nativeSync)
          : null;
      if (status['sync_configured'] == true && _syncStatus == null) {
        _syncConfigurationError = 'native_sync_status_unavailable';
      }
      if (nativeError != null && nativeError.isNotEmpty) {
        _captureError = nativeError;
      }
    } catch (error) {
      _nativeStatusFailures += 1;
      if (_nativeStatusFailures >= 3) {
        _statusReadError = 'native_status_failed:$error';
      }
    }
  }

  Future<Map<String, Object?>> _saveReplayClip(int requestedSeconds) async {
    final root = _recordingFolder;
    if (root == null || !Directory(root).existsSync()) {
      return <String, Object?>{
        'saved': false,
        'pending': false,
        'error': 'recording_folder_not_selected',
      };
    }
    final seconds = requestedSeconds.clamp(1, 86400);
    final ffi = _ffi ??= WindowsReplayFfi.open();
    var handle = _nativeHandle;
    var temporaryHandle = false;
    try {
      if (handle == null) {
        handle = ffi.create(
          workDirectory: _runtimeDirectory!.path,
          sampleRate: _sampleRate,
          bufferSeconds: _bufferSeconds,
        );
        temporaryHandle = true;
      }
      final availableMillis = ffi.availableMillis(handle);
      _availableMillis = availableMillis;
      if (availableMillis <= 0) {
        return <String, Object?>{
          'saved': false,
          'pending': false,
          'error': 'buffer_empty',
        };
      }

      final savedMillis = math.min(availableMillis, seconds * 1000);
      final savedSeconds = math.max(1, savedMillis ~/ 1000);
      final ffmpeg = _resolveFfmpeg();
      if (ffmpeg == null) {
        return <String, Object?>{
          'saved': false,
          'pending': false,
          'error': 'ffmpeg_unavailable',
        };
      }
      final now = DateTime.now();
      final baseName = 'echoclip-${_timestamp(now)}-${savedSeconds}s.mp3';
      final output = _uniqueFile(Directory(root), baseName);

      final outcome = await Isolate.run(() {
        try {
          final workerFfi = WindowsReplayFfi.open();
          final code = workerFfi.saveLatestCode(
            handle!,
            seconds,
            output.path,
            format: 1,
            mp3BitrateKbps: 128,
            ffmpegPath: ffmpeg,
          );
          return (
            code: code,
            error: code == WindowsReplayFfi.ok
                ? null
                : workerFfi.lastError(handle),
          );
        } catch (error) {
          return (code: WindowsReplayFfi.coreError, error: error.toString());
        }
      });
      if (outcome.code != WindowsReplayFfi.ok) {
        try {
          if (await output.exists()) {
            await output.delete();
          }
        } catch (_) {}
        return <String, Object?>{
          'saved': false,
          'pending': false,
          'error': outcome.error ?? 'native_save_failed:${outcome.code}',
        };
      }
      return <String, Object?>{
        'saved': true,
        'pending': false,
        'name': path.basename(output.path),
        'uri': output.path,
      };
    } catch (error) {
      return <String, Object?>{
        'saved': false,
        'pending': false,
        'error': 'native_save_failed:$error',
      };
    } finally {
      if (temporaryHandle && handle != null) {
        try {
          ffi.destroy(handle);
        } catch (_) {}
      } else {
        _refreshNativeSnapshot();
      }
    }
  }

  List<Object?> _listGroups() {
    final root = _validRootDirectory();
    if (root == null) {
      return <Object?>[];
    }
    final groups = root
        .listSync(followLinks: false)
        .whereType<Directory>()
        .where((directory) => !path.basename(directory.path).startsWith('.'))
        .map(
          (directory) => <String, Object?>{
            'name': path.basename(directory.path),
            'uri': directory.path,
            'modified': directory.statSync().modified.millisecondsSinceEpoch,
          },
        )
        .toList();
    groups.sort(
      (left, right) => (left['name']! as String).toLowerCase().compareTo(
        (right['name']! as String).toLowerCase(),
      ),
    );
    return groups;
  }

  List<Object?> _listRecordings() {
    final root = _validRootDirectory();
    if (root == null) {
      return <Object?>[];
    }
    final recordings = <Map<String, Object?>>[];
    _appendRecordings(root, root, null, null, recordings);
    for (final entity in root.listSync(followLinks: false)) {
      if (entity is Directory &&
          !path.basename(entity.path).startsWith('.') &&
          _isDirectChild(root.path, entity.path)) {
        _appendRecordings(
          root,
          entity,
          path.basename(entity.path),
          entity.path,
          recordings,
        );
      }
    }
    recordings.sort(
      (left, right) =>
          (right['modified']! as int).compareTo(left['modified']! as int),
    );
    return recordings;
  }

  void _appendRecordings(
    Directory root,
    Directory directory,
    String? groupName,
    String? groupUri,
    List<Map<String, Object?>> output,
  ) {
    for (final entity in directory.listSync(followLinks: false)) {
      if (entity is! File || !_isRecordingFile(entity.path)) {
        continue;
      }
      final stat = entity.statSync();
      output.add(<String, Object?>{
        'name': path.basename(entity.path),
        'uri': entity.path,
        'parentUri': directory.path,
        'groupName': groupName,
        'groupUri': groupUri,
        'size': stat.size,
        'modified': stat.modified.millisecondsSinceEpoch,
      });
    }
  }

  Future<Map<String, Object?>> _createGroup(Map<String, Object?> args) async {
    final root = _validRootDirectory();
    final name = _sanitizeName(args['name'], keepExtension: true);
    if (root == null) {
      return _operationError('recording_folder_not_selected');
    }
    if (name == null) {
      return _operationError('invalid_name');
    }
    final target = Directory(path.join(root.path, name));
    if (await target.exists() || await File(target.path).exists()) {
      return _operationError('name_already_exists');
    }
    await target.create();
    return <String, Object?>{'ok': true, 'name': name, 'uri': target.path};
  }

  Future<Map<String, Object?>> _renameGroup(Map<String, Object?> args) async {
    final root = _validRootDirectory();
    final source = _validGroup(args['uri']);
    final name = _sanitizeName(args['name'], keepExtension: true);
    if (root == null || source == null) {
      return _operationError('invalid_group_uri');
    }
    if (name == null) {
      return _operationError('invalid_name');
    }
    final target = Directory(path.join(root.path, name));
    if (await FileSystemEntity.type(target.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      return _operationError('name_already_exists');
    }
    final renamed = await source.rename(target.path);
    return <String, Object?>{
      'ok': true,
      'name': path.basename(renamed.path),
      'uri': renamed.path,
    };
  }

  Future<Map<String, Object?>> _deleteGroup(Map<String, Object?> args) async {
    final group = _validGroup(args['uri']);
    if (group == null) {
      return _operationError('invalid_group_uri');
    }
    await group.delete(recursive: true);
    return <String, Object?>{'ok': true};
  }

  Future<Map<String, Object?>> _renameRecording(
    Map<String, Object?> args,
  ) async {
    final source = _validRecording(args['uri']);
    final cleanName = _sanitizeName(args['name'], keepExtension: true);
    if (source == null) {
      return _operationError('invalid_recording_uri');
    }
    if (cleanName == null) {
      return _operationError('invalid_name');
    }
    final extension = path.extension(cleanName).isEmpty
        ? path.extension(source.path)
        : '';
    final finalName = '$cleanName$extension';
    if (!_recordingExtensions.contains(
      path.extension(finalName).toLowerCase(),
    )) {
      return _operationError('unsupported_recording_extension');
    }
    final target = File(path.join(path.dirname(source.path), finalName));
    if (await target.exists()) {
      return _operationError('name_already_exists');
    }
    final renamed = await source.rename(target.path);
    return <String, Object?>{
      'ok': true,
      'name': path.basename(renamed.path),
      'uri': renamed.path,
    };
  }

  Future<Map<String, Object?>> _deleteRecording(
    Map<String, Object?> args,
  ) async {
    final source = _validRecording(args['uri']);
    if (source == null) {
      return _operationError('invalid_recording_uri');
    }
    if (_playbackUri != null && _samePath(_playbackUri!, source.path)) {
      await _player.stop();
      _playbackUri = null;
    }
    await source.delete();
    return <String, Object?>{'ok': true};
  }

  Future<Map<String, Object?>> _moveRecording(Map<String, Object?> args) async {
    final root = _validRootDirectory();
    final source = _validRecording(args['uri']);
    if (root == null || source == null) {
      return _operationError('invalid_recording_uri');
    }
    final requestedGroup = args['groupUri'];
    final targetDirectory = requestedGroup == null
        ? root
        : _validGroup(requestedGroup);
    if (targetDirectory == null) {
      return _operationError('invalid_group_uri');
    }
    final target = _uniqueFile(targetDirectory, path.basename(source.path));
    final moved = await source.rename(target.path);
    return <String, Object?>{'ok': true, 'uri': moved.path};
  }

  Future<Map<String, Object?>> _playRecording(Map<String, Object?> args) async {
    final recording = _validRecording(args['uri']);
    if (recording == null) {
      return <String, Object?>{
        ..._playbackMap(),
        'error': 'invalid_recording_uri',
      };
    }
    _playbackUri = recording.path;
    _playbackPositionMs = 0;
    _playbackDurationMs = 0;
    _playbackSpeed = _sanitizeSpeed(args['speed']);
    await _player.stop();
    await _player.play(DeviceFileSource(recording.path));
    await _player.setPlaybackRate(_playbackSpeed);
    _playerState = PlayerState.playing;
    final duration = await _player.getDuration();
    final position = await _player.getCurrentPosition();
    _playbackDurationMs = duration?.inMilliseconds ?? _playbackDurationMs;
    _playbackPositionMs = position?.inMilliseconds ?? 0;
    return _playbackMap();
  }

  Future<Map<String, Object?>> _pausePreview() async {
    await _player.pause();
    _playerState = PlayerState.paused;
    return _refreshPlaybackMap();
  }

  Future<Map<String, Object?>> _resumePreview() async {
    if (_playbackUri != null) {
      await _player.resume();
      await _player.setPlaybackRate(_playbackSpeed);
      _playerState = PlayerState.playing;
    }
    return _refreshPlaybackMap();
  }

  Future<Map<String, Object?>> _stopPreview() async {
    await _player.stop();
    _playerState = PlayerState.stopped;
    _playbackPositionMs = 0;
    return _playbackMap();
  }

  Future<Map<String, Object?>> _seekPreview(Map<String, Object?> args) async {
    final requested = _asInt(args['positionMs'], _playbackPositionMs);
    final position = requested
        .clamp(0, math.max(0, _playbackDurationMs))
        .toInt();
    await _player.seek(Duration(milliseconds: position));
    _playbackPositionMs = position;
    return _refreshPlaybackMap();
  }

  Future<Map<String, Object?>> _setPlaybackSpeed(
    Map<String, Object?> args,
  ) async {
    _playbackSpeed = _sanitizeSpeed(args['speed']);
    if (_playerState == PlayerState.playing ||
        _playerState == PlayerState.paused) {
      await _player.setPlaybackRate(_playbackSpeed);
    }
    return _refreshPlaybackMap();
  }

  Future<Map<String, Object?>> _refreshPlaybackMap() async {
    final duration = await _player.getDuration();
    final position = await _player.getCurrentPosition();
    _playbackDurationMs = duration?.inMilliseconds ?? _playbackDurationMs;
    _playbackPositionMs = position?.inMilliseconds ?? _playbackPositionMs;
    return _playbackMap();
  }

  Map<String, Object?> _playbackMap() => <String, Object?>{
    'playing': _playerState == PlayerState.playing,
    'paused': _playerState == PlayerState.paused,
    'uri': _playbackUri,
    'positionMs': _playbackPositionMs,
    'durationMs': _playbackDurationMs,
    'speed': _playbackSpeed,
  };

  Map<String, Object?> _schedulerSnapshotMap(WindowsReplayFfi ffi, int handle) {
    return <String, Object?>{
      ...ffi.schedulerSnapshotJson(handle),
      'schedulingPrecision': 'exact',
      'exactAlarmPermission': true,
      'recordingDestinationReady': _validRootDirectory() != null,
      'ffmpegAvailable': _resolveFfmpeg() != null,
      'uploadConfigured':
          _isValidSyncHost(_syncServerHost) &&
          _syncProtectedUploadKey?.isNotEmpty == true,
      'processResident': true,
    };
  }

  Future<Map<String, Object?>> _scheduleSnapshot() async {
    final ffi = _ffi ??= WindowsReplayFfi.open();
    final handle = await _ensureNativeHandle();
    _configureSchedulerRuntime(ffi, handle);
    return <String, Object?>{..._schedulerSnapshotMap(ffi, handle), 'ok': true};
  }

  Future<Map<String, Object?>> _upsertScheduledTask(
    Map<String, Object?> args,
  ) async {
    final task = args['task'];
    if (task is! Map) {
      return _operationError('invalid_scheduled_task');
    }
    final ffi = _ffi ??= WindowsReplayFfi.open();
    final handle = await _ensureNativeHandle();
    _configureSchedulerRuntime(ffi, handle);
    final code = ffi.schedulerUpsertCode(
      handle,
      Map<String, Object?>.from(task),
    );
    if (code != WindowsReplayFfi.ok) {
      return _operationError(
        ffi.errorFor('ec_scheduler_upsert', code, handle).toString(),
      );
    }
    return <String, Object?>{..._schedulerSnapshotMap(ffi, handle), 'ok': true};
  }

  Future<Map<String, Object?>> _deleteScheduledTask(
    Map<String, Object?> args,
  ) async {
    final taskId = args['taskId']?.toString().trim() ?? '';
    if (taskId.isEmpty) {
      return _operationError('scheduled_task_id_required');
    }
    final ffi = _ffi ??= WindowsReplayFfi.open();
    final handle = await _ensureNativeHandle();
    final code = ffi.schedulerDeleteCode(handle, taskId);
    if (code != WindowsReplayFfi.ok) {
      return _operationError(
        ffi.errorFor('ec_scheduler_delete', code, handle).toString(),
      );
    }
    return <String, Object?>{..._schedulerSnapshotMap(ffi, handle), 'ok': true};
  }

  Future<Map<String, Object?>> _setScheduledTaskEnabled(
    Map<String, Object?> args,
  ) async {
    final taskId = args['taskId']?.toString().trim() ?? '';
    if (taskId.isEmpty) {
      return _operationError('scheduled_task_id_required');
    }
    final ffi = _ffi ??= WindowsReplayFfi.open();
    final handle = await _ensureNativeHandle();
    final code = ffi.schedulerSetEnabledCode(
      handle,
      taskId,
      _asInt(args['expectedRevision'], 0),
      args['enabled'] == true,
    );
    if (code != WindowsReplayFfi.ok) {
      return _operationError(
        ffi.errorFor('ec_scheduler_set_enabled', code, handle).toString(),
      );
    }
    return <String, Object?>{..._schedulerSnapshotMap(ffi, handle), 'ok': true};
  }

  Future<Map<String, Object?>> _convertWavToMp3(
    Map<String, Object?> args,
  ) async {
    final source = _validRecording(args['uri']);
    if (source == null || path.extension(source.path).toLowerCase() != '.wav') {
      return _operationError('wav_source_required');
    }
    final ffmpeg = _resolveFfmpeg();
    if (ffmpeg == null) {
      return _operationError('ffmpeg_unavailable');
    }
    final bitrate = _sanitizeBitrate(args['mp3BitrateKbps']);
    final output = _uniqueFile(
      Directory(path.dirname(source.path)),
      '${path.basenameWithoutExtension(source.path)}.mp3',
    );
    final outcome = await Isolate.run(() {
      final ffi = WindowsReplayFfi.open();
      final code = ffi.transcodeWavToMp3Code(
        inputPath: source.path,
        outputPath: output.path,
        ffmpegPath: ffmpeg,
        bitrateKbps: bitrate,
      );
      return (
        code: code,
        error: code == WindowsReplayFfi.ok ? null : ffi.lastError(0),
      );
    });
    if (outcome.code != WindowsReplayFfi.ok) {
      if (await output.exists()) {
        await output.delete();
      }
      return _operationError(outcome.error ?? 'wav_to_mp3_failed');
    }
    return <String, Object?>{
      'ok': true,
      'name': path.basename(output.path),
      'uri': output.path,
      'size': await output.length(),
    };
  }

  String? _resolveFfmpeg() {
    final executableDirectory = path.dirname(Platform.resolvedExecutable);
    final candidates = <String>[
      path.join(executableDirectory, 'ffmpeg.exe'),
      path.join(executableDirectory, 'tools', 'ffmpeg.exe'),
      path.join(
        executableDirectory,
        'data',
        'flutter_assets',
        'bin',
        'ffmpeg.exe',
      ),
      path.join(Directory.current.path, 'ffmpeg.exe'),
    ];
    final pathVariable = Platform.environment['PATH'];
    if (pathVariable != null) {
      for (final directory in pathVariable.split(';')) {
        if (directory.trim().isNotEmpty) {
          candidates.add(path.join(directory.trim(), 'ffmpeg.exe'));
        }
      }
    }
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    return null;
  }

  Future<Map<String, Object?>> _clearCache() async {
    var deletedBytes = _directorySize(_runtimeDirectory);

    final ffi = _ffi ??= WindowsReplayFfi.open();
    var handle = _nativeHandle;
    final wasRunning = _running;
    var temporaryHandle = false;
    try {
      if (handle == null) {
        handle = ffi.create(
          workDirectory: _runtimeDirectory!.path,
          sampleRate: _sampleRate,
          bufferSeconds: _bufferSeconds,
        );
        temporaryHandle = true;
      }
      final clearResult = ffi.clearCode(handle);
      if (clearResult != WindowsReplayFfi.ok) {
        throw ffi.errorFor('ec_clear', clearResult, handle);
      }
      _availableMillis = 0;
      _persistedAvailableMillis = 0;
      _nativeCacheBytes = 0;
      _sessionStartedUnixMillis = wasRunning
          ? DateTime.now().millisecondsSinceEpoch
          : 0;
      await _persistSettings();
      if (wasRunning) {
        _configureNativeCapture(ffi, handle);
        final restartResult = ffi.startCaptureCode(handle);
        if (restartResult != WindowsReplayFfi.ok) {
          throw ffi.errorFor('ec_start_capture', restartResult, handle);
        }
        _running = true;
        _serviceActive = true;
        _refreshNativeSnapshot();
      }
    } catch (error) {
      _captureError = wasRunning ? _captureStartError(error) : _captureError;
      if (wasRunning) {
        _running = false;
        _serviceActive = false;
      }
      return <String, Object?>{
        'ok': false,
        'error': 'native_clear_failed:$error',
        'deletedBytes': deletedBytes,
        'cacheBytes': _cachedCacheBytes,
        'activeReplayCachePreserved': false,
      };
    } finally {
      if (temporaryHandle && handle != null) {
        try {
          ffi.destroy(handle);
        } catch (_) {}
      }
    }
    return <String, Object?>{
      'ok': true,
      'deletedBytes': deletedBytes,
      'cacheBytes': _cachedCacheBytes,
      'activeReplayCachePreserved': false,
    };
  }

  Map<String, Object?> _cacheStatus() {
    if (_nativeHandle != null) {
      _refreshNativeSnapshot();
    } else {
      // This is an explicit, low-frequency settings query. Replay/meter status
      // uses cached counters and never recursively scans the cache directory.
      _nativeCacheBytes = _directorySize(_runtimeDirectory);
    }
    return <String, Object?>{
      'ok': true,
      'cacheBytes': _cachedCacheBytes,
      'activeReplayCachePreserved': false,
    };
  }

  void _configureNativeCapture(WindowsReplayFfi ffi, int handle) {
    final result = ffi.configureCaptureCode(
      handle,
      microphoneEnabled: _microphoneEnabled,
      systemAudioEnabled: _systemAudioEnabled,
      microphoneDeviceId: _microphoneDeviceId,
    );
    if (result != WindowsReplayFfi.ok) {
      throw ffi.errorFor('ec_configure_capture', result, handle);
    }
  }

  Future<Map<String, Object?>> _openUrl(Map<String, Object?> args) async {
    final raw = args['url']?.toString();
    final uri = raw == null ? null : Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme) {
      return _operationError('invalid_url');
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    return opened
        ? <String, Object?>{'ok': true}
        : _operationError('open_url_failed');
  }

  Directory? _validRootDirectory() {
    final root = _recordingFolder;
    if (root == null) {
      return null;
    }
    final directory = Directory(root);
    return directory.existsSync() ? directory : null;
  }

  Directory? _validGroup(Object? uri) {
    final root = _validRootDirectory();
    final raw = uri?.toString();
    if (root == null || raw == null) {
      return null;
    }
    final candidate = Directory(path.normalize(path.absolute(raw)));
    if (!candidate.existsSync() || !_isDirectChild(root.path, candidate.path)) {
      return null;
    }
    return candidate;
  }

  File? _validRecording(Object? uri) {
    final root = _validRootDirectory();
    final raw = uri?.toString();
    if (root == null || raw == null) {
      return null;
    }
    final candidate = File(path.normalize(path.absolute(raw)));
    if (!candidate.existsSync() ||
        !_isWithinOrDirectGroup(root.path, candidate.path) ||
        !_isRecordingFile(candidate.path)) {
      return null;
    }
    return candidate;
  }

  bool _isWithinOrDirectGroup(String root, String candidate) {
    final parent = path.dirname(candidate);
    return _samePath(root, parent) || _isDirectChild(root, parent);
  }

  bool _isDirectChild(String parent, String candidate) {
    final normalizedParent = path.normalize(path.absolute(parent));
    final normalizedCandidate = path.normalize(path.absolute(candidate));
    return _samePath(path.dirname(normalizedCandidate), normalizedParent);
  }

  bool _samePath(String left, String right) {
    return path.normalize(path.absolute(left)).toLowerCase() ==
        path.normalize(path.absolute(right)).toLowerCase();
  }

  bool _isRecordingFile(String filePath) {
    return _recordingExtensions.contains(
      path.extension(filePath).toLowerCase(),
    );
  }

  String? _sanitizeName(Object? value, {required bool keepExtension}) {
    var result = value?.toString().trim();
    if (result == null || result.isEmpty) {
      return null;
    }
    result = result.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_');
    result = result.replaceFirst(RegExp(r'[. ]+$'), '');
    if (!keepExtension) {
      result = path.basenameWithoutExtension(result);
    }
    if (result.length > 80) {
      result = result.substring(0, 80).replaceFirst(RegExp(r'[. ]+$'), '');
    }
    final stem = path.basenameWithoutExtension(result).toUpperCase();
    if (result.isEmpty ||
        result == '.' ||
        result == '..' ||
        RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$').hasMatch(stem)) {
      return null;
    }
    return result;
  }

  File _uniqueFile(Directory parent, String preferredName) {
    final extension = path.extension(preferredName);
    final stem = path.basenameWithoutExtension(preferredName);
    var candidate = File(path.join(parent.path, preferredName));
    var suffix = 2;
    while (candidate.existsSync() || Directory(candidate.path).existsSync()) {
      candidate = File(path.join(parent.path, '$stem ($suffix)$extension'));
      suffix++;
    }
    return candidate;
  }

  String _timestamp(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}${two(value.month)}${two(value.day)}-'
        '${two(value.hour)}${two(value.minute)}${two(value.second)}';
  }

  int _directorySize(Directory? directory) {
    if (directory == null || !directory.existsSync()) {
      return 0;
    }
    var total = 0;
    for (final entity in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) {
        try {
          total += entity.lengthSync();
        } catch (_) {}
      }
    }
    return total;
  }

  Map<String, Object?> _failureFor(String method, Object error) {
    final message = 'windows_backend_exception:$error';
    if (method == 'saveReplayClip') {
      return <String, Object?>{
        'saved': false,
        'pending': false,
        'error': message,
      };
    }
    if (method == 'getRecordingFolder' || method == 'chooseRecordingFolder') {
      return <String, Object?>{'selected': false, 'error': message};
    }
    if (method.contains('Replay') || method == 'getReplayStatus') {
      return <String, Object?>{
        ..._commandMap(error: message),
        'availableMillis': _availableMillis,
      };
    }
    return _operationError(message);
  }

  Map<String, Object?> _operationError(String error) => <String, Object?>{
    'ok': false,
    'error': error,
  };

  String _captureStartError(Object error) {
    final message = error.toString();
    final normalized = message.toLowerCase();
    if (normalized.contains('permission') ||
        normalized.contains('access is denied') ||
        normalized.contains('access denied') ||
        normalized.contains('0x80070005')) {
      return 'microphone_permission_denied';
    }
    return 'capture_start_failed:$message';
  }

  int _nativeInt(Object? value, int fallback) {
    return value is num ? value.toInt() : fallback;
  }

  double _nativeDouble(Object? value, double fallback) {
    return value is num ? value.toDouble() : fallback;
  }

  int _sanitizeSampleRate(Object? value) {
    final rate = _asInt(value, 16000);
    return _sampleRates.contains(rate) ? rate : 16000;
  }

  int _sanitizeBufferSeconds(Object? value) {
    return _asInt(value, 1800).clamp(60, 24 * 60 * 60);
  }

  int _sanitizeUploadPort(Object? value) {
    final port = _asInt(value, 32581);
    return port >= 1 && port <= 65535 ? port : 32581;
  }

  bool _isValidSyncHost(String value) {
    final host = value.trim();
    return host.isNotEmpty &&
        !host.contains('://') &&
        !host.contains(RegExp(r'\s')) &&
        !host.contains('/') &&
        !host.contains('?') &&
        !host.contains('#');
  }

  String _sanitizeLanguage(Object? value) {
    final mode = value?.toString();
    return const {'system', 'en', 'zh'}.contains(mode) ? mode! : 'system';
  }

  String _sanitizeRecordingMode(Object? value) {
    return value?.toString() == 'lockscreen' ? 'lockscreen' : 'standard';
  }

  String _sanitizeTrigger(Object? value) {
    return value?.toString() == 'keyguard_locked'
        ? 'keyguard_locked'
        : 'screen_off';
  }

  double _sanitizeSpeed(Object? value) {
    return _asDouble(value, 1).clamp(0.5, 2.0);
  }

  int _sanitizeBitrate(Object? value) {
    final bitrate = _asInt(value, 128);
    const choices = <int>{32, 48, 64, 96, 128, 160, 192, 256, 320};
    return choices.contains(bitrate) ? bitrate : 128;
  }

  int _asInt(Object? value, int fallback) {
    return value is num ? value.toInt() : int.tryParse('$value') ?? fallback;
  }

  double _asDouble(Object? value, double fallback) {
    return value is num
        ? value.toDouble()
        : double.tryParse('$value') ?? fallback;
  }
}

String _newDeviceId() {
  final random = math.Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
}
