part of '../main.dart';

class ScheduledTasksPage extends StatefulWidget {
  const ScheduledTasksPage({
    super.key,
    required this.snapshot,
    required this.busy,
    required this.onRefresh,
    required this.onUpsert,
    required this.onDelete,
    required this.onSetEnabled,
    required this.onRequestExactAlarm,
  });

  final ScheduleSnapshot? snapshot;
  final bool busy;
  final Future<void> Function() onRefresh;
  final Future<bool> Function(Map<String, Object?> task) onUpsert;
  final Future<bool> Function(ScheduledTaskModel task) onDelete;
  final Future<bool> Function(ScheduledTaskModel task, bool enabled)
  onSetEnabled;
  final Future<void> Function() onRequestExactAlarm;

  @override
  State<ScheduledTasksPage> createState() => _ScheduledTasksPageState();
}

class _ScheduledTasksPageState extends State<ScheduledTasksPage> {
  Timer? _displayTimer;
  int _refreshTicks = 0;

  @override
  void initState() {
    super.initState();
    _displayTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() {});
      _refreshTicks += 1;
      if (_refreshTicks >= 5 && !widget.busy) {
        _refreshTicks = 0;
        unawaited(widget.onRefresh());
      }
    });
  }

  @override
  void dispose() {
    _displayTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final snapshot = widget.snapshot;
    return ListView(
      key: const ValueKey('schedule.page'),
      children: [
        _PageHeading(
          title: l10n.scheduledTasksTitle,
          subtitle: snapshot == null
              ? null
              : l10n.scheduleTaskCount(snapshot.tasks.length),
          actions: [
            IconButton(
              tooltip: l10n.refresh,
              onPressed: widget.busy ? null : widget.onRefresh,
              icon: const Icon(Icons.refresh, size: 20),
            ),
            FilledButton.icon(
              onPressed: widget.busy ? null : () => _editTask(),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.newScheduledTask),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (widget.busy) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
        ],
        if (snapshot?.error?.isNotEmpty == true) ...[
          _ScheduleNotice(
            icon: Icons.error_outline,
            text: l10n.scheduleOperationFailed(snapshot!.error!),
            error: true,
          ),
          const SizedBox(height: 12),
        ],
        if (snapshot != null && _needsExactAlarmPermission(snapshot)) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: widget.busy ? null : widget.onRequestExactAlarm,
              icon: const Icon(Icons.alarm_add, size: 18),
              label: Text(l10n.requestExactAlarm),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (snapshot?.nextWakeup != null) ...[
          _buildNextTask(context, snapshot!),
          const SizedBox(height: 16),
        ],
        if (snapshot != null) ...[
          _Panel(
            key: const ValueKey('schedule.presets'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionHeading(
                  title: l10n.schedulePresetsTitle(snapshot.presets.length),
                  icon: Icons.bookmarks_outlined,
                ),
                const SizedBox(height: 12),
                if (snapshot.presets.isEmpty)
                  Text(
                    l10n.schedulePresetsHint,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF6A7D73),
                    ),
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) => Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final preset in snapshot.presets)
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: math.min(320, constraints.maxWidth),
                            ),
                            child: InputChip(
                              label: Text(
                                preset.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                              backgroundColor: const Color(0xFFF3F7F5),
                              side: const BorderSide(color: Color(0xFFDCE5DF)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              avatar: const Icon(
                                Icons.bookmark_outline,
                                size: 18,
                              ),
                              onPressed: widget.busy
                                  ? null
                                  : () => _editTask(null, preset),
                              deleteButtonTooltipMessage:
                                  l10n.deleteSchedulePreset,
                              onDeleted: widget.busy
                                  ? null
                                  : () => _deletePreset(preset),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (snapshot == null)
          _Panel(
            key: const ValueKey('schedule.loading'),
            child: _PageEmptyState(
              icon: Icons.hourglass_empty,
              title: l10n.loadingScheduledTasks,
            ),
          )
        else if (snapshot.tasks.isEmpty)
          _Panel(
            key: const ValueKey('schedule.empty'),
            child: _PageEmptyState(
              icon: Icons.alarm_off_outlined,
              title: l10n.noScheduledTasks,
              description: l10n.scheduleEmptyHint,
            ),
          )
        else
          for (final task in snapshot.tasks) ...[
            _buildTaskCard(context, task),
            const SizedBox(height: 12),
          ],
        if (snapshot != null) ...[
          SizedBox(height: snapshot.tasks.isEmpty ? 16 : 4),
          _buildHistory(context, snapshot),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  bool _needsExactAlarmPermission(ScheduleSnapshot snapshot) {
    return defaultTargetPlatform == TargetPlatform.android &&
        snapshot.schedulingPrecision == 'approximate' &&
        !snapshot.exactAlarmPermission;
  }

  Widget _buildNextTask(BuildContext context, ScheduleSnapshot snapshot) {
    final due = snapshot.nextWakeup;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3EF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const _SurfaceIcon(Icons.next_plan_outlined, active: true),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              due == null
                  ? context.l10n.noUpcomingTask
                  : context.l10n.nextScheduledTask(
                      _formatRemaining(due),
                      _formatScheduleDateTime(due),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(BuildContext context, ScheduledTaskModel task) {
    final l10n = context.l10n;
    return _Panel(
      key: ValueKey('schedule.task.${task.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  task.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF243E33),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: task.enabled,
                onChanged: widget.busy
                    ? null
                    : (enabled) =>
                          unawaited(widget.onSetEnabled(task, enabled)),
              ),
              PopupMenuButton<String>(
                enabled: !widget.busy,
                icon: const Icon(Icons.more_horiz, color: Color(0xFF7B8F83)),
                onSelected: (value) {
                  if (value == 'edit') {
                    _editTask(task);
                  } else if (value == 'delete') {
                    _deleteTask(task);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text(l10n.edit)),
                  PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            task.nextDue == null
                ? _schedulerStateLabel(context, task.state)
                : l10n.scheduleDue(
                    _formatRemaining(task.nextDue!),
                    _formatScheduleDateTime(task.nextDue!),
                  ),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF6A7D73)),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _taskTag(_triggerSummary(context, task.trigger)),
              for (final action in task.actions)
                _taskTag(_actionSummary(context, action)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _taskTag(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFFF0F5F2),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, color: Color(0xFF607B6B)),
    ),
  );

  Widget _buildHistory(BuildContext context, ScheduleSnapshot snapshot) {
    final l10n = context.l10n;
    final history = snapshot.history.take(20).toList();
    return _Panel(
      key: const ValueKey('schedule.history'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeading(title: l10n.scheduleHistory, icon: Icons.history),
          const SizedBox(height: 12),
          if (history.isEmpty)
            Text(
              l10n.noScheduleHistory,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFF718378)),
            )
          else
            for (final (index, execution) in history.indexed) ...[
              if (index > 0)
                const Divider(height: 24, color: Color(0xFFE0E7E3)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      _resultIcon(execution.result),
                      size: 20,
                      color: const Color(0xFF607B6B),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          execution.taskName,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF243E33),
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            _schedulerResultLabel(context, execution.result),
                            if (execution.scheduledFor != null)
                              l10n.schedulePlannedAt(
                                _formatScheduleDateTime(
                                  execution.scheduledFor!,
                                ),
                              ),
                            if (execution.startedAt != null)
                              l10n.scheduleStartedAt(
                                _formatScheduleDateTime(execution.startedAt!),
                              ),
                            if (execution.lateByMillis > 0)
                              l10n.scheduleLateBy(
                                _formatDurationLabel(
                                  l10n,
                                  (execution.lateByMillis / 1000).round(),
                                ),
                              ),
                          ].join(' · '),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFF6A7D73)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
        ],
      ),
    );
  }

  Future<void> _deletePreset(SchedulePresetModel preset) async {
    if (await _confirm(
      context,
      title: context.l10n.deleteSchedulePreset,
      message: context.l10n.confirmDeleteSchedulePreset(preset.name),
    )) {
      await widget.onUpsert({'operation': 'delete_preset', 'id': preset.id});
    }
  }

  Future<void> _editTask([
    ScheduledTaskModel? task,
    SchedulePresetModel? preset,
  ]) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (routeContext) => ScheduledTaskEditorPage(
          task: task,
          preset: preset,
          presetCount: widget.snapshot?.presets.length ?? 0,
          onSubmit: widget.onUpsert,
        ),
      ),
    );
  }

  Future<void> _deleteTask(ScheduledTaskModel task) async {
    final confirmed = await _confirm(
      context,
      title: context.l10n.deleteScheduledTask,
      message: context.l10n.confirmDeleteScheduledTask(task.name),
    );
    if (confirmed) {
      await widget.onDelete(task);
    }
  }
}

class _ScheduleNotice extends StatelessWidget {
  const _ScheduleNotice({
    required this.icon,
    required this.text,
    this.error = false,
  });

  final IconData icon;
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: error ? scheme.errorContainer : const Color(0xFFEAF3EF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

enum _ScheduleTriggerChoice { countdown, timePoint }

class ScheduledTaskEditorPage extends StatefulWidget {
  const ScheduledTaskEditorPage({
    super.key,
    this.task,
    this.preset,
    this.presetCount = 0,
    required this.onSubmit,
  });

  final ScheduledTaskModel? task;
  final SchedulePresetModel? preset;
  final int presetCount;
  final Future<bool> Function(Map<String, Object?> task) onSubmit;

  @override
  State<ScheduledTaskEditorPage> createState() =>
      ScheduledTaskEditorPageState();
}

class ScheduledTaskEditorPageState extends State<ScheduledTaskEditorPage> {
  static const List<int> _bitrateOptions = [64, 96, 128, 160, 192, 256, 320];

  late final TextEditingController _nameController;
  late final TextEditingController _saveSecondsController;
  _ScheduleTriggerChoice _trigger = _ScheduleTriggerChoice.countdown;
  DateTime _timePoint = DateTime.now().add(const Duration(hours: 1));
  int _countdownHours = 0;
  int _countdownMinutes = 10;
  int _countdownSeconds = 0;
  bool _recordingConfigured = false;
  bool _recordingEnabled = true;
  bool _uploadConfigured = false;
  bool _uploadEnabled = true;
  bool _saveRecent = false;
  bool _enabled = true;
  bool _allowPartial = true;
  String _format = 'mp3';
  int _bitrate = 128;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _nameController = TextEditingController(text: task?.name ?? '');
    _saveSecondsController = TextEditingController(text: '30');
    _timePoint = DateTime(
      _timePoint.year,
      _timePoint.month,
      _timePoint.day,
      _timePoint.hour,
      _timePoint.minute,
      _timePoint.second,
    );
    if (task != null) {
      _enabled = task.enabled;
      _loadTrigger(task.trigger);
      _loadActions(task.actions);
    } else if (widget.preset case final preset?) {
      _enabled = preset.enabled;
      _loadTrigger(preset.trigger);
      _loadActions(preset.actions);
    }
  }

  void _loadTrigger(Map<String, Object?> trigger) {
    if (trigger['type'] == 'time_point') {
      _trigger = _ScheduleTriggerChoice.timePoint;
      final millis = trigger['dueAtUtcMillis'];
      if (millis is num) {
        final parsed = DateTime.fromMillisecondsSinceEpoch(
          millis.toInt(),
          isUtc: true,
        ).toLocal();
        _timePoint = DateTime(
          parsed.year,
          parsed.month,
          parsed.day,
          parsed.hour,
          parsed.minute,
          parsed.second,
        );
      }
      return;
    }
    final delay = trigger['delayMillis'];
    final seconds = delay is num ? delay.toInt() ~/ 1000 : 600;
    final boundedSeconds = seconds.clamp(0, 86399);
    _countdownHours = boundedSeconds ~/ 3600;
    _countdownMinutes = (boundedSeconds % 3600) ~/ 60;
    _countdownSeconds = boundedSeconds % 60;
  }

  void _loadActions(List<Map<String, Object?>> actions) {
    for (final action in actions) {
      switch (action['type']) {
        case 'start_recording':
          _recordingConfigured = true;
          _recordingEnabled = true;
          break;
        case 'stop_recording':
          _recordingConfigured = true;
          _recordingEnabled = false;
          break;
        case 'set_upload_enabled':
          _uploadConfigured = true;
          _uploadEnabled = action['enabled'] == true;
          break;
        case 'save_recent':
          _saveRecent = true;
          _saveSecondsController.text =
              (action['seconds'] as num?)?.toInt().toString() ?? '30';
          _format = action['format']?.toString() == 'wav' ? 'wav' : 'mp3';
          _bitrate = (action['mp3BitrateKbps'] as num?)?.toInt() ?? 128;
          _allowPartial = action['allowPartial'] != false;
          break;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _saveSecondsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        key: const ValueKey<String>('schedule.editor.page'),
        appBar: AppBar(
          leading: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(
            widget.task == null
                ? l10n.newScheduledTask
                : l10n.editScheduledTask,
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                children: [
                  _EditorSection(
                    title: l10n.scheduleTaskSettings,
                    icon: Icons.tune,
                    child: Column(
                      children: [
                        TextField(
                          controller: _nameController,
                          autofocus: widget.task == null,
                          decoration: InputDecoration(
                            labelText: l10n.scheduleName,
                            hintText: l10n.scheduleNameAutomatic,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l10n.scheduleEnabled),
                          value: _enabled,
                          onChanged: _saving
                              ? null
                              : (value) => setState(() => _enabled = value),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _EditorSection(
                    title: l10n.scheduleRunTime,
                    icon: Icons.schedule,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SegmentedButton<_ScheduleTriggerChoice>(
                          segments: [
                            ButtonSegment(
                              value: _ScheduleTriggerChoice.countdown,
                              icon: const Icon(Icons.timer_outlined),
                              label: Text(l10n.scheduleCountdown),
                            ),
                            ButtonSegment(
                              value: _ScheduleTriggerChoice.timePoint,
                              icon: const Icon(Icons.event_outlined),
                              label: Text(l10n.scheduleTimePoint),
                            ),
                          ],
                          selected: {_trigger},
                          onSelectionChanged: _saving
                              ? null
                              : (values) =>
                                    setState(() => _trigger = values.first),
                        ),
                        const SizedBox(height: 20),
                        if (_trigger == _ScheduleTriggerChoice.countdown)
                          _TimeWheelPicker(
                            keyPrefix: 'schedule.countdown',
                            hours: _countdownHours,
                            minutes: _countdownMinutes,
                            seconds: _countdownSeconds,
                            enabled: !_saving,
                            onHoursChanged: (value) =>
                                setState(() => _countdownHours = value),
                            onMinutesChanged: (value) =>
                                setState(() => _countdownMinutes = value),
                            onSecondsChanged: (value) =>
                                setState(() => _countdownSeconds = value),
                          )
                        else ...[
                          OutlinedButton.icon(
                            key: const ValueKey<String>(
                              'schedule.timePoint.date',
                            ),
                            onPressed: _saving ? null : _chooseTimePointDate,
                            icon: const Icon(Icons.calendar_month),
                            label: Text(
                              l10n.scheduleChooseDate(
                                _formatScheduleDate(_timePoint),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _TimeWheelPicker(
                            keyPrefix: 'schedule.timePoint',
                            hours: _timePoint.hour,
                            minutes: _timePoint.minute,
                            seconds: _timePoint.second,
                            enabled: !_saving,
                            onHoursChanged: (value) =>
                                _updateTimePoint(hour: value),
                            onMinutesChanged: (value) =>
                                _updateTimePoint(minute: value),
                            onSecondsChanged: (value) =>
                                _updateTimePoint(second: value),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _EditorSection(
                    title: l10n.scheduleActionsAtRun,
                    icon: Icons.playlist_add_check,
                    child: Column(
                      children: [
                        _BinaryScheduleActionCard(
                          key: const ValueKey<String>(
                            'schedule.action.recording',
                          ),
                          icon: Icons.mic_outlined,
                          title: l10n.scheduleRecordingAction,
                          configured: _recordingConfigured,
                          targetEnabled: _recordingEnabled,
                          enabledLabel: l10n.scheduleStartRecording,
                          disabledLabel: l10n.scheduleStopRecording,
                          enabled: !_saving,
                          onConfiguredChanged: (value) =>
                              setState(() => _recordingConfigured = value),
                          onTargetChanged: (value) =>
                              setState(() => _recordingEnabled = value),
                        ),
                        const SizedBox(height: 12),
                        _BinaryScheduleActionCard(
                          key: const ValueKey<String>('schedule.action.upload'),
                          icon: Icons.cloud_upload_outlined,
                          title: l10n.scheduleUploadAction,
                          configured: _uploadConfigured,
                          targetEnabled: _uploadEnabled,
                          enabledLabel: l10n.scheduleEnableUpload,
                          disabledLabel: l10n.scheduleDisableUpload,
                          enabled: !_saving,
                          onConfiguredChanged: (value) =>
                              setState(() => _uploadConfigured = value),
                          onTargetChanged: (value) =>
                              setState(() => _uploadEnabled = value),
                        ),
                        const SizedBox(height: 12),
                        _EditorActionSurface(
                          key: const ValueKey<String>(
                            'schedule.action.saveRecent',
                          ),
                          child: Column(
                            children: [
                              SwitchListTile(
                                secondary: const Icon(Icons.save_alt_outlined),
                                contentPadding: EdgeInsets.zero,
                                title: Text(l10n.scheduleSaveRecent),
                                value: _saveRecent,
                                onChanged: _saving
                                    ? null
                                    : (value) =>
                                          setState(() => _saveRecent = value),
                              ),
                              ...[
                                const SizedBox(height: 8),
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final durationField = TextField(
                                      controller: _saveSecondsController,
                                      enabled: !_saving && _saveRecent,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                      decoration: InputDecoration(
                                        labelText: l10n.scheduleSaveSeconds,
                                        border: const OutlineInputBorder(),
                                      ),
                                    );
                                    final formatField =
                                        DropdownButtonFormField<String>(
                                          isExpanded: true,
                                          initialValue: _format,
                                          decoration: InputDecoration(
                                            labelText: l10n.outputFormat,
                                            border: const OutlineInputBorder(),
                                          ),
                                          items: const [
                                            DropdownMenuItem(
                                              value: 'mp3',
                                              child: Text('MP3'),
                                            ),
                                            DropdownMenuItem(
                                              value: 'wav',
                                              child: Text('WAV'),
                                            ),
                                          ],
                                          onChanged: _saving || !_saveRecent
                                              ? null
                                              : (value) => setState(
                                                  () => _format =
                                                      value ?? _format,
                                                ),
                                        );
                                    if (constraints.maxWidth < 560) {
                                      return Column(
                                        children: [
                                          durationField,
                                          const SizedBox(height: 12),
                                          formatField,
                                        ],
                                      );
                                    }
                                    return Row(
                                      children: [
                                        Expanded(child: durationField),
                                        const SizedBox(width: 12),
                                        Expanded(child: formatField),
                                      ],
                                    );
                                  },
                                ),
                                if (_format == 'mp3') ...[
                                  const SizedBox(height: 12),
                                  DropdownButtonFormField<int>(
                                    isExpanded: true,
                                    initialValue: _bitrate,
                                    decoration: InputDecoration(
                                      labelText: l10n.mp3Bitrate,
                                      border: const OutlineInputBorder(),
                                    ),
                                    items: [
                                      for (final bitrate in _bitrateOptions)
                                        DropdownMenuItem(
                                          value: bitrate,
                                          child: Text('$bitrate kbps'),
                                        ),
                                    ],
                                    onChanged: _saving || !_saveRecent
                                        ? null
                                        : (value) => setState(
                                            () => _bitrate = value ?? _bitrate,
                                          ),
                                  ),
                                ],
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(l10n.scheduleAllowPartial),
                                  value: _allowPartial,
                                  onChanged: _saving || !_saveRecent
                                      ? null
                                      : (value) => setState(
                                          () => _allowPartial = value ?? true,
                                        ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    _ScheduleNotice(
                      icon: Icons.error_outline,
                      text: _error!,
                      error: true,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: Text(l10n.cancel),
                ),
                Tooltip(
                  message: widget.presetCount >= 9
                      ? l10n.schedulePresetLimit
                      : l10n.saveSchedulePreset,
                  child: OutlinedButton.icon(
                    key: const ValueKey('schedule.savePreset'),
                    onPressed: _saving || widget.presetCount >= 9
                        ? null
                        : () => _submit(asPreset: true),
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: Text(l10n.saveSchedulePreset),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(l10n.saveScheduledTask),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _chooseTimePointDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _timePoint.isBefore(now) ? now : _timePoint,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) {
      return;
    }
    setState(() {
      _timePoint = DateTime(
        date.year,
        date.month,
        date.day,
        _timePoint.hour,
        _timePoint.minute,
        _timePoint.second,
      );
    });
  }

  void _updateTimePoint({int? hour, int? minute, int? second}) {
    setState(() {
      _timePoint = DateTime(
        _timePoint.year,
        _timePoint.month,
        _timePoint.day,
        hour ?? _timePoint.hour,
        minute ?? _timePoint.minute,
        second ?? _timePoint.second,
      );
    });
  }

  Future<void> _submit({bool asPreset = false}) async {
    final name = _nameController.text.trim();
    final actions = <Map<String, Object?>>[];
    if (_uploadConfigured) {
      actions.add({'type': 'set_upload_enabled', 'enabled': _uploadEnabled});
    }
    if (_recordingConfigured) {
      actions.add({
        'type': _recordingEnabled ? 'start_recording' : 'stop_recording',
      });
    }
    final saveSeconds = int.tryParse(_saveSecondsController.text) ?? 0;
    if (_saveRecent) {
      actions.add({
        'type': 'save_recent',
        'seconds': saveSeconds,
        'format': _format,
        'mp3BitrateKbps': _bitrate,
        'allowPartial': _allowPartial,
      });
    }
    final trigger = _buildTrigger();
    final error = _validate(trigger, actions, saveSeconds, asPreset: asPreset);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final task = <String, Object?>{
      if (!asPreset && widget.task != null) 'id': widget.task!.id,
      if (!asPreset && widget.task != null)
        'expectedRevision': widget.task!.revision,
      'name': name,
      'namePrefix': asPreset
          ? context.l10n.schedulePresetNamePrefix
          : context.l10n.scheduleTaskNamePrefix,
      'enabled': _enabled,
      'trigger': trigger,
      'actions': actions,
    };
    setState(() {
      _saving = true;
      _error = null;
    });
    final ok = await widget.onSubmit(
      asPreset ? {'operation': 'save_preset', 'task': task} : task,
    );
    if (!mounted) {
      return;
    }
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _error = context.l10n.scheduleSaveFailed;
      });
    }
  }

  Map<String, Object?> _buildTrigger() {
    if (_trigger == _ScheduleTriggerChoice.timePoint) {
      return {
        'type': 'time_point',
        'dueAtUtcMillis': _timePoint.toUtc().millisecondsSinceEpoch,
        'localDatetime': _timePoint.toIso8601String(),
        'timezoneId': _timePoint.timeZoneName,
        'utcOffsetMinutes': _timePoint.timeZoneOffset.inMinutes,
      };
    }
    return {
      'type': 'countdown',
      'delayMillis':
          (_countdownHours * 3600 +
              _countdownMinutes * 60 +
              _countdownSeconds) *
          1000,
    };
  }

  String? _validate(
    Map<String, Object?> trigger,
    List<Map<String, Object?>> actions,
    int saveSeconds, {
    bool asPreset = false,
  }) {
    final l10n = context.l10n;
    if (actions.isEmpty) {
      return l10n.scheduleActionRequired;
    }
    if (trigger['type'] == 'countdown' &&
        (trigger['delayMillis'] as int) <= 0) {
      return l10n.scheduleCountdownRequired;
    }
    if (!asPreset &&
        trigger['type'] == 'time_point' &&
        !_timePoint.isAfter(DateTime.now())) {
      return l10n.scheduleTimePointPast;
    }
    if (_saveRecent && (saveSeconds < 1 || saveSeconds > 86400)) {
      return l10n.scheduleSaveDurationInvalid;
    }
    return null;
  }
}

class _EditorSection extends StatelessWidget {
  const _EditorSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFE0E7E3)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

class _EditorActionSurface extends StatelessWidget {
  const _EditorActionSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF3F7F5),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFE0E7E3)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: child,
        ),
      ),
    );
  }
}

class _BinaryScheduleActionCard extends StatelessWidget {
  const _BinaryScheduleActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.configured,
    required this.targetEnabled,
    required this.enabledLabel,
    required this.disabledLabel,
    required this.enabled,
    required this.onConfiguredChanged,
    required this.onTargetChanged,
  });

  final IconData icon;
  final String title;
  final bool configured;
  final bool targetEnabled;
  final String enabledLabel;
  final String disabledLabel;
  final bool enabled;
  final ValueChanged<bool> onConfiguredChanged;
  final ValueChanged<bool> onTargetChanged;

  @override
  Widget build(BuildContext context) {
    return _EditorActionSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            secondary: Icon(icon),
            contentPadding: EdgeInsets.zero,
            title: Text(title),
            value: configured,
            onChanged: enabled ? onConfiguredChanged : null,
          ),
          ...[
            const SizedBox(height: 4),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment<bool>(value: true, label: Text(enabledLabel)),
                ButtonSegment<bool>(value: false, label: Text(disabledLabel)),
              ],
              selected: {targetEnabled},
              onSelectionChanged: enabled && configured
                  ? (values) => onTargetChanged(values.first)
                  : null,
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _TimeWheelPicker extends StatelessWidget {
  const _TimeWheelPicker({
    required this.keyPrefix,
    required this.hours,
    required this.minutes,
    required this.seconds,
    required this.enabled,
    required this.onHoursChanged,
    required this.onMinutesChanged,
    required this.onSecondsChanged,
  });

  final String keyPrefix;
  final int hours;
  final int minutes;
  final int seconds;
  final bool enabled;
  final ValueChanged<int> onHoursChanged;
  final ValueChanged<int> onMinutesChanged;
  final ValueChanged<int> onSecondsChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey<String>('$keyPrefix.wheels'),
      height: 196,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withAlpha(105),
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (final label in [
                l10n.scheduleHours,
                l10n.scheduleMinutes,
                l10n.scheduleSeconds,
              ]) ...[
                if (label != l10n.scheduleHours) const SizedBox(width: 20),
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _TimeWheelColumn(
                    key: ValueKey<String>('$keyPrefix.hours'),
                    value: hours,
                    maxValue: 23,
                    label: l10n.scheduleHours,
                    enabled: enabled,
                    onChanged: onHoursChanged,
                  ),
                ),
                _wheelDivider(context),
                Expanded(
                  child: _TimeWheelColumn(
                    key: ValueKey<String>('$keyPrefix.minutes'),
                    value: minutes,
                    maxValue: 59,
                    label: l10n.scheduleMinutes,
                    enabled: enabled,
                    onChanged: onMinutesChanged,
                  ),
                ),
                _wheelDivider(context),
                Expanded(
                  child: _TimeWheelColumn(
                    key: ValueKey<String>('$keyPrefix.seconds'),
                    value: seconds,
                    maxValue: 59,
                    label: l10n.scheduleSeconds,
                    enabled: enabled,
                    onChanged: onSecondsChanged,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _wheelDivider(BuildContext context) {
    return SizedBox(
      width: 20,
      child: Center(
        child: Text(
          ':',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _TimeWheelColumn extends StatefulWidget {
  const _TimeWheelColumn({
    super.key,
    required this.value,
    required this.maxValue,
    required this.label,
    required this.enabled,
    required this.onChanged,
  });

  final int value;
  final int maxValue;
  final String label;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  State<_TimeWheelColumn> createState() => _TimeWheelColumnState();
}

class _TimeWheelColumnState extends State<_TimeWheelColumn> {
  late final FixedExtentScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FixedExtentScrollController(initialItem: widget.value);
  }

  @override
  void didUpdateWidget(covariant _TimeWheelColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        _controller.hasClients &&
        _controller.selectedItem != widget.value) {
      _controller.jumpToItem(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: widget.label,
      child: Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withAlpha(135),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          ListWheelScrollView.useDelegate(
            controller: _controller,
            scrollBehavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                ...ScrollConfiguration.of(context).dragDevices,
                PointerDeviceKind.mouse,
              },
            ),
            itemExtent: 44,
            diameterRatio: 1.65,
            physics: widget.enabled
                ? const FixedExtentScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            useMagnifier: true,
            magnification: 1.08,
            overAndUnderCenterOpacity: 0.42,
            onSelectedItemChanged: widget.enabled ? widget.onChanged : null,
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: widget.maxValue + 1,
              builder: (context, index) {
                if (index < 0 || index > widget.maxValue) {
                  return null;
                }
                return Center(
                  child: Text(
                    index.toString().padLeft(2, '0'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: index == widget.value
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

String _formatScheduleDate(DateTime time) {
  final local = time.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

String _formatScheduleDateTime(DateTime time) {
  final local = time.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
}

String _formatRemaining(DateTime due) {
  final remaining = due.difference(DateTime.now());
  if (remaining.isNegative) {
    return '00:00:00';
  }
  final seconds = remaining.inSeconds;
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final tail = seconds % 60;
  return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${tail.toString().padLeft(2, '0')}';
}

String _triggerSummary(BuildContext context, Map<String, Object?> trigger) {
  if (trigger['type'] == 'time_point') {
    return context.l10n.scheduleTimePoint;
  }
  final delay = trigger['delayMillis'];
  final seconds = delay is num ? (delay.toInt() / 1000).round() : 0;
  return context.l10n.scheduleCountdownWithDuration(
    _formatDurationLabel(context.l10n, seconds),
  );
}

String _actionSummary(BuildContext context, Map<String, Object?> action) {
  return switch (action['type']) {
    'start_recording' => context.l10n.scheduleStartRecording,
    'stop_recording' => context.l10n.scheduleStopRecording,
    'set_upload_enabled' =>
      action['enabled'] == true
          ? context.l10n.scheduleEnableUpload
          : context.l10n.scheduleDisableUpload,
    'save_recent' => context.l10n.scheduleSaveActionSummary(
      (action['format'] ?? 'wav').toString().toUpperCase(),
      (action['seconds'] ?? 0).toString(),
    ),
    _ => action['type']?.toString() ?? '',
  };
}

String _schedulerStateLabel(BuildContext context, String state) {
  final zh = Localizations.localeOf(context).languageCode == 'zh';
  return switch (state) {
    'armed' => zh ? '等待执行' : 'Armed',
    'running' => zh ? '执行中' : 'Running',
    'succeeded' => zh ? '已完成' : 'Succeeded',
    'partially_succeeded' => zh ? '部分成功' : 'Partially succeeded',
    'failed' => zh ? '失败' : 'Failed',
    'missed' => zh ? '已错过' : 'Missed',
    'disabled' => zh ? '已停用' : 'Disabled',
    'canceled' => zh ? '已取消' : 'Canceled',
    _ => state,
  };
}

String _schedulerResultLabel(BuildContext context, String result) {
  if (result == 'interrupted') {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return zh ? '已中断' : 'Interrupted';
  }
  return _schedulerStateLabel(context, result);
}

IconData _resultIcon(String result) {
  return switch (result) {
    'succeeded' => Icons.check_circle_outline,
    'partially_succeeded' => Icons.warning_amber_outlined,
    'missed' => Icons.schedule_outlined,
    'running' => Icons.hourglass_top,
    _ => Icons.error_outline,
  };
}
