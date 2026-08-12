part of '../main.dart';

class _LibraryPage extends StatefulWidget {
  const _LibraryPage({
    required this.groups,
    required this.clips,
    required this.playback,
    required this.onRefresh,
    required this.onPlay,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onSeek,
    required this.onSpeedChanged,
    required this.onCreateGroup,
    required this.onRenameGroup,
    required this.onDeleteGroup,
    required this.onRenameClip,
    required this.onDeleteClip,
    required this.onDeleteClips,
    required this.onMoveClip,
  });

  final List<RecordingGroup> groups;
  final List<ClipItem> clips;
  final PlaybackSnapshot playback;
  final Future<void> Function() onRefresh;
  final Future<void> Function(ClipItem clip) onPlay;
  final Future<void> Function() onPause;
  final Future<void> Function() onResume;
  final Future<void> Function() onStop;
  final Future<void> Function(int positionMs) onSeek;
  final Future<void> Function(double speed) onSpeedChanged;
  final Future<void> Function(String name) onCreateGroup;
  final Future<void> Function(RecordingGroup group, String name) onRenameGroup;
  final Future<void> Function(RecordingGroup group) onDeleteGroup;
  final Future<void> Function(ClipItem clip, String name) onRenameClip;
  final Future<void> Function(ClipItem clip) onDeleteClip;
  final Future<void> Function(List<ClipItem> clips) onDeleteClips;
  final Future<void> Function(ClipItem clip, RecordingGroup? group) onMoveClip;

  @override
  State<_LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<_LibraryPage> {
  static const List<double> _speedOptions = [
    0.1,
    0.25,
    0.5,
    0.75,
    1,
    1.25,
    1.5,
    2,
    3,
    4,
    8,
    16,
  ];

  final Set<String> _selectedClipUris = {};
  bool _isEditing = false;

  List<RecordingGroup> get groups => widget.groups;
  List<ClipItem> get clips => widget.clips;
  PlaybackSnapshot get playback => widget.playback;
  Future<void> Function() get onRefresh => widget.onRefresh;
  Future<void> Function(ClipItem clip) get onPlay => widget.onPlay;
  Future<void> Function() get onPause => widget.onPause;
  Future<void> Function() get onResume => widget.onResume;
  Future<void> Function() get onStop => widget.onStop;
  Future<void> Function(int positionMs) get onSeek => widget.onSeek;
  Future<void> Function(double speed) get onSpeedChanged =>
      widget.onSpeedChanged;
  Future<void> Function(String name) get onCreateGroup => widget.onCreateGroup;
  Future<void> Function(RecordingGroup group, String name) get onRenameGroup =>
      widget.onRenameGroup;
  Future<void> Function(RecordingGroup group) get onDeleteGroup =>
      widget.onDeleteGroup;
  Future<void> Function(ClipItem clip, String name) get onRenameClip =>
      widget.onRenameClip;
  Future<void> Function(ClipItem clip) get onDeleteClip => widget.onDeleteClip;
  Future<void> Function(List<ClipItem> clips) get onDeleteClips =>
      widget.onDeleteClips;
  Future<void> Function(ClipItem clip, RecordingGroup? group) get onMoveClip =>
      widget.onMoveClip;

  @override
  void didUpdateWidget(covariant _LibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final liveUris = clips.map((clip) => clip.uri).whereType<String>().toSet();
    _selectedClipUris.removeWhere((uri) => !liveUris.contains(uri));
    if (_selectedClipUris.isEmpty && liveUris.isEmpty && _isEditing) {
      _isEditing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rootClips = clips.where((clip) => clip.groupUri == null).toList();
    final groupSections = [
      _ClipGroupSection(title: l10n.unGrouped, group: null, clips: rootClips),
      for (final group in groups)
        _ClipGroupSection(
          title: group.name,
          group: group,
          clips: clips.where((clip) => clip.groupUri == group.uri).toList(),
        ),
    ];

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.library_music),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.libraryTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (_isEditing)
                Text(
                  '${_selectedClipUris.length}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              if (_isEditing)
                IconButton(
                  tooltip: l10n.selectAll,
                  onPressed: clips.isEmpty ? null : _selectAll,
                  icon: const Icon(Icons.select_all),
                )
              else
                IconButton(
                  tooltip: l10n.newGroup,
                  onPressed: () => _createGroup(context),
                  icon: const Icon(Icons.create_new_folder),
                ),
              if (_isEditing)
                IconButton(
                  tooltip: l10n.deleteSelected,
                  onPressed: _selectedClipUris.isEmpty
                      ? null
                      : () => _deleteSelectedClips(context),
                  icon: const Icon(Icons.delete_outline),
                ),
              IconButton(
                tooltip: _isEditing ? l10n.done : l10n.edit,
                onPressed: _toggleEditing,
                icon: Icon(_isEditing ? Icons.done : Icons.edit),
              ),
              if (!_isEditing)
                IconButton(
                  tooltip: l10n.refresh,
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: clips.isEmpty && groups.isEmpty
                ? Center(child: Text(l10n.emptyRecordings))
                : ListView(
                    children: [
                      for (final section in groupSections)
                        if (section.clips.isNotEmpty || section.group != null)
                          _buildSection(context, section),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, _ClipGroupSection section) {
    final group = section.group;
    return ExpansionTile(
      key: PageStorageKey('recording-group-${group?.uri ?? 'root'}'),
      initiallyExpanded: group == null || section.clips.isNotEmpty,
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      leading: Icon(group == null ? Icons.folder_open : Icons.folder),
      title: Text('${section.title} (${section.clips.length})'),
      trailing: group == null
          ? null
          : PopupMenuButton<String>(
              tooltip: context.l10n.groupActions,
              onSelected: (value) {
                switch (value) {
                  case 'rename':
                    _renameGroup(context, group);
                    break;
                  case 'delete':
                    _deleteGroup(context, group);
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'rename',
                  child: Text(context.l10n.renameGroup),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(context.l10n.deleteGroup),
                ),
              ],
            ),
      children: [
        if (section.clips.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(44, 0, 0, 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(context.l10n.emptyRecordings),
            ),
          )
        else
          for (final clip in section.clips) _buildClipTile(context, clip),
      ],
    );
  }

  Widget _buildClipTile(BuildContext context, ClipItem clip) {
    final isActive = clip.uri != null && clip.uri == playback.uri;
    final uri = clip.uri;
    final selected = uri != null && _selectedClipUris.contains(uri);
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          onTap: _isEditing ? () => _toggleClipSelection(clip) : null,
          leading: _isEditing
              ? Checkbox(
                  value: selected,
                  onChanged: uri == null
                      ? null
                      : (_) => _toggleClipSelection(clip),
                )
              : IconButton.filledTonal(
                  tooltip: context.l10n.preview,
                  onPressed: () => onPlay(clip),
                  icon: const Icon(Icons.play_arrow),
                ),
          title: Text(clip.name),
          subtitle: Text(
            [
              if (clip.durationSeconds != null)
                _formatDuration(clip.durationSeconds!),
              if (clip.size != null) _formatBytes(clip.size!),
              _formatTime(clip.createdAt),
            ].join(' · '),
          ),
          trailing: _isEditing
              ? null
              : PopupMenuButton<String>(
                  tooltip: context.l10n.recordingActions,
                  onSelected: (value) {
                    switch (value) {
                      case 'rename':
                        _renameClip(context, clip);
                        break;
                      case 'move':
                        _moveClip(context, clip);
                        break;
                      case 'delete':
                        _deleteClip(context, clip);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'rename',
                      child: Text(context.l10n.rename),
                    ),
                    PopupMenuItem(
                      value: 'move',
                      child: Text(context.l10n.moveToGroup),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(context.l10n.delete),
                    ),
                  ],
                ),
        ),
        if (isActive && !_isEditing)
          _PlaybackControls(
            playback: playback,
            speedOptions: _speedOptions,
            onPause: onPause,
            onResume: onResume,
            onStop: onStop,
            onSeek: onSeek,
            onSpeedChanged: onSpeedChanged,
          ),
        const Divider(height: 1),
      ],
    );
  }

  void _toggleEditing() {
    setState(() {
      _isEditing = !_isEditing;
      if (!_isEditing) {
        _selectedClipUris.clear();
      }
    });
  }

  void _toggleClipSelection(ClipItem clip) {
    final uri = clip.uri;
    if (uri == null) {
      return;
    }
    setState(() {
      if (_selectedClipUris.contains(uri)) {
        _selectedClipUris.remove(uri);
      } else {
        _selectedClipUris.add(uri);
      }
    });
  }

  void _selectAll() {
    final selectableUris = clips.map((clip) => clip.uri).whereType<String>();
    setState(() {
      if (_selectedClipUris.length == selectableUris.length) {
        _selectedClipUris.clear();
      } else {
        _selectedClipUris
          ..clear()
          ..addAll(selectableUris);
      }
    });
  }

  Future<void> _deleteSelectedClips(BuildContext context) async {
    final selectedClips = clips
        .where(
          (clip) => clip.uri != null && _selectedClipUris.contains(clip.uri),
        )
        .toList();
    if (selectedClips.isEmpty) {
      return;
    }
    final confirmed = await _confirm(
      context,
      title: context.l10n.batchDeleteRecordings,
      message: context.l10n.confirmBatchDeleteRecordings(selectedClips.length),
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    await onDeleteClips(selectedClips);
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedClipUris.clear();
      _isEditing = false;
    });
  }

  Future<void> _createGroup(BuildContext context) async {
    final name = await _promptText(
      context,
      title: context.l10n.newGroup,
      label: context.l10n.groupName,
    );
    if (name == null) {
      return;
    }
    await onCreateGroup(name);
  }

  Future<void> _renameGroup(BuildContext context, RecordingGroup group) async {
    final name = await _promptText(
      context,
      title: context.l10n.renameGroup,
      label: context.l10n.groupName,
      initialValue: group.name,
    );
    if (name == null) {
      return;
    }
    await onRenameGroup(group, name);
  }

  Future<void> _deleteGroup(BuildContext context, RecordingGroup group) async {
    final confirmed = await _confirm(
      context,
      title: context.l10n.deleteGroup,
      message: context.l10n.confirmDeleteGroup,
    );
    if (confirmed) {
      await onDeleteGroup(group);
    }
  }

  Future<void> _renameClip(BuildContext context, ClipItem clip) async {
    final name = await _promptText(
      context,
      title: context.l10n.renameRecording,
      label: context.l10n.fileName,
      initialValue: clip.name,
    );
    if (name == null) {
      return;
    }
    await onRenameClip(clip, name);
  }

  Future<void> _deleteClip(BuildContext context, ClipItem clip) async {
    final confirmed = await _confirm(
      context,
      title: context.l10n.deleteRecording,
      message: context.l10n.confirmDeleteRecording(clip.name),
    );
    if (confirmed) {
      await onDeleteClip(clip);
    }
  }

  Future<void> _moveClip(BuildContext context, ClipItem clip) async {
    final target = await showDialog<Object?>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.l10n.moveToGroup),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(_UngroupTarget.instance),
            child: Text(context.l10n.unGrouped),
          ),
          for (final group in groups)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(group),
              child: Text(group.name),
            ),
        ],
      ),
    );
    if (!context.mounted) {
      return;
    }
    if (target == null) {
      return;
    }
    await onMoveClip(clip, target is RecordingGroup ? target : null);
  }
}

enum _UngroupTarget { instance }

Future<String?> _promptText(
  BuildContext context, {
  required String title,
  required String label,
  String? initialValue,
}) async {
  final controller = TextEditingController(text: initialValue ?? '');
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) {
          Navigator.of(context).pop(controller.text.trim());
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: Text(context.l10n.ok),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(context.l10n.ok),
        ),
      ],
    ),
  );
  return confirmed == true;
}

class _ClipGroupSection {
  const _ClipGroupSection({
    required this.title,
    required this.group,
    required this.clips,
  });

  final String title;
  final RecordingGroup? group;
  final List<ClipItem> clips;
}

class _PlaybackControls extends StatefulWidget {
  const _PlaybackControls({
    required this.playback,
    required this.speedOptions,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onSeek,
    required this.onSpeedChanged,
  });

  final PlaybackSnapshot playback;
  final List<double> speedOptions;
  final Future<void> Function() onPause;
  final Future<void> Function() onResume;
  final Future<void> Function() onStop;
  final Future<void> Function(int positionMs) onSeek;
  final Future<void> Function(double speed) onSpeedChanged;

  @override
  State<_PlaybackControls> createState() => _PlaybackControlsState();
}

class _PlaybackControlsState extends State<_PlaybackControls> {
  Timer? _positionTimer;
  late int _positionMs;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _positionMs = widget.playback.positionMs;
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant _PlaybackControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDragging &&
        (oldWidget.playback.positionMs != widget.playback.positionMs ||
            oldWidget.playback.uri != widget.playback.uri)) {
      _positionMs = widget.playback.positionMs;
    }
    _syncTimer();
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    super.dispose();
  }

  void _syncTimer() {
    if (widget.playback.playing) {
      _positionTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _isDragging) {
          return;
        }
        final duration = widget.playback.durationMs;
        final next = _positionMs + (1000 * widget.playback.speed).round();
        setState(() {
          _positionMs = duration > 0 ? math.min(next, duration) : next;
        });
        if (duration > 0 && next >= duration) {
          unawaited(widget.onStop());
        }
      });
    } else {
      _positionTimer?.cancel();
      _positionTimer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.playback.durationMs <= 0
        ? 1
        : widget.playback.durationMs;
    final position = _positionMs.clamp(0, duration).toInt();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(_formatDuration(position ~/ 1000)),
              const Spacer(),
              Text(_formatDuration(widget.playback.durationMs ~/ 1000)),
            ],
          ),
          Slider(
            value: position.toDouble(),
            min: 0,
            max: duration.toDouble(),
            onChangeStart: (_) {
              _isDragging = true;
            },
            onChanged: (value) {
              setState(() {
                _positionMs = value.round();
              });
            },
            onChangeEnd: (value) {
              _isDragging = false;
              widget.onSeek(value.round());
            },
          ),
          Row(
            children: [
              IconButton(
                tooltip: widget.playback.playing
                    ? context.l10n.pause
                    : context.l10n.resume,
                onPressed: widget.playback.playing
                    ? widget.onPause
                    : widget.onResume,
                icon: Icon(
                  widget.playback.playing ? Icons.pause : Icons.play_arrow,
                ),
              ),
              IconButton(
                tooltip: context.l10n.stop,
                onPressed: widget.onStop,
                icon: const Icon(Icons.stop),
              ),
              const Spacer(),
              DropdownButton<double>(
                value: _nearestSpeed(
                  widget.playback.speed,
                  widget.speedOptions,
                ),
                items: [
                  for (final speed in widget.speedOptions)
                    DropdownMenuItem(
                      value: speed,
                      child: Text(
                        '${speed.toStringAsFixed(speed < 1 ? 2 : 1)}x',
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    widget.onSpeedChanged(value);
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  double _nearestSpeed(double speed, List<double> options) {
    return options.reduce(
      (best, value) =>
          (value - speed).abs() < (best - speed).abs() ? value : best,
    );
  }
}
