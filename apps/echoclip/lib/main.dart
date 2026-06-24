import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n/app_localizations.dart';

void main() {
  runApp(const EchoClipApp());
}

enum UiLanguageMode {
  system,
  english,
  chinese;

  String get storageValue {
    return switch (this) {
      UiLanguageMode.system => 'system',
      UiLanguageMode.english => 'en',
      UiLanguageMode.chinese => 'zh',
    };
  }

  Locale? get locale {
    return switch (this) {
      UiLanguageMode.system => null,
      UiLanguageMode.english => const Locale('en'),
      UiLanguageMode.chinese => const Locale('zh'),
    };
  }

  static UiLanguageMode fromStorageValue(String? value) {
    return switch (value) {
      'en' => UiLanguageMode.english,
      'zh' => UiLanguageMode.chinese,
      _ => UiLanguageMode.system,
    };
  }
}

enum RecordingMode {
  standard,
  lockscreen;

  String get storageValue {
    return switch (this) {
      RecordingMode.standard => 'standard',
      RecordingMode.lockscreen => 'lockscreen',
    };
  }

  static RecordingMode fromStorageValue(String? value) {
    return switch (value) {
      'lockscreen' => RecordingMode.lockscreen,
      _ => RecordingMode.standard,
    };
  }
}

enum LockRecordingTrigger {
  screenOff,
  keyguardLocked;

  String get storageValue {
    return switch (this) {
      LockRecordingTrigger.screenOff => 'screen_off',
      LockRecordingTrigger.keyguardLocked => 'keyguard_locked',
    };
  }

  static LockRecordingTrigger fromStorageValue(String? value) {
    return switch (value) {
      'keyguard_locked' => LockRecordingTrigger.keyguardLocked,
      _ => LockRecordingTrigger.screenOff,
    };
  }
}

class EchoClipApp extends StatefulWidget {
  const EchoClipApp({super.key});

  @override
  State<EchoClipApp> createState() => _EchoClipAppState();
}

class _EchoClipAppState extends State<EchoClipApp> {
  static const MethodChannel _replayChannel = MethodChannel(
    'com.echoclip/replay_service',
  );

  UiLanguageMode _languageMode = UiLanguageMode.system;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLanguageMode());
  }

  Future<void> _loadLanguageMode() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    final response = await _replayChannel.invokeMapMethod<String, Object?>(
      'getUiLanguageMode',
    );
    if (!mounted || response == null) {
      return;
    }
    setState(() {
      _languageMode = UiLanguageMode.fromStorageValue(
        response['mode']?.toString(),
      );
    });
  }

  Future<void> _setLanguageMode(UiLanguageMode mode) async {
    setState(() {
      _languageMode = mode;
    });
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    final response = await _replayChannel.invokeMapMethod<String, Object?>(
      'setUiLanguageMode',
      {'mode': mode.storageValue},
    );
    if (!mounted || response == null) {
      return;
    }
    final applied = UiLanguageMode.fromStorageValue(
      response['mode']?.toString(),
    );
    if (applied != _languageMode) {
      setState(() {
        _languageMode = applied;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      locale: _languageMode.locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B7F79),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F8F7),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF6F8F7),
          foregroundColor: Color(0xFF151B1E),
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
        ),
        useMaterial3: true,
      ),
      home: EchoClipHome(
        languageMode: _languageMode,
        onLanguageModeChanged: _setLanguageMode,
      ),
    );
  }
}

enum AppSection {
  recorder(Icons.home_outlined),
  library(Icons.library_music),
  processing(Icons.equalizer),
  settings(Icons.tune);

  const AppSection(this.icon);

  final IconData icon;
}

extension _L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}

final DateTime _epochDateTime = DateTime.fromMillisecondsSinceEpoch(0);

class EchoClipHome extends StatefulWidget {
  const EchoClipHome({
    super.key,
    required this.languageMode,
    required this.onLanguageModeChanged,
  });

  final UiLanguageMode languageMode;
  final Future<void> Function(UiLanguageMode mode) onLanguageModeChanged;

  @override
  State<EchoClipHome> createState() => _EchoClipHomeState();
}

class _EchoClipHomeState extends State<EchoClipHome> {
  static const MethodChannel _replayChannel = MethodChannel(
    'com.echoclip/replay_service',
  );

  AppSection _section = AppSection.recorder;
  Timer? _statusTimer;
  Timer? _meterTimer;
  bool _meterPollInFlight = false;
  bool _isBuffering = defaultTargetPlatform != TargetPlatform.android;
  bool _serviceActive = defaultTargetPlatform != TargetPlatform.android;
  bool _folderSelected = defaultTargetPlatform != TargetPlatform.android;
  String? _folderUri;
  int _sampleRate = 16000;
  int _bufferSeconds = 1800;
  int _cacheBytes = 0;
  RecordingMode _recordingMode = RecordingMode.standard;
  LockRecordingTrigger _lockRecordingTrigger = LockRecordingTrigger.screenOff;
  String _evidenceState = 'off';
  String _platformStatus = defaultTargetPlatform == TargetPlatform.android
      ? 'Android service stopped'
      : 'Windows demo mode';
  final ValueNotifier<MeterSnapshot> _meterSnapshot =
      ValueNotifier<MeterSnapshot>(
        MeterSnapshot(
          running: defaultTargetPlatform != TargetPlatform.android,
          recordedMillis: defaultTargetPlatform == TargetPlatform.android
              ? 0
              : 42000,
          sessionRecordedMillis: defaultTargetPlatform == TargetPlatform.android
              ? 0
              : 42000,
          sessionStartedAt: defaultTargetPlatform == TargetPlatform.android
              ? _epochDateTime
              : DateTime.now().subtract(const Duration(seconds: 42)),
          level: 0,
          peakLevel: 0,
        ),
      );
  final List<ClipItem> _clips = [];
  final List<RecordingGroup> _groups = [];
  PlaybackSnapshot _playback = const PlaybackSnapshot(
    playing: false,
    paused: false,
    uri: null,
    positionMs: 0,
    durationMs: 0,
    speed: 1.0,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapAndroid());
    _statusTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      _refreshReplayStatus();
    });
    _meterTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _tickMeter();
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _meterTimer?.cancel();
    _meterSnapshot.dispose();
    super.dispose();
  }

  Future<void> _bootstrapAndroid() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    await _refreshRecordingFolder(promptIfMissing: true);
    await _loadAudioSettings();
    await _loadRecordingModeSettings();
    await _loadCacheStatus();
    await _loadRecordings();
    await _refreshReplayStatus();
  }

  Future<void> _loadAudioSettings() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    final response = await _replayChannel.invokeMapMethod<String, Object?>(
      'getAudioSettings',
    );
    if (!mounted || response == null) {
      return;
    }

    setState(() {
      _sampleRate = response['sampleRate'] is int
          ? response['sampleRate'] as int
          : _sampleRate;
      _bufferSeconds = response['bufferSeconds'] is int
          ? response['bufferSeconds'] as int
          : _bufferSeconds;
    });
  }

  Future<void> _loadRecordingModeSettings() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    final response = await _replayChannel.invokeMapMethod<String, Object?>(
      'getRecordingModeSettings',
    );
    if (!mounted || response == null) {
      return;
    }

    setState(() {
      _recordingMode = RecordingMode.fromStorageValue(
        response['mode']?.toString(),
      );
      _lockRecordingTrigger = LockRecordingTrigger.fromStorageValue(
        response['trigger']?.toString(),
      );
    });
  }

  Future<void> _setRecordingMode(RecordingMode mode) async {
    if (_recordingMode == mode) {
      return;
    }

    if (defaultTargetPlatform != TargetPlatform.android) {
      setState(() {
        _recordingMode = mode;
        _platformStatus = context.l10n.windowsDemoMode;
      });
      return;
    }

    final previousMode = _recordingMode;
    setState(() {
      _recordingMode = mode;
      _platformStatus = _recordingModeStatusText(context.l10n);
    });

    try {
      await _replayChannel.invokeMapMethod<String, Object?>(
        'setRecordingModeSettings',
        {
          'mode': mode.storageValue,
          'trigger': _lockRecordingTrigger.storageValue,
        },
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _platformStatus = _serviceActive
            ? context.l10n.settingsSavedNextRecording
            : _recordingModeStatusText(context.l10n);
      });
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _recordingMode = previousMode;
        _platformStatus = context.l10n.androidServiceError(error.code);
      });
    }
  }

  Future<void> _setLockRecordingTrigger(LockRecordingTrigger trigger) async {
    if (_lockRecordingTrigger == trigger) {
      return;
    }

    setState(() {
      _lockRecordingTrigger = trigger;
      _platformStatus = _recordingModeStatusText(context.l10n);
    });

    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    try {
      await _replayChannel.invokeMapMethod<String, Object?>(
        'setRecordingModeSettings',
        {'mode': _recordingMode.storageValue, 'trigger': trigger.storageValue},
      );
      if (_recordingMode == RecordingMode.lockscreen && _serviceActive) {
        await _replayChannel.invokeMapMethod<String, Object?>('startReplay', {
          'mode': _recordingMode.storageValue,
          'trigger': trigger.storageValue,
        });
      }
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _platformStatus = context.l10n.androidServiceError(error.code);
      });
    }
  }

  Future<void> _updateAudioSettings({
    int? sampleRate,
    int? bufferSeconds,
  }) async {
    final nextSampleRate = sampleRate ?? _sampleRate;
    final nextBufferSeconds = bufferSeconds ?? _bufferSeconds;

    if (defaultTargetPlatform != TargetPlatform.android) {
      setState(() {
        _sampleRate = nextSampleRate;
        _bufferSeconds = nextBufferSeconds;
      });
      return;
    }

    final response = await _replayChannel.invokeMapMethod<String, Object?>(
      'setAudioSettings',
      {'sampleRate': nextSampleRate, 'bufferSeconds': nextBufferSeconds},
    );
    if (!mounted || response == null) {
      return;
    }

    final applied = response['applied'] == true;
    final l10n = context.l10n;
    setState(() {
      _sampleRate = response['sampleRate'] is int
          ? response['sampleRate'] as int
          : nextSampleRate;
      _bufferSeconds = response['bufferSeconds'] is int
          ? response['bufferSeconds'] as int
          : nextBufferSeconds;
      _platformStatus = applied
          ? l10n.recordingSettingsSaved
          : l10n.settingsSavedNextRecording;
    });
  }

  Future<void> _refreshRecordingFolder({bool promptIfMissing = false}) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    final response = await _replayChannel.invokeMapMethod<String, Object?>(
      'getRecordingFolder',
    );
    final selected = response?['selected'] == true;
    if (!mounted) {
      return;
    }

    setState(() {
      _folderSelected = selected;
      _folderUri = response?['uri']?.toString();
    });

    if (!selected && promptIfMissing) {
      await _chooseRecordingFolder();
    }
  }

  Future<void> _chooseRecordingFolder() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      setState(() {
        _folderSelected = true;
        _platformStatus = context.l10n.windowsDemoMode;
      });
      return;
    }

    final response = await _replayChannel.invokeMapMethod<String, Object?>(
      'chooseRecordingFolder',
    );
    if (!mounted) {
      return;
    }

    final selected = response?['selected'] == true;
    final l10n = context.l10n;
    setState(() {
      _folderSelected = selected;
      _folderUri = response?['uri']?.toString();
      _platformStatus = selected
          ? l10n.recordingFolderReady
          : l10n.folderSetupError(response?['error']?.toString() ?? 'unknown');
    });
    if (selected) {
      await _loadRecordings();
    }
  }

  Future<void> _refreshReplayStatus() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    try {
      final response = await _replayChannel.invokeMapMethod<String, Object?>(
        'getReplayStatus',
      );
      if (!mounted) {
        return;
      }

      final running = response?['running'] == true;
      final serviceActive = response?['serviceActive'] == true;
      final availableSeconds = response?['availableSeconds'];
      final availableMillis = response?['availableMillis'];
      final captureError = response?['captureError'];
      final sampleRate = response?['sampleRate'];
      final bufferSeconds = response?['bufferSeconds'];
      final cacheBytes = response?['cacheBytes'];
      final sessionStartedUnixMillis = response?['sessionStartedUnixMillis'];
      final l10n = context.l10n;
      setState(() {
        _isBuffering = running;
        _serviceActive = serviceActive;
        _recordingMode = RecordingMode.fromStorageValue(
          response?['recordingMode']?.toString(),
        );
        _lockRecordingTrigger = LockRecordingTrigger.fromStorageValue(
          response?['lockRecordingTrigger']?.toString(),
        );
        _evidenceState = response?['evidenceState']?.toString() ?? 'off';
        _platformStatus = _friendlyRecordingStatus(
          l10n: l10n,
          running: running,
          serviceActive: serviceActive,
          recordingMode: _recordingMode,
          lockRecordingTrigger: _lockRecordingTrigger,
          evidenceState: _evidenceState,
          rawError: captureError?.toString(),
        );
        if (sampleRate is int) {
          _sampleRate = sampleRate;
        }
        if (bufferSeconds is int) {
          _bufferSeconds = bufferSeconds;
        }
        if (cacheBytes is int) {
          _cacheBytes = cacheBytes;
        }
      });
      if (availableMillis is num) {
        _updateMeterSnapshot(
          running: running,
          recordedMillis: availableMillis.toInt(),
          sessionStartedUnixMillis: sessionStartedUnixMillis is num
              ? sessionStartedUnixMillis.toInt()
              : null,
        );
      } else if (availableSeconds is int) {
        _updateMeterSnapshot(
          running: running,
          recordedMillis: availableSeconds * 1000,
          sessionStartedUnixMillis: sessionStartedUnixMillis is num
              ? sessionStartedUnixMillis.toInt()
              : null,
        );
      }
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _platformStatus = context.l10n.androidServiceError(error.code);
      });
    }
  }

  void _applyReplayStatusResponse(Map<String, Object?>? response) {
    if (response == null) {
      return;
    }
    final running = response['running'] == true;
    final serviceActive = response.containsKey('serviceActive')
        ? response['serviceActive'] == true
        : running;
    final error = response['error'];
    setState(() {
      _isBuffering = running;
      _serviceActive = serviceActive;
      if (response.containsKey('recordingMode')) {
        _recordingMode = RecordingMode.fromStorageValue(
          response['recordingMode']?.toString(),
        );
      }
      if (response.containsKey('lockRecordingTrigger')) {
        _lockRecordingTrigger = LockRecordingTrigger.fromStorageValue(
          response['lockRecordingTrigger']?.toString(),
        );
      }
      if (response.containsKey('evidenceState')) {
        _evidenceState = response['evidenceState']?.toString() ?? 'off';
      } else if (!serviceActive) {
        _evidenceState = 'off';
      }
      _platformStatus = error == null
          ? _recordingModeStatusText(context.l10n)
          : context.l10n.androidServiceError(error.toString());
    });
  }

  String _recordingModeStatusText(AppLocalizations l10n) {
    if (_recordingMode == RecordingMode.standard) {
      return _isBuffering
          ? l10n.recordingStatusNormal
          : l10n.recordingStatusPaused;
    }
    return switch (_evidenceState) {
      'recording' => l10n.lockRecordingStatusRecording,
      'armed' =>
        _lockRecordingTrigger == LockRecordingTrigger.keyguardLocked
            ? l10n.lockRecordingStatusArmedKeyguard
            : l10n.lockRecordingStatusArmedScreenOff,
      _ => l10n.lockRecordingStatusOff,
    };
  }

  void _tickMeter() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final snapshot = _meterSnapshot.value;
      if (snapshot.running) {
        _meterSnapshot.value = snapshot.copyWith(
          recordedMillis: math.min(
            snapshot.recordedMillis + 50,
            _bufferSeconds * 1000,
          ),
          sessionRecordedMillis: snapshot.sessionRecordedMillis + 50,
        );
      }
      unawaited(_refreshMeterStatus());
      return;
    }

    final snapshot = _meterSnapshot.value;
    if (!snapshot.running) {
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch / 180.0;
    final pulse =
        (math.sin(now * 0.9) * 0.18 + math.sin(now * 0.37) * 0.28 + 0.34)
            .clamp(0.03, 0.86)
            .toDouble();
    _meterSnapshot.value = MeterSnapshot(
      running: true,
      recordedMillis: snapshot.recordedMillis + 50,
      sessionRecordedMillis: snapshot.sessionRecordedMillis + 50,
      sessionStartedAt: snapshot.sessionStartedAt,
      level: pulse,
      peakLevel: math.max(snapshot.peakLevel * 0.94, pulse),
    );
  }

  Future<void> _refreshMeterStatus() async {
    if (_meterPollInFlight) {
      return;
    }

    _meterPollInFlight = true;
    try {
      final response = await _replayChannel.invokeMapMethod<String, Object?>(
        'getMeterStatus',
      );
      if (!mounted || response == null) {
        return;
      }

      final running = response['running'] == true;
      final serviceActive = response['serviceActive'] == true;
      final recordedMillis = response['availableMillis'];
      final sessionStartedUnixMillis = response['sessionStartedUnixMillis'];
      final level = response['level'];
      final peakLevel = response['peakLevel'];
      _updateMeterSnapshot(
        running: running,
        recordedMillis: recordedMillis is num
            ? recordedMillis.toInt()
            : _meterSnapshot.value.recordedMillis,
        sessionStartedUnixMillis: sessionStartedUnixMillis is num
            ? sessionStartedUnixMillis.toInt()
            : null,
        level: level is num ? level.toDouble() : _meterSnapshot.value.level,
        peakLevel: peakLevel is num
            ? peakLevel.toDouble()
            : _meterSnapshot.value.peakLevel,
      );
      if ((running != _isBuffering || serviceActive != _serviceActive) &&
          mounted) {
        setState(() {
          _isBuffering = running;
          _serviceActive = serviceActive;
          _recordingMode = RecordingMode.fromStorageValue(
            response['recordingMode']?.toString(),
          );
          _lockRecordingTrigger = LockRecordingTrigger.fromStorageValue(
            response['lockRecordingTrigger']?.toString(),
          );
          _evidenceState = response['evidenceState']?.toString() ?? 'off';
          _platformStatus = _recordingModeStatusText(context.l10n);
        });
      }
    } on PlatformException {
      _updateMeterSnapshot(running: false, recordedMillis: 0, level: 0);
    } finally {
      _meterPollInFlight = false;
    }
  }

  void _updateMeterSnapshot({
    required bool running,
    required int recordedMillis,
    int? sessionStartedUnixMillis,
    double? level,
    double? peakLevel,
  }) {
    final previous = _meterSnapshot.value;
    final displayRecordedMillis =
        !running && recordedMillis == 0 && previous.recordedMillis > 0
        ? previous.recordedMillis
        : recordedMillis;
    final providedSessionStartedAt = sessionStartedUnixMillis == null
        ? null
        : sessionStartedUnixMillis > 0
        ? DateTime.fromMillisecondsSinceEpoch(sessionStartedUnixMillis)
        : _epochDateTime;
    final sessionStartedAt = running
        ? providedSessionStartedAt ??
              previous.sessionStartedAt ??
              DateTime.now().subtract(
                Duration(milliseconds: displayRecordedMillis),
              )
        : providedSessionStartedAt ??
              previous.sessionStartedAt ??
              _epochDateTime;
    final sessionRecordedMillis = running
        ? math.max(
            0,
            DateTime.now().difference(sessionStartedAt).inMilliseconds,
          )
        : 0;
    _meterSnapshot.value = MeterSnapshot(
      running: running,
      recordedMillis: displayRecordedMillis,
      sessionRecordedMillis: sessionRecordedMillis,
      sessionStartedAt: sessionStartedAt,
      level: (level ?? previous.level).clamp(0.0, 1.0).toDouble(),
      peakLevel: (peakLevel ?? previous.peakLevel).clamp(0.0, 1.0).toDouble(),
    );
  }

  Future<void> _toggleBuffering() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      setState(() {
        _isBuffering = !_isBuffering;
        _platformStatus = context.l10n.windowsDemoMode;
      });
      _updateMeterSnapshot(
        running: _isBuffering,
        recordedMillis: _meterSnapshot.value.recordedMillis,
        sessionStartedUnixMillis: _isBuffering
            ? DateTime.now().millisecondsSinceEpoch
            : null,
        level: _isBuffering ? _meterSnapshot.value.level : 0,
        peakLevel: _isBuffering ? _meterSnapshot.value.peakLevel : 0,
      );
      return;
    }

    if (!_folderSelected) {
      await _chooseRecordingFolder();
      if (!_folderSelected) {
        return;
      }
    }

    try {
      final lockscreenMode = _recordingMode == RecordingMode.lockscreen;
      final shouldStop = lockscreenMode ? _serviceActive : _isBuffering;
      final method = shouldStop ? 'stopReplay' : 'startReplay';
      final arguments = shouldStop
          ? null
          : {
              'mode': _recordingMode.storageValue,
              'trigger': _lockRecordingTrigger.storageValue,
            };
      final response = await _replayChannel.invokeMapMethod<String, Object?>(
        method,
        arguments,
      );
      if (!mounted) {
        return;
      }

      _applyReplayStatusResponse(response);
      final running = response?['running'] == true;
      _updateMeterSnapshot(
        running: running,
        recordedMillis: _meterSnapshot.value.recordedMillis,
        sessionStartedUnixMillis: running
            ? DateTime.now().millisecondsSinceEpoch
            : null,
        level: running ? _meterSnapshot.value.level : 0,
        peakLevel: running ? _meterSnapshot.value.peakLevel : 0,
      );
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _platformStatus = context.l10n.androidServiceError(error.code);
      });
    }
  }

  Future<void> _saveClip(int seconds) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      if (!_folderSelected) {
        await _chooseRecordingFolder();
        if (!_folderSelected) {
          return;
        }
      }

      try {
        final response = await _replayChannel.invokeMapMethod<String, Object?>(
          'saveReplayClip',
          {'seconds': seconds},
        );
        if (!mounted) {
          return;
        }

        final saved = response?['saved'] == true;
        final l10n = context.l10n;
        if (!saved) {
          setState(() {
            _platformStatus = l10n.androidSaveError(
              response?['error']?.toString() ?? 'unknown',
            );
          });
          return;
        }

        final pending = response?['pending'] == true;
        setState(() {
          _platformStatus = pending
              ? l10n.androidSaveStarted
              : l10n.androidClipSaved;
        });
        if (pending) {
          unawaited(_reloadRecordingsAfterSave());
        } else {
          await _loadRecordings();
        }
        await _loadCacheStatus();
        return;
      } on PlatformException catch (error) {
        if (!mounted) {
          return;
        }
        setState(() {
          _platformStatus = context.l10n.androidSaveError(error.code);
        });
        return;
      }
    }

    setState(() {
      final l10n = context.l10n;
      _clips.insert(
        0,
        ClipItem(
          name: l10n.recentDurationName(_formatDurationLabel(l10n, seconds)),
          durationSeconds: seconds,
          createdAt: DateTime.now(),
          uri: null,
          parentUri: null,
          groupName: null,
          groupUri: null,
          size: null,
        ),
      );
    });
  }

  Future<void> _reloadRecordingsAfterSave() async {
    await Future<void>.delayed(const Duration(seconds: 1));
    await _loadRecordings();
    await Future<void>.delayed(const Duration(seconds: 3));
    await _loadRecordings();
  }

  Future<void> _loadRecordings() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    final groupsResponse = await _replayChannel.invokeListMethod<Object?>(
      'listGroups',
    );
    final recordingsResponse = await _replayChannel.invokeListMethod<Object?>(
      'listRecordings',
    );
    if (!mounted || recordingsResponse == null) {
      return;
    }

    setState(() {
      _groups
        ..clear()
        ..addAll(
          (groupsResponse ?? const <Object?>[]).whereType<Map>().map(
            RecordingGroup.fromNative,
          ),
        );
      _clips
        ..clear()
        ..addAll(recordingsResponse.whereType<Map>().map(ClipItem.fromNative));
    });
  }

  Future<void> _playClip(ClipItem clip) async {
    final uri = clip.uri;
    if (uri == null || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    final response = await _replayChannel.invokeMapMethod<String, Object?>(
      'playRecording',
      {'uri': uri, 'speed': _playback.speed},
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _playback = PlaybackSnapshot.fromNative(response, fallback: _playback);
      _platformStatus = response?['playing'] == true
          ? context.l10n.previewPlaying
          : context.l10n.previewError(
              response?['error']?.toString() ?? 'unknown',
            );
    });
  }

  Future<void> _pausePreview() async {
    final response = await _replayChannel.invokeMapMethod<String, Object?>(
      'pausePreview',
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _playback = PlaybackSnapshot.fromNative(response, fallback: _playback);
    });
  }

  Future<void> _resumePreview() async {
    final response = await _replayChannel.invokeMapMethod<String, Object?>(
      'resumePreview',
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _playback = PlaybackSnapshot.fromNative(response, fallback: _playback);
    });
  }

  Future<void> _stopPreview() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    final response = await _replayChannel.invokeMapMethod<String, Object?>(
      'stopPreview',
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _playback = PlaybackSnapshot.fromNative(response, fallback: _playback);
      _platformStatus = context.l10n.previewStopped;
    });
  }

  Future<void> _seekPreview(int positionMs) async {
    final response = await _replayChannel.invokeMapMethod<String, Object?>(
      'seekPreview',
      {'positionMs': positionMs},
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _playback = PlaybackSnapshot.fromNative(response, fallback: _playback);
    });
  }

  Future<void> _setPlaybackSpeed(double speed) async {
    final response = await _replayChannel.invokeMapMethod<String, Object?>(
      'setPlaybackSpeed',
      {'speed': speed},
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _playback = PlaybackSnapshot.fromNative(
        response,
        fallback: _playback.copyWith(speed: speed),
      );
    });
  }

  Future<void> _createGroup(String name) async {
    await _runLibraryMutation('createGroup', {'name': name});
  }

  Future<void> _renameGroup(RecordingGroup group, String name) async {
    await _runLibraryMutation('renameGroup', {'uri': group.uri, 'name': name});
  }

  Future<void> _deleteGroup(RecordingGroup group) async {
    await _runLibraryMutation('deleteGroup', {'uri': group.uri});
  }

  Future<void> _renameClip(ClipItem clip, String name) async {
    await _runLibraryMutation('renameRecording', {
      'uri': clip.uri,
      'name': name,
    });
  }

  Future<void> _deleteClip(ClipItem clip) async {
    if (clip.uri != null && clip.uri == _playback.uri) {
      await _stopPreview();
    }
    await _runLibraryMutation('deleteRecording', {'uri': clip.uri});
  }

  Future<void> _deleteClips(List<ClipItem> clips) async {
    if (defaultTargetPlatform != TargetPlatform.android || clips.isEmpty) {
      return;
    }
    if (clips.any((clip) => clip.uri != null && clip.uri == _playback.uri)) {
      await _stopPreview();
    }

    var deleted = 0;
    String? firstError;
    for (final clip in clips) {
      final uri = clip.uri;
      if (uri == null) {
        continue;
      }
      final response = await _replayChannel.invokeMapMethod<String, Object?>(
        'deleteRecording',
        {'uri': uri},
      );
      if (response?['ok'] == true) {
        deleted += 1;
      } else {
        firstError ??= response?['error']?.toString() ?? 'delete_failed';
      }
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _platformStatus = firstError == null
          ? context.l10n.deletedRecordings(deleted)
          : context.l10n.deletedRecordingsWithError(deleted, firstError);
    });
    await _loadRecordings();
  }

  Future<void> _moveClip(ClipItem clip, RecordingGroup? group) async {
    await _runLibraryMutation('moveRecording', {
      'uri': clip.uri,
      'parentUri': clip.parentUri,
      'groupUri': group?.uri,
    });
  }

  Future<bool> _processClip({
    required ClipItem clip,
    required double gainDb,
    required String format,
    required int mp3BitrateKbps,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android || clip.uri == null) {
      return false;
    }
    final response = await _replayChannel
        .invokeMapMethod<String, Object?>('processRecording', {
          'uri': clip.uri,
          'parentUri': clip.parentUri,
          'gainDb': gainDb,
          'format': format,
          'mp3BitrateKbps': mp3BitrateKbps,
        });
    if (!mounted) {
      return false;
    }
    final ok = response?['ok'] == true;
    setState(() {
      _platformStatus = ok
          ? context.l10n.processedRecording(response?['name']?.toString() ?? '')
          : context.l10n.processingStatusError(
              response?['error']?.toString() ?? 'unknown',
            );
    });
    if (ok) {
      await _loadRecordings();
    }
    return ok;
  }

  Future<Map<String, Object?>> _clearCache() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return <String, Object?>{'ok': false, 'error': 'unsupported_platform'};
    }
    final response = await _replayChannel.invokeMapMethod<String, Object?>(
      'clearCache',
    );
    final result = Map<String, Object?>.from(response ?? const {});
    if (!mounted) {
      return result;
    }
    final ok = result['ok'] == true;
    final deletedBytes = result['deletedBytes'];
    final cacheBytes = result['cacheBytes'];
    setState(() {
      if (cacheBytes is int) {
        _cacheBytes = cacheBytes;
      } else if (ok) {
        _cacheBytes = 0;
      }
      _platformStatus = ok
          ? context.l10n.cacheClearedStatus(
              _formatBytes(deletedBytes is int ? deletedBytes : 0),
            )
          : context.l10n.clearCacheStatusError(
              result['error']?.toString() ?? 'unknown',
            );
    });
    if (ok && !_isBuffering) {
      _meterSnapshot.value = _meterSnapshot.value.copyWith(
        recordedMillis: 0,
        sessionRecordedMillis: 0,
        sessionStartedAt: _epochDateTime,
        level: 0,
        peakLevel: 0,
      );
    }
    return result;
  }

  Future<void> _loadCacheStatus() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    final response = await _replayChannel.invokeMapMethod<String, Object?>(
      'getCacheStatus',
    );
    if (!mounted || response == null) {
      return;
    }
    final cacheBytes = response['cacheBytes'];
    if (cacheBytes is int) {
      setState(() {
        _cacheBytes = cacheBytes;
      });
    }
  }

  Future<void> _openExternalUrl(String url) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    await _replayChannel.invokeMapMethod<String, Object?>('openUrl', {
      'url': url,
    });
  }

  Future<void> _runLibraryMutation(
    String method,
    Map<String, Object?> arguments,
  ) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    final response = await _replayChannel.invokeMapMethod<String, Object?>(
      method,
      arguments,
    );
    if (!mounted) {
      return;
    }

    final ok = response?['ok'] == true;
    setState(() {
      _platformStatus = ok
          ? context.l10n.libraryUpdated
          : context.l10n.libraryError(response?['error']?.toString() ?? method);
    });
    if (ok) {
      await _loadRecordings();
    }
  }

  Widget _recordingModeMenu(BuildContext context) {
    final l10n = context.l10n;
    return PopupMenuButton<RecordingMode>(
      initialValue: _recordingMode,
      tooltip: _recordingModeLabel(l10n, _recordingMode),
      onSelected: _setRecordingMode,
      itemBuilder: (context) => [
        for (final mode in RecordingMode.values)
          PopupMenuItem(
            value: mode,
            child: Text(_recordingModeLabel(l10n, mode)),
          ),
      ],
      child: Chip(
        avatar: const Icon(Icons.swap_horiz, size: 18),
        label: Text(_recordingModeLabel(l10n, _recordingMode)),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = switch (_section) {
      AppSection.recorder => _RecorderPage(
        isBuffering: _isBuffering,
        platformStatus: _platformStatus,
        meterSnapshot: _meterSnapshot,
        folderSelected: _folderSelected,
        onSave: _saveClip,
        onChooseFolder: _chooseRecordingFolder,
      ),
      AppSection.library => _LibraryPage(
        groups: _groups,
        clips: _clips,
        playback: _playback,
        onRefresh: _loadRecordings,
        onPlay: _playClip,
        onPause: _pausePreview,
        onResume: _resumePreview,
        onStop: _stopPreview,
        onSeek: _seekPreview,
        onSpeedChanged: _setPlaybackSpeed,
        onCreateGroup: _createGroup,
        onRenameGroup: _renameGroup,
        onDeleteGroup: _deleteGroup,
        onRenameClip: _renameClip,
        onDeleteClip: _deleteClip,
        onDeleteClips: _deleteClips,
        onMoveClip: _moveClip,
      ),
      AppSection.processing => _ProcessingPage(
        clips: _clips,
        onProcess: _processClip,
      ),
      AppSection.settings => _SettingsPage(
        folderUri: _folderUri,
        sampleRate: _sampleRate,
        bufferSeconds: _bufferSeconds,
        cacheBytes: _cacheBytes,
        lockRecordingTrigger: _lockRecordingTrigger,
        languageMode: widget.languageMode,
        onChooseFolder: _chooseRecordingFolder,
        onUpdateAudioSettings: _updateAudioSettings,
        onLockRecordingTriggerChanged: _setLockRecordingTrigger,
        onClearCache: _clearCache,
        onLanguageModeChanged: widget.onLanguageModeChanged,
        onOpenUrl: _openExternalUrl,
      ),
    };

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F7),
      appBar: AppBar(
        title: Text(_appBarTitle(context, _section)),
        centerTitle: false,
        backgroundColor: const Color(0xFFF6F8F7),
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        actions: [
          if (_section == AppSection.recorder)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _recordingModeMenu(context),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(padding: const EdgeInsets.all(20), child: content),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _section.index,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        onDestinationSelected: (index) {
          setState(() => _section = AppSection.values[index]);
          if (AppSection.values[index] == AppSection.settings) {
            unawaited(_loadCacheStatus());
          }
        },
        destinations: [
          for (final section in AppSection.values)
            NavigationDestination(
              icon: Icon(section.icon),
              selectedIcon: Icon(_selectedIconFor(section)),
              label: _sectionLabel(context, section),
            ),
        ],
      ),
      floatingActionButton: _section == AppSection.recorder
          ? FloatingActionButton(
              onPressed: _toggleBuffering,
              tooltip:
                  (_recordingMode == RecordingMode.lockscreen
                      ? _serviceActive
                      : _isBuffering)
                  ? context.l10n.pause
                  : context.l10n.resume,
              child: Icon(
                (_recordingMode == RecordingMode.lockscreen
                        ? _serviceActive
                        : _isBuffering)
                    ? Icons.pause
                    : Icons.play_arrow,
              ),
            )
          : null,
    );
  }
}

String _appBarTitle(BuildContext context, AppSection section) {
  return section == AppSection.recorder
      ? context.l10n.appTitle
      : _sectionLabel(context, section);
}

String _sectionLabel(BuildContext context, AppSection section) {
  final l10n = context.l10n;
  return switch (section) {
    AppSection.recorder => l10n.navHome,
    AppSection.library => l10n.navLibrary,
    AppSection.processing => l10n.navProcessing,
    AppSection.settings => l10n.navSettings,
  };
}

String _languageModeLabel(AppLocalizations l10n, UiLanguageMode mode) {
  return switch (mode) {
    UiLanguageMode.system => l10n.followSystemLanguage,
    UiLanguageMode.english => l10n.englishLanguage,
    UiLanguageMode.chinese => l10n.chineseLanguage,
  };
}

String _recordingModeLabel(AppLocalizations l10n, RecordingMode mode) {
  return switch (mode) {
    RecordingMode.standard => l10n.standardRecordingMode,
    RecordingMode.lockscreen => l10n.lockRecordingMode,
  };
}

String _friendlyRecordingStatus({
  required AppLocalizations l10n,
  required bool running,
  bool serviceActive = false,
  RecordingMode recordingMode = RecordingMode.standard,
  LockRecordingTrigger lockRecordingTrigger = LockRecordingTrigger.screenOff,
  String evidenceState = 'off',
  String? rawError,
}) {
  final normalizedError = _normalizeNativeDetail(rawError);
  if (normalizedError == null) {
    if (recordingMode == RecordingMode.lockscreen) {
      return switch (evidenceState) {
        'recording' => l10n.lockRecordingStatusRecording,
        'armed' =>
          lockRecordingTrigger == LockRecordingTrigger.keyguardLocked
              ? l10n.lockRecordingStatusArmedKeyguard
              : l10n.lockRecordingStatusArmedScreenOff,
        _ =>
          serviceActive
              ? l10n.lockRecordingStatusArmedScreenOff
              : l10n.lockRecordingStatusOff,
      };
    }
    return running ? l10n.recordingStatusNormal : l10n.recordingStatusPaused;
  }

  final message = switch (normalizedError) {
    final value when value.startsWith('storage_low') =>
      l10n.recordingStatusStorageLow,
    'microphone_permission_lost' => l10n.recordingStatusPermissionLost,
    final value when value.startsWith('invalid_min_buffer') =>
      l10n.recordingStatusAudioUnavailable,
    'audio_record_not_initialized' => l10n.recordingStatusAudioUnavailable,
    'pcm_queue_full' => l10n.recordingStatusQueueBusy,
    'pcm_worker_stopped' => l10n.recordingStatusBackendUnavailable,
    'pcm_invalid_handle' => l10n.recordingStatusBackendUnavailable,
    'pcm_panic_caught' => l10n.recordingStatusBackendUnavailable,
    'pcm_queue_closed' => l10n.recordingStatusBackendUnavailable,
    'pcm_push_failed' => l10n.recordingStatusBackendUnavailable,
    'pcm_unknown_push_code' => l10n.recordingStatusBackendUnavailable,
    'rust_recorder_start_failed' => l10n.recordingStatusBackendUnavailable,
    final value when value.startsWith('capture_exception') =>
      l10n.recordingStatusCaptureIssue,
    _ => l10n.recordingStatusCaptureIssue,
  };

  final detail = _readableNativeDetail(normalizedError);
  return detail == null
      ? message
      : l10n.recordingStatusWithDetail(message, detail);
}

String? _normalizeNativeDetail(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null ||
      trimmed.isEmpty ||
      trimmed.toLowerCase() == 'null' ||
      trimmed.toLowerCase() == 'none') {
    return null;
  }
  return trimmed;
}

String? _readableNativeDetail(String value) {
  if (value.startsWith('storage_low') ||
      value.startsWith('invalid_min_buffer') ||
      value.startsWith('capture_exception')) {
    return value
        .split(':')
        .where((part) => part.isNotEmpty)
        .skip(1)
        .join(' / ');
  }
  return null;
}

IconData _selectedIconFor(AppSection section) {
  return switch (section) {
    AppSection.recorder => Icons.home,
    AppSection.library => Icons.library_music,
    AppSection.processing => Icons.equalizer,
    AppSection.settings => Icons.tune,
  };
}

class MeterSnapshot {
  const MeterSnapshot({
    required this.running,
    required this.recordedMillis,
    required this.sessionRecordedMillis,
    required this.sessionStartedAt,
    required this.level,
    required this.peakLevel,
  });

  final bool running;
  final int recordedMillis;
  final int sessionRecordedMillis;
  final DateTime? sessionStartedAt;
  final double level;
  final double peakLevel;

  MeterSnapshot copyWith({
    bool? running,
    int? recordedMillis,
    int? sessionRecordedMillis,
    DateTime? sessionStartedAt,
    bool clearSessionStartedAt = false,
    double? level,
    double? peakLevel,
  }) {
    return MeterSnapshot(
      running: running ?? this.running,
      recordedMillis: recordedMillis ?? this.recordedMillis,
      sessionRecordedMillis:
          sessionRecordedMillis ?? this.sessionRecordedMillis,
      sessionStartedAt: clearSessionStartedAt
          ? null
          : sessionStartedAt ?? this.sessionStartedAt,
      level: level ?? this.level,
      peakLevel: peakLevel ?? this.peakLevel,
    );
  }
}

class _RecorderPage extends StatefulWidget {
  const _RecorderPage({
    required this.isBuffering,
    required this.platformStatus,
    required this.meterSnapshot,
    required this.folderSelected,
    required this.onSave,
    required this.onChooseFolder,
  });

  final bool isBuffering;
  final String platformStatus;
  final ValueListenable<MeterSnapshot> meterSnapshot;
  final bool folderSelected;
  final Future<void> Function(int seconds) onSave;
  final Future<void> Function() onChooseFolder;

  @override
  State<_RecorderPage> createState() => _RecorderPageState();
}

class _RecorderPageState extends State<_RecorderPage> {
  static const List<SaveDurationOption> _durations = [
    SaveDurationOption(10),
    SaveDurationOption(30),
    SaveDurationOption(60),
    SaveDurationOption(120),
    SaveDurationOption(300),
    SaveDurationOption(600),
    SaveDurationOption(1800),
    SaveDurationOption(3600),
    SaveDurationOption(7200),
    SaveDurationOption(18000),
    SaveDurationOption(43200),
    SaveDurationOption(86400),
  ];

  SaveDurationOption _selectedDuration = _durations[1];
  SaveDurationMode _durationMode = SaveDurationMode.preset;
  int _customDurationSeconds = 30;

  int get _activeSaveSeconds {
    return switch (_durationMode) {
      SaveDurationMode.preset => _selectedDuration.seconds,
      SaveDurationMode.custom => _customDurationSeconds,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListView(
      children: [
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    widget.isBuffering ? Icons.graphic_eq : Icons.pause_circle,
                    color: widget.isBuffering
                        ? const Color(0xFF1B7F79)
                        : Colors.orange,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.isBuffering
                          ? l10n.replayRunning
                          : l10n.recordingPaused,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ValueListenableBuilder<MeterSnapshot>(
                valueListenable: widget.meterSnapshot,
                builder: (context, snapshot, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _RecordingTimeSummary(
                        snapshot: snapshot,
                        statusText: widget.platformStatus,
                      ),
                      const SizedBox(height: 10),
                      LoudnessMeter(
                        level: snapshot.level,
                        peakLevel: snapshot.peakLevel,
                        isRecording: snapshot.running,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ValueListenableBuilder<MeterSnapshot>(
                    valueListenable: widget.meterSnapshot,
                    builder: (context, snapshot, _) {
                      final canSave =
                          widget.folderSelected && snapshot.recordedMillis > 0;
                      return FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(152, 56),
                        ),
                        onPressed: canSave
                            ? () => widget.onSave(_activeSaveSeconds)
                            : null,
                        icon: const Icon(Icons.save_alt),
                        label: Text(
                          l10n.saveClip(
                            _formatDurationLabel(l10n, _activeSaveSeconds),
                          ),
                        ),
                      );
                    },
                  ),
                  SegmentedButton<SaveDurationMode>(
                    segments: [
                      ButtonSegment(
                        value: SaveDurationMode.preset,
                        icon: const Icon(Icons.timer_outlined),
                        label: Text(l10n.presetSaveDuration),
                      ),
                      ButtonSegment(
                        value: SaveDurationMode.custom,
                        icon: const Icon(Icons.edit_calendar),
                        label: Text(l10n.customSaveDuration),
                      ),
                    ],
                    selected: {_durationMode},
                    onSelectionChanged: (values) {
                      setState(() => _durationMode = values.first);
                    },
                  ),
                  if (_durationMode == SaveDurationMode.preset)
                    DropdownMenu<SaveDurationOption>(
                      initialSelection: _selectedDuration,
                      width: 168,
                      leadingIcon: const Icon(Icons.timer_outlined),
                      inputDecorationTheme: const InputDecorationTheme(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12),
                        constraints: BoxConstraints(minHeight: 56),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(28)),
                        ),
                      ),
                      onSelected: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _selectedDuration = value;
                        });
                      },
                      dropdownMenuEntries: [
                        for (final option in _durations)
                          DropdownMenuEntry(
                            value: option,
                            label: _formatDurationLabel(l10n, option.seconds),
                          ),
                      ],
                    )
                  else
                    _SaveSecondsField(
                      seconds: _customDurationSeconds,
                      onChanged: (seconds) {
                        setState(() => _customDurationSeconds = seconds);
                      },
                    ),
                  if (!widget.folderSelected)
                    OutlinedButton.icon(
                      onPressed: widget.onChooseFolder,
                      icon: const Icon(Icons.folder_open),
                      label: Text(l10n.chooseFolder),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecordingTimeSummary extends StatelessWidget {
  const _RecordingTimeSummary({
    required this.snapshot,
    required this.statusText,
  });

  final MeterSnapshot snapshot;
  final String statusText;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final startedAt = snapshot.sessionStartedAt ?? _epochDateTime;
    final startText = snapshot.running
        ? l10n.recordingStartedAt(_formatSessionStart(startedAt))
        : l10n.lastRecordingStartedAt(_formatSessionStart(startedAt));
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: const Color(0xFF6C7472),
    );
    final numberStyle = theme.textTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final totalStyle = theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(startText, style: labelStyle),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              flex: 6,
              child: _TimeBlock(
                label: l10n.currentRecordingDuration,
                value: _formatDurationMillis(snapshot.sessionRecordedMillis),
                labelStyle: labelStyle,
                valueStyle: numberStyle,
              ),
            ),
            Container(
              width: 1,
              height: 44,
              margin: const EdgeInsets.symmetric(horizontal: 14),
              color: const Color(0xFFD7DFDC),
            ),
            Expanded(
              flex: 5,
              child: _TimeBlock(
                label: l10n.totalRecordedDuration,
                value: _formatDurationMillis(snapshot.recordedMillis),
                labelStyle: labelStyle,
                valueStyle: totalStyle,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          statusText,
          style: theme.textTheme.bodySmall?.copyWith(
            color: const Color(0xFF52615E),
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }
}

class _TimeBlock extends StatelessWidget {
  const _TimeBlock({
    required this.label,
    required this.value,
    required this.labelStyle,
    required this.valueStyle,
  });

  final String label;
  final String value;
  final TextStyle? labelStyle;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: labelStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: valueStyle),
        ),
      ],
    );
  }
}

class LoudnessMeter extends StatelessWidget {
  const LoudnessMeter({
    super.key,
    required this.level,
    required this.peakLevel,
    required this.isRecording,
  });

  final double level;
  final double peakLevel;
  final bool isRecording;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalizedLevel = isRecording
        ? level.clamp(0.0, 1.0).toDouble()
        : 0.0;
    final normalizedPeak = isRecording
        ? math.max(peakLevel, normalizedLevel).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final dbText = normalizedLevel <= 0.001
        ? '-∞ dB'
        : '${(20 * math.log(normalizedLevel) / math.ln10).clamp(-60, 0).toStringAsFixed(0)} dB';

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: normalizedLevel),
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOutCubic,
      builder: (context, animatedLevel, _) {
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: normalizedPeak),
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          builder: (context, animatedPeak, _) {
            return _buildMeter(
              context: context,
              theme: theme,
              dbText: dbText,
              level: animatedLevel,
              peakLevel: animatedPeak,
            );
          },
        );
      },
    );
  }

  Widget _buildMeter({
    required BuildContext context,
    required ThemeData theme,
    required String dbText,
    required double level,
    required double peakLevel,
  }) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4F3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0E7E5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.graphic_eq, color: Color(0xFF1B7F79)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.loudnessTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text(
                dbText,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF52615E),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          RepaintBoundary(
            child: SizedBox(
              height: 46,
              width: double.infinity,
              child: CustomPaint(
                painter: _LoudnessMeterPainter(
                  level: level,
                  peakLevel: peakLevel,
                  active: isRecording,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoudnessMeterPainter extends CustomPainter {
  const _LoudnessMeterPainter({
    required this.level,
    required this.peakLevel,
    required this.active,
  });

  final double level;
  final double peakLevel;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final track = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(8),
    );
    canvas.drawRRect(track, Paint()..color = Colors.white);

    final segmentWidth = 5.0;
    final gap = 3.0;
    final segmentCount = math.max(
      1,
      (size.width / (segmentWidth + gap)).floor(),
    );
    final activeCount = (segmentCount * level).round();
    final peakIndex = (segmentCount * peakLevel).round().clamp(0, segmentCount);

    for (var index = 0; index < segmentCount; index++) {
      final ratio = index / math.max(1, segmentCount - 1);
      final x = index * (segmentWidth + gap);
      final segmentHeight = size.height * (0.36 + ratio * 0.54);
      final top = (size.height - segmentHeight) / 2;
      final isLit = active && index < activeCount;
      final paint = Paint()
        ..color = isLit ? _levelColor(ratio) : const Color(0xFFD9E1DF);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, top, segmentWidth, segmentHeight),
          const Radius.circular(3),
        ),
        paint,
      );
    }

    if (active && peakIndex > 0) {
      final x = ((peakIndex - 1) * (segmentWidth + gap)).clamp(
        0.0,
        size.width - 2,
      );
      final peakPaint = Paint()
        ..color = const Color(0xFF171A1D)
        ..strokeWidth = 2;
      canvas.drawLine(Offset(x, 4), Offset(x, size.height - 4), peakPaint);
    }
  }

  Color _levelColor(double ratio) {
    if (ratio > 0.82) {
      return const Color(0xFFD94B3D);
    }
    if (ratio > 0.62) {
      return const Color(0xFFE3A72F);
    }
    return const Color(0xFF1B7F79);
  }

  @override
  bool shouldRepaint(covariant _LoudnessMeterPainter oldDelegate) {
    return oldDelegate.level != level ||
        oldDelegate.peakLevel != peakLevel ||
        oldDelegate.active != active;
  }
}

class _LibraryPage extends StatefulWidget {
  const _LibraryPage({
    required this.groups,
    required this.clips,
    required this.playback,
    required this.onRefresh,
    required this.onPlay,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onSeek,
    required this.onSpeedChanged,
    required this.onCreateGroup,
    required this.onRenameGroup,
    required this.onDeleteGroup,
    required this.onRenameClip,
    required this.onDeleteClip,
    required this.onDeleteClips,
    required this.onMoveClip,
  });

  final List<RecordingGroup> groups;
  final List<ClipItem> clips;
  final PlaybackSnapshot playback;
  final Future<void> Function() onRefresh;
  final Future<void> Function(ClipItem clip) onPlay;
  final Future<void> Function() onPause;
  final Future<void> Function() onResume;
  final Future<void> Function() onStop;
  final Future<void> Function(int positionMs) onSeek;
  final Future<void> Function(double speed) onSpeedChanged;
  final Future<void> Function(String name) onCreateGroup;
  final Future<void> Function(RecordingGroup group, String name) onRenameGroup;
  final Future<void> Function(RecordingGroup group) onDeleteGroup;
  final Future<void> Function(ClipItem clip, String name) onRenameClip;
  final Future<void> Function(ClipItem clip) onDeleteClip;
  final Future<void> Function(List<ClipItem> clips) onDeleteClips;
  final Future<void> Function(ClipItem clip, RecordingGroup? group) onMoveClip;

  @override
  State<_LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<_LibraryPage> {
  static const List<double> _speedOptions = [
    0.1,
    0.25,
    0.5,
    0.75,
    1,
    1.25,
    1.5,
    2,
    3,
    4,
    8,
    16,
  ];

  final Set<String> _selectedClipUris = {};
  bool _isEditing = false;

  List<RecordingGroup> get groups => widget.groups;
  List<ClipItem> get clips => widget.clips;
  PlaybackSnapshot get playback => widget.playback;
  Future<void> Function() get onRefresh => widget.onRefresh;
  Future<void> Function(ClipItem clip) get onPlay => widget.onPlay;
  Future<void> Function() get onPause => widget.onPause;
  Future<void> Function() get onResume => widget.onResume;
  Future<void> Function() get onStop => widget.onStop;
  Future<void> Function(int positionMs) get onSeek => widget.onSeek;
  Future<void> Function(double speed) get onSpeedChanged =>
      widget.onSpeedChanged;
  Future<void> Function(String name) get onCreateGroup => widget.onCreateGroup;
  Future<void> Function(RecordingGroup group, String name) get onRenameGroup =>
      widget.onRenameGroup;
  Future<void> Function(RecordingGroup group) get onDeleteGroup =>
      widget.onDeleteGroup;
  Future<void> Function(ClipItem clip, String name) get onRenameClip =>
      widget.onRenameClip;
  Future<void> Function(ClipItem clip) get onDeleteClip => widget.onDeleteClip;
  Future<void> Function(List<ClipItem> clips) get onDeleteClips =>
      widget.onDeleteClips;
  Future<void> Function(ClipItem clip, RecordingGroup? group) get onMoveClip =>
      widget.onMoveClip;

  @override
  void didUpdateWidget(covariant _LibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final liveUris = clips.map((clip) => clip.uri).whereType<String>().toSet();
    _selectedClipUris.removeWhere((uri) => !liveUris.contains(uri));
    if (_selectedClipUris.isEmpty && liveUris.isEmpty && _isEditing) {
      _isEditing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rootClips = clips.where((clip) => clip.groupUri == null).toList();
    final groupSections = [
      _ClipGroupSection(title: l10n.unGrouped, group: null, clips: rootClips),
      for (final group in groups)
        _ClipGroupSection(
          title: group.name,
          group: group,
          clips: clips.where((clip) => clip.groupUri == group.uri).toList(),
        ),
    ];

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.library_music),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.libraryTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (_isEditing)
                Text(
                  '${_selectedClipUris.length}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              if (_isEditing)
                IconButton(
                  tooltip: l10n.selectAll,
                  onPressed: clips.isEmpty ? null : _selectAll,
                  icon: const Icon(Icons.select_all),
                )
              else
                IconButton(
                  tooltip: l10n.newGroup,
                  onPressed: () => _createGroup(context),
                  icon: const Icon(Icons.create_new_folder),
                ),
              if (_isEditing)
                IconButton(
                  tooltip: l10n.deleteSelected,
                  onPressed: _selectedClipUris.isEmpty
                      ? null
                      : () => _deleteSelectedClips(context),
                  icon: const Icon(Icons.delete_outline),
                ),
              IconButton(
                tooltip: _isEditing ? l10n.done : l10n.edit,
                onPressed: _toggleEditing,
                icon: Icon(_isEditing ? Icons.done : Icons.edit),
              ),
              if (!_isEditing)
                IconButton(
                  tooltip: l10n.refresh,
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: clips.isEmpty && groups.isEmpty
                ? Center(child: Text(l10n.emptyRecordings))
                : ListView(
                    children: [
                      for (final section in groupSections)
                        if (section.clips.isNotEmpty || section.group != null)
                          _buildSection(context, section),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, _ClipGroupSection section) {
    final group = section.group;
    return ExpansionTile(
      key: PageStorageKey('recording-group-${group?.uri ?? 'root'}'),
      initiallyExpanded: group == null || section.clips.isNotEmpty,
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      leading: Icon(group == null ? Icons.folder_open : Icons.folder),
      title: Text('${section.title} (${section.clips.length})'),
      trailing: group == null
          ? null
          : PopupMenuButton<String>(
              tooltip: context.l10n.groupActions,
              onSelected: (value) {
                switch (value) {
                  case 'rename':
                    _renameGroup(context, group);
                    break;
                  case 'delete':
                    _deleteGroup(context, group);
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'rename',
                  child: Text(context.l10n.renameGroup),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(context.l10n.deleteGroup),
                ),
              ],
            ),
      children: [
        if (section.clips.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(44, 0, 0, 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(context.l10n.emptyRecordings),
            ),
          )
        else
          for (final clip in section.clips) _buildClipTile(context, clip),
      ],
    );
  }

  Widget _buildClipTile(BuildContext context, ClipItem clip) {
    final isActive = clip.uri != null && clip.uri == playback.uri;
    final uri = clip.uri;
    final selected = uri != null && _selectedClipUris.contains(uri);
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          onTap: _isEditing ? () => _toggleClipSelection(clip) : null,
          leading: _isEditing
              ? Checkbox(
                  value: selected,
                  onChanged: uri == null
                      ? null
                      : (_) => _toggleClipSelection(clip),
                )
              : IconButton.filledTonal(
                  tooltip: context.l10n.preview,
                  onPressed: () => onPlay(clip),
                  icon: const Icon(Icons.play_arrow),
                ),
          title: Text(clip.name),
          subtitle: Text(
            [
              if (clip.durationSeconds != null)
                _formatDuration(clip.durationSeconds!),
              if (clip.size != null) _formatBytes(clip.size!),
              _formatTime(clip.createdAt),
            ].join(' · '),
          ),
          trailing: _isEditing
              ? null
              : PopupMenuButton<String>(
                  tooltip: context.l10n.recordingActions,
                  onSelected: (value) {
                    switch (value) {
                      case 'rename':
                        _renameClip(context, clip);
                        break;
                      case 'move':
                        _moveClip(context, clip);
                        break;
                      case 'delete':
                        _deleteClip(context, clip);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'rename',
                      child: Text(context.l10n.rename),
                    ),
                    PopupMenuItem(
                      value: 'move',
                      child: Text(context.l10n.moveToGroup),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(context.l10n.delete),
                    ),
                  ],
                ),
        ),
        if (isActive && !_isEditing)
          _PlaybackControls(
            playback: playback,
            speedOptions: _speedOptions,
            onPause: onPause,
            onResume: onResume,
            onStop: onStop,
            onSeek: onSeek,
            onSpeedChanged: onSpeedChanged,
          ),
        const Divider(height: 1),
      ],
    );
  }

  void _toggleEditing() {
    setState(() {
      _isEditing = !_isEditing;
      if (!_isEditing) {
        _selectedClipUris.clear();
      }
    });
  }

  void _toggleClipSelection(ClipItem clip) {
    final uri = clip.uri;
    if (uri == null) {
      return;
    }
    setState(() {
      if (_selectedClipUris.contains(uri)) {
        _selectedClipUris.remove(uri);
      } else {
        _selectedClipUris.add(uri);
      }
    });
  }

  void _selectAll() {
    final selectableUris = clips.map((clip) => clip.uri).whereType<String>();
    setState(() {
      if (_selectedClipUris.length == selectableUris.length) {
        _selectedClipUris.clear();
      } else {
        _selectedClipUris
          ..clear()
          ..addAll(selectableUris);
      }
    });
  }

  Future<void> _deleteSelectedClips(BuildContext context) async {
    final selectedClips = clips
        .where(
          (clip) => clip.uri != null && _selectedClipUris.contains(clip.uri),
        )
        .toList();
    if (selectedClips.isEmpty) {
      return;
    }
    final confirmed = await _confirm(
      context,
      title: context.l10n.batchDeleteRecordings,
      message: context.l10n.confirmBatchDeleteRecordings(selectedClips.length),
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    await onDeleteClips(selectedClips);
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedClipUris.clear();
      _isEditing = false;
    });
  }

  Future<void> _createGroup(BuildContext context) async {
    final name = await _promptText(
      context,
      title: context.l10n.newGroup,
      label: context.l10n.groupName,
    );
    if (name == null) {
      return;
    }
    await onCreateGroup(name);
  }

  Future<void> _renameGroup(BuildContext context, RecordingGroup group) async {
    final name = await _promptText(
      context,
      title: context.l10n.renameGroup,
      label: context.l10n.groupName,
      initialValue: group.name,
    );
    if (name == null) {
      return;
    }
    await onRenameGroup(group, name);
  }

  Future<void> _deleteGroup(BuildContext context, RecordingGroup group) async {
    final confirmed = await _confirm(
      context,
      title: context.l10n.deleteGroup,
      message: context.l10n.confirmDeleteGroup,
    );
    if (confirmed) {
      await onDeleteGroup(group);
    }
  }

  Future<void> _renameClip(BuildContext context, ClipItem clip) async {
    final name = await _promptText(
      context,
      title: context.l10n.renameRecording,
      label: context.l10n.fileName,
      initialValue: clip.name,
    );
    if (name == null) {
      return;
    }
    await onRenameClip(clip, name);
  }

  Future<void> _deleteClip(BuildContext context, ClipItem clip) async {
    final confirmed = await _confirm(
      context,
      title: context.l10n.deleteRecording,
      message: context.l10n.confirmDeleteRecording(clip.name),
    );
    if (confirmed) {
      await onDeleteClip(clip);
    }
  }

  Future<void> _moveClip(BuildContext context, ClipItem clip) async {
    final target = await showDialog<Object?>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.l10n.moveToGroup),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(_UngroupTarget.instance),
            child: Text(context.l10n.unGrouped),
          ),
          for (final group in groups)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(group),
              child: Text(group.name),
            ),
        ],
      ),
    );
    if (!context.mounted) {
      return;
    }
    if (target == null) {
      return;
    }
    await onMoveClip(clip, target is RecordingGroup ? target : null);
  }
}

enum _UngroupTarget { instance }

Future<String?> _promptText(
  BuildContext context, {
  required String title,
  required String label,
  String? initialValue,
}) async {
  final controller = TextEditingController(text: initialValue ?? '');
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) {
          Navigator.of(context).pop(controller.text.trim());
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: Text(context.l10n.ok),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(context.l10n.ok),
        ),
      ],
    ),
  );
  return confirmed == true;
}

class _ClipGroupSection {
  const _ClipGroupSection({
    required this.title,
    required this.group,
    required this.clips,
  });

  final String title;
  final RecordingGroup? group;
  final List<ClipItem> clips;
}

class _PlaybackControls extends StatefulWidget {
  const _PlaybackControls({
    required this.playback,
    required this.speedOptions,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onSeek,
    required this.onSpeedChanged,
  });

  final PlaybackSnapshot playback;
  final List<double> speedOptions;
  final Future<void> Function() onPause;
  final Future<void> Function() onResume;
  final Future<void> Function() onStop;
  final Future<void> Function(int positionMs) onSeek;
  final Future<void> Function(double speed) onSpeedChanged;

  @override
  State<_PlaybackControls> createState() => _PlaybackControlsState();
}

class _PlaybackControlsState extends State<_PlaybackControls> {
  Timer? _positionTimer;
  late int _positionMs;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _positionMs = widget.playback.positionMs;
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant _PlaybackControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDragging &&
        (oldWidget.playback.positionMs != widget.playback.positionMs ||
            oldWidget.playback.uri != widget.playback.uri)) {
      _positionMs = widget.playback.positionMs;
    }
    _syncTimer();
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    super.dispose();
  }

  void _syncTimer() {
    if (widget.playback.playing) {
      _positionTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _isDragging) {
          return;
        }
        final duration = widget.playback.durationMs;
        final next = _positionMs + (1000 * widget.playback.speed).round();
        setState(() {
          _positionMs = duration > 0 ? math.min(next, duration) : next;
        });
        if (duration > 0 && next >= duration) {
          unawaited(widget.onStop());
        }
      });
    } else {
      _positionTimer?.cancel();
      _positionTimer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.playback.durationMs <= 0
        ? 1
        : widget.playback.durationMs;
    final position = _positionMs.clamp(0, duration).toInt();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(_formatDuration(position ~/ 1000)),
              const Spacer(),
              Text(_formatDuration(widget.playback.durationMs ~/ 1000)),
            ],
          ),
          Slider(
            value: position.toDouble(),
            min: 0,
            max: duration.toDouble(),
            onChangeStart: (_) {
              _isDragging = true;
            },
            onChanged: (value) {
              setState(() {
                _positionMs = value.round();
              });
            },
            onChangeEnd: (value) {
              _isDragging = false;
              widget.onSeek(value.round());
            },
          ),
          Row(
            children: [
              IconButton(
                tooltip: widget.playback.playing
                    ? context.l10n.pause
                    : context.l10n.resume,
                onPressed: widget.playback.playing
                    ? widget.onPause
                    : widget.onResume,
                icon: Icon(
                  widget.playback.playing ? Icons.pause : Icons.play_arrow,
                ),
              ),
              IconButton(
                tooltip: context.l10n.stop,
                onPressed: widget.onStop,
                icon: const Icon(Icons.stop),
              ),
              const Spacer(),
              DropdownButton<double>(
                value: _nearestSpeed(
                  widget.playback.speed,
                  widget.speedOptions,
                ),
                items: [
                  for (final speed in widget.speedOptions)
                    DropdownMenuItem(
                      value: speed,
                      child: Text(
                        '${speed.toStringAsFixed(speed < 1 ? 2 : 1)}x',
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    widget.onSpeedChanged(value);
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  double _nearestSpeed(double speed, List<double> options) {
    return options.reduce(
      (best, value) =>
          (value - speed).abs() < (best - speed).abs() ? value : best,
    );
  }
}

class _ProcessingPage extends StatefulWidget {
  const _ProcessingPage({required this.clips, required this.onProcess});

  final List<ClipItem> clips;
  final Future<bool> Function({
    required ClipItem clip,
    required double gainDb,
    required String format,
    required int mp3BitrateKbps,
  })
  onProcess;

  @override
  State<_ProcessingPage> createState() => _ProcessingPageState();
}

class _ProcessingPageState extends State<_ProcessingPage> {
  static const List<int> _bitrateOptions = [64, 96, 128, 160, 192, 256, 320];

  String? _selectedUri;
  double _gainDb = 0;
  String _format = 'mp3';
  int _mp3BitrateKbps = 128;
  bool _processing = false;
  String? _message;

  ClipItem? get _selectedClip {
    for (final clip in widget.clips) {
      if (clip.uri == _selectedUri) {
        return clip;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _selectedUri = widget.clips
        .map((clip) => clip.uri)
        .whereType<String>()
        .firstOrNull;
  }

  @override
  void didUpdateWidget(covariant _ProcessingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final uris = widget.clips.map((clip) => clip.uri).whereType<String>();
    if (_selectedUri == null || !uris.contains(_selectedUri)) {
      _selectedUri = uris.isEmpty ? null : uris.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListView(
      children: [
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _selectedUri,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.sourceRecording,
                  prefixIcon: const Icon(Icons.library_music),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                ),
                items: [
                  for (final clip in widget.clips)
                    if (clip.uri != null)
                      DropdownMenuItem(
                        value: clip.uri,
                        child: Text(clip.name, overflow: TextOverflow.ellipsis),
                      ),
                ],
                selectedItemBuilder: (context) => [
                  for (final clip in widget.clips)
                    if (clip.uri != null)
                      Text(
                        clip.name,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                ],
                onChanged: _processing
                    ? null
                    : (value) => setState(() => _selectedUri = value),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Icon(Icons.volume_up),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.gainDb(
                        '${_gainDb >= 0 ? '+' : ''}${_gainDb.toStringAsFixed(1)}',
                      ),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _gainDb,
                min: -24,
                max: 24,
                divisions: 96,
                label:
                    '${_gainDb >= 0 ? '+' : ''}${_gainDb.toStringAsFixed(1)} dB',
                onChanged: _processing
                    ? null
                    : (value) => setState(() => _gainDb = value),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _format,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.outputFormat,
                  prefixIcon: const Icon(Icons.audio_file),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 'mp3', child: Text('MP3')),
                  DropdownMenuItem(value: 'wav', child: Text('WAV')),
                ],
                onChanged: _processing
                    ? null
                    : (value) => setState(() => _format = value ?? 'mp3'),
              ),
              if (_format == 'mp3') ...[
                const SizedBox(height: 14),
                DropdownButtonFormField<int>(
                  initialValue: _mp3BitrateKbps,
                  decoration: InputDecoration(
                    labelText: l10n.mp3Bitrate,
                    prefixIcon: const Icon(Icons.speed),
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                  ),
                  items: [
                    for (final value in _bitrateOptions)
                      DropdownMenuItem(
                        value: value,
                        child: Text('$value kbps'),
                      ),
                  ],
                  onChanged: _processing
                      ? null
                      : (value) => setState(
                          () => _mp3BitrateKbps = value ?? _mp3BitrateKbps,
                        ),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _processing || _selectedClip == null
                    ? null
                    : _processSelectedClip,
                icon: _processing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_fix_high),
                label: Text(
                  _processing ? l10n.processing : l10n.generateProcessedCopy,
                ),
              ),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(_message!, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _processSelectedClip() async {
    final clip = _selectedClip;
    if (clip == null) {
      return;
    }
    setState(() {
      _processing = true;
      _message = null;
    });
    final ok = await widget.onProcess(
      clip: clip,
      gainDb: _gainDb,
      format: _format,
      mp3BitrateKbps: _mp3BitrateKbps,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _processing = false;
      _message = ok
          ? context.l10n.processingComplete
          : context.l10n.processingFailed;
    });
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) {
      return null;
    }
    return iterator.current;
  }
}

class _BufferMinutesField extends StatefulWidget {
  const _BufferMinutesField({
    required this.bufferSeconds,
    required this.onChanged,
  });

  final int bufferSeconds;
  final ValueChanged<int> onChanged;

  @override
  State<_BufferMinutesField> createState() => _BufferMinutesFieldState();
}

class _BufferMinutesFieldState extends State<_BufferMinutesField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  int get _minutes => (widget.bufferSeconds / 60).round().clamp(1, 1440);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _minutes.toString());
    _focusNode = FocusNode()..addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant _BufferMinutesField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bufferSeconds != widget.bufferSeconds &&
        !_focusNode.hasFocus) {
      _controller.text = _minutes.toString();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) {
      _applyValue();
    }
  }

  void _applyValue() {
    final parsed = int.tryParse(_controller.text.trim()) ?? _minutes;
    final minutes = parsed.clamp(1, 1440).toInt();
    _controller.text = minutes.toString();
    if (minutes != _minutes) {
      widget.onChanged(minutes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onSubmitted: (_) => _applyValue(),
      decoration: InputDecoration(
        labelText: l10n.bufferDurationMinutes,
        helperText: l10n.bufferDurationHelper,
        suffixText: l10n.minutesUnit,
        prefixIcon: const Icon(Icons.schedule),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
    );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({
    required this.folderUri,
    required this.sampleRate,
    required this.bufferSeconds,
    required this.cacheBytes,
    required this.lockRecordingTrigger,
    required this.languageMode,
    required this.onChooseFolder,
    required this.onUpdateAudioSettings,
    required this.onLockRecordingTriggerChanged,
    required this.onClearCache,
    required this.onLanguageModeChanged,
    required this.onOpenUrl,
  });

  static const List<int> _sampleRateOptions = [8000, 16000, 24000, 48000];
  static const String _repositoryUrl =
      'https://github.com/MaidTendouAris/EchoClip';
  static const String _issuesUrl =
      'https://github.com/MaidTendouAris/EchoClip/issues';

  final String? folderUri;
  final int sampleRate;
  final int bufferSeconds;
  final int cacheBytes;
  final LockRecordingTrigger lockRecordingTrigger;
  final UiLanguageMode languageMode;
  final Future<void> Function() onChooseFolder;
  final Future<void> Function({int? sampleRate, int? bufferSeconds})
  onUpdateAudioSettings;
  final Future<void> Function(LockRecordingTrigger trigger)
  onLockRecordingTriggerChanged;
  final Future<Map<String, Object?>> Function() onClearCache;
  final Future<void> Function(UiLanguageMode mode) onLanguageModeChanged;
  final Future<void> Function(String url) onOpenUrl;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final estimatedPcmBytes = sampleRate * bufferSeconds * 2;

    return ListView(
      children: [
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder),
                title: Text(l10n.recordingFolder),
                subtitle: Text(folderUri ?? l10n.notSelected),
                trailing: FilledButton.icon(
                  onPressed: onChooseFolder,
                  icon: const Icon(Icons.folder_open),
                  label: Text(l10n.change),
                ),
              ),
              const Divider(height: 28),
              Text(
                l10n.languageSettings,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<UiLanguageMode>(
                key: ValueKey(languageMode),
                initialValue: languageMode,
                decoration: InputDecoration(
                  labelText: l10n.appLanguage,
                  prefixIcon: const Icon(Icons.language),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                ),
                items: [
                  for (final mode in UiLanguageMode.values)
                    DropdownMenuItem(
                      value: mode,
                      child: Text(_languageModeLabel(l10n, mode)),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  onLanguageModeChanged(value);
                },
              ),
              const Divider(height: 28),
              Text(
                l10n.recordingSettings,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: sampleRate,
                decoration: InputDecoration(
                  labelText: l10n.androidSampleRate,
                  prefixIcon: const Icon(Icons.graphic_eq),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                ),
                items: [
                  for (final value in _sampleRateOptions)
                    DropdownMenuItem(
                      value: value,
                      child: Text(_formatHertz(value)),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  onUpdateAudioSettings(sampleRate: value);
                },
              ),
              const SizedBox(height: 14),
              _BufferMinutesField(
                bufferSeconds: bufferSeconds,
                onChanged: (minutes) {
                  onUpdateAudioSettings(bufferSeconds: minutes * 60);
                },
              ),
              const SizedBox(height: 14),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.memory),
                title: Text(
                  l10n.estimatedPcmBuffer(_formatBytes(estimatedPcmBytes)),
                ),
                subtitle: Text(
                  l10n.pcmBufferSubtitle(_formatHertz(sampleRate)),
                ),
              ),
              const Divider(height: 28),
              Text(
                l10n.lockRecordingSettings,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<LockRecordingTrigger>(
                initialValue: lockRecordingTrigger,
                decoration: InputDecoration(
                  labelText: l10n.lockRecordingTrigger,
                  prefixIcon: const Icon(Icons.screen_lock_portrait),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                ),
                items: [
                  DropdownMenuItem(
                    value: LockRecordingTrigger.screenOff,
                    child: Text(l10n.lockRecordingTriggerScreenOff),
                  ),
                  DropdownMenuItem(
                    value: LockRecordingTrigger.keyguardLocked,
                    child: Text(l10n.lockRecordingTriggerKeyguard),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  onLockRecordingTriggerChanged(value);
                },
              ),
              const Divider(height: 28),
              Text(
                l10n.cacheTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.storage),
                title: Text(l10n.currentCacheSize(_formatBytes(cacheBytes))),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.cleaning_services),
                title: Text(l10n.clearCache),
                subtitle: Text(l10n.clearCacheSubtitle),
                trailing: IconButton.filledTonal(
                  tooltip: l10n.clearCache,
                  onPressed: () => _confirmClearCache(context),
                  icon: const Icon(Icons.delete_sweep),
                ),
              ),
              const Divider(height: 28),
              Text(
                l10n.aboutProject,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.code),
                title: Text(l10n.githubRepository),
                subtitle: Text(l10n.githubRepositorySubtitle),
                onTap: () => onOpenUrl(_repositoryUrl),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.balance),
                title: Text(l10n.licenseTitle),
                subtitle: Text(l10n.licenseSubtitle),
                onTap: () => onOpenUrl('$_repositoryUrl/blob/main/LICENSE'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.bug_report),
                title: Text(l10n.issueFeedback),
                subtitle: Text(l10n.issueFeedbackSubtitle),
                onTap: () => onOpenUrl(_issuesUrl),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmClearCache(BuildContext context) async {
    final confirmed = await _confirm(
      context,
      title: context.l10n.clearCache,
      message: context.l10n.confirmClearCache,
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    final result = await onClearCache();
    if (!context.mounted) {
      return;
    }
    final deletedBytes = result['deletedBytes'];
    final activePreserved = result['activeReplayCachePreserved'] == true;
    final l10n = context.l10n;
    final message = result['ok'] == true
        ? (activePreserved
              ? l10n.cacheClearedActivePreserved(
                  _formatBytes(deletedBytes is int ? deletedBytes : 0),
                )
              : l10n.cacheCleared(
                  _formatBytes(deletedBytes is int ? deletedBytes : 0),
                ))
        : l10n.cacheClearFailed(result['error']?.toString() ?? 'unknown');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE1E7E5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}

enum SaveDurationMode { preset, custom }

class _SaveSecondsField extends StatefulWidget {
  const _SaveSecondsField({required this.seconds, required this.onChanged});

  final int seconds;
  final ValueChanged<int> onChanged;

  @override
  State<_SaveSecondsField> createState() => _SaveSecondsFieldState();
}

class _SaveSecondsFieldState extends State<_SaveSecondsField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  int get _seconds => widget.seconds.clamp(1, 86400).toInt();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _seconds.toString());
    _focusNode = FocusNode()..addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant _SaveSecondsField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seconds != widget.seconds && !_focusNode.hasFocus) {
      _controller.text = _seconds.toString();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) {
      _applyValue();
    }
  }

  void _applyValue() {
    final parsed = int.tryParse(_controller.text.trim()) ?? _seconds;
    final seconds = parsed.clamp(1, 86400).toInt();
    _controller.text = seconds.toString();
    if (seconds != _seconds) {
      widget.onChanged(seconds);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SizedBox(
      width: 184,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onSubmitted: (_) => _applyValue(),
        decoration: InputDecoration(
          labelText: l10n.customSaveSeconds,
          helperText: l10n.customSaveSecondsHelper,
          suffixText: l10n.secondsUnit,
          prefixIcon: const Icon(Icons.timer_outlined),
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(28)),
          ),
        ),
      ),
    );
  }
}

class SaveDurationOption {
  const SaveDurationOption(this.seconds);

  final int seconds;
}

class RecordingGroup {
  const RecordingGroup({required this.name, required this.uri});

  factory RecordingGroup.fromNative(Map<dynamic, dynamic> value) {
    return RecordingGroup(
      name: value['name']?.toString() ?? 'Unnamed group',
      uri: value['uri']?.toString() ?? '',
    );
  }

  final String name;
  final String uri;
}

class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.playing,
    required this.paused,
    required this.uri,
    required this.positionMs,
    required this.durationMs,
    required this.speed,
  });

  factory PlaybackSnapshot.fromNative(
    Map<dynamic, dynamic>? value, {
    required PlaybackSnapshot fallback,
  }) {
    if (value == null) {
      return fallback;
    }
    final position = value['positionMs'];
    final duration = value['durationMs'];
    final speed = value['speed'];
    return PlaybackSnapshot(
      playing: value['playing'] == true,
      paused: value['paused'] == true,
      uri: value['uri']?.toString(),
      positionMs: position is int ? position : fallback.positionMs,
      durationMs: duration is int ? duration : fallback.durationMs,
      speed: speed is num ? speed.toDouble() : fallback.speed,
    );
  }

  final bool playing;
  final bool paused;
  final String? uri;
  final int positionMs;
  final int durationMs;
  final double speed;

  PlaybackSnapshot copyWith({
    bool? playing,
    bool? paused,
    String? uri,
    int? positionMs,
    int? durationMs,
    double? speed,
  }) {
    return PlaybackSnapshot(
      playing: playing ?? this.playing,
      paused: paused ?? this.paused,
      uri: uri ?? this.uri,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      speed: speed ?? this.speed,
    );
  }
}

class ClipItem {
  const ClipItem({
    required this.name,
    required this.createdAt,
    required this.uri,
    required this.parentUri,
    required this.groupName,
    required this.groupUri,
    required this.size,
    this.durationSeconds,
  });

  factory ClipItem.fromNative(Map<dynamic, dynamic> value) {
    final modified = value['modified'];
    final size = value['size'];
    return ClipItem(
      name: value['name']?.toString() ?? 'recording.wav',
      uri: value['uri']?.toString(),
      parentUri: value['parentUri']?.toString(),
      groupName: value['groupName']?.toString(),
      groupUri: value['groupUri']?.toString(),
      size: size is int ? size : null,
      createdAt: modified is int && modified > 0
          ? DateTime.fromMillisecondsSinceEpoch(modified)
          : DateTime.now(),
    );
  }

  final String name;
  final int? durationSeconds;
  final DateTime createdAt;
  final String? uri;
  final String? parentUri;
  final String? groupName;
  final String? groupUri;
  final int? size;
}

String _formatDuration(int totalSeconds) {
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

String _formatDurationMillis(int totalMillis) {
  final safeMillis = math.max(0, totalMillis);
  final totalSeconds = safeMillis ~/ 1000;
  final centiseconds = (safeMillis % 1000) ~/ 10;
  final seconds = totalSeconds % 60;
  final minutes = (totalSeconds ~/ 60) % 60;
  final hours = totalSeconds ~/ 3600;

  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}.'
      '${centiseconds.toString().padLeft(2, '0')}';
}

String _formatSessionStart(DateTime time) {
  return '${time.year}.'
      '${time.month.toString().padLeft(2, '0')}.'
      '${time.day.toString().padLeft(2, '0')} '
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}

String _formatDurationLabel(AppLocalizations l10n, int totalSeconds) {
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  if (hours == 0) {
    if (minutes == 0) {
      return l10n.secondsShort(totalSeconds);
    }
    return l10n.minutesShort(minutes);
  }
  if (minutes == 0) {
    return l10n.hoursShort(hours);
  }
  return l10n.hoursMinutesShort(hours, minutes);
}

String _formatHertz(int sampleRate) {
  if (sampleRate >= 1000 && sampleRate % 1000 == 0) {
    return '${sampleRate ~/ 1000} kHz';
  }
  return '$sampleRate Hz';
}

String _formatTime(DateTime time) {
  return '${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final kb = bytes / 1024;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(1)} KB';
  }
  final mb = kb / 1024;
  if (mb < 1024) {
    return '${mb.toStringAsFixed(1)} MB';
  }
  return '${(mb / 1024).toStringAsFixed(2)} GB';
}
