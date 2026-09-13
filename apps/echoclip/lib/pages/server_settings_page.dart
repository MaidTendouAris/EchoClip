part of '../main.dart';

class ServerSettingsPage extends StatefulWidget {
  const ServerSettingsPage({
    super.key,
    required this.initialSettings,
    required this.onEnabledChanged,
    required this.onSave,
    required this.onRefresh,
    required this.onTestConnection,
    this.initialConnectionTest,
  });

  final ServerSyncSettings initialSettings;
  final ServerConnectionTestResult? initialConnectionTest;
  final Future<ServerSyncSettings> Function(bool enabled) onEnabledChanged;
  final Future<ServerSyncSettings> Function({
    required String serverHost,
    required int uploadPort,
    String? uploadKey,
    bool clearKey,
  })
  onSave;
  final Future<ServerSyncSettings> Function() onRefresh;
  final Future<ServerConnectionTestResult> Function({
    String? serverHost,
    int? uploadPort,
    String? uploadKey,
  })
  onTestConnection;

  @override
  State<ServerSettingsPage> createState() => _ServerSettingsPageState();
}

class _ServerSettingsPageState extends State<ServerSettingsPage> {
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _keyController;
  late ServerSyncSettings _settings;
  bool _enabled = false;
  bool _busy = false;
  bool _testing = false;
  bool _obscureKey = true;
  ServerConnectionTestResult? _connectionTest;
  String? _formError;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
    _enabled = _settings.enabled;
    _connectionTest = widget.initialConnectionTest;
    _hostController = TextEditingController(text: _settings.serverHost);
    _portController = TextEditingController(
      text: _settings.uploadPort.toString(),
    );
    _keyController = TextEditingController();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F7),
      appBar: AppBar(
        title: Text(l10n.serverSettings),
        backgroundColor: const Color(0xFFF6F8F7),
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                _Panel(
                  child: SwitchListTile(
                    key: const ValueKey('serverSettings.enabled'),
                    contentPadding: EdgeInsets.zero,
                    value: _enabled,
                    title: Text(l10n.serverSyncEnabled),
                    subtitle: Text(l10n.serverSyncEnabledDescription),
                    onChanged: _busy ? null : _setEnabled,
                  ),
                ),
                const SizedBox(height: 16),
                _Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        key: const ValueKey('serverSettings.host'),
                        controller: _hostController,
                        enabled: !_busy,
                        onChanged: (_) => _invalidateConnectionTest(),
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: l10n.serverHost,
                          hintText: '192.168.1.231',
                          prefixIcon: const Icon(Icons.dns_outlined),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        key: const ValueKey('serverSettings.port'),
                        controller: _portController,
                        enabled: !_busy,
                        onChanged: (_) => _invalidateConnectionTest(),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          labelText: l10n.serverUploadPort,
                          hintText: '32581',
                          prefixIcon: const Icon(Icons.lan_outlined),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        key: const ValueKey('serverSettings.key'),
                        controller: _keyController,
                        enabled: !_busy,
                        onChanged: (_) => _invalidateConnectionTest(),
                        obscureText: _obscureKey,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: l10n.serverUploadKey,
                          helperText: _settings.keyConfigured
                              ? l10n.serverUploadKeyConfigured
                              : l10n.serverUploadKeyRequired,
                          prefixIcon: const Icon(Icons.key_outlined),
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setState(() => _obscureKey = !_obscureKey),
                            icon: Icon(
                              _obscureKey
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),

                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.devices_other_outlined),
                        title: Text(l10n.serverDeviceId),
                        subtitle: SelectableText(
                          _settings.deviceId.isEmpty ? '—' : _settings.deviceId,
                        ),
                      ),
                      if (_formError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _formError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            key: const ValueKey('serverSettings.save'),
                            onPressed: _busy ? null : _save,
                            icon: const Icon(Icons.save_outlined),
                            label: Text(l10n.saveSettings),
                          ),
                          OutlinedButton.icon(
                            key: const ValueKey(
                              'serverSettings.testConnection',
                            ),
                            onPressed: _busy ? null : _testConnection,
                            icon: _testing
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.network_check_outlined),
                            label: Text(
                              _testing
                                  ? l10n.serverTestingConnection
                                  : l10n.serverTestConnection,
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy || !_settings.keyConfigured
                                ? null
                                : _clearKey,
                            icon: const Icon(Icons.key_off_outlined),
                            label: Text(l10n.removeServerKey),
                          ),
                        ],
                      ),
                      if (_connectionTest != null) ...[
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              _connectionTest!.success
                                  ? Icons.check_circle_outline
                                  : Icons.error_outline,
                              color: _connectionTest!.success
                                  ? const Color(0xFF2E9B62)
                                  : Theme.of(context).colorScheme.error,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _connectionTest!.success
                                        ? l10n.serverConnectionTestSucceeded
                                        : l10n.serverConnectionTestFailed,
                                  ),
                                  if (_connectionTest!.error?.isNotEmpty ==
                                      true)
                                    SelectableText(
                                      _connectionTest!.error!,
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.serverConnectionStatus,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            tooltip: l10n.refresh,
                            onPressed: _busy ? null : _refresh,
                            icon: const Icon(Icons.refresh),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _ServerStatusSummary(
                        settings: _settings,
                        connectionTest: _connectionTest,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.serverConnectionLogs,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      if (_settings.status?.logs.isNotEmpty != true)
                        Text(
                          l10n.noServerConnectionLogs,
                          style: Theme.of(context).textTheme.bodyMedium,
                        )
                      else
                        for (final log in _settings.status!.logs.reversed)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(_logIcon(log.event), size: 19),
                            title: Text(_logLabel(l10n, log.event)),
                            subtitle: Text(log.message),
                            trailing: Text(_formatLogTime(log.unixSeconds)),
                          ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _invalidateConnectionTest() {
    if (_connectionTest != null) {
      setState(() => _connectionTest = null);
    }
  }

  Future<void> _setEnabled(bool enabled) async {
    setState(() {
      _busy = true;
      _formError = null;
    });
    try {
      final settings = await widget.onEnabledChanged(enabled);
      if (!mounted) {
        return;
      }
      setState(() {
        _settings = settings;
        _enabled = settings.enabled;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _formError = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _save() async {
    var serverHost = _hostController.text.trim();
    if (serverHost.startsWith('[') && serverHost.endsWith(']')) {
      serverHost = serverHost.substring(1, serverHost.length - 1);
    }
    final uploadPort = int.tryParse(_portController.text.trim());
    final key = _keyController.text.trim();
    final hostInvalid =
        serverHost.isEmpty ||
        serverHost.contains('://') ||
        serverHost.contains(RegExp(r'\s')) ||
        serverHost.contains('/') ||
        serverHost.contains('?') ||
        serverHost.contains('#');
    if (hostInvalid) {
      setState(() => _formError = context.l10n.serverHostInvalid);
      return;
    }
    if (uploadPort == null || uploadPort < 1 || uploadPort > 65535) {
      setState(() => _formError = context.l10n.serverUploadPortInvalid);
      return;
    }
    if (key.isEmpty && !_settings.keyConfigured) {
      setState(() => _formError = context.l10n.serverUploadKeyRequired);
      return;
    }
    if (key.isNotEmpty) {
      try {
        if (base64Decode(key).length != 32) {
          throw const FormatException();
        }
      } on FormatException {
        setState(() => _formError = context.l10n.serverUploadKeyInvalid);
        return;
      }
    }
    setState(() {
      _busy = true;
      _formError = null;
    });
    try {
      final settings = await widget.onSave(
        serverHost: serverHost,
        uploadPort: uploadPort,
        uploadKey: key.isEmpty ? null : key,
      );
      if (!mounted) {
        return;
      }
      _keyController.clear();
      setState(() {
        _settings = settings;
        _enabled = settings.enabled;
        _hostController.text = settings.serverHost;
        _portController.text = settings.uploadPort.toString();
      });
    } catch (error) {
      if (mounted) {
        setState(() => _formError = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _testConnection() async {
    var serverHost = _hostController.text.trim();
    if (serverHost.startsWith('[') && serverHost.endsWith(']')) {
      serverHost = serverHost.substring(1, serverHost.length - 1);
    }
    final uploadPort = int.tryParse(_portController.text.trim());
    final key = _keyController.text.trim();
    final hostInvalid =
        serverHost.isEmpty ||
        serverHost.contains('://') ||
        serverHost.contains(RegExp(r'\s')) ||
        serverHost.contains('/') ||
        serverHost.contains('?') ||
        serverHost.contains('#');
    if (hostInvalid) {
      setState(() => _formError = context.l10n.serverHostInvalid);
      return;
    }
    if (uploadPort == null || uploadPort < 1 || uploadPort > 65535) {
      setState(() => _formError = context.l10n.serverUploadPortInvalid);
      return;
    }
    if (key.isEmpty && !_settings.keyConfigured) {
      setState(() => _formError = context.l10n.serverUploadKeyRequired);
      return;
    }
    if (key.isNotEmpty) {
      try {
        if (base64Decode(key).length != 32) {
          throw const FormatException();
        }
      } on FormatException {
        setState(() => _formError = context.l10n.serverUploadKeyInvalid);
        return;
      }
    }
    setState(() {
      _busy = true;
      _testing = true;
      _formError = null;
      _connectionTest = null;
    });
    try {
      final result = await widget.onTestConnection(
        serverHost: serverHost,
        uploadPort: uploadPort,
        uploadKey: key.isEmpty ? null : key,
      );
      if (mounted) {
        setState(() => _connectionTest = result);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _formError = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _testing = false;
        });
      }
    }
  }

  Future<void> _clearKey() async {
    setState(() {
      _busy = true;
      _formError = null;
    });
    try {
      final settings = await widget.onSave(
        serverHost: _hostController.text.trim(),
        uploadPort: int.tryParse(_portController.text.trim()) ?? 32581,
        clearKey: true,
      );
      if (mounted) {
        setState(() {
          _settings = settings;
          _enabled = false;
          _hostController.text = settings.serverHost;
          _portController.text = settings.uploadPort.toString();
          _keyController.clear();
          _connectionTest = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _formError = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    try {
      final settings = await widget.onRefresh();
      if (mounted) {
        setState(() {
          _settings = settings;
          _enabled = settings.enabled;
          _hostController.text = settings.serverHost;
          _portController.text = settings.uploadPort.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  IconData _logIcon(String event) => switch (event) {
    'connected' => Icons.cloud_done_outlined,
    'disconnected' => Icons.cloud_off_outlined,
    'retention_gap' => Icons.warning_amber_outlined,
    'stopped' => Icons.stop_circle_outlined,
    _ => Icons.info_outline,
  };

  String _logLabel(AppLocalizations l10n, String event) => switch (event) {
    'started' => l10n.serverEventStarted,
    'connected' => l10n.serverEventConnected,
    'disconnected' => l10n.serverEventDisconnected,
    'retention_gap' => l10n.serverEventRetentionGap,
    'stopped' => l10n.serverEventStopped,
    _ => event,
  };

  String _formatLogTime(int unixSeconds) {
    if (unixSeconds <= 0) {
      return '—';
    }
    final time = DateTime.fromMillisecondsSinceEpoch(
      unixSeconds * 1000,
    ).toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}

class _ServerStatusSummary extends StatelessWidget {
  const _ServerStatusSummary({required this.settings, this.connectionTest});

  final ServerSyncSettings settings;
  final ServerConnectionTestResult? connectionTest;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = settings.status;
    final label = !settings.configured
        ? l10n.serverNotConfigured
        : !settings.enabled
        ? l10n.serverSyncDisabled
        : status?.running == true
        ? status?.connected == true
              ? l10n.serverConnected
              : (settings.configurationError ?? status?.lastError)
                        ?.isNotEmpty ==
                    true
              ? l10n.serverConnectionFailed
              : l10n.serverConnecting
        : connectionTest?.success == true
        ? l10n.serverConnected
        : connectionTest != null
        ? l10n.serverConnectionFailed
        : l10n.serverConnecting;
    final error = settings.configurationError ?? status?.lastError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(settings.connectionLabel.isEmpty ? '—' : settings.connectionLabel),
        if (status != null) ...[
          const SizedBox(height: 6),
          Text(l10n.serverUploadLag(status.lagSamples)),
          Text(l10n.serverReconnectCount(status.reconnectCount)),
          if (status.keyId.isNotEmpty) Text(l10n.serverKeyId(status.keyId)),
        ],
        if (error?.isNotEmpty == true) ...[
          const SizedBox(height: 8),
          SelectableText(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}
