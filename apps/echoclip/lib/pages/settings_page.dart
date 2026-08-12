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
          borderRadius: BorderRadius.all(Radius.circular(8)),
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

    return ListView(
      children: [
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder),
                title: Text(l10n.recordingFolder),
                subtitle: Text(folderUri ?? l10n.notSelected),
                trailing: FilledButton.icon(
                  onPressed: onChooseFolder,
                  icon: const Icon(Icons.folder_open),
                  label: Text(l10n.change),
                ),
              ),
              const Divider(height: 28),
              Text(
                l10n.languageSettings,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<UiLanguageMode>(
                key: ValueKey(languageMode),
                initialValue: languageMode,
                decoration: InputDecoration(
                  labelText: l10n.appLanguage,
                  prefixIcon: const Icon(Icons.language),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                ),
                items: [
                  for (final mode in UiLanguageMode.values)
                    DropdownMenuItem(
                      value: mode,
                      child: Text(_languageModeLabel(l10n, mode)),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  onLanguageModeChanged(value);
                },
              ),
              const Divider(height: 28),
              Text(
                l10n.recordingSettings,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 14),
              Text(
                l10n.audioSources,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                l10n.audioSourcesDescription,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                key: const ValueKey('settings.microphone'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                secondary: const Icon(Icons.mic_outlined),
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
                secondary: const Icon(Icons.speaker_outlined),
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
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                        ),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: _systemDefaultDeviceValue,
                          child: Text(l10n.systemDefaultInputDevice),
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
                                microphoneDeviceId:
                                    value == _systemDefaultDeviceValue
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
              const Divider(height: 28),
              DropdownButtonFormField<int>(
                initialValue: sampleRate,
                decoration: InputDecoration(
                  labelText: l10n.sampleRate,
                  prefixIcon: const Icon(Icons.graphic_eq),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                ),
                items: [
                  for (final value in _sampleRateOptions)
                    DropdownMenuItem(
                      value: value,
                      child: Text(_formatHertz(value)),
                    ),
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
                title: Text(
                  l10n.estimatedPcmBuffer(_formatBytes(estimatedPcmBytes)),
                ),
                subtitle: Text(
                  l10n.pcmBufferSubtitle(_formatHertz(sampleRate)),
                ),
              ),
              const Divider(height: 28),
              Text(
                l10n.lockRecordingSettings,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<LockRecordingTrigger>(
                initialValue: lockRecordingTrigger,
                decoration: InputDecoration(
                  labelText: l10n.lockRecordingTrigger,
                  prefixIcon: const Icon(Icons.screen_lock_portrait),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                ),
                items: [
                  DropdownMenuItem(
                    value: LockRecordingTrigger.screenOff,
                    child: Text(l10n.lockRecordingTriggerScreenOff),
                  ),
                  DropdownMenuItem(
                    value: LockRecordingTrigger.keyguardLocked,
                    child: Text(l10n.lockRecordingTriggerKeyguard),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  onLockRecordingTriggerChanged(value);
                },
              ),
              const Divider(height: 28),
              Text(
                l10n.cacheTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.storage),
                title: Text(l10n.currentCacheSize(_formatBytes(cacheBytes))),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.cleaning_services),
                title: Text(l10n.clearCache),
                subtitle: Text(l10n.clearCacheSubtitle),
                trailing: IconButton.filledTonal(
                  tooltip: l10n.clearCache,
                  onPressed: () => _confirmClearCache(context),
                  icon: const Icon(Icons.delete_sweep),
                ),
              ),
              const Divider(height: 28),
              Text(
                l10n.aboutProject,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.code),
                title: Text(l10n.githubRepository),
                subtitle: Text(l10n.githubRepositorySubtitle),
                onTap: () => onOpenUrl(_repositoryUrl),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.balance),
                title: Text(l10n.licenseTitle),
                subtitle: Text(l10n.licenseSubtitle),
                onTap: () => onOpenUrl('$_repositoryUrl/blob/main/LICENSE'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.bug_report),
                title: Text(l10n.issueFeedback),
                subtitle: Text(l10n.issueFeedbackSubtitle),
                onTap: () => onOpenUrl(_issuesUrl),
              ),
            ],
          ),
        ),
      ],
    );
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
