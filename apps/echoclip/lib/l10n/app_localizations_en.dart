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
  String get showWindow => 'Show window';

  @override
  String get hideWindow => 'Hide window';

  @override
  String get exitApp => 'Exit EchoClip';

  @override
  String get navHome => 'Home';

  @override
  String get navLibrary => 'Recordings';

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
  String get lastRecordingTimeUnavailable => 'No previous recording time';

  @override
  String get recordingStatusNormal => 'Recording normally';

  @override
  String get recordingStatusPaused => 'Recording is paused';

  @override
  String get recordingStatusPermissionLost =>
      'Microphone permission is unavailable. Check the system privacy settings.';

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
  String get loudnessRecordingLabel => 'Recording';

  @override
  String get loudnessHistoryLabel => 'Last 6 seconds';

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
  String get saveRecentLabel => 'Save recent audio';

  @override
  String get chooseSaveDuration => 'Choose duration';

  @override
  String libraryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count recordings',
      one: '1 recording',
    );
    return '$_temp0';
  }

  @override
  String librarySelected(int count) {
    return '$count selected';
  }

  @override
  String get allRecordings => 'All';

  @override
  String get searchRecordings => 'Search recordings';

  @override
  String get clearSearch => 'Clear search';

  @override
  String get sortRecordings => 'Sort recordings';

  @override
  String get libraryNewest => 'Newest first';

  @override
  String get libraryOldest => 'Oldest first';

  @override
  String get libraryNameOrder => 'File name';

  @override
  String get librarySize => 'Size';

  @override
  String get librarySavedAt => 'Saved at';

  @override
  String get libraryNoMatches => 'No matching recordings';

  @override
  String get librarySearchHint =>
      'Try another name or choose a different group.';

  @override
  String get libraryEmptyHint => 'Save a clip from Home to see it here.';

  @override
  String get audioFileLabel => 'Audio';

  @override
  String get playbackSpeed => 'Playback speed';

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
  String get outputFormat => 'Output format';

  @override
  String get mp3Bitrate => 'MP3 bitrate';

  @override
  String get settingsOverview => 'Recording, storage and preferences';

  @override
  String get internalStorage => 'Internal storage';

  @override
  String scheduleTaskCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tasks',
      one: '1 task',
    );
    return '$_temp0';
  }

  @override
  String get scheduleEmptyHint => 'Create a task or start from a saved preset.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get serverSettings => 'Server settings';

  @override
  String get serverSettingsDescription =>
      'Configure encrypted real-time upload and review connection history';

  @override
  String get serverConnectionDetails => 'Server connection';

  @override
  String get serverNotConfigured => 'Not configured';

  @override
  String get serverSyncDisabled => 'Sync disabled';

  @override
  String get serverConnected => 'Connected';

  @override
  String get serverConnectionFailed => 'Connection failed';

  @override
  String get serverConnecting => 'Connecting';

  @override
  String get serverSyncEnabled => 'Upload while recording';

  @override
  String get serverSyncEnabledDescription =>
      'Upload only PCM recorded after this switch is enabled; network retries never read older cache';

  @override
  String get serverHost => 'IP address or domain';

  @override
  String get serverUploadPort => 'Upload port';

  @override
  String get serverUploadKey => 'Unique upload key';

  @override
  String get serverUploadKeyConfigured =>
      'A protected key is already configured. Leave blank to keep it.';

  @override
  String get serverUploadKeyRequired =>
      'Enter the 32-byte Base64 key generated by the server';

  @override
  String get serverUploadKeyInvalid =>
      'The upload key must be a valid Base64 encoding of exactly 32 bytes';

  @override
  String get serverDeviceId => 'Client device ID';

  @override
  String get saveSettings => 'Save settings';

  @override
  String get serverTestConnection => 'Test connection';

  @override
  String get serverTestingConnection => 'Testing connection…';

  @override
  String get serverConnectionTestSucceeded => 'Server connection succeeded';

  @override
  String get serverConnectionTestFailed => 'Server connection failed';

  @override
  String get removeServerKey => 'Remove key';

  @override
  String get serverConnectionStatus => 'Connection status';

  @override
  String get serverConnectionLogs => 'Connection logs and disconnect history';

  @override
  String get noServerConnectionLogs =>
      'No connection events recorded in this app session';

  @override
  String get serverHostInvalid =>
      'Enter an IP address or domain without http:// or a path';

  @override
  String get serverUploadPortInvalid => 'Enter an upload port from 1 to 65535';

  @override
  String serverUploadLag(int samples) {
    return 'Pending upload: $samples samples';
  }

  @override
  String serverReconnectCount(int count) {
    return 'Reconnects: $count';
  }

  @override
  String serverKeyId(Object keyId) {
    return 'Key ID: $keyId';
  }

  @override
  String get serverEventStarted => 'Sync started';

  @override
  String get serverEventConnected => 'Connected';

  @override
  String get serverEventDisconnected => 'Disconnected';

  @override
  String get serverEventRetentionGap => 'Local retention gap';

  @override
  String get serverEventStopped => 'Sync stopped';

  @override
  String get close => 'Close';

  @override
  String get recordingFolder => 'Recording folder';

  @override
  String get notSelected => 'Not selected';

  @override
  String get change => 'Change';

  @override
  String get recordingSettings => 'Recording settings';

  @override
  String get audioSources => 'Audio sources';

  @override
  String get audioSourcesDescription =>
      'Choose one or both sources. EchoClip mixes them into the same replay buffer.';

  @override
  String get recordMicrophone => 'Record microphone';

  @override
  String get recordMicrophoneDescription =>
      'Capture voice and other sounds from the selected input device';

  @override
  String get recordSystemAudio => 'Record system audio';

  @override
  String get recordSystemAudioDescription =>
      'Capture the sound currently playing through Windows';

  @override
  String get systemAudioUnavailable =>
      'System audio capture is not available on this platform';

  @override
  String get inputDevice => 'Microphone input device';

  @override
  String get systemDefaultInputDevice => 'System default input device';

  @override
  String get inputDeviceManagedBySystem => 'Managed by the system';

  @override
  String get noInputDevices => 'No input devices found';

  @override
  String get unavailableInputDevice =>
      'Selected input device is currently unavailable';

  @override
  String get refreshInputDevices => 'Refresh input devices';

  @override
  String defaultInputDevice(Object name) {
    return '$name (current default)';
  }

  @override
  String get audioSourceRequired => 'Keep at least one audio source selected';

  @override
  String get audioSourceSettingsSaved => 'Audio source settings saved';

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
  String get sampleRate => 'Sample rate';

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
      'Clear temporary export cache; the active replay cache is preserved while recording';

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
  String get windowsRecordingMode => 'Windows microphone recording';

  @override
  String get windowsRecordingModeDescription =>
      'Windows uses standard instant replay recording. Lock-screen triggers are available on Android only.';

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
  String serviceError(Object error) {
    return 'Recording service error: $error';
  }

  @override
  String saveError(Object error) {
    return 'Save error: $error';
  }

  @override
  String get saveStarted => 'Saving recording';

  @override
  String get clipSaved => 'Recording saved';

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

  @override
  String get navScheduledTasks => 'Scheduled tasks';

  @override
  String get scheduledTasksTitle => 'Scheduled tasks';

  @override
  String get newScheduledTask => 'New task';

  @override
  String scheduleOperationFailed(Object error) {
    return 'Scheduled task operation failed: $error';
  }

  @override
  String get loadingScheduledTasks => 'Loading scheduled tasks…';

  @override
  String get noScheduledTasks => 'No scheduled tasks';

  @override
  String get requestExactAlarm => 'Allow exact alarms';

  @override
  String get noUpcomingTask => 'No task is waiting to run';

  @override
  String nextScheduledTask(Object remaining, Object time) {
    return 'Next run: $time ($remaining remaining)';
  }

  @override
  String scheduleDue(Object remaining, Object time) {
    return 'Scheduled $time ($remaining remaining)';
  }

  @override
  String get scheduleHistory => 'Execution history';

  @override
  String get noScheduleHistory => 'No execution history';

  @override
  String schedulePlannedAt(Object time) {
    return 'Planned $time';
  }

  @override
  String scheduleStartedAt(Object time) {
    return 'Started $time';
  }

  @override
  String scheduleLateBy(Object duration) {
    return 'Late by $duration';
  }

  @override
  String get deleteScheduledTask => 'Delete scheduled task';

  @override
  String confirmDeleteScheduledTask(Object name) {
    return 'Delete “$name”? Existing execution history is kept.';
  }

  @override
  String get editScheduledTask => 'Edit scheduled task';

  @override
  String get scheduleName => 'Task name';

  @override
  String get scheduleTaskSettings => 'Task settings';

  @override
  String get scheduleRunTime => 'Run time';

  @override
  String get scheduleActionsAtRun => 'Actions when the task runs';

  @override
  String get scheduleHours => 'Hours';

  @override
  String get scheduleMinutes => 'Minutes';

  @override
  String get scheduleSeconds => 'Seconds';

  @override
  String scheduleChooseDate(Object date) {
    return 'Date: $date';
  }

  @override
  String get scheduleCountdown => 'Countdown';

  @override
  String get scheduleTimePoint => 'Time point';

  @override
  String get scheduleRecordingAction => 'Recording action';

  @override
  String get scheduleNoChange => 'No change';

  @override
  String get scheduleStartRecording => 'Start recording';

  @override
  String get scheduleStopRecording => 'Stop recording';

  @override
  String get scheduleUploadAction => 'Live upload';

  @override
  String get scheduleEnableUpload => 'Enable upload';

  @override
  String get scheduleDisableUpload => 'Disable upload';

  @override
  String get scheduleSaveRecent => 'Save recent audio';

  @override
  String get scheduleSaveSeconds => 'Save duration (seconds)';

  @override
  String get scheduleAllowPartial =>
      'Save available audio when the buffer is shorter';

  @override
  String get scheduleEnabled => 'Enable task after saving';

  @override
  String get saveScheduledTask => 'Save task';

  @override
  String get scheduleSaveFailed =>
      'Could not save the task. Check the input and platform state.';

  @override
  String get scheduleNameRequired => 'Enter a task name.';

  @override
  String get scheduleActionRequired => 'Select at least one action.';

  @override
  String get scheduleCountdownRequired =>
      'The countdown must be greater than 0 seconds.';

  @override
  String get scheduleTimePointPast =>
      'The selected time must be in the future.';

  @override
  String get scheduleSaveDurationInvalid =>
      'Save duration must be between 1 and 86400 seconds.';

  @override
  String scheduleCountdownWithDuration(Object duration) {
    return 'Countdown $duration';
  }

  @override
  String scheduleSaveActionSummary(Object format, Object seconds) {
    return 'Save recent $seconds s · $format';
  }

  @override
  String get convertWavToMp3 => 'Convert to MP3';

  @override
  String get convertWavBitrate => 'Choose MP3 bitrate';

  @override
  String get convertingWavToMp3 => 'Converting WAV…';

  @override
  String convertedWavToMp3(Object name) {
    return 'Created MP3: $name';
  }

  @override
  String convertWavToMp3Failed(Object error) {
    return 'WAV to MP3 failed: $error';
  }

  @override
  String get scheduleNameAutomatic => 'Leave blank to generate a name';

  @override
  String get scheduleTaskNamePrefix => 'Task';

  @override
  String get schedulePresetNamePrefix => 'Preset';

  @override
  String get saveSchedulePreset => 'Save preset';

  @override
  String get deleteSchedulePreset => 'Delete preset';

  @override
  String schedulePresetsTitle(int count) {
    return 'Task presets ($count/9)';
  }

  @override
  String get schedulePresetsHint =>
      'Save up to 9 presets in the task editor to quickly create tasks later.';

  @override
  String confirmDeleteSchedulePreset(String name) {
    return 'Delete preset “$name”? Existing tasks will be kept.';
  }

  @override
  String get schedulePresetLimit =>
      'You can save up to 9 presets. Delete a preset first.';

  @override
  String get saveInProgress => 'Saving · Cancel';

  @override
  String get saveCanceling => 'Canceling…';

  @override
  String get saveCanceled => 'Save canceled';

  @override
  String saveWritingProgress(int progress) {
    return 'Writing $progress% · Cancel';
  }

  @override
  String get shareRecording => 'Share';

  @override
  String get shareRecordingFailed =>
      'Unable to share. Check that the recording exists and folder access is allowed.';

  @override
  String get saveFailedStatus => 'Save failed';

  @override
  String get saveCancelFailedStatus => 'Cancel failed';

  @override
  String get saveCancelingStatus => 'Canceling save';

  @override
  String get saveWritingStatus => 'Writing audio';
}
