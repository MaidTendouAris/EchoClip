import 'package:echoclip/main.dart';

SettingsPage presentationSettings({
  bool desktop = false,
  Future<void> Function()? chooseFolder,
}) => SettingsPage(
  folderUri: desktop
      ? r'D:\Recordings\EchoClip'
      : 'content://com.android.externalstorage.documents/tree/primary%3AEchoClip',
  sampleRate: 16000,
  bufferSeconds: 1800,
  cacheBytes: 8388608,
  audioInputDevices: desktop
      ? const [
          AudioInputDevice(
            id: 'mic:1',
            name: 'USB microphone',
            isDefault: true,
          ),
        ]
      : const [],
  microphoneEnabled: true,
  systemAudioEnabled: false,
  microphoneDeviceId: null,
  systemAudioSupported: desktop,
  inputDeviceSelectionSupported: desktop,
  audioSourceSettingsBusy: false,
  lockRecordingTrigger: LockRecordingTrigger.screenOff,
  languageMode: UiLanguageMode.system,
  onChooseFolder: chooseFolder ?? () async {},
  onUpdateAudioSettings: ({sampleRate, bufferSeconds}) async {},
  onUpdateAudioSourceSettings:
      ({
        required microphoneEnabled,
        required systemAudioEnabled,
        microphoneDeviceId,
      }) async {},
  onRefreshAudioInputDevices: () async {},
  onOpenServerSettings: () async {},
  onLockRecordingTriggerChanged: (_) async {},
  onClearCache: () async => {'ok': true, 'deletedBytes': 0},
  onLanguageModeChanged: (_) async {},
  onOpenUrl: (_) async {},
);

ScheduleSnapshot presentationSchedule({
  bool populated = false,
  String lang = 'en',
}) {
  final due = DateTime(2026, 9, 13, 9).millisecondsSinceEpoch;
  return ScheduleSnapshot.fromNative({
    'ok': true,
    'schedulingPrecision': 'exact',
    'exactAlarmPermission': true,
    'recordingDestinationReady': true,
    'ffmpegAvailable': true,
    'uploadConfigured': true,
    'processResident': true,
    'nextWakeupUtcMillis': populated ? due : null,
    'presets': populated
        ? [
            {
              'id': 'preset:1',
              'name': lang == 'zh' ? '会议录音' : 'Meeting recording',
              'enabled': true,
              'trigger': {'type': 'countdown', 'delayMillis': 900000},
              'actions': [
                {'type': 'start_recording'},
              ],
            },
          ]
        : [],
    'tasks': populated
        ? [
            {
              'id': 'task:1',
              'revision': 1,
              'name': lang == 'zh' ? '晨间录音' : 'Morning recording',
              'enabled': true,
              'state': 'armed',
              'trigger': {'type': 'time_point', 'dueAtUtcMillis': due},
              'nextDueUtcMillis': due,
              'actions': [
                {'type': 'start_recording'},
              ],
            },
            {
              'id': 'task:2',
              'revision': 1,
              'name': lang == 'zh' ? '保存最近的片段' : 'Save the latest clip',
              'enabled': false,
              'state': 'disabled',
              'trigger': {'type': 'countdown', 'delayMillis': 600000},
              'actions': [
                {
                  'type': 'save_recent',
                  'seconds': 30,
                  'format': 'mp3',
                  'mp3BitrateKbps': 128,
                  'allowPartial': true,
                },
              ],
            },
          ]
        : [],
    'history': populated
        ? [
            {
              'executionId': 'execution:1',
              'taskName': lang == 'zh' ? '午间随记' : 'Afternoon notes',
              'result': 'succeeded',
              'scheduledForUtcMillis': due - 86400000,
              'startedAtUtcMillis': due - 86400000,
              'lateByMillis': 0,
              'actionResults': [],
            },
          ]
        : [],
  });
}

ScheduledTasksPage presentationTasks({
  bool populated = false,
  String lang = 'en',
  Future<bool> Function(ScheduledTaskModel, bool)? setEnabled,
}) => ScheduledTasksPage(
  snapshot: presentationSchedule(populated: populated, lang: lang),
  busy: false,
  onRefresh: () async {},
  onUpsert: (_) async => true,
  onDelete: (_) async => true,
  onSetEnabled: setEnabled ?? (_, _) async => true,
  onRequestExactAlarm: () async {},
);
