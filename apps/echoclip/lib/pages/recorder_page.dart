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
    this.headerActions = const [],
    this.saveProgress = const ClipSaveProgress(),
    this.saveOutcome,
    this.saveErrorDetail,
  });

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
    final custom = await showDialog<int>(
      context: context,
      builder: (_) => _SaveDurationDialog(seconds: _customDurationSeconds),
    );
    if (!mounted || custom == null) return;
    setState(() {
      _customDurationSeconds = custom;
      _durationMode = SaveDurationMode.custom;
    });
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
              child: PopupMenuButton<int>(
                key: const ValueKey('save.duration'),
                enabled: !saving.busy,
                tooltip: l10n.chooseSaveDuration,
                position: PopupMenuPosition.under,
                onSelected: _chooseSaveDuration,
                itemBuilder: (_) => [
                  CheckedPopupMenuItem(
                    value: -1,
                    checked: _durationMode == SaveDurationMode.custom,
                    child: Text(l10n.customSaveDuration),
                  ),
                  const PopupMenuDivider(),
                  for (final option in _durations)
                    CheckedPopupMenuItem(
                      value: option.seconds,
                      checked:
                          _durationMode == SaveDurationMode.preset &&
                          option == _selectedDuration,
                      child: Text(_formatDurationLabel(l10n, option.seconds)),
                    ),
                ],
                child: Ink(
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
                          _formatDurationLabel(l10n, _activeSaveSeconds),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.keyboard_arrow_down, size: 20),
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
                      ? (saving.cancellable && !saving.canceling
                            ? () => widget.onSave(_activeSaveSeconds)
                            : null)
                      : widget.folderSelected && snapshot.recordedMillis > 0
                      ? () => widget.onSave(_activeSaveSeconds)
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
      ClipSaveOutcome.failed => l10n.saveFailedStatus,
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
    final description = errorDetail == null
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

class _SaveDurationDialog extends StatefulWidget {
  const _SaveDurationDialog({required this.seconds});
  final int seconds;
  @override
  State<_SaveDurationDialog> createState() => _SaveDurationDialogState();
}

class _SaveDurationDialogState extends State<_SaveDurationDialog> {
  final _form = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: '${widget.seconds}');
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply() {
    if (_form.currentState!.validate()) {
      Navigator.of(context).pop(int.parse(_controller.text));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.l10n.customSaveDuration),
    content: Form(
      key: _form,
      child: TextFormField(
        key: const ValueKey('save.customSeconds'),
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onFieldSubmitted: (_) => _apply(),
        validator: (value) {
          final seconds = int.tryParse(value ?? '');
          return seconds == null || seconds < 1 || seconds > 86400
              ? context.l10n.customSaveSecondsHelper
              : null;
        },
        decoration: InputDecoration(
          labelText: context.l10n.customSaveSeconds,
          helperText: context.l10n.customSaveSecondsHelper,
          border: const OutlineInputBorder(),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(context.l10n.cancel),
      ),
      FilledButton(onPressed: _apply, child: Text(context.l10n.ok)),
    ],
  );
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
