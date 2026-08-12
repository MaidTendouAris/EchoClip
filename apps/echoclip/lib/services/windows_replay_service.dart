import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';

import 'windows_replay_ffi.dart';

/// Native Windows implementation behind [ReplayServiceClient].
///
/// Microphone capture, WASAPI system-audio loopback, mixing, and the rolling
/// one-minute segments live entirely in the Rust DLL. Dart only issues
/// lifecycle/export commands and serves the desktop settings, library,
/// playback, and processing UI.
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
  Future<void> _operationTail = Future<void>.value();
  Directory? _runtimeDirectory;
  Directory? _processingDirectory;
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

  bool _running = false;
  bool _serviceActive = false;
  int _sessionStartedUnixMillis = 0;
  int _availableMillis = 0;
  int _persistedAvailableMillis = 0;
  int _nativeCacheBytes = 0;
  int _processingCacheBytes = 0;
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

  Future<Object?> invoke(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    await _ensureInitialized();
    final args = arguments ?? const <String, Object?>{};
    try {
      return switch (method) {
        'getUiLanguageMode' => <String, Object?>{'mode': _uiLanguageMode},
        'setUiLanguageMode' => _setUiLanguageMode(args['mode']),
        'getAudioSettings' => _audioSettingsMap(),
        'setAudioSettings' => _setAudioSettings(args),
        'listAudioInputDevices' => _listAudioInputDevices(),
        'getAudioSourceSettings' => _audioSourceSettingsMap(),
        'setAudioSourceSettings' => _setAudioSourceSettings(args),
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
        'processRecording' => _processRecording(args),
        'clearCache' => _runExclusive(_clearCache),
        'getCacheStatus' => _cacheStatus(),
        'openUrl' => _openUrl(args),
        _ => <String, Object?>{
          'ok': false,
          'error': 'unsupported_windows_method:$method',
        },
      };
    } catch (error) {
      if (method == 'listGroups' || method == 'listRecordings') {
        return <Object?>[];
      }
      return _failureFor(method, error);
    }
  }

  Future<void> dispose() async {
    await _runExclusive(() async {
      await _stopReplay();
    });
    await _playerStateSubscription.cancel();
    await _positionSubscription.cancel();
    await _durationSubscription.cancel();
    await _completeSubscription.cancel();
    await _player.dispose();
  }

  Future<T> _runExclusive<T>(Future<T> Function() action) {
    final previous = _operationTail;
    final release = Completer<void>();
    _operationTail = release.future;
    return previous.then((_) => action()).whenComplete(release.complete);
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
    final processing = Directory(path.join(support.path, 'processing-cache'));
    await support.create(recursive: true);
    await runtime.create(recursive: true);
    await processing.create(recursive: true);
    _runtimeDirectory = runtime;
    _processingDirectory = processing;
    _nativeCacheBytes = _directorySize(runtime);
    _processingCacheBytes = _directorySize(processing);
    _settingsFile = File(path.join(support.path, 'settings.json'));

    final settingsFile = _settingsFile!;
    if (!await settingsFile.exists()) {
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
      final storedFolder = decoded['recordingFolder']?.toString();
      if (storedFolder != null && Directory(storedFolder).existsSync()) {
        _recordingFolder = path.normalize(path.absolute(storedFolder));
      }
      final persistedMillis = _asInt(decoded['lastAvailableMillis'], 0);
      _persistedAvailableMillis = persistedMillis > 0 ? persistedMillis : 0;
      _availableMillis = _persistedAvailableMillis;
    } catch (_) {
      // A malformed settings file should never prevent the recorder starting.
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
    _sampleRate = nextRate;
    _bufferSeconds = nextBuffer;
    await _persistSettings();
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
    return _audioSourceSettingsMap(applied: applied);
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
      final staleHandle = _nativeHandle;
      _nativeHandle = null;
      if (staleHandle != null) {
        // A capture device failure can leave a stopped worker behind. Dispose
        // it before creating another worker for the same segmented cache.
        try {
          ffi.stopCaptureCode(staleHandle);
        } catch (_) {}
        try {
          ffi.destroy(staleHandle);
        } catch (_) {}
      }
      final handle = ffi.create(
        workDirectory: _runtimeDirectory!.path,
        sampleRate: _sampleRate,
        bufferSeconds: _bufferSeconds,
      );
      _nativeHandle = handle;
      _activeSampleRate = _sampleRate;
      _statusReadError = null;
      _nativeStatusFailures = 0;
      _level = 0;
      _peakLevel = 0;
      _configureNativeCapture(ffi, handle);
      final result = ffi.startCaptureCode(handle);
      if (result != WindowsReplayFfi.ok) {
        throw ffi.errorFor('ec_start_capture', result, handle);
      }
      _running = true;
      _serviceActive = true;
      _sessionStartedUnixMillis = DateTime.now().millisecondsSinceEpoch;
      _refreshNativeSnapshot();
      return _commandMap();
    } catch (error) {
      _captureError = _captureStartError(error);
      _running = false;
      _serviceActive = false;
      final handle = _nativeHandle;
      _nativeHandle = null;
      _activeSampleRate = null;
      if (handle != null) {
        try {
          _ffi?.destroy(handle);
        } catch (_) {}
      }
      return _commandMap(error: _captureError);
    }
  }

  Future<Map<String, Object?>> _stopReplay() async {
    final handle = _nativeHandle;
    _nativeHandle = null;
    _running = false;
    _serviceActive = false;
    _activeSampleRate = null;
    _statusReadError = null;
    _nativeStatusFailures = 0;
    if (handle != null) {
      try {
        final ffi = _ffi ??= WindowsReplayFfi.open();
        // Remember how much replayable audio remains on disk so the save
        // action stays available after the worker is destroyed.
        _persistedAvailableMillis = ffi.availableMillis(handle);
        _availableMillis = _persistedAvailableMillis;
        await _persistSettings();
        final result = ffi.stopCaptureCode(handle);
        if (result != WindowsReplayFfi.ok) {
          throw ffi.errorFor('ec_stop_capture', result, handle);
        }
      } catch (error) {
        _captureError = 'capture_stop_failed:$error';
      } finally {
        try {
          _ffi?.destroy(handle);
        } catch (error) {
          _captureError ??= 'capture_destroy_failed:$error';
        }
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
      'sessionStartedUnixMillis': _running ? _sessionStartedUnixMillis : 0,
      'captureError': _captureError ?? _statusReadError,
      'backend': 'rust_cpal_wasapi_segmented_pcm16',
      'sampleRate': _activeSampleRate ?? _sampleRate,
      'bufferSeconds': _bufferSeconds,
      'cacheBytes': _cachedCacheBytes,
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
      'sessionStartedUnixMillis': _running ? _sessionStartedUnixMillis : 0,
      'level': _level.clamp(0.0, 1.0),
      'peakLevel': _peakLevel.clamp(0.0, 1.0),
      'captureError': _captureError ?? _statusReadError,
    };
  }

  int get _cachedCacheBytes => _nativeCacheBytes + _processingCacheBytes;

  void _refreshNativeSnapshot() {
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
      _running = captureRunning == true;
      _serviceActive = _running;
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

  Future<Map<String, Object?>> _processRecording(
    Map<String, Object?> args,
  ) async {
    final source = _validRecording(args['uri']);
    if (source == null) {
      return _operationError('invalid_recording_uri');
    }
    final format = args['format']?.toString().toLowerCase() == 'wav'
        ? 'wav'
        : 'mp3';
    final gainDb = _asDouble(args['gainDb'], 0).clamp(-24.0, 24.0);
    final bitrate = _sanitizeBitrate(args['mp3BitrateKbps']);
    final requestedParent = args['parentUri'];
    final parent = requestedParent == null
        ? Directory(path.dirname(source.path))
        : _validRecordingParent(requestedParent);
    if (parent == null) {
      return _operationError('invalid_parent_uri');
    }
    final gainLabel = gainDb >= 0
        ? '+${gainDb.toStringAsFixed(1)}dB'
        : '${gainDb.toStringAsFixed(1)}dB';
    final sourceBase = path.basenameWithoutExtension(source.path);
    final output = _uniqueFile(parent, '$sourceBase-$gainLabel.$format');

    try {
      if (format == 'wav' &&
          path.extension(source.path).toLowerCase() == '.wav') {
        final processed = await _applyGainToPcm16Wav(source, output, gainDb);
        if (processed) {
          return <String, Object?>{
            'ok': true,
            'name': path.basename(output.path),
            'uri': output.path,
            'size': await output.length(),
          };
        }
      }

      final ffmpeg = _resolveFfmpeg();
      if (ffmpeg == null) {
        return _operationError('ffmpeg_unavailable');
      }
      final command = <String>[
        '-y',
        '-hide_banner',
        '-nostdin',
        '-i',
        source.path,
        '-af',
        'volume=${gainDb}dB',
        '-vn',
        if (format == 'wav') ...<String>['-c:a', 'pcm_s16le'] else ...<String>[
          '-c:a',
          'libmp3lame',
          '-b:a',
          '${bitrate}k',
        ],
        output.path,
      ];
      final process = await Process.start(
        ffmpeg,
        command,
        runInShell: false,
        mode: ProcessStartMode.normal,
      );
      final stdoutFuture = process.stdout.transform(utf8.decoder).join();
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      int exitCode;
      try {
        exitCode = await process.exitCode.timeout(const Duration(minutes: 2));
      } on TimeoutException {
        process.kill();
        await stdoutFuture;
        await stderrFuture;
        return _operationError('ffmpeg_timeout');
      }
      final outputText = '${await stdoutFuture}\n${await stderrFuture}';
      if (exitCode != 0 ||
          !await output.exists() ||
          await output.length() == 0) {
        if (await output.exists()) {
          await output.delete();
        }
        final tail = outputText.length <= 240
            ? outputText
            : outputText.substring(outputText.length - 240);
        return _operationError('ffmpeg_failed:$exitCode:$tail');
      }
      return <String, Object?>{
        'ok': true,
        'name': path.basename(output.path),
        'uri': output.path,
        'size': await output.length(),
      };
    } catch (error) {
      try {
        if (await output.exists()) {
          await output.delete();
        }
      } catch (_) {}
      return _operationError('process_failed:$error');
    }
  }

  Future<bool> _applyGainToPcm16Wav(
    File source,
    File output,
    double gainDb,
  ) async {
    final input = await source.open();
    RandomAccessFile? destination;
    try {
      final length = await input.length();
      if (length < 44) {
        return false;
      }
      final riff = await input.read(12);
      if (ascii.decode(riff.sublist(0, 4), allowInvalid: true) != 'RIFF' ||
          ascii.decode(riff.sublist(8, 12), allowInvalid: true) != 'WAVE') {
        return false;
      }
      var offset = 12;
      var pcm16 = false;
      var dataOffset = -1;
      var dataLength = 0;
      while (offset + 8 <= length) {
        await input.setPosition(offset);
        final header = await input.read(8);
        if (header.length < 8) {
          break;
        }
        final id = ascii.decode(header.sublist(0, 4), allowInvalid: true);
        final chunkLength = ByteData.sublistView(
          Uint8List.fromList(header),
        ).getUint32(4, Endian.little);
        if (id == 'fmt ' && chunkLength >= 16) {
          final formatData = await input.read(math.min(chunkLength, 40));
          if (formatData.length >= 16) {
            final view = ByteData.sublistView(Uint8List.fromList(formatData));
            pcm16 =
                view.getUint16(0, Endian.little) == 1 &&
                view.getUint16(14, Endian.little) == 16;
          }
        } else if (id == 'data') {
          dataOffset = offset + 8;
          dataLength = math.min(chunkLength, length - dataOffset);
          break;
        }
        offset += 8 + chunkLength + (chunkLength.isOdd ? 1 : 0);
      }
      if (!pcm16 || dataOffset < 0 || dataLength <= 0) {
        return false;
      }

      destination = await output.open(mode: FileMode.writeOnly);
      await input.setPosition(0);
      var copied = 0;
      final gain = math.pow(10, gainDb / 20).toDouble();
      while (copied < length) {
        final count = math.min(256 * 1024, length - copied);
        final block = Uint8List.fromList(await input.read(count));
        if (block.isEmpty) {
          break;
        }
        final blockStart = copied;
        final blockEnd = copied + block.length;
        final processStart = math.max(blockStart, dataOffset);
        final processEnd = math.min(blockEnd, dataOffset + dataLength);
        if (processEnd > processStart) {
          var localStart = processStart - blockStart;
          final localEnd = processEnd - blockStart;
          if (localStart.isOdd) {
            localStart++;
          }
          final data = ByteData.sublistView(block);
          for (var index = localStart; index + 1 < localEnd; index += 2) {
            final sample = data.getInt16(index, Endian.little);
            final adjusted = (sample * gain).round().clamp(-32768, 32767);
            data.setInt16(index, adjusted, Endian.little);
          }
        }
        await destination.writeFrom(block);
        copied += block.length;
      }
      await destination.flush();
      return copied == length;
    } finally {
      await input.close();
      await destination?.close();
    }
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
    final processing = _processingDirectory!;
    await for (final entity in processing.list(followLinks: false)) {
      deletedBytes += _entitySize(entity);
      await entity.delete(recursive: true);
    }
    _processingCacheBytes = 0;

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
    _processingCacheBytes = _directorySize(_processingDirectory);
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

  Directory? _validRecordingParent(Object? uri) {
    final root = _validRootDirectory();
    final raw = uri?.toString();
    if (root == null || raw == null) {
      return null;
    }
    final candidate = Directory(path.normalize(path.absolute(raw)));
    if (!candidate.existsSync()) {
      return null;
    }
    if (_samePath(candidate.path, root.path) ||
        _isDirectChild(root.path, candidate.path)) {
      return candidate;
    }
    return null;
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

  int _entitySize(FileSystemEntity entity) {
    if (entity is File) {
      try {
        return entity.lengthSync();
      } catch (_) {
        return 0;
      }
    }
    return entity is Directory ? _directorySize(entity) : 0;
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
