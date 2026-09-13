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

  /// No description provided for @showWindow.
  ///
  /// In en, this message translates to:
  /// **'Show window'**
  String get showWindow;

  /// No description provided for @hideWindow.
  ///
  /// In en, this message translates to:
  /// **'Hide window'**
  String get hideWindow;

  /// No description provided for @exitApp.
  ///
  /// In en, this message translates to:
  /// **'Exit EchoClip'**
  String get exitApp;

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

  /// No description provided for @lastRecordingTimeUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No previous recording time'**
  String get lastRecordingTimeUnavailable;

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
  /// **'Microphone permission is unavailable. Check the system privacy settings.'**
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

  /// No description provided for @loudnessRecordingLabel.
  ///
  /// In en, this message translates to:
  /// **'Recording'**
  String get loudnessRecordingLabel;

  /// No description provided for @loudnessHistoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Last 6 seconds'**
  String get loudnessHistoryLabel;

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

  /// No description provided for @saveRecentLabel.
  ///
  /// In en, this message translates to:
  /// **'Save recent audio'**
  String get saveRecentLabel;

  /// No description provided for @chooseSaveDuration.
  ///
  /// In en, this message translates to:
  /// **'Choose duration'**
  String get chooseSaveDuration;

  /// No description provided for @libraryCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 recording} other{{count} recordings}}'**
  String libraryCount(int count);

  /// No description provided for @librarySelected.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String librarySelected(int count);

  /// No description provided for @allRecordings.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get allRecordings;

  /// No description provided for @searchRecordings.
  ///
  /// In en, this message translates to:
  /// **'Search recordings'**
  String get searchRecordings;

  /// No description provided for @clearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get clearSearch;

  /// No description provided for @sortRecordings.
  ///
  /// In en, this message translates to:
  /// **'Sort recordings'**
  String get sortRecordings;

  /// No description provided for @libraryNewest.
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get libraryNewest;

  /// No description provided for @libraryOldest.
  ///
  /// In en, this message translates to:
  /// **'Oldest first'**
  String get libraryOldest;

  /// No description provided for @libraryNameOrder.
  ///
  /// In en, this message translates to:
  /// **'File name'**
  String get libraryNameOrder;

  /// No description provided for @librarySize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get librarySize;

  /// No description provided for @librarySavedAt.
  ///
  /// In en, this message translates to:
  /// **'Saved at'**
  String get librarySavedAt;

  /// No description provided for @libraryNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matching recordings'**
  String get libraryNoMatches;

  /// No description provided for @librarySearchHint.
  ///
  /// In en, this message translates to:
  /// **'Try another name or choose a different group.'**
  String get librarySearchHint;

  /// No description provided for @libraryEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Save a clip from Home to see it here.'**
  String get libraryEmptyHint;

  /// No description provided for @audioFileLabel.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get audioFileLabel;

  /// No description provided for @playbackSpeed.
  ///
  /// In en, this message translates to:
  /// **'Playback speed'**
  String get playbackSpeed;

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

  /// No description provided for @settingsOverview.
  ///
  /// In en, this message translates to:
  /// **'Recording, storage and preferences'**
  String get settingsOverview;

  /// No description provided for @internalStorage.
  ///
  /// In en, this message translates to:
  /// **'Internal storage'**
  String get internalStorage;

  /// No description provided for @scheduleTaskCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 task} other{{count} tasks}}'**
  String scheduleTaskCount(int count);

  /// No description provided for @scheduleEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Create a task or start from a saved preset.'**
  String get scheduleEmptyHint;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @serverSettings.
  ///
  /// In en, this message translates to:
  /// **'Server settings'**
  String get serverSettings;

  /// No description provided for @serverSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Configure encrypted real-time upload and review connection history'**
  String get serverSettingsDescription;

  /// No description provided for @serverConnectionDetails.
  ///
  /// In en, this message translates to:
  /// **'Server connection'**
  String get serverConnectionDetails;

  /// No description provided for @serverNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Not configured'**
  String get serverNotConfigured;

  /// No description provided for @serverSyncDisabled.
  ///
  /// In en, this message translates to:
  /// **'Sync disabled'**
  String get serverSyncDisabled;

  /// No description provided for @serverConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get serverConnected;

  /// No description provided for @serverConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed'**
  String get serverConnectionFailed;

  /// No description provided for @serverConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get serverConnecting;

  /// No description provided for @serverSyncEnabled.
  ///
  /// In en, this message translates to:
  /// **'Upload while recording'**
  String get serverSyncEnabled;

  /// No description provided for @serverSyncEnabledDescription.
  ///
  /// In en, this message translates to:
  /// **'Upload only PCM recorded after this switch is enabled; network retries never read older cache'**
  String get serverSyncEnabledDescription;

  /// No description provided for @serverHost.
  ///
  /// In en, this message translates to:
  /// **'IP address or domain'**
  String get serverHost;

  /// No description provided for @serverUploadPort.
  ///
  /// In en, this message translates to:
  /// **'Upload port'**
  String get serverUploadPort;

  /// No description provided for @serverUploadKey.
  ///
  /// In en, this message translates to:
  /// **'Unique upload key'**
  String get serverUploadKey;

  /// No description provided for @serverUploadKeyConfigured.
  ///
  /// In en, this message translates to:
  /// **'A protected key is already configured. Leave blank to keep it.'**
  String get serverUploadKeyConfigured;

  /// No description provided for @serverUploadKeyRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter the 32-byte Base64 key generated by the server'**
  String get serverUploadKeyRequired;

  /// No description provided for @serverUploadKeyInvalid.
  ///
  /// In en, this message translates to:
  /// **'The upload key must be a valid Base64 encoding of exactly 32 bytes'**
  String get serverUploadKeyInvalid;

  /// No description provided for @serverDeviceId.
  ///
  /// In en, this message translates to:
  /// **'Client device ID'**
  String get serverDeviceId;

  /// No description provided for @saveSettings.
  ///
  /// In en, this message translates to:
  /// **'Save settings'**
  String get saveSettings;

  /// No description provided for @serverTestConnection.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get serverTestConnection;

  /// No description provided for @serverTestingConnection.
  ///
  /// In en, this message translates to:
  /// **'Testing connection…'**
  String get serverTestingConnection;

  /// No description provided for @serverConnectionTestSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Server connection succeeded'**
  String get serverConnectionTestSucceeded;

  /// No description provided for @serverConnectionTestFailed.
  ///
  /// In en, this message translates to:
  /// **'Server connection failed'**
  String get serverConnectionTestFailed;

  /// No description provided for @removeServerKey.
  ///
  /// In en, this message translates to:
  /// **'Remove key'**
  String get removeServerKey;

  /// No description provided for @serverConnectionStatus.
  ///
  /// In en, this message translates to:
  /// **'Connection status'**
  String get serverConnectionStatus;

  /// No description provided for @serverConnectionLogs.
  ///
  /// In en, this message translates to:
  /// **'Connection logs and disconnect history'**
  String get serverConnectionLogs;

  /// No description provided for @noServerConnectionLogs.
  ///
  /// In en, this message translates to:
  /// **'No connection events recorded in this app session'**
  String get noServerConnectionLogs;

  /// No description provided for @serverHostInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter an IP address or domain without http:// or a path'**
  String get serverHostInvalid;

  /// No description provided for @serverUploadPortInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter an upload port from 1 to 65535'**
  String get serverUploadPortInvalid;

  /// No description provided for @serverUploadLag.
  ///
  /// In en, this message translates to:
  /// **'Pending upload: {samples} samples'**
  String serverUploadLag(int samples);

  /// No description provided for @serverReconnectCount.
  ///
  /// In en, this message translates to:
  /// **'Reconnects: {count}'**
  String serverReconnectCount(int count);

  /// No description provided for @serverKeyId.
  ///
  /// In en, this message translates to:
  /// **'Key ID: {keyId}'**
  String serverKeyId(Object keyId);

  /// No description provided for @serverEventStarted.
  ///
  /// In en, this message translates to:
  /// **'Sync started'**
  String get serverEventStarted;

  /// No description provided for @serverEventConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get serverEventConnected;

  /// No description provided for @serverEventDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get serverEventDisconnected;

  /// No description provided for @serverEventRetentionGap.
  ///
  /// In en, this message translates to:
  /// **'Local retention gap'**
  String get serverEventRetentionGap;

  /// No description provided for @serverEventStopped.
  ///
  /// In en, this message translates to:
  /// **'Sync stopped'**
  String get serverEventStopped;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

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

  /// No description provided for @audioSources.
  ///
  /// In en, this message translates to:
  /// **'Audio sources'**
  String get audioSources;

  /// No description provided for @audioSourcesDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose one or both sources. EchoClip mixes them into the same replay buffer.'**
  String get audioSourcesDescription;

  /// No description provided for @recordMicrophone.
  ///
  /// In en, this message translates to:
  /// **'Record microphone'**
  String get recordMicrophone;

  /// No description provided for @recordMicrophoneDescription.
  ///
  /// In en, this message translates to:
  /// **'Capture voice and other sounds from the selected input device'**
  String get recordMicrophoneDescription;

  /// No description provided for @recordSystemAudio.
  ///
  /// In en, this message translates to:
  /// **'Record system audio'**
  String get recordSystemAudio;

  /// No description provided for @recordSystemAudioDescription.
  ///
  /// In en, this message translates to:
  /// **'Capture the sound currently playing through Windows'**
  String get recordSystemAudioDescription;

  /// No description provided for @systemAudioUnavailable.
  ///
  /// In en, this message translates to:
  /// **'System audio capture is not available on this platform'**
  String get systemAudioUnavailable;

  /// No description provided for @inputDevice.
  ///
  /// In en, this message translates to:
  /// **'Microphone input device'**
  String get inputDevice;

  /// No description provided for @systemDefaultInputDevice.
  ///
  /// In en, this message translates to:
  /// **'System default input device'**
  String get systemDefaultInputDevice;

  /// No description provided for @inputDeviceManagedBySystem.
  ///
  /// In en, this message translates to:
  /// **'Managed by the system'**
  String get inputDeviceManagedBySystem;

  /// No description provided for @noInputDevices.
  ///
  /// In en, this message translates to:
  /// **'No input devices found'**
  String get noInputDevices;

  /// No description provided for @unavailableInputDevice.
  ///
  /// In en, this message translates to:
  /// **'Selected input device is currently unavailable'**
  String get unavailableInputDevice;

  /// No description provided for @refreshInputDevices.
  ///
  /// In en, this message translates to:
  /// **'Refresh input devices'**
  String get refreshInputDevices;

  /// No description provided for @defaultInputDevice.
  ///
  /// In en, this message translates to:
  /// **'{name} (current default)'**
  String defaultInputDevice(Object name);

  /// No description provided for @audioSourceRequired.
  ///
  /// In en, this message translates to:
  /// **'Keep at least one audio source selected'**
  String get audioSourceRequired;

  /// No description provided for @audioSourceSettingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Audio source settings saved'**
  String get audioSourceSettingsSaved;

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

  /// No description provided for @sampleRate.
  ///
  /// In en, this message translates to:
  /// **'Sample rate'**
  String get sampleRate;

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
  /// **'Clear temporary export cache; the active replay cache is preserved while recording'**
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

  /// No description provided for @windowsRecordingMode.
  ///
  /// In en, this message translates to:
  /// **'Windows microphone recording'**
  String get windowsRecordingMode;

  /// No description provided for @windowsRecordingModeDescription.
  ///
  /// In en, this message translates to:
  /// **'Windows uses standard instant replay recording. Lock-screen triggers are available on Android only.'**
  String get windowsRecordingModeDescription;

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

  /// No description provided for @serviceError.
  ///
  /// In en, this message translates to:
  /// **'Recording service error: {error}'**
  String serviceError(Object error);

  /// No description provided for @saveError.
  ///
  /// In en, this message translates to:
  /// **'Save error: {error}'**
  String saveError(Object error);

  /// No description provided for @saveStarted.
  ///
  /// In en, this message translates to:
  /// **'Saving recording'**
  String get saveStarted;

  /// No description provided for @clipSaved.
  ///
  /// In en, this message translates to:
  /// **'Recording saved'**
  String get clipSaved;

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

  /// No description provided for @navScheduledTasks.
  ///
  /// In en, this message translates to:
  /// **'Scheduled tasks'**
  String get navScheduledTasks;

  /// No description provided for @scheduledTasksTitle.
  ///
  /// In en, this message translates to:
  /// **'Scheduled tasks'**
  String get scheduledTasksTitle;

  /// No description provided for @newScheduledTask.
  ///
  /// In en, this message translates to:
  /// **'New task'**
  String get newScheduledTask;

  /// No description provided for @scheduleOperationFailed.
  ///
  /// In en, this message translates to:
  /// **'Scheduled task operation failed: {error}'**
  String scheduleOperationFailed(Object error);

  /// No description provided for @loadingScheduledTasks.
  ///
  /// In en, this message translates to:
  /// **'Loading scheduled tasks…'**
  String get loadingScheduledTasks;

  /// No description provided for @noScheduledTasks.
  ///
  /// In en, this message translates to:
  /// **'No scheduled tasks'**
  String get noScheduledTasks;

  /// No description provided for @requestExactAlarm.
  ///
  /// In en, this message translates to:
  /// **'Allow exact alarms'**
  String get requestExactAlarm;

  /// No description provided for @noUpcomingTask.
  ///
  /// In en, this message translates to:
  /// **'No task is waiting to run'**
  String get noUpcomingTask;

  /// No description provided for @nextScheduledTask.
  ///
  /// In en, this message translates to:
  /// **'Next run: {time} ({remaining} remaining)'**
  String nextScheduledTask(Object remaining, Object time);

  /// No description provided for @scheduleDue.
  ///
  /// In en, this message translates to:
  /// **'Scheduled {time} ({remaining} remaining)'**
  String scheduleDue(Object remaining, Object time);

  /// No description provided for @scheduleHistory.
  ///
  /// In en, this message translates to:
  /// **'Execution history'**
  String get scheduleHistory;

  /// No description provided for @noScheduleHistory.
  ///
  /// In en, this message translates to:
  /// **'No execution history'**
  String get noScheduleHistory;

  /// No description provided for @schedulePlannedAt.
  ///
  /// In en, this message translates to:
  /// **'Planned {time}'**
  String schedulePlannedAt(Object time);

  /// No description provided for @scheduleStartedAt.
  ///
  /// In en, this message translates to:
  /// **'Started {time}'**
  String scheduleStartedAt(Object time);

  /// No description provided for @scheduleLateBy.
  ///
  /// In en, this message translates to:
  /// **'Late by {duration}'**
  String scheduleLateBy(Object duration);

  /// No description provided for @deleteScheduledTask.
  ///
  /// In en, this message translates to:
  /// **'Delete scheduled task'**
  String get deleteScheduledTask;

  /// No description provided for @confirmDeleteScheduledTask.
  ///
  /// In en, this message translates to:
  /// **'Delete “{name}”? Existing execution history is kept.'**
  String confirmDeleteScheduledTask(Object name);

  /// No description provided for @editScheduledTask.
  ///
  /// In en, this message translates to:
  /// **'Edit scheduled task'**
  String get editScheduledTask;

  /// No description provided for @scheduleName.
  ///
  /// In en, this message translates to:
  /// **'Task name'**
  String get scheduleName;

  /// No description provided for @scheduleTaskSettings.
  ///
  /// In en, this message translates to:
  /// **'Task settings'**
  String get scheduleTaskSettings;

  /// No description provided for @scheduleRunTime.
  ///
  /// In en, this message translates to:
  /// **'Run time'**
  String get scheduleRunTime;

  /// No description provided for @scheduleActionsAtRun.
  ///
  /// In en, this message translates to:
  /// **'Actions when the task runs'**
  String get scheduleActionsAtRun;

  /// No description provided for @scheduleHours.
  ///
  /// In en, this message translates to:
  /// **'Hours'**
  String get scheduleHours;

  /// No description provided for @scheduleMinutes.
  ///
  /// In en, this message translates to:
  /// **'Minutes'**
  String get scheduleMinutes;

  /// No description provided for @scheduleSeconds.
  ///
  /// In en, this message translates to:
  /// **'Seconds'**
  String get scheduleSeconds;

  /// No description provided for @scheduleChooseDate.
  ///
  /// In en, this message translates to:
  /// **'Date: {date}'**
  String scheduleChooseDate(Object date);

  /// No description provided for @scheduleCountdown.
  ///
  /// In en, this message translates to:
  /// **'Countdown'**
  String get scheduleCountdown;

  /// No description provided for @scheduleTimePoint.
  ///
  /// In en, this message translates to:
  /// **'Time point'**
  String get scheduleTimePoint;

  /// No description provided for @scheduleRecordingAction.
  ///
  /// In en, this message translates to:
  /// **'Recording action'**
  String get scheduleRecordingAction;

  /// No description provided for @scheduleNoChange.
  ///
  /// In en, this message translates to:
  /// **'No change'**
  String get scheduleNoChange;

  /// No description provided for @scheduleStartRecording.
  ///
  /// In en, this message translates to:
  /// **'Start recording'**
  String get scheduleStartRecording;

  /// No description provided for @scheduleStopRecording.
  ///
  /// In en, this message translates to:
  /// **'Stop recording'**
  String get scheduleStopRecording;

  /// No description provided for @scheduleUploadAction.
  ///
  /// In en, this message translates to:
  /// **'Live upload'**
  String get scheduleUploadAction;

  /// No description provided for @scheduleEnableUpload.
  ///
  /// In en, this message translates to:
  /// **'Enable upload'**
  String get scheduleEnableUpload;

  /// No description provided for @scheduleDisableUpload.
  ///
  /// In en, this message translates to:
  /// **'Disable upload'**
  String get scheduleDisableUpload;

  /// No description provided for @scheduleSaveRecent.
  ///
  /// In en, this message translates to:
  /// **'Save recent audio'**
  String get scheduleSaveRecent;

  /// No description provided for @scheduleSaveSeconds.
  ///
  /// In en, this message translates to:
  /// **'Save duration (seconds)'**
  String get scheduleSaveSeconds;

  /// No description provided for @scheduleAllowPartial.
  ///
  /// In en, this message translates to:
  /// **'Save available audio when the buffer is shorter'**
  String get scheduleAllowPartial;

  /// No description provided for @scheduleEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enable task after saving'**
  String get scheduleEnabled;

  /// No description provided for @saveScheduledTask.
  ///
  /// In en, this message translates to:
  /// **'Save task'**
  String get saveScheduledTask;

  /// No description provided for @scheduleSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the task. Check the input and platform state.'**
  String get scheduleSaveFailed;

  /// No description provided for @scheduleNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a task name.'**
  String get scheduleNameRequired;

  /// No description provided for @scheduleActionRequired.
  ///
  /// In en, this message translates to:
  /// **'Select at least one action.'**
  String get scheduleActionRequired;

  /// No description provided for @scheduleCountdownRequired.
  ///
  /// In en, this message translates to:
  /// **'The countdown must be greater than 0 seconds.'**
  String get scheduleCountdownRequired;

  /// No description provided for @scheduleTimePointPast.
  ///
  /// In en, this message translates to:
  /// **'The selected time must be in the future.'**
  String get scheduleTimePointPast;

  /// No description provided for @scheduleSaveDurationInvalid.
  ///
  /// In en, this message translates to:
  /// **'Save duration must be between 1 and 86400 seconds.'**
  String get scheduleSaveDurationInvalid;

  /// No description provided for @scheduleCountdownWithDuration.
  ///
  /// In en, this message translates to:
  /// **'Countdown {duration}'**
  String scheduleCountdownWithDuration(Object duration);

  /// No description provided for @scheduleSaveActionSummary.
  ///
  /// In en, this message translates to:
  /// **'Save recent {seconds} s · {format}'**
  String scheduleSaveActionSummary(Object format, Object seconds);

  /// No description provided for @convertWavToMp3.
  ///
  /// In en, this message translates to:
  /// **'Convert to MP3'**
  String get convertWavToMp3;

  /// No description provided for @convertWavBitrate.
  ///
  /// In en, this message translates to:
  /// **'Choose MP3 bitrate'**
  String get convertWavBitrate;

  /// No description provided for @convertingWavToMp3.
  ///
  /// In en, this message translates to:
  /// **'Converting WAV…'**
  String get convertingWavToMp3;

  /// No description provided for @convertedWavToMp3.
  ///
  /// In en, this message translates to:
  /// **'Created MP3: {name}'**
  String convertedWavToMp3(Object name);

  /// No description provided for @convertWavToMp3Failed.
  ///
  /// In en, this message translates to:
  /// **'WAV to MP3 failed: {error}'**
  String convertWavToMp3Failed(Object error);

  /// No description provided for @scheduleNameAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Leave blank to generate a name'**
  String get scheduleNameAutomatic;

  /// No description provided for @scheduleTaskNamePrefix.
  ///
  /// In en, this message translates to:
  /// **'Task'**
  String get scheduleTaskNamePrefix;

  /// No description provided for @schedulePresetNamePrefix.
  ///
  /// In en, this message translates to:
  /// **'Preset'**
  String get schedulePresetNamePrefix;

  /// No description provided for @saveSchedulePreset.
  ///
  /// In en, this message translates to:
  /// **'Save preset'**
  String get saveSchedulePreset;

  /// No description provided for @deleteSchedulePreset.
  ///
  /// In en, this message translates to:
  /// **'Delete preset'**
  String get deleteSchedulePreset;

  /// No description provided for @schedulePresetsTitle.
  ///
  /// In en, this message translates to:
  /// **'Task presets ({count}/9)'**
  String schedulePresetsTitle(int count);

  /// No description provided for @schedulePresetsHint.
  ///
  /// In en, this message translates to:
  /// **'Save up to 9 presets in the task editor to quickly create tasks later.'**
  String get schedulePresetsHint;

  /// No description provided for @confirmDeleteSchedulePreset.
  ///
  /// In en, this message translates to:
  /// **'Delete preset “{name}”? Existing tasks will be kept.'**
  String confirmDeleteSchedulePreset(String name);

  /// No description provided for @schedulePresetLimit.
  ///
  /// In en, this message translates to:
  /// **'You can save up to 9 presets. Delete a preset first.'**
  String get schedulePresetLimit;

  /// No description provided for @saveInProgress.
  ///
  /// In en, this message translates to:
  /// **'Saving · Cancel'**
  String get saveInProgress;

  /// No description provided for @saveCanceling.
  ///
  /// In en, this message translates to:
  /// **'Canceling…'**
  String get saveCanceling;

  /// No description provided for @saveCanceled.
  ///
  /// In en, this message translates to:
  /// **'Save canceled'**
  String get saveCanceled;

  /// No description provided for @saveWritingProgress.
  ///
  /// In en, this message translates to:
  /// **'Writing {progress}% · Cancel'**
  String saveWritingProgress(int progress);

  /// No description provided for @shareRecording.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareRecording;

  /// No description provided for @shareRecordingFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to share. Check that the recording exists and folder access is allowed.'**
  String get shareRecordingFailed;

  /// No description provided for @saveFailedStatus.
  ///
  /// In en, this message translates to:
  /// **'Save failed'**
  String get saveFailedStatus;

  /// No description provided for @saveCancelFailedStatus.
  ///
  /// In en, this message translates to:
  /// **'Cancel failed'**
  String get saveCancelFailedStatus;

  /// No description provided for @saveCancelingStatus.
  ///
  /// In en, this message translates to:
  /// **'Canceling save'**
  String get saveCancelingStatus;

  /// No description provided for @saveWritingStatus.
  ///
  /// In en, this message translates to:
  /// **'Writing audio'**
  String get saveWritingStatus;
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
