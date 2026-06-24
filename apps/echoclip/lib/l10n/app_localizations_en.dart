// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'EchoClip';

  @override
  String get navHome => 'Home';

  @override
  String get navLibrary => 'Recordings';

  @override
  String get navProcessing => 'Processing';

  @override
  String get navSettings => 'Settings';

  @override
  String get replayRunning => 'Instant replay running';

  @override
  String get recordingPaused => 'Recording paused';

  @override
  String get currentRecordingDuration => 'This recording';

  @override
  String get totalRecordedDuration => 'Total buffered';

  @override
  String recordingStartedAt(Object time) {
    return 'Started $time';
  }

  @override
  String lastRecordingStartedAt(Object time) {
    return 'Last recording $time';
  }

  @override
  String get recordingStatusNormal => 'Recording normally';

  @override
  String get recordingStatusPaused => 'Recording is paused';

  @override
  String get recordingStatusPermissionLost =>
      'Microphone permission is unavailable. Check Android permissions.';

  @override
  String get recordingStatusStorageLow =>
      'Internal storage is low. Free some space before recording.';

  @override
  String get recordingStatusAudioUnavailable =>
      'Microphone initialization failed. Another app may be using it.';

  @override
  String get recordingStatusQueueBusy =>
      'Audio buffer is busy. Recording may drop a little audio.';

  @override
  String get recordingStatusBackendUnavailable =>
      'Audio backend is not ready. Restart recording if this persists.';

  @override
  String get recordingStatusCaptureIssue =>
      'Audio capture encountered a problem.';

  @override
  String recordingStatusWithDetail(Object message, Object detail) {
    return '$message · Details: $detail';
  }

  @override
  String get standardRecordingMode => 'Standard recording mode';

  @override
  String get lockRecordingMode => 'Lock screen recording mode';

  @override
  String get lockRecordingStatusOff => 'Lock screen recording mode is off';

  @override
  String get lockRecordingStatusArmedScreenOff =>
      'Lock screen recording armed. Recording starts when the screen turns off.';

  @override
  String get lockRecordingStatusArmedKeyguard =>
      'Lock screen recording armed. Recording starts when the phone is locked.';

  @override
  String get lockRecordingStatusRecording =>
      'Lock screen recording is writing to the replay cache';

  @override
  String saveClip(Object duration) {
    return 'Save $duration';
  }

  @override
  String get pause => 'Pause';

  @override
  String get resume => 'Resume';

  @override
  String get chooseFolder => 'Choose folder';

  @override
  String get presetSaveDuration => 'Preset';

  @override
  String get customSaveDuration => 'Custom';

  @override
  String get customSaveSeconds => 'Save duration (seconds)';

  @override
  String get customSaveSecondsHelper => '1 to 86400 seconds';

  @override
  String get secondsUnit => 'sec';

  @override
  String secondsShort(int seconds) {
    return '${seconds}s';
  }

  @override
  String minutesShort(int minutes) {
    return '$minutes min';
  }

  @override
  String hoursShort(int hours) {
    return '$hours hr';
  }

  @override
  String hoursMinutesShort(int hours, int minutes) {
    return '$hours hr $minutes min';
  }

  @override
  String recentDurationName(Object duration) {
    return 'Last $duration';
  }

  @override
  String get loudnessTitle => 'Live loudness';

  @override
  String get silenceLabel => 'Silence';

  @override
  String get microphoneInputLabel => 'Mic input';

  @override
  String get notRecordingLabel => 'Not recording';

  @override
  String get peakLabel => 'Peak';

  @override
  String get libraryTitle => 'Recordings';

  @override
  String get unGrouped => 'Ungrouped';

  @override
  String get emptyRecordings => 'No recordings';

  @override
  String get selectAll => 'Select all';

  @override
  String get newGroup => 'New group';

  @override
  String get deleteSelected => 'Delete selected';

  @override
  String get stopPreview => 'Stop preview';

  @override
  String get done => 'Done';

  @override
  String get edit => 'Edit';

  @override
  String get refresh => 'Refresh';

  @override
  String get groupActions => 'Group actions';

  @override
  String get renameGroup => 'Rename group';

  @override
  String get deleteGroup => 'Delete group';

  @override
  String get preview => 'Preview';

  @override
  String get recordingActions => 'Recording actions';

  @override
  String get rename => 'Rename';

  @override
  String get moveToGroup => 'Move to group';

  @override
  String get delete => 'Delete';

  @override
  String get batchDeleteRecordings => 'Delete recordings';

  @override
  String confirmBatchDeleteRecordings(int count) {
    return 'Delete $count selected recordings? This cannot be undone.';
  }

  @override
  String get groupName => 'Group name';

  @override
  String get confirmDeleteGroup =>
      'Delete this group and every recording inside it? This cannot be undone.';

  @override
  String get renameRecording => 'Rename recording';

  @override
  String get deleteRecording => 'Delete recording';

  @override
  String get fileName => 'File name';

  @override
  String confirmDeleteRecording(Object name) {
    return 'Delete $name? This cannot be undone.';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get ok => 'OK';

  @override
  String get stop => 'Stop';

  @override
  String get processingTitle => 'Audio processing';

  @override
  String get sourceRecording => 'Source recording';

  @override
  String gainDb(Object gain) {
    return 'Gain $gain dB';
  }

  @override
  String get outputFormat => 'Output format';

  @override
  String get mp3Bitrate => 'MP3 bitrate';

  @override
  String get processing => 'Processing';

  @override
  String get generateProcessedCopy => 'Generate processed copy';

  @override
  String get processingComplete =>
      'Processing complete. A new recording file was created.';

  @override
  String get processingFailed =>
      'Processing failed. Check FFmpeg or the source file.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get recordingFolder => 'Recording folder';

  @override
  String get notSelected => 'Not selected';

  @override
  String get change => 'Change';

  @override
  String get recordingSettings => 'Recording settings';

  @override
  String get lockRecordingSettings => 'Lock screen recording';

  @override
  String get lockRecordingTrigger => 'Trigger';

  @override
  String get lockRecordingTriggerScreenOff => 'When screen turns off';

  @override
  String get lockRecordingTriggerKeyguard => 'When phone is locked';

  @override
  String get languageSettings => 'Language';

  @override
  String get appLanguage => 'App language';

  @override
  String get followSystemLanguage => 'Follow system';

  @override
  String get englishLanguage => 'English';

  @override
  String get chineseLanguage => '简体中文';

  @override
  String get androidSampleRate => 'Android sample rate';

  @override
  String get bufferDuration => 'Buffer duration';

  @override
  String get bufferDurationMinutes => 'Buffer duration (minutes)';

  @override
  String get bufferDurationHelper => '1 to 1440 minutes';

  @override
  String get minutesUnit => 'min';

  @override
  String estimatedPcmBuffer(Object size) {
    return 'Estimated PCM buffer: $size';
  }

  @override
  String pcmBufferSubtitle(Object sampleRate) {
    return '$sampleRate · mono · 16-bit PCM · changes while recording apply on next start';
  }

  @override
  String get cacheTitle => 'Cache';

  @override
  String currentCacheSize(Object size) {
    return 'Current cache size: $size';
  }

  @override
  String get clearCache => 'Clear cache';

  @override
  String get clearCacheSubtitle =>
      'Clear temporary export and processing cache; the active replay cache is preserved while recording';

  @override
  String get confirmClearCache =>
      'Clear EchoClip temporary cache? Saved recordings will not be deleted.';

  @override
  String cacheCleared(Object size) {
    return 'Cleared $size';
  }

  @override
  String cacheClearedActivePreserved(Object size) {
    return 'Cleared $size; active replay cache preserved';
  }

  @override
  String cacheClearFailed(Object error) {
    return 'Clear failed: $error';
  }

  @override
  String get aboutProject => 'Project';

  @override
  String get githubRepository => 'GitHub repository';

  @override
  String get githubRepositorySubtitle => 'View source code and documentation';

  @override
  String get licenseTitle => 'License';

  @override
  String get licenseSubtitle => 'GPL-3.0-only';

  @override
  String get issueFeedback => 'Report an issue';

  @override
  String get issueFeedbackSubtitle => 'Open GitHub Issues';

  @override
  String get windowsDemoMode => 'Windows demo mode';

  @override
  String get recordingSettingsSaved => 'Recording settings saved';

  @override
  String get settingsSavedNextRecording => 'Settings saved for next recording';

  @override
  String get recordingFolderReady => 'Recording folder ready';

  @override
  String folderSetupError(Object error) {
    return 'Folder setup error: $error';
  }

  @override
  String captureError(Object error) {
    return 'Capture error: $error';
  }

  @override
  String androidServiceRunning(Object backend) {
    return 'Android foreground service running · $backend';
  }

  @override
  String androidServiceStopped(Object backend) {
    return 'Android service stopped · $backend';
  }

  @override
  String androidServiceError(Object error) {
    return 'Android service error: $error';
  }

  @override
  String androidSaveError(Object error) {
    return 'Android save error: $error';
  }

  @override
  String get androidSaveStarted => 'Android save started';

  @override
  String get androidClipSaved => 'Android clip saved';

  @override
  String get previewPlaying => 'Preview playing';

  @override
  String previewError(Object error) {
    return 'Preview error: $error';
  }

  @override
  String get previewStopped => 'Preview stopped';

  @override
  String deletedRecordings(int count) {
    return 'Deleted $count recordings';
  }

  @override
  String deletedRecordingsWithError(int count, Object error) {
    return 'Deleted $count recordings, error: $error';
  }

  @override
  String processedRecording(Object name) {
    return 'Processed recording: $name';
  }

  @override
  String processingStatusError(Object error) {
    return 'Processing error: $error';
  }

  @override
  String cacheClearedStatus(Object size) {
    return 'Cache cleared: $size';
  }

  @override
  String clearCacheStatusError(Object error) {
    return 'Clear cache error: $error';
  }

  @override
  String get libraryUpdated => 'Library updated';

  @override
  String libraryError(Object error) {
    return 'Library error: $error';
  }

  @override
  String get unnamedGroup => 'Unnamed group';
}
