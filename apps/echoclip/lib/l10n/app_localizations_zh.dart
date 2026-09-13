// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'EchoClip';

  @override
  String get showWindow => '显示窗口';

  @override
  String get hideWindow => '隐藏窗口';

  @override
  String get exitApp => '退出 EchoClip';

  @override
  String get navHome => '主页';

  @override
  String get navLibrary => '录音列表';

  @override
  String get navSettings => '设置';

  @override
  String get replayRunning => '即时回放运行中';

  @override
  String get recordingPaused => '录制已暂停';

  @override
  String get currentRecordingDuration => '本次录音';

  @override
  String get totalRecordedDuration => '总缓冲';

  @override
  String recordingStartedAt(Object time) {
    return '开始于 $time';
  }

  @override
  String lastRecordingStartedAt(Object time) {
    return '上次录制 $time';
  }

  @override
  String get lastRecordingTimeUnavailable => '暂无上次录制时间';

  @override
  String get recordingStatusNormal => '录音正常运行中';

  @override
  String get recordingStatusPaused => '录音已暂停';

  @override
  String get recordingStatusPermissionLost => '麦克风权限不可用，请检查系统隐私设置。';

  @override
  String get recordingStatusStorageLow => '内部存储空间不足，请清理空间后继续录音。';

  @override
  String get recordingStatusAudioUnavailable => '麦克风初始化失败，可能正被其他应用占用。';

  @override
  String get recordingStatusQueueBusy => '音频缓冲繁忙，录音可能出现少量丢帧。';

  @override
  String get recordingStatusBackendUnavailable => '音频后端未就绪，如持续出现请重启录音。';

  @override
  String get recordingStatusCaptureIssue => '音频采集遇到问题。';

  @override
  String recordingStatusWithDetail(Object message, Object detail) {
    return '$message · 详情：$detail';
  }

  @override
  String get standardRecordingMode => '标准录音模式';

  @override
  String get lockRecordingMode => '锁屏录音模式';

  @override
  String get lockRecordingStatusOff => '锁屏录音模式未启动';

  @override
  String get lockRecordingStatusArmedScreenOff => '锁屏录音模式待命中，黑屏后自动录音';

  @override
  String get lockRecordingStatusArmedKeyguard => '锁屏录音模式待命中，手机锁定后自动录音';

  @override
  String get lockRecordingStatusRecording => '锁屏录音正在写入回放缓存';

  @override
  String saveClip(Object duration) {
    return '保存 $duration';
  }

  @override
  String get pause => '暂停';

  @override
  String get resume => '继续';

  @override
  String get chooseFolder => '选择目录';

  @override
  String get presetSaveDuration => '预设';

  @override
  String get customSaveDuration => '自定义';

  @override
  String get customSaveSeconds => '保存时长（秒）';

  @override
  String get customSaveSecondsHelper => '1 到 86400 秒';

  @override
  String get secondsUnit => '秒';

  @override
  String secondsShort(int seconds) {
    return '$seconds 秒';
  }

  @override
  String minutesShort(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String hoursShort(int hours) {
    return '$hours 小时';
  }

  @override
  String hoursMinutesShort(int hours, int minutes) {
    return '$hours 小时 $minutes 分钟';
  }

  @override
  String recentDurationName(Object duration) {
    return '最近 $duration';
  }

  @override
  String get loudnessRecordingLabel => '录制中';

  @override
  String get loudnessHistoryLabel => '最近 6 秒';

  @override
  String get loudnessTitle => '实时响度';

  @override
  String get silenceLabel => '静音';

  @override
  String get microphoneInputLabel => '麦克风输入';

  @override
  String get notRecordingLabel => '未录制';

  @override
  String get peakLabel => '峰值';

  @override
  String get saveRecentLabel => '保存最近的音频';

  @override
  String get chooseSaveDuration => '选择保存时长';

  @override
  String libraryCount(int count) {
    return '$count 段录音';
  }

  @override
  String librarySelected(int count) {
    return '已选 $count 项';
  }

  @override
  String get allRecordings => '全部';

  @override
  String get searchRecordings => '搜索录音';

  @override
  String get clearSearch => '清除搜索';

  @override
  String get sortRecordings => '录音排序';

  @override
  String get libraryNewest => '最新优先';

  @override
  String get libraryOldest => '最早优先';

  @override
  String get libraryNameOrder => '按文件名';

  @override
  String get librarySize => '大小';

  @override
  String get librarySavedAt => '保存时间';

  @override
  String get libraryNoMatches => '没有匹配的录音';

  @override
  String get librarySearchHint => '试试其他名称，或切换分组。';

  @override
  String get libraryEmptyHint => '在主页保存音频片段，即可在这里查看。';

  @override
  String get audioFileLabel => '音频';

  @override
  String get playbackSpeed => '播放速度';

  @override
  String get libraryTitle => '录音列表';

  @override
  String get unGrouped => '未分组';

  @override
  String get emptyRecordings => '暂无录音';

  @override
  String get selectAll => '全选';

  @override
  String get newGroup => '新建分组';

  @override
  String get deleteSelected => '删除所选';

  @override
  String get stopPreview => '停止预览';

  @override
  String get done => '完成';

  @override
  String get edit => '编辑';

  @override
  String get refresh => '刷新';

  @override
  String get groupActions => '分组操作';

  @override
  String get renameGroup => '重命名分组';

  @override
  String get deleteGroup => '删除分组';

  @override
  String get preview => '预览';

  @override
  String get recordingActions => '录音操作';

  @override
  String get rename => '重命名';

  @override
  String get moveToGroup => '移动到分组';

  @override
  String get delete => '删除';

  @override
  String get batchDeleteRecordings => '批量删除录音';

  @override
  String confirmBatchDeleteRecordings(int count) {
    return '确定删除选中的 $count 个录音？此操作不可撤销。';
  }

  @override
  String get groupName => '分组名';

  @override
  String get confirmDeleteGroup => '将删除分组及其中录音，此操作不可撤销。';

  @override
  String get renameRecording => '重命名录音';

  @override
  String get deleteRecording => '删除录音';

  @override
  String get fileName => '文件名';

  @override
  String confirmDeleteRecording(Object name) {
    return '确定删除 $name？此操作不可撤销。';
  }

  @override
  String get cancel => '取消';

  @override
  String get ok => '确定';

  @override
  String get stop => '停止';

  @override
  String get outputFormat => '输出格式';

  @override
  String get mp3Bitrate => 'MP3 码率';

  @override
  String get settingsOverview => '录音、存储与应用偏好';

  @override
  String get internalStorage => '内部存储';

  @override
  String scheduleTaskCount(int count) {
    return '$count 个任务';
  }

  @override
  String get scheduleEmptyHint => '新建任务，或使用已保存的预设。';

  @override
  String get settingsTitle => '设置';

  @override
  String get serverSettings => '服务器设置';

  @override
  String get serverSettingsDescription => '配置加密实时上传，并查看连接日志与断连记录';

  @override
  String get serverConnectionDetails => '服务器连接状态';

  @override
  String get serverNotConfigured => '未配置';

  @override
  String get serverSyncDisabled => '同步已关闭';

  @override
  String get serverConnected => '已连接';

  @override
  String get serverConnectionFailed => '连接失败';

  @override
  String get serverConnecting => '正在连接';

  @override
  String get serverSyncEnabled => '录音时实时上传';

  @override
  String get serverSyncEnabledDescription => '仅上传开启此开关后新录制的 PCM；断网重试不会读取开启前的缓存';

  @override
  String get serverHost => 'IP 地址或域名';

  @override
  String get serverUploadPort => '上传端口';

  @override
  String get serverUploadKey => '唯一上传密钥';

  @override
  String get serverUploadKeyConfigured => '已保存受系统保护的密钥；留空可继续使用原密钥';

  @override
  String get serverUploadKeyRequired => '请输入服务器生成的 32 字节 Base64 密钥';

  @override
  String get serverUploadKeyInvalid => '上传密钥必须是有效的 Base64，解码后长度应为 32 字节';

  @override
  String get serverDeviceId => '客户端设备 ID';

  @override
  String get saveSettings => '保存设置';

  @override
  String get serverTestConnection => '测试连接';

  @override
  String get serverTestingConnection => '正在测试连接…';

  @override
  String get serverConnectionTestSucceeded => '服务器连接成功';

  @override
  String get serverConnectionTestFailed => '服务器连接失败';

  @override
  String get removeServerKey => '移除密钥';

  @override
  String get serverConnectionStatus => '连接状态';

  @override
  String get serverConnectionLogs => '连接日志与断连记录';

  @override
  String get noServerConnectionLogs => '本次应用运行期间暂无连接事件';

  @override
  String get serverHostInvalid => '请输入不带 http:// 和路径的 IP 地址或域名';

  @override
  String get serverUploadPortInvalid => '请输入 1 到 65535 之间的上传端口';

  @override
  String serverUploadLag(int samples) {
    return '待上传：$samples 个采样';
  }

  @override
  String serverReconnectCount(int count) {
    return '重连次数：$count';
  }

  @override
  String serverKeyId(Object keyId) {
    return '密钥 ID：$keyId';
  }

  @override
  String get serverEventStarted => '同步已启动';

  @override
  String get serverEventConnected => '已连接';

  @override
  String get serverEventDisconnected => '连接已断开';

  @override
  String get serverEventRetentionGap => '本地缓存出现缺口';

  @override
  String get serverEventStopped => '同步已停止';

  @override
  String get close => '关闭';

  @override
  String get recordingFolder => '录音目录';

  @override
  String get notSelected => '未选择';

  @override
  String get change => '更改';

  @override
  String get recordingSettings => '录制设置';

  @override
  String get audioSources => '音频来源';

  @override
  String get audioSourcesDescription =>
      '可选择一个或同时选择两个来源，EchoClip 会将声音混合到同一回放缓存中。';

  @override
  String get recordMicrophone => '录制麦克风声音';

  @override
  String get recordMicrophoneDescription => '从选定的输入设备采集人声及环境声音';

  @override
  String get recordSystemAudio => '录制系统声音';

  @override
  String get recordSystemAudioDescription => '采集 Windows 当前正在播放的声音';

  @override
  String get systemAudioUnavailable => '当前平台暂不支持录制系统声音';

  @override
  String get inputDevice => '麦克风输入设备';

  @override
  String get systemDefaultInputDevice => '系统默认输入设备';

  @override
  String get inputDeviceManagedBySystem => '由系统管理';

  @override
  String get noInputDevices => '未发现输入设备';

  @override
  String get unavailableInputDevice => '已选输入设备当前不可用';

  @override
  String get refreshInputDevices => '刷新输入设备';

  @override
  String defaultInputDevice(Object name) {
    return '$name（当前默认）';
  }

  @override
  String get audioSourceRequired => '请至少保留一个音频来源';

  @override
  String get audioSourceSettingsSaved => '音频来源设置已保存';

  @override
  String get lockRecordingSettings => '锁屏录音';

  @override
  String get lockRecordingTrigger => '触发条件';

  @override
  String get lockRecordingTriggerScreenOff => '屏幕关闭时';

  @override
  String get lockRecordingTriggerKeyguard => '手机锁定时';

  @override
  String get languageSettings => '语言';

  @override
  String get appLanguage => '应用语言';

  @override
  String get followSystemLanguage => '跟随系统';

  @override
  String get englishLanguage => 'English';

  @override
  String get chineseLanguage => '简体中文';

  @override
  String get androidSampleRate => 'Android 采样率';

  @override
  String get sampleRate => '采样率';

  @override
  String get bufferDuration => '缓存时长';

  @override
  String get bufferDurationMinutes => '缓存时长（分钟）';

  @override
  String get bufferDurationHelper => '1 到 1440 分钟';

  @override
  String get minutesUnit => '分钟';

  @override
  String estimatedPcmBuffer(Object size) {
    return '预计 PCM 缓冲：$size';
  }

  @override
  String pcmBufferSubtitle(Object sampleRate) {
    return '$sampleRate · 单声道 · 16-bit PCM · 录制中修改下次启动生效';
  }

  @override
  String get cacheTitle => '缓存';

  @override
  String currentCacheSize(Object size) {
    return '当前缓存大小：$size';
  }

  @override
  String get clearCache => '清除缓存';

  @override
  String get clearCacheSubtitle => '清理临时导出缓存；录制中会保留当前回放缓存';

  @override
  String get confirmClearCache => '确定清除 EchoClip 的临时缓存？此操作不会删除已保存录音。';

  @override
  String cacheCleared(Object size) {
    return '已清理 $size';
  }

  @override
  String cacheClearedActivePreserved(Object size) {
    return '已清理 $size，当前回放缓存已保留';
  }

  @override
  String cacheClearFailed(Object error) {
    return '清理失败：$error';
  }

  @override
  String get aboutProject => '项目';

  @override
  String get githubRepository => 'GitHub 仓库';

  @override
  String get githubRepositorySubtitle => '查看源代码与文档';

  @override
  String get licenseTitle => '许可证';

  @override
  String get licenseSubtitle => 'GPL-3.0-only';

  @override
  String get issueFeedback => '问题反馈';

  @override
  String get issueFeedbackSubtitle => '打开 GitHub Issues';

  @override
  String get windowsDemoMode => 'Windows 演示模式';

  @override
  String get windowsRecordingMode => 'Windows 麦克风录音';

  @override
  String get windowsRecordingModeDescription =>
      'Windows 使用标准即时回放录音；锁屏触发功能仅适用于 Android。';

  @override
  String get recordingSettingsSaved => '录制设置已保存';

  @override
  String get settingsSavedNextRecording => '设置已保存，将在下次录制时生效';

  @override
  String get recordingFolderReady => '录音目录已就绪';

  @override
  String folderSetupError(Object error) {
    return '目录设置错误：$error';
  }

  @override
  String captureError(Object error) {
    return '采集错误：$error';
  }

  @override
  String androidServiceRunning(Object backend) {
    return 'Android 前台服务运行中 · $backend';
  }

  @override
  String androidServiceStopped(Object backend) {
    return 'Android 服务已停止 · $backend';
  }

  @override
  String androidServiceError(Object error) {
    return 'Android 服务错误：$error';
  }

  @override
  String androidSaveError(Object error) {
    return 'Android 保存错误：$error';
  }

  @override
  String get androidSaveStarted => 'Android 保存已开始';

  @override
  String get androidClipSaved => 'Android 录音已保存';

  @override
  String serviceError(Object error) {
    return '录音服务错误：$error';
  }

  @override
  String saveError(Object error) {
    return '保存错误：$error';
  }

  @override
  String get saveStarted => '正在保存录音';

  @override
  String get clipSaved => '录音已保存';

  @override
  String get previewPlaying => '正在预览';

  @override
  String previewError(Object error) {
    return '预览错误：$error';
  }

  @override
  String get previewStopped => '预览已停止';

  @override
  String deletedRecordings(int count) {
    return '已删除 $count 个录音';
  }

  @override
  String deletedRecordingsWithError(int count, Object error) {
    return '已删除 $count 个录音，错误：$error';
  }

  @override
  String cacheClearedStatus(Object size) {
    return '缓存已清理：$size';
  }

  @override
  String clearCacheStatusError(Object error) {
    return '清理缓存错误：$error';
  }

  @override
  String get libraryUpdated => '录音列表已更新';

  @override
  String libraryError(Object error) {
    return '录音列表错误：$error';
  }

  @override
  String get unnamedGroup => '未命名分组';

  @override
  String get navScheduledTasks => '定时任务';

  @override
  String get scheduledTasksTitle => '定时任务';

  @override
  String get newScheduledTask => '新建任务';

  @override
  String scheduleOperationFailed(Object error) {
    return '定时任务操作失败：$error';
  }

  @override
  String get loadingScheduledTasks => '正在读取定时任务…';

  @override
  String get noScheduledTasks => '暂无定时任务';

  @override
  String get requestExactAlarm => '允许精确闹钟';

  @override
  String get noUpcomingTask => '当前没有等待执行的任务';

  @override
  String nextScheduledTask(Object remaining, Object time) {
    return '下次执行：$time（剩余 $remaining）';
  }

  @override
  String scheduleDue(Object remaining, Object time) {
    return '计划 $time（剩余 $remaining）';
  }

  @override
  String get scheduleHistory => '执行历史';

  @override
  String get noScheduleHistory => '暂无执行记录';

  @override
  String schedulePlannedAt(Object time) {
    return '计划 $time';
  }

  @override
  String scheduleStartedAt(Object time) {
    return '实际 $time';
  }

  @override
  String scheduleLateBy(Object duration) {
    return '迟到 $duration';
  }

  @override
  String get deleteScheduledTask => '删除定时任务';

  @override
  String confirmDeleteScheduledTask(Object name) {
    return '确定删除“$name”？已有执行历史不会删除。';
  }

  @override
  String get editScheduledTask => '编辑定时任务';

  @override
  String get scheduleName => '任务名称';

  @override
  String get scheduleTaskSettings => '任务设置';

  @override
  String get scheduleRunTime => '任务运行时间';

  @override
  String get scheduleActionsAtRun => '任务启动时执行';

  @override
  String get scheduleHours => '时';

  @override
  String get scheduleMinutes => '分';

  @override
  String get scheduleSeconds => '秒';

  @override
  String scheduleChooseDate(Object date) {
    return '日期：$date';
  }

  @override
  String get scheduleCountdown => '倒计时';

  @override
  String get scheduleTimePoint => '指定时间';

  @override
  String get scheduleRecordingAction => '录音操作';

  @override
  String get scheduleNoChange => '保持不变';

  @override
  String get scheduleStartRecording => '开启录音';

  @override
  String get scheduleStopRecording => '关闭录音';

  @override
  String get scheduleUploadAction => '实时上传';

  @override
  String get scheduleEnableUpload => '开启上传';

  @override
  String get scheduleDisableUpload => '关闭上传';

  @override
  String get scheduleSaveRecent => '保存最近片段';

  @override
  String get scheduleSaveSeconds => '保存时长（秒）';

  @override
  String get scheduleAllowPartial => '缓存不足时保存现有部分';

  @override
  String get scheduleEnabled => '保存后启用任务';

  @override
  String get saveScheduledTask => '保存任务';

  @override
  String get scheduleSaveFailed => '任务保存失败，请检查输入或平台状态。';

  @override
  String get scheduleNameRequired => '请输入任务名称。';

  @override
  String get scheduleActionRequired => '请至少选择一个操作。';

  @override
  String get scheduleCountdownRequired => '倒计时必须大于 0 秒。';

  @override
  String get scheduleTimePointPast => '指定时间必须晚于当前时间。';

  @override
  String get scheduleSaveDurationInvalid => '保存时长应为 1 到 86400 秒。';

  @override
  String scheduleCountdownWithDuration(Object duration) {
    return '倒计时 $duration';
  }

  @override
  String scheduleSaveActionSummary(Object format, Object seconds) {
    return '保存最近 $seconds 秒 · $format';
  }

  @override
  String get convertWavToMp3 => '转换为 MP3';

  @override
  String get convertWavBitrate => '选择 MP3 码率';

  @override
  String get convertingWavToMp3 => '正在转换 WAV…';

  @override
  String convertedWavToMp3(Object name) {
    return '已生成 MP3：$name';
  }

  @override
  String convertWavToMp3Failed(Object error) {
    return 'WAV 转 MP3 失败：$error';
  }

  @override
  String get scheduleNameAutomatic => '留空时自动生成名称';

  @override
  String get scheduleTaskNamePrefix => '任务';

  @override
  String get schedulePresetNamePrefix => '预设';

  @override
  String get saveSchedulePreset => '保存预设';

  @override
  String get deleteSchedulePreset => '删除预设';

  @override
  String schedulePresetsTitle(int count) {
    return '任务预设（$count/9）';
  }

  @override
  String get schedulePresetsHint => '在任务编辑页保存预设，方便下次快速新建任务。最多保存 9 个。';

  @override
  String confirmDeleteSchedulePreset(String name) {
    return '删除预设“$name”？已创建的任务不受影响。';
  }

  @override
  String get schedulePresetLimit => '最多保存 9 个预设，请先删除一个预设。';

  @override
  String get saveInProgress => '保存中 · 点击取消';

  @override
  String get saveCanceling => '正在取消…';

  @override
  String get saveCanceled => '已取消保存';

  @override
  String saveWritingProgress(int progress) {
    return '写入 $progress% · 取消';
  }

  @override
  String get shareRecording => '分享';

  @override
  String get shareRecordingFailed => '无法分享录音，请检查文件是否存在及目录访问权限。';

  @override
  String get saveFailedStatus => '保存失败';

  @override
  String get saveCancelFailedStatus => '取消失败';

  @override
  String get saveCancelingStatus => '正在取消保存';

  @override
  String get saveWritingStatus => '正在写入录音';
}
