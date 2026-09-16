part of '../main.dart';

class StartupTasksPage extends StatefulWidget {
  const StartupTasksPage({super.key});
  @override
  State<StartupTasksPage> createState() => _StartupTasksPageState();
}

class _StartupTasksPageState extends State<StartupTasksPage> {
  final _client = const ReplayServiceClient();
  ScheduleSnapshot? _snapshot;
  bool _busy = false;
  String? _error;
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
          _snapshot = value;
          _error = value.ok ? null : value.error;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<bool> _mutate(Future<ScheduleSnapshot> Function() action) async {
    if (_busy) return false;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await action();
      if (mounted) {
        setState(() {
          if (result.ok) _snapshot = result;
          _error = result.ok ? null : result.error ?? 'startup_failed';
        });
      }
      return result.ok;
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _setActions({bool? recording, bool? upload}) => _mutate(
    () => _client.upsertScheduledTask({
      'operation': 'set_startup_actions',
      'recordingEnabled': recording ?? _snapshot!.startupRecordingEnabled,
      'uploadEnabled': upload ?? _snapshot!.startupUploadEnabled,
    }),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ready = _snapshot?.ok == true && !_busy;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F7),
      appBar: AppBar(title: Text(l10n.startupTasks)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  l10n.startupTasksHelp,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                _Panel(
                  child: Column(
                    children: [
                      SwitchListTile(
                        key: const ValueKey('startup.recording'),
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(Icons.mic_none),
                        title: Text(l10n.startupRecording),
                        subtitle: Text(l10n.startupRecordingHelp),
                        value: _snapshot?.startupRecordingEnabled ?? false,
                        onChanged: ready
                            ? (value) => _setActions(recording: value)
                            : null,
                      ),
                      const Divider(height: 24),
                      SwitchListTile(
                        key: const ValueKey('startup.upload'),
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(Icons.cloud_upload_outlined),
                        title: Text(l10n.startupUpload),
                        subtitle: Text(l10n.startupUploadHelp),
                        value: _snapshot?.startupUploadEnabled ?? false,
                        onChanged: ready
                            ? (value) => _setActions(upload: value)
                            : null,
                      ),
                    ],
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.startupFailed,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _busy ? null : _load,
                          tooltip: l10n.refresh,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                  ),
                if (_snapshot == null && _error == null)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
