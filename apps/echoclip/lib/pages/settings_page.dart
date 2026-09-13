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

  int get _minutes => (widget.bufferSeconds / 60).round().clamp(1, 1440);

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
    final minutes = parsed.clamp(1, 1440).toInt();
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
  });

  static const List<int> _sampleRateOptions = [8000, 16000, 24000, 48000];
  static const String _systemDefaultDeviceValue =
      '__echoclip_system_default_input__';
  static const String _repositoryUrl =
      'https://github.com/MaidTendouAris/EchoClip';
  static const String _issuesUrl =
      'https://github.com/MaidTendouAris/EchoClip/issues';

  final String? folderUri;
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
    final language = _SettingsSection(
      title: l10n.languageSettings,
      icon: Icons.language,
      children: [
        DropdownButtonFormField<UiLanguageMode>(
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
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              key: const ValueKey('settings.inputDevice'),
              child: DropdownButtonFormField<String>(
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
        DropdownButtonFormField<int>(
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
    final lock = _SettingsSection(
      title: l10n.lockRecordingSettings,
      icon: Icons.screen_lock_portrait,
      children: [
        DropdownButtonFormField<LockRecordingTrigger>(
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
                          child: stack([folder, sources, quality, lock]),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: stack([language, server, cache, about]),
                        ),
                      ],
                    )
                  : stack([
                      folder,
                      language,
                      sources,
                      quality,
                      lock,
                      server,
                      cache,
                      about,
                    ]);
            },
          ),
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
