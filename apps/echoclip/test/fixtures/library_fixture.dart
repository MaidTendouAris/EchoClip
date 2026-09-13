import 'package:echoclip/main.dart';

List<RecordingGroup> sampleGroups([String language = 'en']) => [
  RecordingGroup(name: language == 'zh' ? '工作' : 'Work', uri: 'group:work'),
  RecordingGroup(name: language == 'zh' ? '灵感' : 'Ideas', uri: 'group:ideas'),
  RecordingGroup(name: language == 'zh' ? '待整理' : 'Inbox', uri: 'group:empty'),
];

List<ClipItem> sampleClips([String language = 'en']) => [
  ClipItem(
    name: language == 'zh'
        ? '产品访谈 · 第二轮.wav'
        : 'Interview — second session.wav',
    createdAt: DateTime(2026, 9, 11, 14, 32),
    uri: 'clip:interview',
    parentUri: 'group:work',
    groupName: language == 'zh' ? '工作' : 'Work',
    groupUri: 'group:work',
    size: 4288912,
  ),
  ClipItem(
    name: language == 'zh' ? '午后随记.mp3' : 'Afternoon notes.mp3',
    createdAt: DateTime(2026, 9, 11, 12, 8),
    uri: 'clip:notes',
    parentUri: 'root',
    groupName: null,
    groupUri: null,
    size: 1264800,
  ),
  ClipItem(
    name: language == 'zh' ? '雨声与街道.wav' : 'Rain on the street.wav',
    createdAt: DateTime(2026, 9, 10, 20, 16),
    uri: 'clip:rain',
    parentUri: 'group:ideas',
    groupName: language == 'zh' ? '灵感' : 'Ideas',
    groupUri: 'group:ideas',
    size: 8841200,
  ),
  ClipItem(
    name: language == 'zh'
        ? '项目讨论 · 设计与下一阶段的计划.wav'
        : 'Design review — plans for the next project phase.wav',
    createdAt: DateTime(2026, 9, 10, 10, 5),
    uri: 'clip:review',
    parentUri: 'group:work',
    groupName: language == 'zh' ? '工作' : 'Work',
    groupUri: 'group:work',
    size: 26881000,
  ),
  ClipItem(
    name: language == 'zh' ? '周末的想法.mp3' : 'Weekend ideas.mp3',
    createdAt: DateTime(2026, 9, 8, 9, 42),
    uri: 'clip:ideas',
    parentUri: 'group:ideas',
    groupName: language == 'zh' ? '灵感' : 'Ideas',
    groupUri: 'group:ideas',
    size: 2384000,
  ),
];

const idlePlayback = PlaybackSnapshot(
  playing: false,
  paused: false,
  uri: null,
  positionMs: 0,
  durationMs: 0,
  speed: 1,
);
const samplePlayback = PlaybackSnapshot(
  playing: false,
  paused: true,
  uri: 'clip:interview',
  positionMs: 38000,
  durationMs: 136000,
  speed: 1,
);

LibraryPage testLibrary({
  List<ClipItem>? clips,
  List<RecordingGroup>? groups,
  PlaybackSnapshot playback = idlePlayback,
  Future<void> Function(ClipItem)? onPlay,
  Future<void> Function()? onPause,
  Future<void> Function()? onResume,
  Future<void> Function()? onStop,
  Future<void> Function(int)? onSeek,
  Future<void> Function(double)? onSpeed,
  Future<void> Function(List<ClipItem>)? onDeleteClips,
  Future<void> Function(String)? onCreateGroup,
  Future<void> Function(ClipItem, String)? onRename,
  Future<void> Function(ClipItem, RecordingGroup?)? onMove,
  Future<bool> Function(ClipItem, int)? onConvert,
}) => LibraryPage(
  groups: groups ?? sampleGroups(),
  clips: clips ?? sampleClips(),
  playback: playback,
  onRefresh: () async {},
  onPlay: onPlay ?? (_) async {},
  onPause: onPause ?? () async {},
  onResume: onResume ?? () async {},
  onStop: onStop ?? () async {},
  onSeek: onSeek ?? (_) async {},
  onSpeedChanged: onSpeed ?? (_) async {},
  onCreateGroup: onCreateGroup ?? (_) async {},
  onRenameGroup: (_, _) async {},
  onDeleteGroup: (_) async {},
  onRenameClip: onRename ?? (_, _) async {},
  onDeleteClip: (_) async {},
  onDeleteClips: onDeleteClips ?? (_) async {},
  onMoveClip: onMove ?? (_, _) async {},
  onConvertWavToMp3: onConvert ?? (_, _) async => true,
);
