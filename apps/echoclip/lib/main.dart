import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:window_manager/window_manager.dart';

import 'l10n/app_localizations.dart';
import 'services/windows_replay_service.dart';

part 'models/app_models.dart';
part 'services/replay_service_client.dart';
part 'utils/formatters.dart';
part 'pages/recorder_page.dart';
part 'widgets/loudness_meter.dart';
part 'pages/library_page.dart';
part 'pages/processing_page.dart';
part 'pages/settings_page.dart';
part 'widgets/shared_widgets.dart';

bool _windowsDesktopPluginsReady = false;

const Size _desktopInitialWindowSize = Size(1080, 720);
const Size _desktopMinimumWindowSize = Size(960, 640);
const double _desktopWindowAspectRatio = 3 / 2;
const double _wideNavigationBreakpoint = 840;
const double _desktopNavigationWidth = 232;
const Key _desktopNavigationKey = ValueKey<String>('navigation.desktop');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_isDesktopPlatform) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: _desktopInitialWindowSize,
        minimumSize: _desktopMinimumWindowSize,
        center: true,
        skipTaskbar: false,
        title: 'EchoClip',
      ),
      () async {
        await windowManager.setAspectRatio(_desktopWindowAspectRatio);
        if (_isWindows) {
          await windowManager.setPreventClose(true);
        }
        await windowManager.show();
        await windowManager.focus();
      },
    );
    _windowsDesktopPluginsReady = _isWindows;
  }
  runApp(const EchoClipApp());
}

class EchoClipApp extends StatefulWidget {
  const EchoClipApp({super.key});

  @override
  State<EchoClipApp> createState() => _EchoClipAppState();
}

class _EchoClipAppState extends State<EchoClipApp> {
  static const ReplayServiceClient _replayClient = ReplayServiceClient();

  UiLanguageMode _languageMode = UiLanguageMode.system;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLanguageMode());
  }

  Future<void> _loadLanguageMode() async {
    if (!_supportsReplayPlatform) {
      return;
    }
    final mode = await _replayClient.getUiLanguageMode();
    if (!mounted) {
      return;
    }
    setState(() {
      _languageMode = mode;
    });
  }

  Future<void> _setLanguageMode(UiLanguageMode mode) async {
    setState(() {
      _languageMode = mode;
    });
    if (!_supportsReplayPlatform) {
      return;
    }
    final applied = await _replayClient.setUiLanguageMode(mode);
    if (!mounted) {
      return;
    }
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
        // Flutter's generic Windows fallback can mix Latin and CJK faces in a
        // single label. Prefer the native UI face there and keep explicit CJK
        // fallbacks for every platform so weights and baselines stay stable.
        fontFamily: _isWindows ? 'Microsoft YaHei UI' : null,
        fontFamilyFallback: const [
          'Microsoft YaHei UI',
          'Microsoft YaHei',
          'Noto Sans CJK SC',
          'Noto Sans SC',
          'Segoe UI',
        ],
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

extension _L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}

final DateTime _epochDateTime = DateTime.fromMillisecondsSinceEpoch(0);

bool get _supportsReplayPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.windows);

bool get _isWindows =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

bool get _isDesktopPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);

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

class _EchoClipHomeState extends State<EchoClipHome>
    with WidgetsBindingObserver, WindowListener, tray.TrayListener {
  static const ReplayServiceClient _replayClient = ReplayServiceClient();

  final HotKey _saveRecentHotKey = HotKey(
    identifier: 'echoclip.save_recent_30_seconds',
    key: PhysicalKeyboardKey.keyS,
    modifiers: const [HotKeyModifier.control, HotKeyModifier.alt],
    scope: HotKeyScope.system,
  );

  AppSection _section = AppSection.recorder;
  Timer? _statusTimer;
  Timer? _meterTimer;
  bool _meterPollInFlight = false;
  bool _hotKeySaveInFlight = false;
  bool _isQuitting = false;
  bool _isBuffering = false;
  bool _serviceActive = false;
  bool _folderSelected = false;
  String? _folderUri;
  int _sampleRate = 16000;
  int _bufferSeconds = 1800;
  List<AudioInputDevice> _audioInputDevices = const [];
  bool _microphoneEnabled = true;
  bool _systemAudioEnabled = false;
  String? _microphoneDeviceId;
  bool _systemAudioSupported = false;
  bool _inputDeviceSelectionSupported = false;
  bool _audioSourceSettingsBusy = false;
  int _cacheBytes = 0;
  RecordingMode _recordingMode = RecordingMode.standard;
  LockRecordingTrigger _lockRecordingTrigger = LockRecordingTrigger.screenOff;
  String _evidenceState = 'off';
  String? _evidenceLastStopReason;
  String _serviceState = 'stopped';
  String _platformStatus = 'Recording service stopped';
  final ValueNotifier<MeterSnapshot> _meterSnapshot =
      ValueNotifier<MeterSnapshot>(
        MeterSnapshot(
          running: false,
          recordedMillis: 0,
          sessionRecordedMillis: 0,
          sessionStartedAt: _epochDateTime,
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
    WidgetsBinding.instance.addObserver(this);
    if (_windowsDesktopPluginsReady) {
      windowManager.addListener(this);
      tray.trayManager.addListener(this);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_initializeWindowsDesktop());
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapPlatform());
    _statusTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      _refreshReplayStatus();
    });
    _meterTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _tickMeter();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_windowsDesktopPluginsReady) {
      windowManager.removeListener(this);
      tray.trayManager.removeListener(this);
      unawaited(_unregisterSaveHotKey());
    }
    _statusTimer?.cancel();
    _meterTimer?.cancel();
    _meterSnapshot.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant EchoClipHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_windowsDesktopPluginsReady &&
        oldWidget.languageMode != widget.languageMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_configureWindowsTray());
        }
      });
    }
  }

  Future<void> _initializeWindowsDesktop() async {
    try {
      await _configureWindowsTray();
      await hotKeyManager.unregisterAll();
      await hotKeyManager.register(
        _saveRecentHotKey,
        keyDownHandler: (_) => unawaited(_saveRecentFromHotKey()),
      );
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _platformStatus = context.l10n.serviceError(error.code);
      });
    }
  }

  Future<void> _configureWindowsTray() async {
    if (!mounted || !_windowsDesktopPluginsReady) {
      return;
    }
    final l10n = context.l10n;
    await tray.trayManager.setIcon('windows/runner/resources/app_icon.ico');
    await tray.trayManager.setToolTip(l10n.appTitle);
    await tray.trayManager.setContextMenu(
      tray.Menu(
        items: [
          tray.MenuItem(key: 'show_window', label: l10n.showWindow),
          tray.MenuItem(key: 'hide_window', label: l10n.hideWindow),
          tray.MenuItem.separator(),
          tray.MenuItem(key: 'exit_app', label: l10n.exitApp),
        ],
      ),
    );
  }

  Future<void> _unregisterSaveHotKey() async {
    try {
      await hotKeyManager.unregister(_saveRecentHotKey);
    } on PlatformException {
      // The native registration is already gone while the app is shutting down.
    }
  }

  Future<void> _saveRecentFromHotKey() async {
    if (_hotKeySaveInFlight) {
      return;
    }
    _hotKeySaveInFlight = true;
    try {
      if (!_folderSelected) {
        await _showWindowsWindow();
      }
      await _saveClip(30);
    } finally {
      _hotKeySaveInFlight = false;
    }
  }

  Future<void> _showWindowsWindow() async {
    await windowManager.show();
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }
    await windowManager.focus();
  }

  Future<void> _hideWindowsWindow() => windowManager.hide();

  Future<void> _exitWindowsApplication() async {
    if (_isQuitting) {
      return;
    }
    _isQuitting = true;
    try {
      if (_serviceActive) {
        await _replayClient.stopReplay();
      }
    } on PlatformException {
      // The process still needs to exit if the recording backend is unavailable.
    }
    await _unregisterSaveHotKey();
    await tray.trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  @override
  void onWindowClose() {
    if (!_isQuitting) {
      unawaited(_hideWindowsWindow());
    }
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_showWindowsWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(tray.trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(tray.MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show_window':
        unawaited(_showWindowsWindow());
        break;
      case 'hide_window':
        unawaited(_hideWindowsWindow());
        break;
      case 'exit_app':
        unawaited(_exitWindowsApplication());
        break;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_supportsReplayPlatform) {
      return;
    }
    unawaited(_refreshAfterResume());
  }

  Future<void> _refreshAfterResume() async {
    await _refreshReplayStatus();
    await _refreshRecordingFolder();
    await _loadAudioSourceSettings();
    await _loadRecordings();
    await _loadCacheStatus();
  }

  Future<void> _bootstrapPlatform() async {
    if (!_supportsReplayPlatform) {
      return;
    }

    await _refreshRecordingFolder(promptIfMissing: true);
    await _loadAudioSettings();
    await _loadAudioSourceSettings();
    await _loadRecordingModeSettings();
    await _loadCacheStatus();
    await _loadRecordings();
    await _refreshReplayStatus();
  }

  Future<void> _loadAudioSettings() async {
    if (!_supportsReplayPlatform) {
      return;
    }

    final settings = await _replayClient.getAudioSettings();
    if (!mounted) {
      return;
    }

    setState(() {
      _sampleRate = settings.sampleRate;
      _bufferSeconds = settings.bufferSeconds;
    });
  }

  Future<void> _loadAudioSourceSettings() async {
    if (!_supportsReplayPlatform) {
      return;
    }

    final settings = await _replayClient.getAudioSourceSettings();
    final devices = settings.inputDeviceSelectionSupported
        ? await _replayClient.listAudioInputDevices()
        : const <AudioInputDevice>[];
    if (!mounted) {
      return;
    }

    setState(() {
      _microphoneEnabled = settings.microphoneEnabled;
      _systemAudioEnabled = settings.systemAudioEnabled;
      _microphoneDeviceId = settings.microphoneDeviceId;
      _systemAudioSupported = settings.systemAudioSupported;
      _inputDeviceSelectionSupported = settings.inputDeviceSelectionSupported;
      _audioInputDevices = devices
          .where((device) => device.id.isNotEmpty)
          .toList();
    });
  }

  Future<void> _refreshAudioInputDevices() async {
    if (!_supportsReplayPlatform || !_inputDeviceSelectionSupported) {
      return;
    }
    final devices = await _replayClient.listAudioInputDevices();
    if (!mounted) {
      return;
    }
    setState(() {
      _audioInputDevices = devices
          .where((device) => device.id.isNotEmpty)
          .toList();
    });
  }

  Future<void> _loadRecordingModeSettings() async {
    if (!_supportsReplayPlatform) {
      return;
    }

    final settings = await _replayClient.getRecordingModeSettings();
    if (!mounted) {
      return;
    }

    setState(() {
      _recordingMode = settings.mode;
      _lockRecordingTrigger = settings.trigger;
    });
  }

  Future<void> _setRecordingMode(RecordingMode mode) async {
    if (_recordingMode == mode) {
      return;
    }

    if (!_supportsReplayPlatform) {
      return;
    }

    final previousMode = _recordingMode;
    setState(() {
      _recordingMode = mode;
      _platformStatus = _recordingModeStatusText(context.l10n);
    });

    try {
      final result = await _replayClient.setRecordingModeSettings(
        mode: mode,
        trigger: _lockRecordingTrigger,
      );
      if (!mounted) {
        return;
      }
      _applyReplayStatusResponse(result);
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
        _platformStatus = context.l10n.serviceError(error.code);
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

    if (!_supportsReplayPlatform) {
      return;
    }

    try {
      await _replayClient.setRecordingModeSettings(
        mode: _recordingMode,
        trigger: trigger,
      );
      if (_recordingMode == RecordingMode.lockscreen && _serviceActive) {
        await _replayClient.startReplay(mode: _recordingMode, trigger: trigger);
      }
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _platformStatus = context.l10n.serviceError(error.code);
      });
    }
  }

  Future<void> _updateAudioSettings({
    int? sampleRate,
    int? bufferSeconds,
  }) async {
    final nextSampleRate = sampleRate ?? _sampleRate;
    final nextBufferSeconds = bufferSeconds ?? _bufferSeconds;

    if (!_supportsReplayPlatform) {
      return;
    }

    final response = await _replayClient.setAudioSettings(
      sampleRate: nextSampleRate,
      bufferSeconds: nextBufferSeconds,
    );
    if (!mounted) {
      return;
    }

    final l10n = context.l10n;
    setState(() {
      _sampleRate = response.sampleRate;
      _bufferSeconds = response.bufferSeconds;
      _platformStatus = response.applied
          ? l10n.recordingSettingsSaved
          : l10n.settingsSavedNextRecording;
    });
  }

  Future<void> _updateAudioSourceSettings({
    required bool microphoneEnabled,
    required bool systemAudioEnabled,
    String? microphoneDeviceId,
  }) async {
    if (_audioSourceSettingsBusy || !_supportsReplayPlatform) {
      return;
    }
    if (!microphoneEnabled && !systemAudioEnabled) {
      _showCurrentPageSnackBar(context.l10n.audioSourceRequired);
      return;
    }

    setState(() => _audioSourceSettingsBusy = true);
    try {
      final response = await _replayClient.setAudioSourceSettings(
        microphoneEnabled: microphoneEnabled,
        systemAudioEnabled: systemAudioEnabled,
        microphoneDeviceId: microphoneDeviceId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _microphoneEnabled = response.microphoneEnabled;
        _systemAudioEnabled = response.systemAudioEnabled;
        _microphoneDeviceId = response.microphoneDeviceId;
        _systemAudioSupported = response.systemAudioSupported;
        _inputDeviceSelectionSupported = response.inputDeviceSelectionSupported;
        _platformStatus = response.applied
            ? context.l10n.audioSourceSettingsSaved
            : context.l10n.settingsSavedNextRecording;
      });
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _platformStatus = context.l10n.serviceError(error.code);
      });
      _showCurrentPageSnackBar(_platformStatus);
    } finally {
      if (mounted) {
        setState(() => _audioSourceSettingsBusy = false);
      }
    }
  }

  Future<void> _refreshRecordingFolder({bool promptIfMissing = false}) async {
    if (!_supportsReplayPlatform) {
      return;
    }

    final response = await _replayClient.getRecordingFolder();
    final selected = response.selected;
    if (!mounted) {
      return;
    }

    setState(() {
      _folderSelected = selected;
      _folderUri = response.uri;
    });

    if (!selected && promptIfMissing) {
      await _chooseRecordingFolder();
    }
  }

  Future<void> _chooseRecordingFolder() async {
    if (!_supportsReplayPlatform) {
      return;
    }

    final response = await _replayClient.chooseRecordingFolder();
    if (!mounted) {
      return;
    }

    final selected = response.selected;
    final l10n = context.l10n;
    setState(() {
      _folderSelected = selected;
      _folderUri = response.uri;
      _platformStatus = selected
          ? l10n.recordingFolderReady
          : l10n.folderSetupError(response.error ?? 'unknown');
    });
    if (selected) {
      await _loadRecordings();
    }
  }

  Future<void> _refreshReplayStatus() async {
    if (!_supportsReplayPlatform) {
      return;
    }

    try {
      final response = await _replayClient.getReplayStatus();
      if (!mounted) {
        return;
      }

      final l10n = context.l10n;
      setState(() {
        _isBuffering = response.running;
        _serviceActive = response.serviceActive;
        _recordingMode = response.recordingMode;
        _lockRecordingTrigger = response.lockRecordingTrigger;
        _evidenceState = response.evidenceState;
        _evidenceLastStopReason = response.evidenceLastStopReason;
        _serviceState = response.serviceState;
        _platformStatus = _friendlyRecordingStatus(
          l10n: l10n,
          running: response.running,
          serviceActive: response.serviceActive,
          recordingMode: _recordingMode,
          lockRecordingTrigger: _lockRecordingTrigger,
          evidenceState: _evidenceState,
          evidenceLastStopReason: _evidenceLastStopReason,
          serviceState: _serviceState,
          rawError: response.captureError,
        );
        if (response.sampleRate != null) {
          _sampleRate = response.sampleRate!;
        }
        if (response.bufferSeconds != null) {
          _bufferSeconds = response.bufferSeconds!;
        }
        if (response.cacheBytes != null) {
          _cacheBytes = response.cacheBytes!;
        }
      });
      _updateMeterSnapshot(
        running: response.running,
        recordedMillis: response.availableMillis,
        sessionStartedUnixMillis: response.sessionStartedUnixMillis,
      );
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _platformStatus = context.l10n.serviceError(error.code);
      });
    }
  }

  void _applyReplayStatusResponse(ReplayCommandResult response) {
    setState(() {
      _isBuffering = response.running;
      _serviceActive = response.serviceActive;
      if (response.recordingMode != null) {
        _recordingMode = response.recordingMode!;
      }
      if (response.lockRecordingTrigger != null) {
        _lockRecordingTrigger = response.lockRecordingTrigger!;
      }
      if (response.evidenceState != null) {
        _evidenceState = response.evidenceState!;
      } else if (!response.serviceActive) {
        _evidenceState = 'off';
      }
      _evidenceLastStopReason = response.evidenceLastStopReason;
      _serviceState = response.serviceState ?? _serviceState;
      _platformStatus = response.error == null
          ? _recordingModeStatusText(context.l10n)
          : context.l10n.serviceError(response.error!);
    });
  }

  String _recordingModeStatusText(AppLocalizations l10n) {
    if (_recordingMode == RecordingMode.standard) {
      return _isBuffering
          ? l10n.recordingStatusNormal
          : l10n.recordingStatusPaused;
    }
    return _friendlyRecordingStatus(
      l10n: l10n,
      running: _isBuffering,
      serviceActive: _serviceActive,
      recordingMode: _recordingMode,
      lockRecordingTrigger: _lockRecordingTrigger,
      evidenceState: _evidenceState,
      evidenceLastStopReason: _evidenceLastStopReason,
      serviceState: _serviceState,
    );
  }

  void _tickMeter() {
    if (_supportsReplayPlatform) {
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
  }

  Future<void> _refreshMeterStatus() async {
    if (_meterPollInFlight) {
      return;
    }

    _meterPollInFlight = true;
    try {
      final response = await _replayClient.getMeterStatus();
      if (!mounted) {
        return;
      }

      _updateMeterSnapshot(
        running: response.running,
        recordedMillis: response.availableMillis,
        sessionStartedUnixMillis: response.sessionStartedUnixMillis,
        level: response.level,
        peakLevel: response.peakLevel,
      );
      if ((response.running != _isBuffering ||
              response.serviceActive != _serviceActive ||
              response.serviceState != _serviceState) &&
          mounted) {
        setState(() {
          _isBuffering = response.running;
          _serviceActive = response.serviceActive;
          _recordingMode = response.recordingMode;
          _lockRecordingTrigger = response.lockRecordingTrigger;
          _evidenceState = response.evidenceState;
          _evidenceLastStopReason = response.evidenceLastStopReason;
          _serviceState = response.serviceState;
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
    if (!_supportsReplayPlatform) {
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
      final response = shouldStop
          ? await _replayClient.stopReplay()
          : await _replayClient.startReplay(
              mode: _recordingMode,
              trigger: _lockRecordingTrigger,
            );
      if (!mounted) {
        return;
      }

      _applyReplayStatusResponse(response);
      _updateMeterSnapshot(
        running: response.running,
        recordedMillis: _meterSnapshot.value.recordedMillis,
        sessionStartedUnixMillis: response.running
            ? DateTime.now().millisecondsSinceEpoch
            : null,
        level: response.running ? _meterSnapshot.value.level : 0,
        peakLevel: response.running ? _meterSnapshot.value.peakLevel : 0,
      );
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _platformStatus = context.l10n.serviceError(error.code);
      });
    }
  }

  Future<void> _saveClip(int seconds) async {
    if (_supportsReplayPlatform) {
      if (!_folderSelected) {
        await _chooseRecordingFolder();
        if (!_folderSelected) {
          return;
        }
      }

      try {
        final response = await _replayClient.saveReplayClip(seconds);
        if (!mounted) {
          return;
        }

        final l10n = context.l10n;
        if (!response.saved) {
          setState(() {
            _platformStatus = l10n.saveError(response.error ?? 'unknown');
          });
          return;
        }

        setState(() {
          _platformStatus = response.pending
              ? l10n.saveStarted
              : l10n.clipSaved;
        });
        if (response.pending) {
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
          _platformStatus = context.l10n.saveError(error.code);
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
    if (!_supportsReplayPlatform) {
      return;
    }

    final groupsResponse = await _replayClient.listGroups();
    final recordingsResponse = await _replayClient.listRecordings();
    if (!mounted) {
      return;
    }

    setState(() {
      _groups
        ..clear()
        ..addAll(groupsResponse);
      _clips
        ..clear()
        ..addAll(recordingsResponse);
    });
  }

  Future<void> _playClip(ClipItem clip) async {
    final uri = clip.uri;
    if (uri == null || !_supportsReplayPlatform) {
      return;
    }
    final response = await _replayClient.playRecording(
      uri: uri,
      speed: _playback.speed,
      fallback: _playback,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _playback = response;
      _platformStatus = response.playing
          ? context.l10n.previewPlaying
          : context.l10n.previewError('unknown');
    });
  }

  Future<void> _pausePreview() async {
    final response = await _replayClient.pausePreview(_playback);
    if (!mounted) {
      return;
    }
    setState(() {
      _playback = response;
    });
  }

  Future<void> _resumePreview() async {
    final response = await _replayClient.resumePreview(_playback);
    if (!mounted) {
      return;
    }
    setState(() {
      _playback = response;
    });
  }

  Future<void> _stopPreview() async {
    if (!_supportsReplayPlatform) {
      return;
    }
    final response = await _replayClient.stopPreview(_playback);
    if (!mounted) {
      return;
    }
    setState(() {
      _playback = response;
      _platformStatus = context.l10n.previewStopped;
    });
  }

  Future<void> _seekPreview(int positionMs) async {
    final response = await _replayClient.seekPreview(
      positionMs: positionMs,
      fallback: _playback,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _playback = response;
    });
  }

  Future<void> _setPlaybackSpeed(double speed) async {
    final response = await _replayClient.setPlaybackSpeed(
      speed: speed,
      fallback: _playback,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _playback = response;
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
    if (!_supportsReplayPlatform || clips.isEmpty) {
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
      try {
        final response = await _replayClient.runLibraryMutation(
          'deleteRecording',
          {'uri': uri},
        );
        if (response.ok) {
          deleted += 1;
        } else {
          firstError ??= response.error ?? 'delete_failed';
        }
      } on PlatformException catch (error) {
        firstError ??= error.code;
      }
    }

    if (!mounted) {
      return;
    }
    final message = firstError == null
        ? context.l10n.deletedRecordings(deleted)
        : context.l10n.deletedRecordingsWithError(deleted, firstError);
    setState(() => _platformStatus = message);
    if (firstError != null) {
      _showCurrentPageSnackBar(message);
    }
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
    if (!_supportsReplayPlatform || clip.uri == null) {
      return false;
    }
    final response = await _replayClient.processRecording(
      clip: clip,
      gainDb: gainDb,
      format: format,
      mp3BitrateKbps: mp3BitrateKbps,
    );
    if (!mounted) {
      return false;
    }
    setState(() {
      _platformStatus = response.ok
          ? context.l10n.processedRecording(response.name ?? '')
          : context.l10n.processingStatusError(response.error ?? 'unknown');
    });
    if (response.ok) {
      await _loadRecordings();
    }
    return response.ok;
  }

  Future<Map<String, Object?>> _clearCache() async {
    if (!_supportsReplayPlatform) {
      return <String, Object?>{'ok': false, 'error': 'unsupported_platform'};
    }
    final response = await _replayClient.clearCache();
    final result = response.toMap();
    if (!mounted) {
      return result;
    }
    setState(() {
      if (response.cacheBytes != null) {
        _cacheBytes = response.cacheBytes!;
      } else if (response.ok) {
        _cacheBytes = 0;
      }
      _platformStatus = response.ok
          ? context.l10n.cacheClearedStatus(
              _formatBytes(response.deletedBytes ?? 0),
            )
          : context.l10n.clearCacheStatusError(response.error ?? 'unknown');
    });
    if (response.ok && !_isBuffering) {
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
    if (!_supportsReplayPlatform) {
      return;
    }
    final response = await _replayClient.getCacheStatus();
    if (!mounted) {
      return;
    }
    if (response.ok) {
      setState(() {
        _cacheBytes = response.cacheBytes;
      });
    }
  }

  Future<void> _openExternalUrl(String url) async {
    if (!_supportsReplayPlatform) {
      return;
    }
    await _replayClient.openUrl(url);
  }

  Future<void> _runLibraryMutation(
    String method,
    Map<String, Object?> arguments,
  ) async {
    if (!_supportsReplayPlatform) {
      return;
    }
    try {
      final response = await _replayClient.runLibraryMutation(
        method,
        arguments,
      );
      if (!mounted) {
        return;
      }

      final message = response.ok
          ? context.l10n.libraryUpdated
          : context.l10n.libraryError(response.error ?? method);
      setState(() => _platformStatus = message);
      if (!response.ok) {
        _showCurrentPageSnackBar(message);
        return;
      }
      await _loadRecordings();
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      final message = context.l10n.libraryError(error.code);
      setState(() => _platformStatus = message);
      _showCurrentPageSnackBar(message);
    }
  }

  void _showCurrentPageSnackBar(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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

  void _selectSection(int index) {
    final nextSection = AppSection.values[index];
    if (_section != nextSection) {
      setState(() => _section = nextSection);
    }
    if (nextSection == AppSection.settings) {
      unawaited(_loadCacheStatus());
      unawaited(_loadAudioSourceSettings());
    } else if (nextSection == AppSection.library ||
        nextSection == AppSection.processing) {
      unawaited(_loadRecordings());
    }
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
      AppSection.settings => SettingsPage(
        folderUri: _folderUri,
        sampleRate: _sampleRate,
        bufferSeconds: _bufferSeconds,
        audioInputDevices: _audioInputDevices,
        microphoneEnabled: _microphoneEnabled,
        systemAudioEnabled: _systemAudioEnabled,
        microphoneDeviceId: _microphoneDeviceId,
        systemAudioSupported: _systemAudioSupported,
        inputDeviceSelectionSupported: _inputDeviceSelectionSupported,
        audioSourceSettingsBusy: _audioSourceSettingsBusy,
        cacheBytes: _cacheBytes,
        lockRecordingTrigger: _lockRecordingTrigger,
        languageMode: widget.languageMode,
        onChooseFolder: _chooseRecordingFolder,
        onUpdateAudioSettings: _updateAudioSettings,
        onUpdateAudioSourceSettings: _updateAudioSourceSettings,
        onRefreshAudioInputDevices: _refreshAudioInputDevices,
        onLockRecordingTriggerChanged: _setLockRecordingTrigger,
        onClearCache: _clearCache,
        onLanguageModeChanged: widget.onLanguageModeChanged,
        onOpenUrl: _openExternalUrl,
      ),
    };

    final windowWidth = MediaQuery.sizeOf(context).width;
    final useDesktopNavigation =
        _isDesktopPlatform || windowWidth >= _wideNavigationBreakpoint;
    final page = Padding(
      padding: EdgeInsets.fromLTRB(
        useDesktopNavigation ? 28 : 20,
        20,
        useDesktopNavigation ? 28 : 20,
        20,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: content,
        ),
      ),
    );

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
        child: useDesktopNavigation
            ? Row(
                children: [
                  _DesktopNavigation(
                    key: _desktopNavigationKey,
                    selectedIndex: _section.index,
                    onDestinationSelected: _selectSection,
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: page),
                ],
              )
            : page,
      ),
      bottomNavigationBar: useDesktopNavigation
          ? null
          : NavigationBar(
              selectedIndex: _section.index,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
              onDestinationSelected: _selectSection,
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

class _DesktopNavigation extends StatelessWidget {
  const _DesktopNavigation({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SizedBox(
      width: _desktopNavigationWidth,
      child: Material(
        color: colors.surfaceContainerLowest,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, section) in AppSection.values.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _DesktopNavigationDestination(
                    key: ValueKey<String>('navigation.desktop.${section.name}'),
                    icon: section.icon,
                    selectedIcon: _selectedIconFor(section),
                    label: _sectionLabel(context, section),
                    selected: index == selectedIndex,
                    onTap: () => onDestinationSelected(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopNavigationDestination extends StatelessWidget {
  const _DesktopNavigationDestination({
    super.key,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = selected
        ? colors.onSecondaryContainer
        : colors.onSurfaceVariant;

    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? colors.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(selected ? selectedIcon : icon, color: foreground),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: foreground,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
