part of '../main.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.groups,
    required this.clips,
    required this.playback,
    required this.onRefresh,
    required this.onPlay,
    this.onShare,
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
    required this.onConvertWavToMp3,
  });

  final List<RecordingGroup> groups;
  final List<ClipItem> clips;
  final PlaybackSnapshot playback;
  final Future<void> Function() onRefresh;
  final Future<void> Function(ClipItem clip) onPlay;
  final Future<void> Function(ClipItem clip)? onShare;
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
  final Future<bool> Function(ClipItem clip, int mp3BitrateKbps)
  onConvertWavToMp3;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
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
  final _search = TextEditingController();
  String _query = '';
  String? _groupFilter;
  _LibrarySort _sort = _LibrarySort.newest;
  static const _ungroupedFilter = 'library:ungrouped';

  List<ClipItem> get _visibleClips {
    final result = clips.where((clip) {
      final inGroup =
          _groupFilter == null ||
          (_groupFilter == _ungroupedFilter
              ? clip.groupUri == null
              : clip.groupUri == _groupFilter);
      return inGroup &&
          clip.name.toLowerCase().contains(_query.trim().toLowerCase());
    }).toList();
    result.sort(
      (a, b) => switch (_sort) {
        _LibrarySort.newest => b.createdAt.compareTo(a.createdAt),
        _LibrarySort.oldest => a.createdAt.compareTo(b.createdAt),
        _LibrarySort.name => a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        ),
      },
    );
    return result;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setFilter(String? value) => setState(() {
    _groupFilter = value;
    _selectedClipUris.clear();
  });

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
  Future<bool> Function(ClipItem clip, int mp3BitrateKbps)
  get onConvertWavToMp3 => widget.onConvertWavToMp3;

  @override
  void didUpdateWidget(covariant LibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_groupFilter != null &&
        _groupFilter != _ungroupedFilter &&
        !groups.any((group) => group.uri == _groupFilter)) {
      _groupFilter = null;
    }
    final liveUris = clips.map((clip) => clip.uri).whereType<String>().toSet();
    _selectedClipUris.removeWhere((uri) => !liveUris.contains(uri));
    if (_selectedClipUris.isEmpty && liveUris.isEmpty && _isEditing) {
      _isEditing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleClips;
    final activeClip = (playback.playing || playback.paused)
        ? clips
              .where((clip) => clip.uri != null && clip.uri == playback.uri)
              .firstOrNull
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= 720 &&
            MediaQuery.textScalerOf(context).scale(1) < 1.5;
        return Column(
          key: const ValueKey('library.page'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: CustomScrollView(
                key: const PageStorageKey('library.scroll'),
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeader(context),
                        const SizedBox(height: 20),
                        _buildSearch(context),
                        const SizedBox(height: 12),
                        _buildGroups(context),
                        if (_isEditing) ...[
                          const SizedBox(height: 12),
                          _buildSelection(context),
                        ],
                        const SizedBox(height: 16),
                        if (wide && visible.isNotEmpty)
                          _buildColumnLabels(context),
                      ],
                    ),
                  ),
                  if (visible.isEmpty)
                    SliverToBoxAdapter(child: _buildEmpty(context))
                  else
                    SliverList.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildClipTile(
                          context,
                          visible[index],
                          wide: wide,
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 8)),
                ],
              ),
            ),
            if (activeClip != null) ...[
              const SizedBox(height: 12),
              Container(
                key: const ValueKey('library.player'),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3EF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFCDDCD4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.graphic_eq,
                          size: 20,
                          color: Color(0xFF267B69),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            activeClip.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    _PlaybackControls(
                      key: ValueKey(activeClip.uri),
                      playback: playback,
                      speedOptions: _speedOptions,
                      onPause: onPause,
                      onResume: onResume,
                      onStop: onStop,
                      onSeek: onSeek,
                      onSpeedChanged: onSpeedChanged,
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final l10n = context.l10n;
    final totalBytes = clips.fold<int>(
      0,
      (total, clip) => total + (clip.size ?? 0),
    );
    final summary = [
      l10n.libraryCount(clips.length),
      if (clips.isNotEmpty && clips.every((clip) => clip.size != null))
        _formatBytes(totalBytes),
    ].join(' · ');
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.libraryTitle,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: const Color(0xFF233E32),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          summary,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: const Color(0xFF6A7D73)),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final labels =
            constraints.maxWidth >= 640 &&
            MediaQuery.textScalerOf(context).scale(1) < 1.5;
        final actions = Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (!_isEditing)
              if (labels)
                OutlinedButton.icon(
                  onPressed: () => _createGroup(context),
                  icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                  label: Text(l10n.newGroup),
                )
              else
                IconButton.filledTonal(
                  tooltip: l10n.newGroup,
                  onPressed: () => _createGroup(context),
                  icon: const Icon(Icons.create_new_folder_outlined, size: 20),
                ),
            if (labels)
              OutlinedButton.icon(
                onPressed: _toggleEditing,
                icon: Icon(_isEditing ? Icons.done : Icons.checklist, size: 18),
                label: Text(_isEditing ? l10n.done : l10n.edit),
              )
            else
              IconButton.outlined(
                tooltip: _isEditing ? l10n.done : l10n.edit,
                onPressed: _toggleEditing,
                icon: Icon(_isEditing ? Icons.done : Icons.checklist, size: 20),
              ),
            if (!_isEditing)
              IconButton(
                tooltip: l10n.refresh,
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh, size: 20),
              ),
          ],
        );
        return MediaQuery.textScalerOf(context).scale(1) >= 1.5 ||
                constraints.maxWidth < 300
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, const SizedBox(height: 12), actions],
              )
            : Row(
                crossAxisAlignment: _isDesktopPlatform
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 12),
                  actions,
                ],
              );
      },
    );
  }

  String _sortLabel(AppLocalizations l10n, _LibrarySort sort) => switch (sort) {
    _LibrarySort.newest => l10n.libraryNewest,
    _LibrarySort.oldest => l10n.libraryOldest,
    _LibrarySort.name => l10n.libraryNameOrder,
  };

  Widget _buildSearch(BuildContext context) => Row(
    children: [
      Expanded(
        child: TextField(
          key: const ValueKey('library.search'),
          controller: _search,
          onChanged: (value) => setState(() {
            _query = value;
            _selectedClipUris.clear();
          }),
          decoration: InputDecoration(
            hintText: context.l10n.searchRecordings,
            filled: true,
            fillColor: Colors.white,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: context.l10n.clearSearch,
                    onPressed: () => setState(() {
                      _search.clear();
                      _query = '';
                      _selectedClipUris.clear();
                    }),
                    icon: const Icon(Icons.close, size: 18),
                  ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFDCE5DF)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFDCE5DF)),
            ),
          ),
        ),
      ),
      const SizedBox(width: 8),
      AppMenuButton<_LibrarySort>(
        key: const ValueKey('library.sort'),
        tooltip: context.l10n.sortRecordings,
        onSelected: (value) => setState(() => _sort = value),
        icon: const Icon(Icons.sort, size: 22),
        itemBuilder: (_) => [
          for (final sort in _LibrarySort.values)
            AppMenuItem(
              value: sort,
              checked: sort == _sort,
              child: Text(_sortLabel(context.l10n, sort)),
            ),
        ],
      ),
    ],
  );

  Widget _buildGroups(BuildContext context) {
    final selectedGroup = groups
        .where((group) => group.uri == _groupFilter)
        .firstOrNull;
    Widget filter(String? value, String label, int count) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: label,
        child: ChoiceChip(
          key: ValueKey('library.group.${value ?? 'all'}'),
          selected: _groupFilter == value,
          onSelected: (_) => _setFilter(value),
          showCheckmark: false,
          selectedColor: const Color(0xFFDCEDE5),
          backgroundColor: Colors.white,
          side: BorderSide(
            color: _groupFilter == value
                ? const Color(0xFFB6D4C5)
                : const Color(0xFFE0E7E3),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: Text(
              '$label  $count',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
      ),
    );
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                filter(null, context.l10n.allRecordings, clips.length),
                filter(
                  _ungroupedFilter,
                  context.l10n.unGrouped,
                  clips.where((clip) => clip.groupUri == null).length,
                ),
                for (final group in groups)
                  filter(
                    group.uri,
                    group.name,
                    clips.where((clip) => clip.groupUri == group.uri).length,
                  ),
              ],
            ),
          ),
        ),
        if (selectedGroup != null) _groupMenu(context, selectedGroup),
      ],
    );
  }

  Widget _groupMenu(BuildContext context, RecordingGroup group) =>
      AppMenuButton<String>(
        key: const ValueKey('library.groupActions'),
        tooltip: context.l10n.groupActions,
        icon: const Icon(Icons.more_horiz),
        onSelected: (value) => value == 'rename'
            ? _renameGroup(context, group)
            : _deleteGroup(context, group),
        itemBuilder: (_) => [
          AppMenuItem(value: 'rename', child: Text(context.l10n.renameGroup)),
          AppMenuItem(value: 'delete', child: Text(context.l10n.deleteGroup)),
        ],
      );

  Widget _buildSelection(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF3EF),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          context.l10n.librarySelected(_selectedClipUris.length),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        TextButton(
          onPressed: _visibleClips.isEmpty ? null : _selectAll,
          child: Text(context.l10n.selectAll),
        ),
        TextButton.icon(
          onPressed: _selectedClipUris.isEmpty
              ? null
              : () => _deleteSelectedClips(context),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: Text(context.l10n.deleteSelected),
        ),
      ],
    ),
  );

  Widget _buildColumnLabels(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
    child: DefaultTextStyle(
      style: Theme.of(
        context,
      ).textTheme.labelSmall!.copyWith(color: const Color(0xFF718378)),
      child: Row(
        children: [
          const SizedBox(width: 58),
          Expanded(child: Text(context.l10n.fileName)),
          const SizedBox(width: 20),
          SizedBox(width: 80, child: Text(context.l10n.librarySize)),
          const SizedBox(width: 20),
          SizedBox(width: 146, child: Text(context.l10n.librarySavedAt)),
          const SizedBox(width: 40),
        ],
      ),
    ),
  );

  Widget _buildEmpty(BuildContext context) {
    final filtered = _query.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: const BoxDecoration(
              color: Color(0xFFEAF1ED),
              shape: BoxShape.circle,
            ),
            child: Icon(
              filtered ? Icons.search_off : Icons.library_music_outlined,
              size: 36,
              color: const Color(0xFF789485),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            filtered
                ? context.l10n.libraryNoMatches
                : context.l10n.emptyRecordings,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            filtered
                ? context.l10n.librarySearchHint
                : context.l10n.libraryEmptyHint,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF718378)),
          ),
        ],
      ),
    );
  }

  Widget _buildClipTile(
    BuildContext context,
    ClipItem clip, {
    required bool wide,
  }) {
    final isActive =
        clip.uri != null &&
        clip.uri == playback.uri &&
        (playback.playing || playback.paused);
    final selected = clip.uri != null && _selectedClipUris.contains(clip.uri);
    final extension = clip.name.contains('.')
        ? clip.name.split('.').last.toUpperCase()
        : context.l10n.audioFileLabel;
    final metadata = [
      extension,
      if (clip.durationSeconds != null) _formatDuration(clip.durationSeconds!),
      if (clip.groupName != null) clip.groupName!,
      if (!wide && clip.size != null) _formatBytes(clip.size!),
    ];
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          clip.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF243E33),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          metadata.join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: Color(0xFF6F8277)),
        ),
        if (!wide) ...[
          const SizedBox(height: 4),
          Text(
            _formatTime(clip.createdAt),
            style: const TextStyle(fontSize: 11, color: Color(0xFF7C8E83)),
          ),
        ],
      ],
    );
    return Material(
      key: ValueKey('library.clip.${clip.uri ?? clip.name}'),
      color: isActive || selected ? const Color(0xFFEAF3EF) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isActive || selected
              ? const Color(0xFFBED6C8)
              : const Color(0xFFE0E7E3),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _isEditing ? () => _toggleClipSelection(clip) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: _isEditing
                    ? Checkbox(
                        value: selected,
                        onChanged: clip.uri == null
                            ? null
                            : (_) => _toggleClipSelection(clip),
                      )
                    : IconButton.filledTonal(
                        key: ValueKey('library.play.${clip.uri ?? clip.name}'),
                        tooltip: isActive
                            ? (playback.playing
                                  ? context.l10n.pause
                                  : context.l10n.resume)
                            : context.l10n.preview,
                        style: IconButton.styleFrom(
                          backgroundColor: isActive
                              ? const Color(0xFF267B69)
                              : const Color(0xFFEDF3EF),
                          foregroundColor: isActive
                              ? Colors.white
                              : const Color(0xFF426D58),
                          minimumSize: const Size(44, 44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => isActive
                            ? (playback.playing ? onPause() : onResume())
                            : onPlay(clip),
                        icon: Icon(
                          isActive && playback.playing
                              ? Icons.pause
                              : Icons.play_arrow_rounded,
                          size: 24,
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(child: details),
              if (wide) ...[
                const SizedBox(width: 20),
                SizedBox(
                  width: 80,
                  child: Text(
                    clip.size == null ? '—' : _formatBytes(clip.size!),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF647B6E),
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                SizedBox(
                  width: 146,
                  child: Text(
                    _formatTime(clip.createdAt),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF647B6E),
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
              if (_isEditing)
                const SizedBox(width: 40)
              else
                SizedBox(width: 40, child: _clipMenu(context, clip)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _clipMenu(BuildContext context, ClipItem clip) =>
      AppMenuButton<String>(
        key: ValueKey('library.actions.${clip.uri ?? clip.name}'),
        tooltip: context.l10n.recordingActions,
        icon: const Icon(Icons.more_horiz, color: Color(0xFF7B8F83)),
        onSelected: (value) {
          switch (value) {
            case 'share':
              widget.onShare?.call(clip);
              break;
            case 'convert_mp3':
              _convertWavToMp3(context, clip);
              break;
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
        itemBuilder: (_) => [
          if (widget.onShare != null && clip.uri != null)
            AppMenuItem(
              value: 'share',
              child: Row(
                children: [
                  const Icon(Icons.share_outlined, size: 20),
                  const SizedBox(width: 12),
                  Expanded(child: Text(context.l10n.shareRecording)),
                ],
              ),
            ),
          if (clip.name.toLowerCase().endsWith('.wav'))
            AppMenuItem(
              value: 'convert_mp3',
              child: Text(context.l10n.convertWavToMp3),
            ),
          AppMenuItem(value: 'rename', child: Text(context.l10n.rename)),
          AppMenuItem(value: 'move', child: Text(context.l10n.moveToGroup)),
          AppMenuItem(value: 'delete', child: Text(context.l10n.delete)),
        ],
      );

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
    final selectableUris = _visibleClips
        .map((clip) => clip.uri)
        .whereType<String>()
        .toSet();
    setState(() {
      if (selectableUris.isNotEmpty &&
          selectableUris.every(_selectedClipUris.contains)) {
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

  Future<void> _convertWavToMp3(BuildContext context, ClipItem clip) async {
    const bitrates = [64, 96, 128, 160, 192, 256, 320];
    final bitrate = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(context.l10n.convertWavBitrate),
        children: [
          for (final value in bitrates)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(value),
              child: Text('$value kbps'),
            ),
        ],
      ),
    );
    if (bitrate == null || !context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.l10n.convertingWavToMp3)));
    final ok = await onConvertWavToMp3(clip, bitrate);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? context.l10n.convertedWavToMp3(
                    clip.name.replaceFirst(
                      RegExp(r'\.wav$', caseSensitive: false),
                      '.mp3',
                    ),
                  )
                : context.l10n.convertWavToMp3Failed('conversion_failed'),
          ),
        ),
      );
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
}) => showDialog<String>(
  context: context,
  builder: (_) => _LibraryNameDialog(
    title: title,
    label: label,
    initialValue: initialValue,
  ),
);

class _LibraryNameDialog extends StatefulWidget {
  const _LibraryNameDialog({
    required this.title,
    required this.label,
    this.initialValue,
  });
  final String title;
  final String label;
  final String? initialValue;
  @override
  State<_LibraryNameDialog> createState() => _LibraryNameDialogState();
}

class _LibraryNameDialogState extends State<_LibraryNameDialog> {
  late final _controller = TextEditingController(
    text: widget.initialValue ?? '',
  );
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      decoration: InputDecoration(labelText: widget.label),
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(context.l10n.cancel),
      ),
      FilledButton(onPressed: _submit, child: Text(context.l10n.ok)),
    ],
  );
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

enum _LibrarySort { newest, oldest, name }

class _PlaybackControls extends StatefulWidget {
  const _PlaybackControls({
    super.key,
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
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                _formatDuration(position ~/ 1000),
                style: const TextStyle(
                  fontSize: 11,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              Expanded(
                child: Slider(
                  key: const ValueKey('library.seek'),
                  value: position.toDouble(),
                  min: 0,
                  max: duration.toDouble(),
                  onChangeStart: (_) => _isDragging = true,
                  onChanged: (value) =>
                      setState(() => _positionMs = value.round()),
                  onChangeEnd: (value) {
                    _isDragging = false;
                    widget.onSeek(value.round());
                  },
                ),
              ),
              Text(
                _formatDuration(widget.playback.durationMs ~/ 1000),
                style: const TextStyle(
                  fontSize: 11,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton.filledTonal(
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
                ],
              ),
              Semantics(
                label: context.l10n.playbackSpeed,
                child: AppMenuButton<double>(
                  key: const ValueKey('library.speed'),
                  tooltip: context.l10n.playbackSpeed,
                  initialValue: _nearestSpeed(
                    widget.playback.speed,
                    widget.speedOptions,
                  ),
                  onSelected: widget.onSpeedChanged,
                  itemBuilder: (_) => [
                    for (final speed in widget.speedOptions)
                      AppMenuItem(
                        value: speed,
                        child: Text(
                          '${speed.toStringAsFixed(speed < 1 ? 2 : 1)}x',
                        ),
                      ),
                  ],
                  childBuilder: (context, open) => Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${_nearestSpeed(widget.playback.speed, widget.speedOptions).toStringAsFixed(widget.playback.speed < 1 ? 2 : 1)}x',
                        ),
                        const SizedBox(width: 8),
                        AppMenuChevron(open: open),
                      ],
                    ),
                  ),
                ),
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
