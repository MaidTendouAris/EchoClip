part of '../main.dart';

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

enum AppSection {
  recorder(Icons.home_outlined),
  library(Icons.library_music),
  processing(Icons.equalizer),
  settings(Icons.tune);

  const AppSection(this.icon);

  final IconData icon;
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
