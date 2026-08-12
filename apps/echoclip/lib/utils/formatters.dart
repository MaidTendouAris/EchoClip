part of '../main.dart';

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
  String? evidenceLastStopReason,
  String serviceState = 'stopped',
  String? rawError,
}) {
  final normalizedError = _normalizeNativeDetail(rawError);
  if (normalizedError == null) {
    if (recordingMode == RecordingMode.lockscreen) {
      if (!serviceActive || serviceState == 'stopped') {
        return l10n.lockRecordingStatusOff;
      }
      if (serviceState == 'lockscreen_recording' ||
          evidenceState == 'recording') {
        return l10n.lockRecordingStatusRecording;
      }
      final armedMessage = _lockRecordingArmedMessage(
        l10n,
        lockRecordingTrigger,
      );
      final stopReason =
          evidenceLastStopReason ??
          switch (serviceState) {
            'lockscreen_stopped_screen_on' => 'screen_on',
            'lockscreen_stopped_user_present' => 'user_present',
            _ => null,
          };
      final reasonLabel = _lockStopReasonLabel(l10n, stopReason);
      return reasonLabel == null
          ? armedMessage
          : l10n.recordingStatusWithDetail(armedMessage, reasonLabel);
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

String _lockRecordingArmedMessage(
  AppLocalizations l10n,
  LockRecordingTrigger trigger,
) {
  return trigger == LockRecordingTrigger.keyguardLocked
      ? l10n.lockRecordingStatusArmedKeyguard
      : l10n.lockRecordingStatusArmedScreenOff;
}

String? _lockStopReasonLabel(AppLocalizations l10n, String? reason) {
  return switch (reason) {
    'screen_on' =>
      l10n.localeName.startsWith('zh') ? '亮屏后已停止' : 'stopped after screen on',
    'user_present' =>
      l10n.localeName.startsWith('zh') ? '解锁后已停止' : 'stopped after unlock',
    _ => null,
  };
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

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) {
      return null;
    }
    return iterator.current;
  }
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
