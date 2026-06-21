import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const EchoClipApp());
}

class EchoClipApp extends StatelessWidget {
  const EchoClipApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EchoClip',
      debugShowCheckedModeBanner: false,
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
      home: const EchoClipHome(),
    );
  }
}

enum AppSection {
  recorder(Icons.home_outlined, '主页'),
  library(Icons.library_music, '已保存录音'),
  processing(Icons.equalizer, '音频处理'),
  settings(Icons.tune, '设置');

  const AppSection(this.icon, this.label);

  final IconData icon;
  final String label;
}

class EchoClipHome extends StatefulWidget {
  const EchoClipHome({super.key});

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
  bool _folderSelected = defaultTargetPlatform != TargetPlatform.android;
  String? _folderUri;
  int _sampleRate = 16000;
  int _bufferSeconds = 1800;
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
    setState(() {
      _sampleRate = response['sampleRate'] is int
          ? response['sampleRate'] as int
          : nextSampleRate;
      _bufferSeconds = response['bufferSeconds'] is int
          ? response['bufferSeconds'] as int
          : nextBufferSeconds;
      _platformStatus = applied
          ? 'Recording settings saved'
          : 'Settings saved for next recording';
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
        _platformStatus = 'Windows demo mode';
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
    setState(() {
      _folderSelected = selected;
      _folderUri = response?['uri']?.toString();
      _platformStatus = selected
          ? 'Recording folder ready'
          : 'Folder setup error: ${response?['error']}';
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
      final availableSeconds = response?['availableSeconds'];
      final availableMillis = response?['availableMillis'];
      final backend = response?['backend'];
      final captureError = response?['captureError'];
      final sampleRate = response?['sampleRate'];
      final bufferSeconds = response?['bufferSeconds'];
      setState(() {
        _isBuffering = running;
        _platformStatus = captureError != null
            ? 'Capture error: $captureError'
            : running
            ? 'Android foreground service running · ${backend ?? 'unknown'}'
            : 'Android service stopped · ${backend ?? 'unknown'}';
        if (sampleRate is int) {
          _sampleRate = sampleRate;
        }
        if (bufferSeconds is int) {
          _bufferSeconds = bufferSeconds;
        }
      });
      if (availableMillis is num) {
        _updateMeterSnapshot(
          running: running,
          recordedMillis: availableMillis.toInt(),
        );
      } else if (availableSeconds is int) {
        _updateMeterSnapshot(
          running: running,
          recordedMillis: availableSeconds * 1000,
        );
      }
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _platformStatus = 'Android service error: ${error.code}';
      });
    }
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
      final recordedMillis = response['availableMillis'];
      final level = response['level'];
      final peakLevel = response['peakLevel'];
      _updateMeterSnapshot(
        running: running,
        recordedMillis: recordedMillis is num
            ? recordedMillis.toInt()
            : _meterSnapshot.value.recordedMillis,
        level: level is num ? level.toDouble() : _meterSnapshot.value.level,
        peakLevel: peakLevel is num
            ? peakLevel.toDouble()
            : _meterSnapshot.value.peakLevel,
      );
      if (running != _isBuffering && mounted) {
        setState(() {
          _isBuffering = running;
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
    double? level,
    double? peakLevel,
  }) {
    final previous = _meterSnapshot.value;
    _meterSnapshot.value = MeterSnapshot(
      running: running,
      recordedMillis: recordedMillis,
      level: (level ?? previous.level).clamp(0.0, 1.0).toDouble(),
      peakLevel: (peakLevel ?? previous.peakLevel).clamp(0.0, 1.0).toDouble(),
    );
  }

  Future<void> _toggleBuffering() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      setState(() {
        _isBuffering = !_isBuffering;
        _platformStatus = 'Windows demo mode';
      });
      _updateMeterSnapshot(
        running: _isBuffering,
        recordedMillis: _meterSnapshot.value.recordedMillis,
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
      final method = _isBuffering ? 'stopReplay' : 'startReplay';
      final response = await _replayChannel.invokeMapMethod<String, Object?>(
        method,
      );
      if (!mounted) {
        return;
      }

      final running = response?['running'] == true;
      final error = response?['error'];
      setState(() {
        _isBuffering = running;
        _platformStatus = error == null
            ? (running
                  ? 'Android foreground service running'
                  : 'Android service stopped')
            : 'Android service error: $error';
      });
      _updateMeterSnapshot(
        running: running,
        recordedMillis: running ? _meterSnapshot.value.recordedMillis : 0,
        level: running ? _meterSnapshot.value.level : 0,
        peakLevel: running ? _meterSnapshot.value.peakLevel : 0,
      );
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _platformStatus = 'Android service error: ${error.code}';
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
        if (!saved) {
          setState(() {
            _platformStatus = 'Android save error: ${response?['error']}';
          });
          return;
        }

        final pending = response?['pending'] == true;
        setState(() {
          _platformStatus = pending
              ? 'Android save started'
              : 'Android clip saved';
        });
        if (pending) {
          unawaited(_reloadRecordingsAfterSave());
        } else {
          await _loadRecordings();
        }
        return;
      } on PlatformException catch (error) {
        if (!mounted) {
          return;
        }
        setState(() {
          _platformStatus = 'Android save error: ${error.code}';
        });
        return;
      }
    }

    setState(() {
      _clips.insert(
        0,
        ClipItem(
          name:
              '最近 ${seconds ~/ 60 > 0 ? '${seconds ~/ 60} 分钟' : '$seconds 秒'}',
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
          ? 'Preview playing'
          : 'Preview error: ${response?['error']}';
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
      _platformStatus = 'Preview stopped';
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
          ? 'Deleted $deleted recordings'
          : 'Deleted $deleted recordings, error: $firstError';
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
          ? 'Processed recording: ${response?['name']}'
          : 'Processing error: ${response?['error']}';
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
    setState(() {
      _platformStatus = ok
          ? 'Cache cleared: ${_formatBytes(deletedBytes is int ? deletedBytes : 0)}'
          : 'Clear cache error: ${result['error']}';
    });
    return result;
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
          ? 'Library updated'
          : 'Library error: ${response?['error'] ?? method}';
    });
    if (ok) {
      await _loadRecordings();
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
        onToggle: _toggleBuffering,
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
        onChooseFolder: _chooseRecordingFolder,
        onUpdateAudioSettings: _updateAudioSettings,
        onClearCache: _clearCache,
      ),
    };

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F7),
      appBar: AppBar(
        title: const Text('EchoClip'),
        centerTitle: false,
        backgroundColor: const Color(0xFFF6F8F7),
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: Padding(padding: const EdgeInsets.all(20), child: content),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _section.index,
        onDestinationSelected: (index) {
          setState(() => _section = AppSection.values[index]);
        },
        destinations: [
          for (final section in AppSection.values)
            NavigationDestination(
              icon: Icon(section.icon),
              selectedIcon: Icon(_selectedIconFor(section)),
              label: section.label,
            ),
        ],
      ),
    );
  }
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
    required this.level,
    required this.peakLevel,
  });

  final bool running;
  final int recordedMillis;
  final double level;
  final double peakLevel;

  MeterSnapshot copyWith({
    bool? running,
    int? recordedMillis,
    double? level,
    double? peakLevel,
  }) {
    return MeterSnapshot(
      running: running ?? this.running,
      recordedMillis: recordedMillis ?? this.recordedMillis,
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
    required this.onToggle,
    required this.onSave,
    required this.onChooseFolder,
  });

  final bool isBuffering;
  final String platformStatus;
  final ValueListenable<MeterSnapshot> meterSnapshot;
  final bool folderSelected;
  final Future<void> Function() onToggle;
  final Future<void> Function(int seconds) onSave;
  final Future<void> Function() onChooseFolder;

  @override
  State<_RecorderPage> createState() => _RecorderPageState();
}

class _RecorderPageState extends State<_RecorderPage> {
  static const List<SaveDurationOption> _durations = [
    SaveDurationOption(10, '10 秒'),
    SaveDurationOption(30, '30 秒'),
    SaveDurationOption(60, '1 分钟'),
    SaveDurationOption(120, '2 分钟'),
    SaveDurationOption(300, '5 分钟'),
    SaveDurationOption(600, '10 分钟'),
    SaveDurationOption(1800, '30 分钟'),
  ];

  SaveDurationOption _selectedDuration = _durations[1];

  @override
  Widget build(BuildContext context) {
    return _Panel(
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
                  widget.isBuffering ? '即时回放运行中' : '录制已暂停',
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
                  Text(
                    _formatDurationMillis(snapshot.recordedMillis),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.platformStatus,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF52615E),
                    ),
                  ),
                  const SizedBox(height: 18),
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
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(152, 56)),
                onPressed: widget.folderSelected
                    ? () => widget.onSave(_selectedDuration.seconds)
                    : null,
                icon: const Icon(Icons.save_alt),
                label: Text('保存 ${_selectedDuration.label}'),
              ),
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
                    DropdownMenuEntry(value: option, label: option.label),
                ],
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(112, 56),
                ),
                onPressed: widget.onToggle,
                icon: Icon(widget.isBuffering ? Icons.pause : Icons.play_arrow),
                label: Text(widget.isBuffering ? '暂停' : '继续'),
              ),
              if (!widget.folderSelected)
                OutlinedButton.icon(
                  onPressed: widget.onChooseFolder,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('选择目录'),
                ),
            ],
          ),
        ],
      ),
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
              Expanded(child: Text('实时响度', style: theme.textTheme.titleMedium)),
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
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '静音',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF6C7472),
                ),
              ),
              const Spacer(),
              Text(
                isRecording ? '麦克风输入' : '未录制',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF6C7472),
                ),
              ),
              const Spacer(),
              Text(
                '峰值',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF6C7472),
                ),
              ),
            ],
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
    final rootClips = clips.where((clip) => clip.groupUri == null).toList();
    final groupSections = [
      _ClipGroupSection(title: '未分组', group: null, clips: rootClips),
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
                  '录音列表',
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
                  tooltip: '全选',
                  onPressed: clips.isEmpty ? null : _selectAll,
                  icon: const Icon(Icons.select_all),
                )
              else
                IconButton(
                  tooltip: '新建分组',
                  onPressed: () => _createGroup(context),
                  icon: const Icon(Icons.create_new_folder),
                ),
              if (_isEditing)
                IconButton(
                  tooltip: '删除所选',
                  onPressed: _selectedClipUris.isEmpty
                      ? null
                      : () => _deleteSelectedClips(context),
                  icon: const Icon(Icons.delete_outline),
                )
              else
                IconButton(
                  tooltip: '停止预览',
                  onPressed: onStop,
                  icon: const Icon(Icons.stop),
                ),
              IconButton(
                tooltip: _isEditing ? '完成' : '编辑',
                onPressed: _toggleEditing,
                icon: Icon(_isEditing ? Icons.done : Icons.edit),
              ),
              if (!_isEditing)
                IconButton(
                  tooltip: '刷新',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: clips.isEmpty && groups.isEmpty
                ? const Center(child: Text('暂无录音'))
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
              tooltip: '分组操作',
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
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'rename', child: Text('重命名分组')),
                PopupMenuItem(value: 'delete', child: Text('删除分组')),
              ],
            ),
      children: [
        if (section.clips.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(44, 0, 0, 14),
            child: Align(alignment: Alignment.centerLeft, child: Text('暂无录音')),
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
                  tooltip: '预览',
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
                  tooltip: '录音操作',
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
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'rename', child: Text('重命名')),
                    PopupMenuItem(value: 'move', child: Text('移动到分组')),
                    PopupMenuItem(value: 'delete', child: Text('删除')),
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
      title: '批量删除录音',
      message: '确定删除选中的 ${selectedClips.length} 个录音？此操作不可撤销。',
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
    final name = await _promptText(context, title: '新建分组', label: '分组名');
    if (name == null) {
      return;
    }
    await onCreateGroup(name);
  }

  Future<void> _renameGroup(BuildContext context, RecordingGroup group) async {
    final name = await _promptText(
      context,
      title: '重命名分组',
      label: '分组名',
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
      title: '删除分组',
      message: '将删除分组及其中录音，此操作不可撤销。',
    );
    if (confirmed) {
      await onDeleteGroup(group);
    }
  }

  Future<void> _renameClip(BuildContext context, ClipItem clip) async {
    final name = await _promptText(
      context,
      title: '重命名录音',
      label: '文件名',
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
      title: '删除录音',
      message: '确定删除 ${clip.name}？此操作不可撤销。',
    );
    if (confirmed) {
      await onDeleteClip(clip);
    }
  }

  Future<void> _moveClip(BuildContext context, ClipItem clip) async {
    final target = await showDialog<Object?>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('移动到分组'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(_UngroupTarget.instance),
            child: const Text('未分组'),
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
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: const Text('确定'),
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
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('确定'),
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
                tooltip: widget.playback.playing ? '暂停' : '继续',
                onPressed: widget.playback.playing
                    ? widget.onPause
                    : widget.onResume,
                icon: Icon(
                  widget.playback.playing ? Icons.pause : Icons.play_arrow,
                ),
              ),
              IconButton(
                tooltip: '停止',
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
    return ListView(
      children: [
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('音频处理', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedUri,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '源录音',
                  prefixIcon: Icon(Icons.library_music),
                  border: OutlineInputBorder(
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
                      '增益 ${_gainDb >= 0 ? '+' : ''}${_gainDb.toStringAsFixed(1)} dB',
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
                decoration: const InputDecoration(
                  labelText: '输出格式',
                  prefixIcon: Icon(Icons.audio_file),
                  border: OutlineInputBorder(
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
                  decoration: const InputDecoration(
                    labelText: 'MP3 码率',
                    prefixIcon: Icon(Icons.speed),
                    border: OutlineInputBorder(
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
                label: Text(_processing ? '处理中' : '生成处理副本'),
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
      _message = ok ? '处理完成，已生成新的录音文件。' : '处理失败，请检查 FFmpeg 或源文件。';
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

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({
    required this.folderUri,
    required this.sampleRate,
    required this.bufferSeconds,
    required this.onChooseFolder,
    required this.onUpdateAudioSettings,
    required this.onClearCache,
  });

  static const List<int> _sampleRateOptions = [8000, 16000, 24000, 48000];
  static const List<int> _bufferSecondOptions = [600, 1800, 3600, 7200, 18000];

  final String? folderUri;
  final int sampleRate;
  final int bufferSeconds;
  final Future<void> Function() onChooseFolder;
  final Future<void> Function({int? sampleRate, int? bufferSeconds})
  onUpdateAudioSettings;
  final Future<Map<String, Object?>> Function() onClearCache;

  @override
  Widget build(BuildContext context) {
    final estimatedPcmBytes = sampleRate * bufferSeconds * 2;

    return ListView(
      children: [
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('设置', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder),
                title: const Text('录音目录'),
                subtitle: Text(folderUri ?? '未选择'),
                trailing: FilledButton.icon(
                  onPressed: onChooseFolder,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('更改'),
                ),
              ),
              const Divider(height: 28),
              Text('录制设置', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: sampleRate,
                decoration: const InputDecoration(
                  labelText: 'Android 采样率',
                  prefixIcon: Icon(Icons.graphic_eq),
                  border: OutlineInputBorder(
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
              DropdownButtonFormField<int>(
                initialValue: bufferSeconds,
                decoration: const InputDecoration(
                  labelText: '缓存时长',
                  prefixIcon: Icon(Icons.schedule),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                ),
                items: [
                  for (final value in _bufferSecondOptions)
                    DropdownMenuItem(
                      value: value,
                      child: Text(_formatLongDuration(value)),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  onUpdateAudioSettings(bufferSeconds: value);
                },
              ),
              const SizedBox(height: 14),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.memory),
                title: Text('预计 PCM 缓冲：${_formatBytes(estimatedPcmBytes)}'),
                subtitle: Text(
                  '${_formatHertz(sampleRate)} · 单声道 · 16-bit PCM · 录制中修改下次启动生效',
                ),
              ),
              const Divider(height: 28),
              Text('缓存', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.cleaning_services),
                title: const Text('清除缓存'),
                subtitle: const Text('清理临时导出、处理缓存；录制中会保留当前回放缓存'),
                trailing: IconButton.filledTonal(
                  tooltip: '清除',
                  onPressed: () => _confirmClearCache(context),
                  icon: const Icon(Icons.delete_sweep),
                ),
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
      title: '清除缓存',
      message: '确定清除 EchoClip 的临时缓存？此操作不会删除已保存录音。',
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
    final message = result['ok'] == true
        ? '已清理 ${_formatBytes(deletedBytes is int ? deletedBytes : 0)}${activePreserved ? '，当前回放缓存已保留' : ''}'
        : '清理失败：${result['error']}';
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

class SaveDurationOption {
  const SaveDurationOption(this.seconds, this.label);

  final int seconds;
  final String label;
}

class RecordingGroup {
  const RecordingGroup({required this.name, required this.uri});

  factory RecordingGroup.fromNative(Map<dynamic, dynamic> value) {
    return RecordingGroup(
      name: value['name']?.toString() ?? '未命名分组',
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
  final millis = safeMillis % 1000;
  final seconds = totalSeconds % 60;
  final minutes = (totalSeconds ~/ 60) % 60;
  final hours = totalSeconds ~/ 3600;

  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}.'
        '${millis.toString().padLeft(3, '0')}';
  }

  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}.'
      '${millis.toString().padLeft(3, '0')}';
}

String _formatLongDuration(int totalSeconds) {
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  if (hours == 0) {
    return '$minutes 分钟';
  }
  if (minutes == 0) {
    return '$hours 小时';
  }
  return '$hours 小时 $minutes 分钟';
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
