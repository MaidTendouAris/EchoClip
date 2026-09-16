part of '../main.dart';

enum ClipSaveOutcome { saved, canceled, failed, cancelFailed }

class ClipSaveProgress {
  const ClipSaveProgress({
    this.busy = false,
    this.canceling = false,
    this.cancellable = false,
    this.progress,
  });
  final bool busy;
  final bool canceling;
  final bool cancellable;
  // The native encoder has no percentage; only SAF file writing reports one.
  final double? progress;
}

class RecorderPage extends StatefulWidget {
  const RecorderPage({
    super.key,
    required this.isBuffering,
    required this.platformStatus,
    required this.meterSnapshot,
    required this.folderSelected,
    required this.onSave,
    required this.onChooseFolder,
    this.onGetBufferWindow,
    this.exportFormat = "mp3",
    this.onSaveRange,
    this.headerActions = const [],
    this.saveProgress = const ClipSaveProgress(),
    this.saveOutcome,
    this.saveErrorDetail,
  });

  final String exportFormat;
  final Future<BufferWindow> Function()? onGetBufferWindow;
  final Future<void> Function(BufferSelection)? onSaveRange;
  final List<Widget> headerActions;
  final ClipSaveProgress saveProgress;
  final ClipSaveOutcome? saveOutcome;
  final String? saveErrorDetail;
  final bool isBuffering;
  final String platformStatus;
  final ValueListenable<MeterSnapshot> meterSnapshot;
  final bool folderSelected;
  final Future<void> Function(int seconds) onSave;
  final Future<void> Function() onChooseFolder;

  @override
  State<RecorderPage> createState() => _RecorderPageState();
}

class _RecorderPageState extends State<RecorderPage> {
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
    SaveDurationOption(14400),
    SaveDurationOption(18000),
    SaveDurationOption(43200),
    SaveDurationOption(86400),
  ];

  SaveDurationOption _selectedDuration = _durations[1];
  SaveDurationMode _durationMode = SaveDurationMode.preset;
  BufferSelection? _selection;
  bool _loadingRange = false;
  int get _maxSaveSeconds => widget.exportFormat == 'wav' ? 14400 : 86400;

  @override
  void didUpdateWidget(covariant RecorderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_activeSaveSeconds > _maxSaveSeconds) {
      _selectedDuration = _durations.firstWhere(
        (value) => value.seconds == _maxSaveSeconds,
      );
      _durationMode = SaveDurationMode.preset;
      _selection = null;
    }
  }

  int get _activeSaveSeconds {
    return switch (_durationMode) {
      SaveDurationMode.preset => _selectedDuration.seconds,
      SaveDurationMode.custom => _selection?.duration.ceil() ?? 1,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final showDetail =
        widget.platformStatus.isNotEmpty &&
        !{
          l10n.recordingPaused,
          l10n.recordingStatusPaused,
          l10n.recordingStatusNormal,
          l10n.replayRunning,
          l10n.clipSaved,
          l10n.saveStarted,
        }.contains(widget.platformStatus);
    return ListView(
      key: const ValueKey('recorder.page'),
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        ValueListenableBuilder<MeterSnapshot>(
          valueListenable: widget.meterSnapshot,
          builder: (context, snapshot, _) {
            final startedAt = snapshot.sessionStartedAt;
            return _PageHeading(
              actions: widget.headerActions,
              alignActionsWithTitle: true,
              title: widget.isBuffering
                  ? l10n.replayRunning
                  : l10n.recordingPaused,
              subtitle: startedAt == null
                  ? l10n.lastRecordingTimeUnavailable
                  : snapshot.running
                  ? l10n.recordingStartedAt(_formatSessionStart(startedAt))
                  : l10n.lastRecordingStartedAt(_formatSessionStart(startedAt)),
            );
          },
        ),
        const SizedBox(height: 20),
        ValueListenableBuilder<MeterSnapshot>(
          valueListenable: widget.meterSnapshot,
          builder: (context, snapshot, _) => _Panel(
            key: const ValueKey('recorder.summary'),
            child: _RecordingTimeSummary(snapshot: snapshot),
          ),
        ),
        if (showDetail) ...[
          const SizedBox(height: 12),
          _ScheduleNotice(
            icon: Icons.info_outline,
            text: widget.platformStatus,
          ),
        ],
        const SizedBox(height: 16),
        ValueListenableBuilder<MeterSnapshot>(
          valueListenable: widget.meterSnapshot,
          builder: (context, snapshot, _) => LoudnessMeter(
            level: snapshot.level,
            peakLevel: snapshot.peakLevel,
            isRecording: snapshot.running,
          ),
        ),
        const SizedBox(height: 16),
        _Panel(
          key: const ValueKey('recorder.save'),
          child: _buildSaveControls(l10n),
        ),
      ],
    );
  }

  Future<void> _chooseSaveDuration(int seconds) async {
    if (seconds > 0) {
      setState(() {
        _selectedDuration = _durations.firstWhere(
          (value) => value.seconds == seconds,
        );
        _durationMode = SaveDurationMode.preset;
      });
      return;
    }
    if (_loadingRange) return;
    setState(() => _loadingRange = true);
    try {
      final window =
          await (widget.onGetBufferWindow?.call() ??
              const ReplayServiceClient().getBufferWindow());
      if (!mounted) return;
      if (window.duration.floor() < 1) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.bufferRangeEmpty)));
        return;
      }
      final selected = await showDialog<BufferSelection>(
        context: context,
        builder: (_) => BufferRangeDialog(
          window: window,
          maxSelectionSeconds: _maxSaveSeconds,
        ),
      );
      if (!mounted || selected == null) return;
      setState(() {
        _selection = selected;
        _durationMode = SaveDurationMode.custom;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.bufferRangeUnavailable)),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingRange = false);
    }
  }

  Future<void> _save() async {
    if (!widget.saveProgress.busy &&
        _durationMode == SaveDurationMode.custom &&
        _selection != null) {
      await (widget.onSaveRange?.call(_selection!) ??
          Future<void>.error(StateError('range_export_unavailable')));
    } else {
      await widget.onSave(_activeSaveSeconds);
    }
  }

  Widget _buildSaveControls(AppLocalizations l10n) {
    final height = math.max(
      52.0,
      MediaQuery.textScalerOf(context).scale(14) + 28,
    );
    final saving = widget.saveProgress;
    final busyLabel = saving.canceling
        ? l10n.saveCanceling
        : saving.progress != null
        ? l10n.saveWritingProgress((saving.progress! * 100).floor())
        : saving.cancellable
        ? l10n.saveInProgress
        : l10n.saveStarted;
    return Column(
      key: const ValueKey('save.controls'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SaveStatusLabel(
          progress: widget.saveProgress,
          outcome: widget.saveOutcome,
          errorDetail: widget.saveErrorDetail,
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final duration = SizedBox(
              height: height,
              child: AppMenuButton<int>(
                key: const ValueKey('save.duration'),
                enabled: !saving.busy && !_loadingRange,
                tooltip: l10n.chooseSaveDuration,
                matchAnchorWidth: true,
                onSelected: _chooseSaveDuration,
                itemBuilder: (_) => [
                  AppMenuItem(
                    value: -1,
                    checked: _durationMode == SaveDurationMode.custom,
                    child: Text(l10n.customSaveDuration),
                  ),
                  const PopupMenuDivider(),
                  for (final option in _durations.where(
                    (option) => option.seconds <= _maxSaveSeconds,
                  ))
                    AppMenuItem(
                      value: option.seconds,
                      checked:
                          _durationMode == SaveDurationMode.preset &&
                          option == _selectedDuration,
                      child: Text(_formatDurationLabel(l10n, option.seconds)),
                    ),
                ],
                childBuilder: (context, open) => Ink(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F8F7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFD3DFD9)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.timer_outlined,
                        size: 20,
                        color: Color(0xFF536C60),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _durationMode == SaveDurationMode.custom &&
                                  _selection != null
                              ? '${_rangeTime(_selection!.start)} – ${_rangeTime(_selection!.end)}'
                              : _formatDurationLabel(l10n, _activeSaveSeconds),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AppMenuChevron(open: open),
                    ],
                  ),
                ),
              ),
            );
            final save = SizedBox(
              height: height,
              child: ValueListenableBuilder<MeterSnapshot>(
                valueListenable: widget.meterSnapshot,
                builder: (context, snapshot, _) => FilledButton.icon(
                  key: const ValueKey('save.submit'),
                  style: FilledButton.styleFrom(
                    minimumSize: Size(0, height),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: saving.busy
                      ? (saving.cancellable && !saving.canceling ? _save : null)
                      : widget.folderSelected && snapshot.recordedMillis > 0
                      ? _save
                      : null,
                  icon: saving.busy
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            key: const ValueKey('save.progress'),
                            value: saving.canceling ? null : saving.progress,
                            strokeWidth: 2,
                            color: saving.canceling
                                ? null
                                : Theme.of(context).colorScheme.onPrimary,
                            semanticsLabel: busyLabel,
                          ),
                        )
                      : const Icon(Icons.save_alt, size: 20),
                  label: Text(
                    saving.busy
                        ? (saving.cancellable &&
                                  !saving.canceling &&
                                  MediaQuery.textScalerOf(context).scale(1) >=
                                      1.5
                              ? l10n.cancel
                              : busyLabel)
                        : _durationMode == SaveDurationMode.custom
                        ? l10n.saveSelectedRange
                        : l10n.saveClip(
                            _formatDurationLabel(l10n, _activeSaveSeconds),
                          ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            );
            return constraints.maxWidth >= 440 &&
                    MediaQuery.textScalerOf(context).scale(1) < 1.5
                ? Row(
                    children: [
                      Expanded(child: duration),
                      const SizedBox(width: 12),
                      Expanded(child: save),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [duration, const SizedBox(height: 10), save],
                  );
          },
        ),
        if (!widget.folderSelected) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: widget.onChooseFolder,
              icon: const Icon(Icons.folder_open, size: 18),
              label: Text(l10n.chooseFolder),
            ),
          ),
        ],
      ],
    );
  }
}

/// A single fixed-height status line; long details stay available in the tooltip.
class _SaveStatusLabel extends StatelessWidget {
  const _SaveStatusLabel({
    required this.progress,
    this.outcome,
    this.errorDetail,
  });
  final ClipSaveProgress progress;
  final ClipSaveOutcome? outcome;
  final String? errorDetail;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final failed =
        outcome == ClipSaveOutcome.failed ||
        outcome == ClipSaveOutcome.cancelFailed;
    final message = switch (outcome) {
      ClipSaveOutcome.saved => l10n.clipSaved,
      ClipSaveOutcome.canceled => l10n.saveCanceled,
      ClipSaveOutcome.failed =>
        errorDetail?.contains('BUFFER_RANGE_EXPIRED') == true
            ? l10n.bufferRangeExpired
            : l10n.saveFailedStatus,
      ClipSaveOutcome.cancelFailed => l10n.saveCancelFailedStatus,
      null =>
        progress.canceling
            ? l10n.saveCancelingStatus
            : progress.busy
            ? (progress.progress == null
                  ? l10n.saveStarted
                  : l10n.saveWritingStatus)
            : l10n.saveRecentLabel,
    };
    final icon = switch (outcome) {
      ClipSaveOutcome.saved => Icons.check_circle_outline,
      ClipSaveOutcome.canceled => Icons.cancel_outlined,
      ClipSaveOutcome.failed ||
      ClipSaveOutcome.cancelFailed => Icons.error_outline,
      null => progress.busy ? Icons.hourglass_top_rounded : null,
    };
    final color = failed
        ? Theme.of(context).colorScheme.error
        : outcome == ClipSaveOutcome.saved
        ? const Color(0xFF267361)
        : const Color(0xFF60766C);
    final style = Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(fontSize: 14, height: 1.4, color: color);
    final description =
        errorDetail == null || errorDetail!.contains('BUFFER_RANGE_EXPIRED')
        ? message
        : '$message\n${l10n.saveError(errorDetail!)}';
    return Semantics(
      key: const ValueKey('save.status'),
      liveRegion: true,
      label: description,
      child: ExcludeSemantics(
        child: Tooltip(
          message: description,
          child: SizedBox(
            height: math.max(
              20,
              MediaQuery.textScalerOf(context).scale(14) * 1.4,
            ),
            child: AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              layoutBuilder: (currentChild, previousChildren) => Stack(
                alignment: AlignmentDirectional.centerStart,
                children: [...previousChildren, ?currentChild],
              ),
              child: Row(
                key: ValueKey(message),
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: color),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      message,
                      style: style,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _rangeTime(double value) {
  final seconds = value.floor();
  return [
    seconds ~/ 3600,
    seconds ~/ 60 % 60,
    seconds % 60,
  ].map((part) => part.toString().padLeft(2, '0')).join(':');
}

class BufferRangeDialog extends StatefulWidget {
  const BufferRangeDialog({
    super.key,
    required this.window,
    this.maxSelectionSeconds = 86400,
  });
  final int maxSelectionSeconds;
  final BufferWindow window;
  @override
  State<BufferRangeDialog> createState() => _BufferRangeDialogState();
}

class _BufferRangeDialogState extends State<BufferRangeDialog> {
  late RangeValues _values;
  late final List<TextEditingController> _start, _end;
  bool _invalid = false;
  int get _maxSeconds => widget.window.duration.floor();

  @override
  void initState() {
    super.initState();
    _values = RangeValues(
      math.max(0, _maxSeconds - widget.maxSelectionSeconds).toDouble(),
      _maxSeconds.toDouble(),
    );
    _start = List.generate(3, (_) => TextEditingController());
    _end = List.generate(3, (_) => TextEditingController());
    _writeFields();
  }

  void _writeFields() {
    for (final (fields, seconds) in [
      (_start, _values.start),
      (_end, _values.end),
    ]) {
      final parts = _rangeTime(seconds).split(':');
      for (var i = 0; i < 3; i++) {
        fields[i].text = parts[i];
      }
    }
  }

  @override
  void dispose() {
    for (final field in [..._start, ..._end]) {
      field.dispose();
    }
    super.dispose();
  }

  int? _seconds(List<TextEditingController> fields) {
    final parts = fields
        .map((field) => int.tryParse(field.text.trim()))
        .toList();
    if (parts.any((part) => part == null || part < 0) ||
        parts[1]! > 59 ||
        parts[2]! > 59) {
      return null;
    }
    return parts[0]! * 3600 + parts[1]! * 60 + parts[2]!;
  }

  bool _readFields() {
    final start = _seconds(_start), end = _seconds(_end);
    final valid =
        start != null &&
        end != null &&
        start < end &&
        end <= _maxSeconds &&
        end - start <= widget.maxSelectionSeconds;
    setState(() {
      _invalid = !valid;
      if (valid) {
        _values = RangeValues(start.toDouble(), end.toDouble());
      }
    });
    return valid;
  }

  void _apply() {
    if (!_readFields()) {
      return;
    }
    try {
      Navigator.of(
        context,
      ).pop(widget.window.select(_values.start, _values.end));
    } on FormatException {
      setState(() => _invalid = true);
    }
  }

  Widget _timeFields(
    List<TextEditingController> fields,
    String label,
    String key,
  ) {
    final l10n = context.l10n;
    final units = [
      l10n.timeHoursShort,
      l10n.timeMinutesShort,
      l10n.timeSecondsShort,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(':'),
                ),
              Expanded(
                child: TextField(
                  key: ValueKey('$key.$i'),
                  controller: fields[i],
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textInputAction: TextInputAction.next,
                  textAlign: TextAlign.center,
                  onChanged: (_) => _readFields(),
                  onSubmitted: (_) => _readFields(),
                  decoration: InputDecoration(
                    labelText: units[i],
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 16,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.bufferRange),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.bufferRangeHelp,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (widget.maxSelectionSeconds == 14400) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.wavSaveLimit,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 16),
              RangeSlider(
                key: const ValueKey('save.rangeSlider'),
                values: _values,
                min: 0,
                max: _maxSeconds.toDouble(),
                labels: RangeLabels(
                  _rangeTime(_values.start),
                  _rangeTime(_values.end),
                ),
                semanticFormatterCallback: _rangeTime,
                onChanged: _maxSeconds < 1
                    ? null
                    : (values) {
                        var start = values.start.round().clamp(
                          0,
                          _maxSeconds - 1,
                        );
                        var end = values.end.round().clamp(1, _maxSeconds);
                        if (start >= end) {
                          if (start != _values.start.round()) {
                            start = end - 1;
                          } else {
                            end = start + 1;
                          }
                        }
                        if (end - start > widget.maxSelectionSeconds) {
                          if (start != _values.start.round()) {
                            end = start + widget.maxSelectionSeconds;
                          } else {
                            start = end - widget.maxSelectionSeconds;
                          }
                        }
                        setState(() {
                          _values = RangeValues(
                            start.toDouble(),
                            end.toDouble(),
                          );
                          _invalid = false;
                          _writeFields();
                        });
                      },
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final start = _rangeTime(0);
                  final end = _rangeTime(_maxSeconds.toDouble());
                  final style = DefaultTextStyle.of(context).style;
                  final painter = TextPainter(
                    text: TextSpan(text: '$start  $end', style: style),
                    textDirection: Directionality.of(context),
                    textScaler: MediaQuery.textScalerOf(context),
                  )..layout();
                  final fits = painter.width <= constraints.maxWidth;
                  painter.dispose();
                  return fits
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [Text(start), Text(end)],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(start),
                            Text(end, textAlign: TextAlign.end),
                          ],
                        );
                },
              ),
              const SizedBox(height: 20),
              _timeFields(_start, l10n.bufferRangeStart, 'save.rangeStart'),
              const SizedBox(height: 20),
              _timeFields(_end, l10n.bufferRangeEnd, 'save.rangeEnd'),
              if (_invalid)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    l10n.bufferRangeInvalid,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('save.rangeApply'),
          onPressed: _apply,
          child: Text(l10n.ok),
        ),
      ],
    );
  }
}

class _RecordingTimeSummary extends StatelessWidget {
  const _RecordingTimeSummary({required this.snapshot});
  final MeterSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: const Color(0xFF6A7D73),
    );
    final numberStyle = theme.textTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: const Color(0xFF243E33),
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final totalStyle = theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w600,
      color: const Color(0xFF243E33),
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final current = _TimeBlock(
      label: l10n.currentRecordingDuration,
      value: _formatDurationMillis(snapshot.sessionRecordedMillis),
      labelStyle: labelStyle,
      valueStyle: numberStyle,
    );
    final total = _TimeBlock(
      label: l10n.totalRecordedDuration,
      value: _formatDurationMillis(snapshot.recordedMillis),
      labelStyle: labelStyle,
      valueStyle: totalStyle,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 280 ||
            MediaQuery.textScalerOf(context).scale(1) >= 1.5) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              current,
              const Divider(height: 28, color: Color(0xFFE0E7E3)),
              total,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(flex: 6, child: current),
            Container(
              width: 1,
              height: 44,
              margin: const EdgeInsets.symmetric(horizontal: 14),
              color: const Color(0xFFD7DFDC),
            ),
            Expanded(flex: 5, child: total),
          ],
        );
      },
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
        Text(label, style: labelStyle),
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
