import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'EchoClip'**
  String get appTitle;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navLibrary.
  ///
  /// In en, this message translates to:
  /// **'Recordings'**
  String get navLibrary;

  /// No description provided for @navProcessing.
  ///
  /// In en, this message translates to:
  /// **'Processing'**
  String get navProcessing;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @replayRunning.
  ///
  /// In en, this message translates to:
  /// **'Instant replay running'**
  String get replayRunning;

  /// No description provided for @recordingPaused.
  ///
  /// In en, this message translates to:
  /// **'Recording paused'**
  String get recordingPaused;

  /// No description provided for @currentRecordingDuration.
  ///
  /// In en, this message translates to:
  /// **'This recording'**
  String get currentRecordingDuration;

  /// No description provided for @totalRecordedDuration.
  ///
  /// In en, this message translates to:
  /// **'Total buffered'**
  String get totalRecordedDuration;

  /// No description provided for @recordingStartedAt.
  ///
  /// In en, this message translates to:
  /// **'Started {time}'**
  String recordingStartedAt(Object time);

  /// No description provided for @lastRecordingStartedAt.
  ///
  /// In en, this message translates to:
  /// **'Last recording {time}'**
  String lastRecordingStartedAt(Object time);

  /// No description provided for @recordingStatusNormal.
  ///
  /// In en, this message translates to:
  /// **'Recording normally'**
  String get recordingStatusNormal;

  /// No description provided for @recordingStatusPaused.
  ///
  /// In en, this message translates to:
  /// **'Recording is paused'**
  String get recordingStatusPaused;

  /// No description provided for @recordingStatusPermissionLost.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission is unavailable. Check Android permissions.'**
  String get recordingStatusPermissionLost;

  /// No description provided for @recordingStatusStorageLow.
  ///
  /// In en, this message translates to:
  /// **'Internal storage is low. Free some space before recording.'**
  String get recordingStatusStorageLow;

  /// No description provided for @recordingStatusAudioUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Microphone initialization failed. Another app may be using it.'**
  String get recordingStatusAudioUnavailable;

  /// No description provided for @recordingStatusQueueBusy.
  ///
  /// In en, this message translates to:
  /// **'Audio buffer is busy. Recording may drop a little audio.'**
  String get recordingStatusQueueBusy;

  /// No description provided for @recordingStatusBackendUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Audio backend is not ready. Restart recording if this persists.'**
  String get recordingStatusBackendUnavailable;

  /// No description provided for @recordingStatusCaptureIssue.
  ///
  /// In en, this message translates to:
  /// **'Audio capture encountered a problem.'**
  String get recordingStatusCaptureIssue;

  /// No description provided for @recordingStatusWithDetail.
  ///
  /// In en, this message translates to:
  /// **'{message} · Details: {detail}'**
  String recordingStatusWithDetail(Object message, Object detail);

  /// No description provided for @standardRecordingMode.
  ///
  /// In en, this message translates to:
  /// **'Standard recording mode'**
  String get standardRecordingMode;

  /// No description provided for @lockRecordingMode.
  ///
  /// In en, this message translates to:
  /// **'Lock screen recording mode'**
  String get lockRecordingMode;

  /// No description provided for @lockRecordingStatusOff.
  ///
  /// In en, this message translates to:
  /// **'Lock screen recording mode is off'**
  String get lockRecordingStatusOff;

  /// No description provided for @lockRecordingStatusArmedScreenOff.
  ///
  /// In en, this message translates to:
  /// **'Lock screen recording armed. Recording starts when the screen turns off.'**
  String get lockRecordingStatusArmedScreenOff;

  /// No description provided for @lockRecordingStatusArmedKeyguard.
  ///
  /// In en, this message translates to:
  /// **'Lock screen recording armed. Recording starts when the phone is locked.'**
  String get lockRecordingStatusArmedKeyguard;

  /// No description provided for @lockRecordingStatusRecording.
  ///
  /// In en, this message translates to:
  /// **'Lock screen recording is writing to the replay cache'**
  String get lockRecordingStatusRecording;

  /// No description provided for @saveClip.
  ///
  /// In en, this message translates to:
  /// **'Save {duration}'**
  String saveClip(Object duration);

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @resume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resume;

  /// No description provided for @chooseFolder.
  ///
  /// In en, this message translates to:
  /// **'Choose folder'**
  String get chooseFolder;

  /// No description provided for @presetSaveDuration.
  ///
  /// In en, this message translates to:
  /// **'Preset'**
  String get presetSaveDuration;

  /// No description provided for @customSaveDuration.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get customSaveDuration;

  /// No description provided for @customSaveSeconds.
  ///
  /// In en, this message translates to:
  /// **'Save duration (seconds)'**
  String get customSaveSeconds;

  /// No description provided for @customSaveSecondsHelper.
  ///
  /// In en, this message translates to:
  /// **'1 to 86400 seconds'**
  String get customSaveSecondsHelper;

  /// No description provided for @secondsUnit.
  ///
  /// In en, this message translates to:
  /// **'sec'**
  String get secondsUnit;

  /// No description provided for @secondsShort.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s'**
  String secondsShort(int seconds);

  /// No description provided for @minutesShort.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String minutesShort(int minutes);

  /// No description provided for @hoursShort.
  ///
  /// In en, this message translates to:
  /// **'{hours} hr'**
  String hoursShort(int hours);

  /// No description provided for @hoursMinutesShort.
  ///
  /// In en, this message translates to:
  /// **'{hours} hr {minutes} min'**
  String hoursMinutesShort(int hours, int minutes);

  /// No description provided for @recentDurationName.
  ///
  /// In en, this message translates to:
  /// **'Last {duration}'**
  String recentDurationName(Object duration);

  /// No description provided for @loudnessTitle.
  ///
  /// In en, this message translates to:
  /// **'Live loudness'**
  String get loudnessTitle;

  /// No description provided for @silenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Silence'**
  String get silenceLabel;

  /// No description provided for @microphoneInputLabel.
  ///
  /// In en, this message translates to:
  /// **'Mic input'**
  String get microphoneInputLabel;

  /// No description provided for @notRecordingLabel.
  ///
  /// In en, this message translates to:
  /// **'Not recording'**
  String get notRecordingLabel;

  /// No description provided for @peakLabel.
  ///
  /// In en, this message translates to:
  /// **'Peak'**
  String get peakLabel;

  /// No description provided for @libraryTitle.
  ///
  /// In en, this message translates to:
  /// **'Recordings'**
  String get libraryTitle;

  /// No description provided for @unGrouped.
  ///
  /// In en, this message translates to:
  /// **'Ungrouped'**
  String get unGrouped;

  /// No description provided for @emptyRecordings.
  ///
  /// In en, this message translates to:
  /// **'No recordings'**
  String get emptyRecordings;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// No description provided for @newGroup.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get newGroup;

  /// No description provided for @deleteSelected.
  ///
  /// In en, this message translates to:
  /// **'Delete selected'**
  String get deleteSelected;

  /// No description provided for @stopPreview.
  ///
  /// In en, this message translates to:
  /// **'Stop preview'**
  String get stopPreview;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @groupActions.
  ///
  /// In en, this message translates to:
  /// **'Group actions'**
  String get groupActions;

  /// No description provided for @renameGroup.
  ///
  /// In en, this message translates to:
  /// **'Rename group'**
  String get renameGroup;

  /// No description provided for @deleteGroup.
  ///
  /// In en, this message translates to:
  /// **'Delete group'**
  String get deleteGroup;

  /// No description provided for @preview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview;

  /// No description provided for @recordingActions.
  ///
  /// In en, this message translates to:
  /// **'Recording actions'**
  String get recordingActions;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @moveToGroup.
  ///
  /// In en, this message translates to:
  /// **'Move to group'**
  String get moveToGroup;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @batchDeleteRecordings.
  ///
  /// In en, this message translates to:
  /// **'Delete recordings'**
  String get batchDeleteRecordings;

  /// No description provided for @confirmBatchDeleteRecordings.
  ///
  /// In en, this message translates to:
  /// **'Delete {count} selected recordings? This cannot be undone.'**
  String confirmBatchDeleteRecordings(int count);

  /// No description provided for @groupName.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get groupName;

  /// No description provided for @confirmDeleteGroup.
  ///
  /// In en, this message translates to:
  /// **'Delete this group and every recording inside it? This cannot be undone.'**
  String get confirmDeleteGroup;

  /// No description provided for @renameRecording.
  ///
  /// In en, this message translates to:
  /// **'Rename recording'**
  String get renameRecording;

  /// No description provided for @deleteRecording.
  ///
  /// In en, this message translates to:
  /// **'Delete recording'**
  String get deleteRecording;

  /// No description provided for @fileName.
  ///
  /// In en, this message translates to:
  /// **'File name'**
  String get fileName;

  /// No description provided for @confirmDeleteRecording.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}? This cannot be undone.'**
  String confirmDeleteRecording(Object name);

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// No description provided for @processingTitle.
  ///
  /// In en, this message translates to:
  /// **'Audio processing'**
  String get processingTitle;

  /// No description provided for @sourceRecording.
  ///
  /// In en, this message translates to:
  /// **'Source recording'**
  String get sourceRecording;

  /// No description provided for @gainDb.
  ///
  /// In en, this message translates to:
  /// **'Gain {gain} dB'**
  String gainDb(Object gain);

  /// No description provided for @outputFormat.
  ///
  /// In en, this message translates to:
  /// **'Output format'**
  String get outputFormat;

  /// No description provided for @mp3Bitrate.
  ///
  /// In en, this message translates to:
  /// **'MP3 bitrate'**
  String get mp3Bitrate;

  /// No description provided for @processing.
  ///
  /// In en, this message translates to:
  /// **'Processing'**
  String get processing;

  /// No description provided for @generateProcessedCopy.
  ///
  /// In en, this message translates to:
  /// **'Generate processed copy'**
  String get generateProcessedCopy;

  /// No description provided for @processingComplete.
  ///
  /// In en, this message translates to:
  /// **'Processing complete. A new recording file was created.'**
  String get processingComplete;

  /// No description provided for @processingFailed.
  ///
  /// In en, this message translates to:
  /// **'Processing failed. Check FFmpeg or the source file.'**
  String get processingFailed;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @recordingFolder.
  ///
  /// In en, this message translates to:
  /// **'Recording folder'**
  String get recordingFolder;

  /// No description provided for @notSelected.
  ///
  /// In en, this message translates to:
  /// **'Not selected'**
  String get notSelected;

  /// No description provided for @change.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// No description provided for @recordingSettings.
  ///
  /// In en, this message translates to:
  /// **'Recording settings'**
  String get recordingSettings;

  /// No description provided for @lockRecordingSettings.
  ///
  /// In en, this message translates to:
  /// **'Lock screen recording'**
  String get lockRecordingSettings;

  /// No description provided for @lockRecordingTrigger.
  ///
  /// In en, this message translates to:
  /// **'Trigger'**
  String get lockRecordingTrigger;

  /// No description provided for @lockRecordingTriggerScreenOff.
  ///
  /// In en, this message translates to:
  /// **'When screen turns off'**
  String get lockRecordingTriggerScreenOff;

  /// No description provided for @lockRecordingTriggerKeyguard.
  ///
  /// In en, this message translates to:
  /// **'When phone is locked'**
  String get lockRecordingTriggerKeyguard;

  /// No description provided for @languageSettings.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageSettings;

  /// No description provided for @appLanguage.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get appLanguage;

  /// No description provided for @followSystemLanguage.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get followSystemLanguage;

  /// No description provided for @englishLanguage.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get englishLanguage;

  /// No description provided for @chineseLanguage.
  ///
  /// In en, this message translates to:
  /// **'简体中文'**
  String get chineseLanguage;

  /// No description provided for @androidSampleRate.
  ///
  /// In en, this message translates to:
  /// **'Android sample rate'**
  String get androidSampleRate;

  /// No description provided for @bufferDuration.
  ///
  /// In en, this message translates to:
  /// **'Buffer duration'**
  String get bufferDuration;

  /// No description provided for @bufferDurationMinutes.
  ///
  /// In en, this message translates to:
  /// **'Buffer duration (minutes)'**
  String get bufferDurationMinutes;

  /// No description provided for @bufferDurationHelper.
  ///
  /// In en, this message translates to:
  /// **'1 to 1440 minutes'**
  String get bufferDurationHelper;

  /// No description provided for @minutesUnit.
  ///
  /// In en, this message translates to:
  /// **'min'**
  String get minutesUnit;

  /// No description provided for @estimatedPcmBuffer.
  ///
  /// In en, this message translates to:
  /// **'Estimated PCM buffer: {size}'**
  String estimatedPcmBuffer(Object size);

  /// No description provided for @pcmBufferSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{sampleRate} · mono · 16-bit PCM · changes while recording apply on next start'**
  String pcmBufferSubtitle(Object sampleRate);

  /// No description provided for @cacheTitle.
  ///
  /// In en, this message translates to:
  /// **'Cache'**
  String get cacheTitle;

  /// No description provided for @currentCacheSize.
  ///
  /// In en, this message translates to:
  /// **'Current cache size: {size}'**
  String currentCacheSize(Object size);

  /// No description provided for @clearCache.
  ///
  /// In en, this message translates to:
  /// **'Clear cache'**
  String get clearCache;

  /// No description provided for @clearCacheSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Clear temporary export and processing cache; the active replay cache is preserved while recording'**
  String get clearCacheSubtitle;

  /// No description provided for @confirmClearCache.
  ///
  /// In en, this message translates to:
  /// **'Clear EchoClip temporary cache? Saved recordings will not be deleted.'**
  String get confirmClearCache;

  /// No description provided for @cacheCleared.
  ///
  /// In en, this message translates to:
  /// **'Cleared {size}'**
  String cacheCleared(Object size);

  /// No description provided for @cacheClearedActivePreserved.
  ///
  /// In en, this message translates to:
  /// **'Cleared {size}; active replay cache preserved'**
  String cacheClearedActivePreserved(Object size);

  /// No description provided for @cacheClearFailed.
  ///
  /// In en, this message translates to:
  /// **'Clear failed: {error}'**
  String cacheClearFailed(Object error);

  /// No description provided for @aboutProject.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get aboutProject;

  /// No description provided for @githubRepository.
  ///
  /// In en, this message translates to:
  /// **'GitHub repository'**
  String get githubRepository;

  /// No description provided for @githubRepositorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'View source code and documentation'**
  String get githubRepositorySubtitle;

  /// No description provided for @licenseTitle.
  ///
  /// In en, this message translates to:
  /// **'License'**
  String get licenseTitle;

  /// No description provided for @licenseSubtitle.
  ///
  /// In en, this message translates to:
  /// **'GPL-3.0-only'**
  String get licenseSubtitle;

  /// No description provided for @issueFeedback.
  ///
  /// In en, this message translates to:
  /// **'Report an issue'**
  String get issueFeedback;

  /// No description provided for @issueFeedbackSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Open GitHub Issues'**
  String get issueFeedbackSubtitle;

  /// No description provided for @windowsDemoMode.
  ///
  /// In en, this message translates to:
  /// **'Windows demo mode'**
  String get windowsDemoMode;

  /// No description provided for @recordingSettingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Recording settings saved'**
  String get recordingSettingsSaved;

  /// No description provided for @settingsSavedNextRecording.
  ///
  /// In en, this message translates to:
  /// **'Settings saved for next recording'**
  String get settingsSavedNextRecording;

  /// No description provided for @recordingFolderReady.
  ///
  /// In en, this message translates to:
  /// **'Recording folder ready'**
  String get recordingFolderReady;

  /// No description provided for @folderSetupError.
  ///
  /// In en, this message translates to:
  /// **'Folder setup error: {error}'**
  String folderSetupError(Object error);

  /// No description provided for @captureError.
  ///
  /// In en, this message translates to:
  /// **'Capture error: {error}'**
  String captureError(Object error);

  /// No description provided for @androidServiceRunning.
  ///
  /// In en, this message translates to:
  /// **'Android foreground service running · {backend}'**
  String androidServiceRunning(Object backend);

  /// No description provided for @androidServiceStopped.
  ///
  /// In en, this message translates to:
  /// **'Android service stopped · {backend}'**
  String androidServiceStopped(Object backend);

  /// No description provided for @androidServiceError.
  ///
  /// In en, this message translates to:
  /// **'Android service error: {error}'**
  String androidServiceError(Object error);

  /// No description provided for @androidSaveError.
  ///
  /// In en, this message translates to:
  /// **'Android save error: {error}'**
  String androidSaveError(Object error);

  /// No description provided for @androidSaveStarted.
  ///
  /// In en, this message translates to:
  /// **'Android save started'**
  String get androidSaveStarted;

  /// No description provided for @androidClipSaved.
  ///
  /// In en, this message translates to:
  /// **'Android clip saved'**
  String get androidClipSaved;

  /// No description provided for @previewPlaying.
  ///
  /// In en, this message translates to:
  /// **'Preview playing'**
  String get previewPlaying;

  /// No description provided for @previewError.
  ///
  /// In en, this message translates to:
  /// **'Preview error: {error}'**
  String previewError(Object error);

  /// No description provided for @previewStopped.
  ///
  /// In en, this message translates to:
  /// **'Preview stopped'**
  String get previewStopped;

  /// No description provided for @deletedRecordings.
  ///
  /// In en, this message translates to:
  /// **'Deleted {count} recordings'**
  String deletedRecordings(int count);

  /// No description provided for @deletedRecordingsWithError.
  ///
  /// In en, this message translates to:
  /// **'Deleted {count} recordings, error: {error}'**
  String deletedRecordingsWithError(int count, Object error);

  /// No description provided for @processedRecording.
  ///
  /// In en, this message translates to:
  /// **'Processed recording: {name}'**
  String processedRecording(Object name);

  /// No description provided for @processingStatusError.
  ///
  /// In en, this message translates to:
  /// **'Processing error: {error}'**
  String processingStatusError(Object error);

  /// No description provided for @cacheClearedStatus.
  ///
  /// In en, this message translates to:
  /// **'Cache cleared: {size}'**
  String cacheClearedStatus(Object size);

  /// No description provided for @clearCacheStatusError.
  ///
  /// In en, this message translates to:
  /// **'Clear cache error: {error}'**
  String clearCacheStatusError(Object error);

  /// No description provided for @libraryUpdated.
  ///
  /// In en, this message translates to:
  /// **'Library updated'**
  String get libraryUpdated;

  /// No description provided for @libraryError.
  ///
  /// In en, this message translates to:
  /// **'Library error: {error}'**
  String libraryError(Object error);

  /// No description provided for @unnamedGroup.
  ///
  /// In en, this message translates to:
  /// **'Unnamed group'**
  String get unnamedGroup;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
