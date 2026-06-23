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
  String get navHome => '主页';

  @override
  String get navLibrary => '已保存录音';

  @override
  String get navProcessing => '音频处理';

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
  String get recordingStatusNormal => '录音正常运行中';

  @override
  String get recordingStatusPaused => '录音已暂停';

  @override
  String get recordingStatusPermissionLost => '麦克风权限不可用，请检查 Android 权限设置。';

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
  String get processingTitle => '音频处理';

  @override
  String get sourceRecording => '源录音';

  @override
  String gainDb(Object gain) {
    return '增益 $gain dB';
  }

  @override
  String get outputFormat => '输出格式';

  @override
  String get mp3Bitrate => 'MP3 码率';

  @override
  String get processing => '处理中';

  @override
  String get generateProcessedCopy => '生成处理副本';

  @override
  String get processingComplete => '处理完成，已生成新的录音文件。';

  @override
  String get processingFailed => '处理失败，请检查 FFmpeg 或源文件。';

  @override
  String get settingsTitle => '设置';

  @override
  String get recordingFolder => '录音目录';

  @override
  String get notSelected => '未选择';

  @override
  String get change => '更改';

  @override
  String get recordingSettings => '录制设置';

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
  String get clearCacheSubtitle => '清理临时导出、处理缓存；录制中会保留当前回放缓存';

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
  String processedRecording(Object name) {
    return '已处理录音：$name';
  }

  @override
  String processingStatusError(Object error) {
    return '处理错误：$error';
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
}
