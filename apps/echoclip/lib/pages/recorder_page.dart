part of '../main.dart';

class _RecorderPage extends StatefulWidget {
  const _RecorderPage({
    required this.isBuffering,
    required this.platformStatus,
    required this.meterSnapshot,
    required this.folderSelected,
    required this.onSave,
    required this.onChooseFolder,
  });

  final bool isBuffering;
  final String platformStatus;
  final ValueListenable<MeterSnapshot> meterSnapshot;
  final bool folderSelected;
  final Future<void> Function(int seconds) onSave;
  final Future<void> Function() onChooseFolder;

  @override
  State<_RecorderPage> createState() => _RecorderPageState();
}

class _RecorderPageState extends State<_RecorderPage> {
  static const List<SaveDurationOption> _durations = [
    SaveDurationOption(10),
    SaveDurationOption(30),
    SaveDurationOption(60),
    SaveDurationOption(120),
    SaveDurationOption(300),
    SaveDurationOption(600),
    SaveDurationOption(1800),
    SaveDurationOption(3600),
    SaveDurationOption(7200),
    SaveDurationOption(18000),
    SaveDurationOption(43200),
    SaveDurationOption(86400),
  ];

  SaveDurationOption _selectedDuration = _durations[1];
  SaveDurationMode _durationMode = SaveDurationMode.preset;
  int _customDurationSeconds = 30;

  int get _activeSaveSeconds {
    return switch (_durationMode) {
      SaveDurationMode.preset => _selectedDuration.seconds,
      SaveDurationMode.custom => _customDurationSeconds,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListView(
      children: [
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    widget.isBuffering ? Icons.graphic_eq : Icons.pause_circle,
                    color: widget.isBuffering
                        ? const Color(0xFF1B7F79)
                        : Colors.orange,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.isBuffering
                          ? l10n.replayRunning
                          : l10n.recordingPaused,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ValueListenableBuilder<MeterSnapshot>(
                valueListenable: widget.meterSnapshot,
                builder: (context, snapshot, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _RecordingTimeSummary(
                        snapshot: snapshot,
                        statusText: widget.platformStatus,
                      ),
                      const SizedBox(height: 10),
                      LoudnessMeter(
                        level: snapshot.level,
                        peakLevel: snapshot.peakLevel,
                        isRecording: snapshot.running,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ValueListenableBuilder<MeterSnapshot>(
                    valueListenable: widget.meterSnapshot,
                    builder: (context, snapshot, _) {
                      final canSave =
                          widget.folderSelected && snapshot.recordedMillis > 0;
                      return FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(152, 56),
                        ),
                        onPressed: canSave
                            ? () => widget.onSave(_activeSaveSeconds)
                            : null,
                        icon: const Icon(Icons.save_alt),
                        label: Text(
                          l10n.saveClip(
                            _formatDurationLabel(l10n, _activeSaveSeconds),
                          ),
                        ),
                      );
                    },
                  ),
                  SegmentedButton<SaveDurationMode>(
                    segments: [
                      ButtonSegment(
                        value: SaveDurationMode.preset,
                        icon: const Icon(Icons.timer_outlined),
                        label: Text(l10n.presetSaveDuration),
                      ),
                      ButtonSegment(
                        value: SaveDurationMode.custom,
                        icon: const Icon(Icons.edit_calendar),
                        label: Text(l10n.customSaveDuration),
                      ),
                    ],
                    selected: {_durationMode},
                    onSelectionChanged: (values) {
                      setState(() => _durationMode = values.first);
                    },
                  ),
                  if (_durationMode == SaveDurationMode.preset)
                    DropdownMenu<SaveDurationOption>(
                      initialSelection: _selectedDuration,
                      width: 168,
                      leadingIcon: const Icon(Icons.timer_outlined),
                      inputDecorationTheme: const InputDecorationTheme(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12),
                        constraints: BoxConstraints(minHeight: 56),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(28)),
                        ),
                      ),
                      onSelected: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _selectedDuration = value;
                        });
                      },
                      dropdownMenuEntries: [
                        for (final option in _durations)
                          DropdownMenuEntry(
                            value: option,
                            label: _formatDurationLabel(l10n, option.seconds),
                          ),
                      ],
                    )
                  else
                    _SaveSecondsField(
                      seconds: _customDurationSeconds,
                      onChanged: (seconds) {
                        setState(() => _customDurationSeconds = seconds);
                      },
                    ),
                  if (!widget.folderSelected)
                    OutlinedButton.icon(
                      onPressed: widget.onChooseFolder,
                      icon: const Icon(Icons.folder_open),
                      label: Text(l10n.chooseFolder),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecordingTimeSummary extends StatelessWidget {
  const _RecordingTimeSummary({
    required this.snapshot,
    required this.statusText,
  });

  final MeterSnapshot snapshot;
  final String statusText;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final startedAt = snapshot.sessionStartedAt ?? _epochDateTime;
    final startText = snapshot.running
        ? l10n.recordingStartedAt(_formatSessionStart(startedAt))
        : l10n.lastRecordingStartedAt(_formatSessionStart(startedAt));
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: const Color(0xFF6C7472),
    );
    final numberStyle = theme.textTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final totalStyle = theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(startText, style: labelStyle),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              flex: 6,
              child: _TimeBlock(
                label: l10n.currentRecordingDuration,
                value: _formatDurationMillis(snapshot.sessionRecordedMillis),
                labelStyle: labelStyle,
                valueStyle: numberStyle,
              ),
            ),
            Container(
              width: 1,
              height: 44,
              margin: const EdgeInsets.symmetric(horizontal: 14),
              color: const Color(0xFFD7DFDC),
            ),
            Expanded(
              flex: 5,
              child: _TimeBlock(
                label: l10n.totalRecordedDuration,
                value: _formatDurationMillis(snapshot.recordedMillis),
                labelStyle: labelStyle,
                valueStyle: totalStyle,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          statusText,
          style: theme.textTheme.bodySmall?.copyWith(
            color: const Color(0xFF52615E),
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }
}

class _TimeBlock extends StatelessWidget {
  const _TimeBlock({
    required this.label,
    required this.value,
    required this.labelStyle,
    required this.valueStyle,
  });

  final String label;
  final String value;
  final TextStyle? labelStyle;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: labelStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: valueStyle),
        ),
      ],
    );
  }
}
