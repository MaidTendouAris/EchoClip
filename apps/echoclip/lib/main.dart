import 'dart:async';
import 'dart:convert';
import 'dart:io' show exit;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:window_manager/window_manager.dart';

import 'l10n/app_localizations.dart';
import 'services/windows_replay_service.dart';
import 'services/desktop_exit.dart';
import 'widgets/loudness_meter_model.dart';

part 'models/app_models.dart';
part 'services/replay_service_client.dart';
part 'utils/formatters.dart';
part 'pages/recorder_page.dart';
part 'widgets/loudness_meter.dart';
part 'pages/library_page.dart';
part 'pages/scheduled_tasks_page.dart';
part 'pages/settings_page.dart';
part 'pages/server_settings_page.dart';
part 'widgets/shared_widgets.dart';

bool _windowsDesktopPluginsReady = false;

const Size _desktopInitialWindowSize = Size(1080, 720);
const Size _desktopMinimumWindowSize = Size(960, 640);
const double _desktopMinimumAspectRatio = 4 / 3;
const double _desktopMaximumAspectRatio = 16 / 9;
const double _wideNavigationBreakpoint = 840;
const double _desktopNavigationWidth = 232;
const Key _desktopNavigationKey = ValueKey<String>('navigation.desktop');

@visibleForTesting
Size constrainDesktopWindowSize(Size size) {
  var width = math.max(size.width, _desktopMinimumWindowSize.width);
  var height = math.max(size.height, _desktopMinimumWindowSize.height);
  final ratio = width / height;
  if (ratio < _desktopMinimumAspectRatio) {
    height = width / _desktopMinimumAspectRatio;
  } else if (ratio > _desktopMaximumAspectRatio) {
    width = height * _desktopMaximumAspectRatio;
  }
  return Size(width, height);
}

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
  ClipSaveProgress _saveProgress = const ClipSaveProgress();
  ClipSaveOutcome? _saveOutcome;
  String? _saveErrorDetail;
  Timer? _saveFeedbackTimer;
  int? _manualSaveJobId;
  bool _saveCancelRequested = false;

  bool _isQuitting = false;
  final _desktopExit = DesktopExitCoordinator();
  bool _windowConstraintInFlight = false;
  bool _isBuffering = false;
  bool _serviceActive = false;
  bool _recordingCommandInFlight = false;
  int _recordingCommandRevision = 0;

  bool get _recordingControlActive =>
      _isBuffering ||
      (_recordingMode == RecordingMode.lockscreen &&
          (_evidenceState == 'armed' || _evidenceState == 'recording'));

  Future<void> _runRecordingCommand(Future<void> Function() action) async {
    if (_recordingCommandInFlight) return;
    setState(() => _recordingCommandInFlight = true);
    _recordingCommandRevision++;
    try {
      await action();
    } finally {
      if (mounted) setState(() => _recordingCommandInFlight = false);
    }
  }

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
  ServerSyncSettings _serverSyncSettings = const ServerSyncSettings(
    enabled: false,
    serverHost: '',
    uploadPort: 32581,
    deviceId: '',
    keyConfigured: false,
  );
  ServerConnectionTestResult? _serverConnectionTest;
  int _cacheBytes = 0;
  RecordingMode _recordingMode = RecordingMode.standard;
  LockRecordingTrigger _lockRecordingTrigger = LockRecordingTrigger.screenOff;
  String _evidenceState = 'off';
  String? _evidenceLastStopReason;
  String _serviceState = 'stopped';
  String _platformStatus = '';
  final ValueNotifier<MeterSnapshot> _meterSnapshot =
      ValueNotifier<MeterSnapshot>(
        MeterSnapshot(
          running: false,
          recordedMillis: 0,
          sessionRecordedMillis: 0,
          sessionStartedAt: null,
          level: 0,
          peakLevel: 0,
        ),
      );
  final List<ClipItem> _clips = [];
  final List<RecordingGroup> _groups = [];
  ScheduleSnapshot? _scheduleSnapshot;
  bool _scheduleBusy = false;
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
    _saveFeedbackTimer?.cancel();
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
    if (_hotKeySaveInFlight || _saveProgress.busy) {
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

    // Stop UI polling before teardown and hide the window immediately. Native
    // capture and upload shutdown can wait on device/network threads; keeping
    // that work behind a visible surface makes Windows show a frozen window.
    _statusTimer?.cancel();
    _statusTimer = null;
    _meterTimer?.cancel();
    _meterTimer = null;
    windowManager.removeListener(this);
    tray.trayManager.removeListener(this);

    await _desktopExit.run(
      hideWindow: windowManager.hide,
      shutdownBackend: WindowsReplayService.instance.dispose,
      releaseDesktopResources: [
        _unregisterSaveHotKey,
        tray.trayManager.destroy,
      ],
      closeWindow: () async {
        await windowManager.setPreventClose(false);
        await windowManager.destroy();
      },
      forceExit: () => exit(0),
    );
  }

  @override
  void onWindowClose() {
    if (!_isQuitting) {
      unawaited(_hideWindowsWindow());
    }
  }

  @override
  void onWindowResized() {
    unawaited(_constrainDesktopWindow());
  }

  Future<void> _constrainDesktopWindow() async {
    if (_isQuitting ||
        _windowConstraintInFlight ||
        !_windowsDesktopPluginsReady) {
      return;
    }
    _windowConstraintInFlight = true;
    try {
      if (await windowManager.isMaximized() ||
          await windowManager.isFullScreen()) {
        return;
      }
      final current = await windowManager.getSize();
      final constrained = constrainDesktopWindowSize(current);
      if ((constrained.width - current.width).abs() > 0.5 ||
          (constrained.height - current.height).abs() > 0.5) {
        await windowManager.setSize(constrained);
      }
    } on PlatformException {
      // Ignore a resize event racing with native window teardown.
    } finally {
      _windowConstraintInFlight = false;
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
    await _loadServerSyncSettings();
    await _loadRecordings();
    await _loadCacheStatus();
    await _loadScheduleSnapshot();
  }

  Future<void> _bootstrapPlatform() async {
    if (!_supportsReplayPlatform) {
      return;
    }

    await _refreshRecordingFolder(promptIfMissing: true);
    await _loadAudioSettings();
    await _loadAudioSourceSettings();
    final serverSettings = await _loadServerSyncSettings();
    if (serverSettings.enabled && serverSettings.configured) {
      unawaited(_testServerConnection());
    }
    await _loadRecordingModeSettings();
    await _loadCacheStatus();
    await _loadRecordings();
    await _loadScheduleSnapshot();
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

  Future<ServerSyncSettings> _loadServerSyncSettings() async {
    if (!_supportsReplayPlatform) {
      return _serverSyncSettings;
    }
    final settings = await _replayClient.getServerSyncSettings();
    if (mounted) {
      setState(() => _serverSyncSettings = settings);
    }
    return settings;
  }

  Future<ServerSyncSettings> _updateServerSyncEnabled(bool enabled) async {
    final update = await _replayClient.setServerSyncEnabled(enabled);
    if (mounted) {
      setState(() => _serverSyncSettings = update);
    }
    return update;
  }

  Future<ServerSyncSettings> _updateServerSyncSettings({
    required String serverHost,
    required int uploadPort,
    String? uploadKey,
    bool clearKey = false,
  }) async {
    final update = await _replayClient.setServerSyncSettings(
      serverHost: serverHost,
      uploadPort: uploadPort,
      uploadKey: uploadKey,
      clearKey: clearKey,
    );
    if (mounted) {
      setState(() {
        _serverSyncSettings = update;
        _serverConnectionTest = null;
      });
    }
    return update;
  }

  Future<ServerConnectionTestResult> _testServerConnection({
    String? serverHost,
    int? uploadPort,
    String? uploadKey,
  }) async {
    final result = await _replayClient.testServerConnection(
      serverHost: serverHost,
      uploadPort: uploadPort,
      uploadKey: uploadKey,
    );
    if (mounted) {
      setState(() => _serverConnectionTest = result);
    }
    return result;
  }

  Future<void> _openServerSettings() async {
    await _loadServerSyncSettings();
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => ServerSettingsPage(
          initialSettings: _serverSyncSettings,
          initialConnectionTest: _serverConnectionTest,
          onEnabledChanged: _updateServerSyncEnabled,
          onSave: _updateServerSyncSettings,
          onRefresh: _replayClient.getServerSyncSettings,
          onTestConnection: _testServerConnection,
        ),
      ),
    );
    await _loadServerSyncSettings();
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

  Future<void> _setRecordingMode(RecordingMode mode) =>
      _runRecordingCommand(() async {
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
        } on PlatformException catch (error) {
          if (!mounted) {
            return;
          }
          setState(() {
            _recordingMode = previousMode;
            _platformStatus = context.l10n.serviceError(error.code);
          });
        }
      });

  Future<void> _setLockRecordingTrigger(LockRecordingTrigger trigger) =>
      _runRecordingCommand(() async {
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
          final response = await _replayClient.setRecordingModeSettings(
            mode: _recordingMode,
            trigger: trigger,
          );
          if (mounted) _applyReplayStatusResponse(response);
        } on PlatformException catch (error) {
          if (!mounted) {
            return;
          }
          setState(() {
            _platformStatus = context.l10n.serviceError(error.code);
          });
        }
      });

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
    if (!_supportsReplayPlatform || _recordingCommandInFlight) {
      return;
    }

    final revision = _recordingCommandRevision;
    try {
      final response = await _replayClient.getReplayStatus();
      if (!mounted ||
          _recordingCommandInFlight ||
          revision != _recordingCommandRevision) {
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
        _serverSyncSettings = ServerSyncSettings(
          enabled: _serverSyncSettings.enabled,
          serverHost: _serverSyncSettings.serverHost,
          uploadPort: _serverSyncSettings.uploadPort,
          deviceId: _serverSyncSettings.deviceId,
          keyConfigured: _serverSyncSettings.keyConfigured,
          status: response.syncStatus ?? _serverSyncSettings.status,
          configurationError:
              response.syncConfigurationError ??
              _serverSyncSettings.configurationError,
        );
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
    if (_meterPollInFlight || _recordingCommandInFlight) {
      return;
    }

    _meterPollInFlight = true;
    final revision = _recordingCommandRevision;
    try {
      final response = await _replayClient.getMeterStatus();
      if (!mounted ||
          _recordingCommandInFlight ||
          revision != _recordingCommandRevision) {
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
    final providedSessionStartedAt =
        sessionStartedUnixMillis != null && sessionStartedUnixMillis > 0
        ? DateTime.fromMillisecondsSinceEpoch(sessionStartedUnixMillis)
        : null;
    final sessionStartedAt = running
        ? providedSessionStartedAt ??
              previous.sessionStartedAt ??
              DateTime.now().subtract(
                Duration(milliseconds: displayRecordedMillis),
              )
        : providedSessionStartedAt ?? previous.sessionStartedAt;
    final sessionRecordedMillis = running && sessionStartedAt != null
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

  Future<void> _toggleBuffering() => _runRecordingCommand(() async {
    if (!_supportsReplayPlatform) {
      return;
    }

    if (!_recordingControlActive && !_folderSelected) {
      await _chooseRecordingFolder();
      if (!_folderSelected) {
        return;
      }
    }

    try {
      final shouldStop = _recordingControlActive;
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
  });

  void _showOperationFeedback(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _clearSaveFeedback() {
    _saveFeedbackTimer?.cancel();
    _saveFeedbackTimer = null;
    _saveOutcome = null;
    _saveErrorDetail = null;
  }

  void _showSaveFeedback(ClipSaveOutcome outcome, {String? detail}) {
    if (!mounted) return;
    _saveFeedbackTimer?.cancel();
    setState(() {
      _saveOutcome = outcome;
      _saveErrorDetail = detail;
    });
    final failed =
        outcome == ClipSaveOutcome.failed ||
        outcome == ClipSaveOutcome.cancelFailed;
    _saveFeedbackTimer = Timer(Duration(seconds: failed ? 8 : 4), () {
      if (mounted) setState(_clearSaveFeedback);
    });
  }

  Future<void> _refreshSavedRecordings() async {
    try {
      await _loadRecordings();
      await _loadCacheStatus();
    } on PlatformException catch (error) {
      // Saving succeeded; a later list refresh failure must not report a failed export.
      debugPrint('Recording list refresh failed: ${error.code}');
    }
  }

  Future<void> _cancelManualSave() async {
    if (!_saveProgress.cancellable || _saveCancelRequested) return;
    setState(() {
      _clearSaveFeedback();
      _saveCancelRequested = true;
      _saveProgress = const ClipSaveProgress(busy: true, canceling: true);
    });
    final jobId = _manualSaveJobId;
    if (jobId == null) return; // The start reply may still be in flight.
    try {
      await _replayClient.cancelSaveJob(jobId);
    } on PlatformException catch (error) {
      if (!mounted || !_saveProgress.busy || _manualSaveJobId != jobId) return;
      setState(() {
        _saveCancelRequested = false;
        _saveProgress = const ClipSaveProgress(busy: true, cancellable: true);
      });
      _showSaveFeedback(ClipSaveOutcome.cancelFailed, detail: error.code);
    }
  }

  Future<void> _saveClip(int seconds) async {
    if (_saveProgress.busy) {
      await _cancelManualSave();
      return;
    }
    if (_supportsReplayPlatform) {
      if (!_folderSelected) {
        await _chooseRecordingFolder();
        if (!_folderSelected || !mounted) return;
      }
      final cancellable = defaultTargetPlatform == TargetPlatform.android;
      setState(() {
        _clearSaveFeedback();
        _manualSaveJobId = null;
        _saveCancelRequested = false;
        _saveProgress = ClipSaveProgress(busy: true, cancellable: cancellable);
      });
      try {
        final response = await _replayClient.saveReplayClip(seconds);
        if (!mounted) return;
        if (!response.saved) {
          _showSaveFeedback(
            ClipSaveOutcome.failed,
            detail: response.error ?? 'unknown',
          );
          return;
        }
        if (response.pending) {
          final jobId = response.jobId;
          if (jobId == null) {
            throw PlatformException(code: 'missing_save_job');
          }
          _manualSaveJobId = jobId;
          if (_saveCancelRequested) await _replayClient.cancelSaveJob(jobId);
          while (mounted) {
            final job = await _replayClient.getSaveJob(jobId);
            if (!mounted) return;
            final phase = job['state']?.toString();
            if (phase == 'Finished') break;
            if (phase == 'Canceled') {
              _showSaveFeedback(ClipSaveOutcome.canceled);
              return;
            }
            if (phase == 'Failed') {
              _showSaveFeedback(
                ClipSaveOutcome.failed,
                detail: job['error']?.toString() ?? 'unknown',
              );
              return;
            }
            setState(() {
              final progress = job['progress'];
              _saveProgress = ClipSaveProgress(
                busy: true,
                cancellable: cancellable,
                canceling: _saveCancelRequested || phase == 'Canceling',
                progress: phase == 'CopyingToSaf' && progress is num
                    ? progress.toDouble().clamp(0, 1)
                    : null,
              );
            });
            await Future<void>.delayed(const Duration(milliseconds: 150));
          }
          if (!mounted) return;
        }
        _showSaveFeedback(ClipSaveOutcome.saved);
        unawaited(_refreshSavedRecordings());
      } on PlatformException catch (error) {
        // A lost status reply must not leave an orphaned manual export running.
        final jobId = _manualSaveJobId;
        if (jobId != null) {
          try {
            await _replayClient.cancelSaveJob(jobId);
          } on PlatformException catch (_) {}
        }
        _showSaveFeedback(ClipSaveOutcome.failed, detail: error.code);
      } finally {
        if (mounted) {
          setState(() {
            _saveProgress = const ClipSaveProgress();
            _manualSaveJobId = null;
            _saveCancelRequested = false;
          });
        }
      }
      return;
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
    _showSaveFeedback(ClipSaveOutcome.saved);
  }

  Future<void> _shareClip(ClipItem clip) async {
    try {
      final response = await _replayClient.shareRecording(
        clip,
        context.l10n.shareRecording,
      );
      if (mounted && !response.ok) {
        _showOperationFeedback(context.l10n.shareRecordingFailed);
      }
    } on PlatformException catch (_) {
      if (mounted) _showOperationFeedback(context.l10n.shareRecordingFailed);
    }
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

  Future<bool> _convertWavClip(ClipItem clip, int mp3BitrateKbps) async {
    if (!_supportsReplayPlatform || clip.uri == null) {
      return false;
    }
    try {
      final response = await _replayClient.convertWavToMp3(
        clip: clip,
        mp3BitrateKbps: mp3BitrateKbps,
      );
      if (!mounted) {
        return false;
      }
      final message = response.ok
          ? context.l10n.convertedWavToMp3(response.name ?? '')
          : context.l10n.convertWavToMp3Failed(response.error ?? 'unknown');
      setState(() => _platformStatus = message);
      if (response.ok) {
        await _loadRecordings();
      } else {
        _showCurrentPageSnackBar(message);
      }
      return response.ok;
    } on PlatformException catch (error) {
      if (mounted) {
        final message = context.l10n.convertWavToMp3Failed(error.code);
        setState(() => _platformStatus = message);
        _showCurrentPageSnackBar(message);
      }
      return false;
    }
  }

  Future<void> _loadScheduleSnapshot() async {
    if (!_supportsReplayPlatform || _scheduleBusy) {
      return;
    }
    setState(() => _scheduleBusy = true);
    try {
      final snapshot = await _replayClient.getScheduleSnapshot();
      if (!mounted) {
        return;
      }
      setState(() => _scheduleSnapshot = snapshot);
    } on PlatformException catch (error) {
      if (mounted) {
        _showCurrentPageSnackBar(
          context.l10n.scheduleOperationFailed(error.code),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _scheduleBusy = false);
      }
    }
  }

  Future<bool> _runScheduleMutation(
    Future<ScheduleSnapshot> Function() operation,
  ) async {
    if (!_supportsReplayPlatform || _scheduleBusy) {
      return false;
    }
    setState(() => _scheduleBusy = true);
    try {
      final snapshot = await operation();
      if (!mounted) {
        return false;
      }
      setState(() => _scheduleSnapshot = snapshot);
      if (!snapshot.ok) {
        _showCurrentPageSnackBar(
          snapshot.error?.contains('PRESET_LIMIT_REACHED') == true
              ? context.l10n.schedulePresetLimit
              : context.l10n.scheduleOperationFailed(
                  snapshot.error ?? 'unknown',
                ),
        );
      }
      return snapshot.ok;
    } on PlatformException catch (error) {
      if (mounted) {
        _showCurrentPageSnackBar(
          context.l10n.scheduleOperationFailed(error.code),
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _scheduleBusy = false);
      }
    }
  }

  Future<bool> _upsertScheduledTask(Map<String, Object?> task) {
    return _runScheduleMutation(() => _replayClient.upsertScheduledTask(task));
  }

  Future<bool> _deleteScheduledTask(ScheduledTaskModel task) {
    return _runScheduleMutation(
      () => _replayClient.deleteScheduledTask(task.id),
    );
  }

  Future<bool> _setScheduledTaskEnabled(ScheduledTaskModel task, bool enabled) {
    return _runScheduleMutation(
      () => _replayClient.setScheduledTaskEnabled(
        taskId: task.id,
        expectedRevision: task.revision,
        enabled: enabled,
      ),
    );
  }

  Future<void> _requestExactAlarmPermission() async {
    await _runScheduleMutation(_replayClient.requestExactAlarmPermission);
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
        clearSessionStartedAt: true,
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
    final compact =
        !_isDesktopPlatform && MediaQuery.sizeOf(context).width < 520;
    return PopupMenuButton<RecordingMode>(
      key: const ValueKey('recording.modeMenu'),
      initialValue: _recordingMode,
      enabled: !_recordingCommandInFlight,
      tooltip: _recordingModeLabel(l10n, _recordingMode),
      onSelected: _setRecordingMode,
      itemBuilder: (context) => [
        for (final mode in RecordingMode.values)
          PopupMenuItem(
            value: mode,
            child: Text(_recordingModeLabel(l10n, mode)),
          ),
      ],
      child: compact
          ? const SizedBox.square(
              dimension: 48,
              child: Center(child: Icon(Icons.swap_horiz, size: 22)),
            )
          : Chip(
              avatar: const Icon(Icons.swap_horiz, size: 18),
              label: Text(_recordingModeLabel(l10n, _recordingMode)),
              visualDensity: VisualDensity.compact,
            ),
    );
  }

  Color _serverConnectionColor(ColorScheme colors) {
    final settings = _serverSyncSettings;
    if (!settings.configured) {
      return colors.outlineVariant;
    }
    if (!settings.enabled) {
      return colors.secondary;
    }
    final status = settings.status;
    if (status?.running == true) {
      if (settings.configurationError?.isNotEmpty == true ||
          status?.lastError?.isNotEmpty == true) {
        return colors.error;
      }
      if (status?.connected == true) {
        return const Color(0xFF2E9B62);
      }
      return const Color(0xFFE7A126);
    }
    final test = _serverConnectionTest;
    if (test != null) {
      return test.success ? const Color(0xFF2E9B62) : colors.error;
    }
    return const Color(0xFFE7A126);
  }

  Widget _serverConnectionIndicator(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IconButton(
      key: const ValueKey('server.connectionIndicator'),
      tooltip: context.l10n.serverConnectionDetails,
      onPressed: _showServerConnectionDetails,
      icon: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: _serverConnectionColor(colors),
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  Future<void> _showServerConnectionDetails() async {
    final settings = await _loadServerSyncSettings();
    if (!mounted) {
      return;
    }
    final status = settings.status;
    final test = _serverConnectionTest;
    final l10n = context.l10n;
    final state = !settings.configured
        ? l10n.serverNotConfigured
        : !settings.enabled
        ? l10n.serverSyncDisabled
        : status?.running == true
        ? status?.connected == true
              ? l10n.serverConnected
              : (settings.configurationError ?? status?.lastError)
                        ?.isNotEmpty ==
                    true
              ? l10n.serverConnectionFailed
              : l10n.serverConnecting
        : test?.success == true
        ? l10n.serverConnected
        : test != null
        ? l10n.serverConnectionFailed
        : l10n.serverConnecting;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: Text(l10n.serverConnectionDetails),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(state, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Text(
                settings.connectionLabel.isEmpty
                    ? '—'
                    : settings.connectionLabel,
              ),
              if (status?.lastError?.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Text(
                  status!.lastError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (settings.configurationError?.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Text(
                  settings.configurationError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (status?.running != true &&
                  test?.error?.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Text(
                  test!.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.close),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              unawaited(_openServerSettings());
            },
            child: Text(l10n.serverSettings),
          ),
        ],
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
    } else if (nextSection == AppSection.library) {
      unawaited(_loadRecordings());
    } else if (nextSection == AppSection.scheduledTasks) {
      unawaited(_loadScheduleSnapshot());
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = switch (_section) {
      AppSection.recorder => RecorderPage(
        isBuffering: _isBuffering,
        platformStatus: _platformStatus,
        meterSnapshot: _meterSnapshot,
        folderSelected: _folderSelected,
        onSave: _saveClip,
        saveProgress: _saveProgress,
        saveOutcome: _saveOutcome,
        saveErrorDetail: _saveErrorDetail,
        onChooseFolder: _chooseRecordingFolder,
        headerActions: [
          _serverConnectionIndicator(context),
          _recordingModeMenu(context),
        ],
      ),
      AppSection.library => LibraryPage(
        groups: _groups,
        clips: _clips,
        playback: _playback,
        onRefresh: _loadRecordings,
        onPlay: _playClip,
        onShare: !kIsWeb && defaultTargetPlatform == TargetPlatform.android
            ? _shareClip
            : null,
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
        onConvertWavToMp3: _convertWavClip,
      ),
      AppSection.scheduledTasks => ScheduledTasksPage(
        snapshot: _scheduleSnapshot,
        busy: _scheduleBusy,
        onRefresh: _loadScheduleSnapshot,
        onUpsert: _upsertScheduledTask,
        onDelete: _deleteScheduledTask,
        onSetEnabled: _setScheduledTaskEnabled,
        onRequestExactAlarm: _requestExactAlarmPermission,
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
        onOpenServerSettings: _openServerSettings,
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
      key: const ValueKey('navigation.page'),
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
      appBar: _isDesktopPlatform
          ? AppBar(
              title: Text(context.l10n.appTitle),
              centerTitle: false,
              backgroundColor: const Color(0xFFF6F8F7),
              surfaceTintColor: Colors.transparent,
              scrolledUnderElevation: 0,
            )
          : null,
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
              backgroundColor: const Color(0xFF267B69),
              foregroundColor: Colors.white,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              onPressed: _recordingCommandInFlight ? null : _toggleBuffering,
              tooltip: _recordingControlActive
                  ? context.l10n.pause
                  : context.l10n.resume,
              child: Icon(
                _recordingControlActive ? Icons.pause : Icons.play_arrow,
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
