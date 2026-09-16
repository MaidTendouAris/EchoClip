part of '../main.dart';

class _BufferMinutesField extends StatefulWidget {
  const _BufferMinutesField({
    required this.bufferSeconds,
    required this.onChanged,
  });

  final int bufferSeconds;
  final ValueChanged<int> onChanged;

  @override
  State<_BufferMinutesField> createState() => _BufferMinutesFieldState();
}

class _BufferMinutesFieldState extends State<_BufferMinutesField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  int get _minutes => (widget.bufferSeconds / 60).round().clamp(5, 1440);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _minutes.toString());
    _focusNode = FocusNode()..addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant _BufferMinutesField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bufferSeconds != widget.bufferSeconds &&
        !_focusNode.hasFocus) {
      _controller.text = _minutes.toString();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) {
      _applyValue();
    }
  }

  void _applyValue() {
    final parsed = int.tryParse(_controller.text.trim()) ?? _minutes;
    final minutes = parsed.clamp(5, 1440).toInt();
    _controller.text = minutes.toString();
    if (minutes != _minutes) {
      widget.onChanged(minutes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onSubmitted: (_) => _applyValue(),
      decoration: InputDecoration(
        labelText: l10n.bufferDurationMinutes,
        helperText: l10n.bufferDurationHelper,
        suffixText: l10n.minutesUnit,
        prefixIcon: const Icon(Icons.schedule),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.folderUri,
    required this.sampleRate,
    required this.bufferSeconds,
    required this.audioInputDevices,
    required this.microphoneEnabled,
    required this.systemAudioEnabled,
    required this.microphoneDeviceId,
    required this.systemAudioSupported,
    required this.inputDeviceSelectionSupported,
    required this.audioSourceSettingsBusy,
    required this.cacheBytes,
    required this.lockRecordingTrigger,
    required this.languageMode,
    required this.onChooseFolder,
    required this.onUpdateAudioSettings,
    required this.onUpdateAudioSourceSettings,
    required this.onRefreshAudioInputDevices,
    required this.onOpenServerSettings,
    required this.onLockRecordingTriggerChanged,
    required this.onClearCache,
    required this.onLanguageModeChanged,
    required this.onOpenUrl,
    this.onOpenStartupTasks,
    this.exportFormat = "mp3",
    this.onExportFormatChanged,
  });

  static const List<int> _sampleRateOptions = [
    8000,
    16000,
    24000,
    44100,
    48000,
  ];
  static const String _systemDefaultDeviceValue =
      '__echoclip_system_default_input__';
  static const String _repositoryUrl =
      'https://github.com/MaidTendouAris/EchoClip';
  static const String _issuesUrl =
      'https://github.com/MaidTendouAris/EchoClip/issues';

  final Future<void> Function()? onOpenStartupTasks;
  final String? folderUri;
  final String exportFormat;
  final Future<void> Function(String)? onExportFormatChanged;
  final int sampleRate;
  final int bufferSeconds;
  final List<AudioInputDevice> audioInputDevices;
  final bool microphoneEnabled;
  final bool systemAudioEnabled;
  final String? microphoneDeviceId;
  final bool systemAudioSupported;
  final bool inputDeviceSelectionSupported;
  final bool audioSourceSettingsBusy;
  final int cacheBytes;
  final LockRecordingTrigger lockRecordingTrigger;
  final UiLanguageMode languageMode;
  final Future<void> Function() onChooseFolder;
  final Future<void> Function({int? sampleRate, int? bufferSeconds})
  onUpdateAudioSettings;
  final Future<void> Function({
    required bool microphoneEnabled,
    required bool systemAudioEnabled,
    String? microphoneDeviceId,
  })
  onUpdateAudioSourceSettings;
  final Future<void> Function() onRefreshAudioInputDevices;
  final Future<void> Function() onOpenServerSettings;
  final Future<void> Function(LockRecordingTrigger trigger)
  onLockRecordingTriggerChanged;
  final Future<Map<String, Object?>> Function() onClearCache;
  final Future<void> Function(UiLanguageMode mode) onLanguageModeChanged;
  final Future<void> Function(String url) onOpenUrl;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final estimatedPcmBytes = sampleRate * bufferSeconds * 2;
    final knownDeviceIds = audioInputDevices.map((device) => device.id).toSet();
    final unavailableDeviceId =
        microphoneDeviceId != null &&
            !knownDeviceIds.contains(microphoneDeviceId)
        ? microphoneDeviceId
        : null;
    final selectedDeviceValue = microphoneDeviceId ?? _systemDefaultDeviceValue;
    final selectedDeviceId = selectedDeviceValue == _systemDefaultDeviceValue
        ? null
        : selectedDeviceValue;

    final folder = _Panel(
      key: const ValueKey('settings.folderCard'),
      child: _SettingsRow(
        icon: Icons.folder_open,
        title: l10n.recordingFolder,
        subtitle: _folderLabel(l10n),
        tooltip: folderUri,
        trailing: OutlinedButton(
          key: const ValueKey('settings.chooseFolder'),
          onPressed: onChooseFolder,
          child: Text(l10n.change),
        ),
      ),
    );
    final startup = _StartupSettingsCard(onOpenTasks: onOpenStartupTasks);
    final language = _SettingsSection(
      title: l10n.languageSettings,
      icon: Icons.language,
      children: [
        AppDropdownField<UiLanguageMode>(
          isExpanded: true,
          key: ValueKey(languageMode),
          initialValue: languageMode,
          decoration: InputDecoration(
            labelText: l10n.appLanguage,
            prefixIcon: const Icon(Icons.language),
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
          items: [
            for (final mode in UiLanguageMode.values)
              DropdownMenuItem(
                value: mode,
                child: Text(
                  _languageModeLabel(l10n, mode),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) {
            if (value == null) {
              return;
            }
            onLanguageModeChanged(value);
          },
        ),
      ],
    );
    final sources = _SettingsSection(
      key: const ValueKey('settings.sourcesCard'),
      title: l10n.audioSources,
      icon: Icons.mic_none,
      children: [
        Text(
          l10n.audioSourcesDescription,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          key: const ValueKey('settings.microphone'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: microphoneEnabled,
          title: Text(l10n.recordMicrophone),
          subtitle: Text(l10n.recordMicrophoneDescription),
          onChanged: audioSourceSettingsBusy
              ? null
              : (value) {
                  if (value == null) {
                    return;
                  }
                  if (!value && !systemAudioEnabled) {
                    _showAudioSourceRequired(context);
                    return;
                  }
                  onUpdateAudioSourceSettings(
                    microphoneEnabled: value,
                    systemAudioEnabled: systemAudioEnabled,
                    microphoneDeviceId: selectedDeviceId,
                  );
                },
        ),
        _SourceVolumeControl(source: 'microphone', enabled: microphoneEnabled),
        CheckboxListTile(
          key: const ValueKey('settings.systemAudio'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: systemAudioEnabled,
          title: Text(l10n.recordSystemAudio),
          subtitle: Text(
            systemAudioSupported
                ? l10n.recordSystemAudioDescription
                : l10n.systemAudioUnavailable,
          ),
          onChanged: audioSourceSettingsBusy || !systemAudioSupported
              ? null
              : (value) {
                  if (value == null) {
                    return;
                  }
                  if (!value && !microphoneEnabled) {
                    _showAudioSourceRequired(context);
                    return;
                  }
                  onUpdateAudioSourceSettings(
                    microphoneEnabled: microphoneEnabled,
                    systemAudioEnabled: value,
                    microphoneDeviceId: selectedDeviceId,
                  );
                },
        ),
        _SourceVolumeControl(
          source: 'system',
          enabled: systemAudioSupported && systemAudioEnabled,
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              key: const ValueKey('settings.inputDevice'),
              child: AppDropdownField<String>(
                key: ValueKey((
                  selectedDeviceValue,
                  Object.hashAll(knownDeviceIds),
                )),
                isExpanded: true,
                initialValue: selectedDeviceValue,
                decoration: InputDecoration(
                  labelText: l10n.inputDevice,
                  helperText: !inputDeviceSelectionSupported
                      ? l10n.inputDeviceManagedBySystem
                      : audioInputDevices.isEmpty
                      ? l10n.noInputDevices
                      : null,
                  prefixIcon: const Icon(Icons.settings_input_component),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                ),
                items: [
                  DropdownMenuItem(
                    value: _systemDefaultDeviceValue,
                    child: Text(
                      l10n.systemDefaultInputDevice,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (unavailableDeviceId != null)
                    DropdownMenuItem(
                      value: unavailableDeviceId,
                      child: Text(
                        l10n.unavailableInputDevice,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  for (final device in audioInputDevices)
                    DropdownMenuItem(
                      value: device.id,
                      child: Text(
                        device.isDefault
                            ? l10n.defaultInputDevice(device.name)
                            : device.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged:
                    audioSourceSettingsBusy ||
                        !inputDeviceSelectionSupported ||
                        !microphoneEnabled
                    ? null
                    : (value) {
                        if (value == null) {
                          return;
                        }
                        onUpdateAudioSourceSettings(
                          microphoneEnabled: microphoneEnabled,
                          systemAudioEnabled: systemAudioEnabled,
                          microphoneDeviceId: value == _systemDefaultDeviceValue
                              ? null
                              : value,
                        );
                      },
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              key: const ValueKey('settings.refreshInputDevices'),
              tooltip: l10n.refreshInputDevices,
              onPressed:
                  audioSourceSettingsBusy ||
                      !inputDeviceSelectionSupported ||
                      !microphoneEnabled
                  ? null
                  : onRefreshAudioInputDevices,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ],
    );
    final quality = _SettingsSection(
      title: l10n.recordingSettings,
      icon: Icons.tune,
      children: [
        AppDropdownField<int>(
          isExpanded: true,
          initialValue: sampleRate,
          decoration: InputDecoration(
            labelText: l10n.sampleRate,
            prefixIcon: const Icon(Icons.graphic_eq),
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
          items: [
            for (final value in _sampleRateOptions)
              DropdownMenuItem(value: value, child: Text(_formatHertz(value))),
          ],
          onChanged: (value) {
            if (value == null) {
              return;
            }
            onUpdateAudioSettings(sampleRate: value);
          },
        ),
        const SizedBox(height: 14),
        _BufferMinutesField(
          bufferSeconds: bufferSeconds,
          onChanged: (minutes) {
            onUpdateAudioSettings(bufferSeconds: minutes * 60);
          },
        ),
        const SizedBox(height: 14),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.memory),
          title: Text(l10n.estimatedPcmBuffer(_formatBytes(estimatedPcmBytes))),
          subtitle: Text(l10n.pcmBufferSubtitle(_formatHertz(sampleRate))),
        ),
      ],
    );
    final export = _SettingsSection(
      title: l10n.saveFormat,
      icon: Icons.audio_file_outlined,
      children: [
        AppDropdownField<String>(
          key: const ValueKey('settings.exportFormat'),
          initialValue: exportFormat,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: l10n.outputFormat,
            prefixIcon: const Icon(Icons.save_alt),
            border: const OutlineInputBorder(),
          ),
          items: [
            for (final format in recordingExportFormats)
              DropdownMenuItem(
                value: format,
                child: Text(format.toUpperCase()),
              ),
          ],
          onChanged: onExportFormatChanged == null
              ? null
              : (value) {
                  if (value != null) onExportFormatChanged!(value);
                },
        ),
        const SizedBox(height: 12),
        Text(exportFormat == 'wav' ? l10n.wavSaveLimit : l10n.saveFormatHelp),
      ],
    );
    final lock = _SettingsSection(
      title: l10n.lockRecordingSettings,
      icon: Icons.screen_lock_portrait,
      children: [
        AppDropdownField<LockRecordingTrigger>(
          isExpanded: true,
          initialValue: lockRecordingTrigger,
          decoration: InputDecoration(
            labelText: l10n.lockRecordingTrigger,
            prefixIcon: const Icon(Icons.screen_lock_portrait),
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
          items: [
            DropdownMenuItem(
              value: LockRecordingTrigger.screenOff,
              child: Text(
                l10n.lockRecordingTriggerScreenOff,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DropdownMenuItem(
              value: LockRecordingTrigger.keyguardLocked,
              child: Text(
                l10n.lockRecordingTriggerKeyguard,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          onChanged: (value) {
            if (value == null) {
              return;
            }
            onLockRecordingTriggerChanged(value);
          },
        ),
      ],
    );
    final server = _Panel(
      child: _SettingsRow(
        key: const ValueKey('settings.serverSync'),
        icon: Icons.cloud_sync_outlined,
        title: l10n.serverSettings,
        subtitle: l10n.serverSettingsDescription,
        onTap: onOpenServerSettings,
        trailing: const Icon(Icons.chevron_right, size: 20),
      ),
    );
    final cache = _SettingsSection(
      title: l10n.cacheTitle,
      icon: Icons.storage_outlined,
      children: [
        Text(
          l10n.currentCacheSize(_formatBytes(cacheBytes)),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: const Color(0xFF243E33)),
        ),
        const SizedBox(height: 16),
        _SettingsRow(
          icon: Icons.cleaning_services_outlined,
          title: l10n.clearCache,
          subtitle: l10n.clearCacheSubtitle,
          trailing: IconButton.filledTonal(
            key: const ValueKey('settings.clearCache'),
            tooltip: l10n.clearCache,
            onPressed: () => _confirmClearCache(context),
            icon: const Icon(Icons.delete_sweep_outlined, size: 20),
          ),
        ),
      ],
    );
    final about = _SettingsSection(
      title: l10n.aboutProject,
      icon: Icons.info_outline,
      children: [
        _SettingsRow(
          icon: Icons.code,
          title: l10n.githubRepository,
          subtitle: l10n.githubRepositorySubtitle,
          onTap: () => onOpenUrl(_repositoryUrl),
          trailing: const Icon(Icons.open_in_new, size: 18),
        ),
        const SizedBox(height: 16),
        _SettingsRow(
          icon: Icons.balance,
          title: l10n.licenseTitle,
          subtitle: l10n.licenseSubtitle,
          onTap: () => onOpenUrl('$_repositoryUrl/blob/main/LICENSE'),
          trailing: const Icon(Icons.chevron_right, size: 20),
        ),
        const SizedBox(height: 16),
        _SettingsRow(
          icon: Icons.bug_report_outlined,
          title: l10n.issueFeedback,
          subtitle: l10n.issueFeedbackSubtitle,
          onTap: () => onOpenUrl(_issuesUrl),
          trailing: const Icon(Icons.open_in_new, size: 18),
        ),
      ],
    );
    final theme = Theme.of(context);
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide(color: Color(0xFFD3DFD9)),
    );
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: const Color(0xFFF6F8F7),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: const BorderSide(color: Color(0xFF267B69), width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 16,
          ),
          helperMaxLines: 4,
          errorMaxLines: 4,
        ),
        listTileTheme: theme.listTileTheme.copyWith(
          titleTextStyle: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
            color: const Color(0xFF243E33),
          ),
          subtitleTextStyle: theme.textTheme.bodySmall?.copyWith(
            color: const Color(0xFF6A7D73),
          ),
          iconColor: const Color(0xFF607B6B),
        ),
      ),
      child: ListView(
        key: const ValueKey('settings.page'),
        children: [
          _PageHeading(
            title: l10n.settingsTitle,
            subtitle: l10n.settingsOverview,
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              Widget stack(List<Widget> cards) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final card in cards) ...[
                    card,
                    const SizedBox(height: 16),
                  ],
                ],
              );
              return constraints.maxWidth >= 920 &&
                      MediaQuery.textScalerOf(context).scale(1) < 1.5
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: stack([
                            folder,
                            sources,
                            quality,
                            export,
                            lock,
                          ]),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: stack([
                            language,
                            startup,
                            server,
                            cache,
                            about,
                          ]),
                        ),
                      ],
                    )
                  : stack([
                      folder,
                      language,
                      startup,
                      sources,
                      quality,
                      export,
                      lock,
                      server,
                      cache,
                      about,
                    ]);
            },
          ),
          const _AppVersionFooter(),
        ],
      ),
    );
  }

  String _folderLabel(AppLocalizations l10n) {
    final value = folderUri;
    if (value == null) return l10n.notSelected;
    final uri = Uri.tryParse(value);
    if (uri?.scheme == 'content' &&
        uri?.host == 'com.android.externalstorage.documents') {
      final segments = uri!.pathSegments;
      final tree = segments.indexOf('tree');
      if (tree >= 0 && tree + 1 < segments.length) {
        final id = segments[tree + 1];
        final separator = id.indexOf(':');
        if (separator > 0) {
          final volume = id.substring(0, separator);
          final folder = id.substring(separator + 1);
          return [
            volume == 'primary' ? l10n.internalStorage : volume,
            if (folder.isNotEmpty) folder,
          ].join(' / ');
        }
      }
    }
    return value;
  }

  void _showAudioSourceRequired(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.l10n.audioSourceRequired)));
  }

  Future<void> _confirmClearCache(BuildContext context) async {
    final confirmed = await _confirm(
      context,
      title: context.l10n.clearCache,
      message: context.l10n.confirmClearCache,
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    final result = await onClearCache();
    if (!context.mounted) {
      return;
    }
    final deletedBytes = result['deletedBytes'];
    final activePreserved = result['activeReplayCachePreserved'] == true;
    final l10n = context.l10n;
    final message = result['ok'] == true
        ? (activePreserved
              ? l10n.cacheClearedActivePreserved(
                  _formatBytes(deletedBytes is int ? deletedBytes : 0),
                )
              : l10n.cacheCleared(
                  _formatBytes(deletedBytes is int ? deletedBytes : 0),
                ))
        : l10n.cacheClearFailed(result['error']?.toString() ?? 'unknown');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeading(title: title, icon: icon),
        const SizedBox(height: 16),
        ...children,
      ],
    ),
  );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.tooltip,
    this.trailing,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? tooltip;
  final Widget? trailing;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final stackAction =
            trailing is ButtonStyleButton &&
            (constraints.maxWidth < 380 ||
                MediaQuery.textScalerOf(context).scale(1) >= 1.5);
        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF243E33),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Tooltip(
                message: tooltip ?? subtitle!,
                child: Text(
                  subtitle!,
                  maxLines: tooltip == null ? null : 2,
                  overflow: tooltip == null ? null : TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6A7D73),
                  ),
                ),
              ),
            ],
            if (stackAction) ...[const SizedBox(height: 10), trailing!],
          ],
        );
        return Row(
          children: [
            _SurfaceIcon(icon),
            const SizedBox(width: 12),
            Expanded(child: details),
            if (trailing != null && !stackAction) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
          ],
        );
      },
    ),
  );
}

class _SourceVolumeControl extends StatefulWidget {
  const _SourceVolumeControl({required this.source, required this.enabled});
  final String source;
  final bool enabled;
  @override
  State<_SourceVolumeControl> createState() => _SourceVolumeControlState();
}

class _SourceVolumeControlState extends State<_SourceVolumeControl> {
  final _client = const ReplayServiceClient();
  final _controller = TextEditingController(text: '100');
  final _focus = FocusNode();
  double _value = 100;
  int _saved = 100;
  int? _pending;
  bool _sending = false;
  bool _loaded = false;
  bool _dragging = false;
  bool _invalid = false;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
    _load();
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focus.hasFocus && !_dragging) {
      _commitText();
    }
  }

  Future<void> _load() async {
    try {
      final values = await _client.getAudioGains();
      if (mounted) {
        setState(() {
          _saved = (values[widget.source] as num? ?? 100).round().clamp(0, 300);
          _value = _saved.toDouble();
          _controller.text = '$_saved';
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loaded = true);
      }
    }
  }

  void _commitText() {
    if (!_loaded || !widget.enabled) {
      return;
    }
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed == null || parsed < 0 || parsed > 300) {
      setState(() => _invalid = true);
      return;
    }
    setState(() {
      _invalid = false;
      _value = parsed.toDouble();
    });
    _commit(_value);
  }

  // Keep pointer updates local. Serialize released values and coalesce newer
  // edits without blocking the next drag on a platform/storage acknowledgement.
  void _commit(double value) {
    final target = value.round();
    _controller.text = '$target';
    if (!_sending && target == _saved) {
      return;
    }
    _revision++;
    _pending = target;
    if (!_sending) {
      unawaited(_drain());
    }
  }

  Future<void> _drain() async {
    _sending = true;
    while (_pending != null) {
      final target = _pending!;
      final revision = _revision;
      _pending = null;
      try {
        final result = await _client.setAudioGain(widget.source, target);
        if (result['ok'] != true) {
          throw StateError('gain_failed');
        }
        _saved = target;
      } catch (_) {
        if (mounted && revision == _revision && !_dragging) {
          setState(() {
            _value = _saved.toDouble();
            _controller.text = '$_saved';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.volumeSaveFailed)),
          );
        }
      }
    }
    _sending = false;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && _loaded;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7F5),
        border: Border.all(color: const Color(0xFFE1E8E4)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.recordingVolume,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 96,
                child: TextField(
                  key: ValueKey('settings.${widget.source}VolumeInput'),
                  enabled: enabled,
                  controller: _controller,
                  focusNode: _focus,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textInputAction: TextInputAction.done,
                  textAlign: TextAlign.end,
                  onSubmitted: (_) => _commitText(),
                  onChanged: (_) {
                    _revision++;
                  },
                  decoration: InputDecoration(
                    suffixText: '%',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              const Text('0%', style: TextStyle(fontSize: 12)),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(trackHeight: 4),
                  child: Slider(
                    key: ValueKey('settings.${widget.source}Volume'),
                    min: 0,
                    max: 300,
                    value: _value,
                    semanticFormatterCallback: (value) => '${value.round()}%',
                    onChangeStart: enabled
                        ? (_) {
                            _dragging = true;
                            _revision++;
                            _focus.unfocus();
                          }
                        : null,
                    onChanged: enabled
                        ? (value) => setState(() {
                            _value = value;
                            _invalid = false;
                            _controller.text = '${value.round()}';
                          })
                        : null,
                    onChangeEnd: enabled
                        ? (value) {
                            _dragging = false;
                            _commit(value);
                          }
                        : null,
                  ),
                ),
              ),
              const Text('300%', style: TextStyle(fontSize: 12)),
            ],
          ),
          if (_invalid)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                context.l10n.volumeInvalid,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}

class _StartupSettingsCard extends StatefulWidget {
  const _StartupSettingsCard({required this.onOpenTasks});
  final Future<void> Function()? onOpenTasks;
  @override
  State<_StartupSettingsCard> createState() => _StartupSettingsCardState();
}

class _StartupSettingsCardState extends State<_StartupSettingsCard> {
  final _client = const ReplayServiceClient();
  bool _enabled = false;
  bool _supported = defaultTargetPlatform != TargetPlatform.android;
  bool _silent = false;
  bool _loaded = false;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await _client.getStartupSettings();
      if (mounted) {
        setState(() {
          _supported =
              value.startupSupported &&
              defaultTargetPlatform != TargetPlatform.android;
          _enabled = _supported && value.startupEnabled;
          _silent = _enabled && value.startupSilent;
          _loaded = value.ok;
        });
      }
    } catch (_) {
      /* The control stays unavailable until the platform is ready. */
    }
  }

  Future<void> _setEnabled(bool enabled) async {
    setState(() => _busy = true);
    try {
      final result = await _client.setStartupEnabled(enabled);
      if (!mounted) return;
      if (result.ok) {
        setState(() {
          _enabled = result.startupEnabled;
          _silent = _enabled && result.startupSilent;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.error?.contains('notification_permission') == true
                  ? context.l10n.startupPermission
                  : context.l10n.startupFailed,
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.startupFailed)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setSilent(bool silent) async {
    setState(() => _busy = true);
    try {
      final result = await _client.setStartupSilent(silent);
      if (!result.ok) throw StateError(result.error ?? 'startup_failed');
      if (mounted) setState(() => _silent = result.startupSilent);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.startupFailed)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const ValueKey('settings.startupEnabled'),
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.power_settings_new),
          title: Text(context.l10n.startupTitle),
          value: _enabled,
          subtitle: Text(
            _supported
                ? context.l10n.startupWindowsHelp
                : context.l10n.startupUnsupported,
          ),
          onChanged: _supported && _loaded && !_busy ? _setEnabled : null,
        ),
        if (_supported) ...[
          SwitchListTile(
            key: const ValueKey('settings.startupSilent'),
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.visibility_off_outlined),
            title: Text(context.l10n.startupSilent),
            subtitle: Text(context.l10n.startupSilentHelp),
            value: _enabled && _silent,
            onChanged: _enabled && _loaded && !_busy ? _setSilent : null,
          ),
          const Divider(height: 20),
          ListTile(
            key: const ValueKey('settings.startup'),
            contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.startupTasks),
            subtitle: Text(context.l10n.startupTasksHelp),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onOpenTasks == null
                ? null
                : () async {
                    await widget.onOpenTasks!();
                    if (mounted) await _load();
                  },
          ),
        ],
      ],
    ),
  );
}

class _AppVersionFooter extends StatefulWidget {
  const _AppVersionFooter();
  @override
  State<_AppVersionFooter> createState() => _AppVersionFooterState();
}

class _AppVersionFooterState extends State<_AppVersionFooter> {
  late final Future<Map<dynamic, dynamic>> _version =
      const ReplayServiceClient().getAppVersion();
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<dynamic, dynamic>>(
    future: _version,
    builder: (context, snapshot) {
      final version = snapshot.data?['version'];
      final build = snapshot.data?['buildNumber'];
      return Padding(
        key: const ValueKey('settings.version'),
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 28),
        child: Text(
          '${context.l10n.softwareVersion} · ${version == null ? '—' : 'EchoClip $version${build == null ? '' : ' ($build)'}'}',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: const Color(0xFF6A7D73)),
        ),
      );
    },
  );
}
