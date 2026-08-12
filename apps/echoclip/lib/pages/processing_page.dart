part of '../main.dart';

class _ProcessingPage extends StatefulWidget {
  const _ProcessingPage({required this.clips, required this.onProcess});

  final List<ClipItem> clips;
  final Future<bool> Function({
    required ClipItem clip,
    required double gainDb,
    required String format,
    required int mp3BitrateKbps,
  })
  onProcess;

  @override
  State<_ProcessingPage> createState() => _ProcessingPageState();
}

class _ProcessingPageState extends State<_ProcessingPage> {
  static const List<int> _bitrateOptions = [64, 96, 128, 160, 192, 256, 320];

  String? _selectedUri;
  double _gainDb = 0;
  String _format = 'mp3';
  int _mp3BitrateKbps = 128;
  bool _processing = false;
  String? _message;

  ClipItem? get _selectedClip {
    for (final clip in widget.clips) {
      if (clip.uri == _selectedUri) {
        return clip;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _selectedUri = widget.clips
        .map((clip) => clip.uri)
        .whereType<String>()
        .firstOrNull;
  }

  @override
  void didUpdateWidget(covariant _ProcessingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final uris = widget.clips.map((clip) => clip.uri).whereType<String>();
    if (_selectedUri == null || !uris.contains(_selectedUri)) {
      _selectedUri = uris.isEmpty ? null : uris.first;
    }
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
              DropdownButtonFormField<String>(
                initialValue: _selectedUri,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.sourceRecording,
                  prefixIcon: const Icon(Icons.library_music),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                ),
                items: [
                  for (final clip in widget.clips)
                    if (clip.uri != null)
                      DropdownMenuItem(
                        value: clip.uri,
                        child: Text(clip.name, overflow: TextOverflow.ellipsis),
                      ),
                ],
                selectedItemBuilder: (context) => [
                  for (final clip in widget.clips)
                    if (clip.uri != null)
                      Text(
                        clip.name,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                ],
                onChanged: _processing
                    ? null
                    : (value) => setState(() => _selectedUri = value),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Icon(Icons.volume_up),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.gainDb(
                        '${_gainDb >= 0 ? '+' : ''}${_gainDb.toStringAsFixed(1)}',
                      ),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _gainDb,
                min: -24,
                max: 24,
                divisions: 96,
                label:
                    '${_gainDb >= 0 ? '+' : ''}${_gainDb.toStringAsFixed(1)} dB',
                onChanged: _processing
                    ? null
                    : (value) => setState(() => _gainDb = value),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _format,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.outputFormat,
                  prefixIcon: const Icon(Icons.audio_file),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 'mp3', child: Text('MP3')),
                  DropdownMenuItem(value: 'wav', child: Text('WAV')),
                ],
                onChanged: _processing
                    ? null
                    : (value) => setState(() => _format = value ?? 'mp3'),
              ),
              if (_format == 'mp3') ...[
                const SizedBox(height: 14),
                DropdownButtonFormField<int>(
                  initialValue: _mp3BitrateKbps,
                  decoration: InputDecoration(
                    labelText: l10n.mp3Bitrate,
                    prefixIcon: const Icon(Icons.speed),
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                  ),
                  items: [
                    for (final value in _bitrateOptions)
                      DropdownMenuItem(
                        value: value,
                        child: Text('$value kbps'),
                      ),
                  ],
                  onChanged: _processing
                      ? null
                      : (value) => setState(
                          () => _mp3BitrateKbps = value ?? _mp3BitrateKbps,
                        ),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _processing || _selectedClip == null
                    ? null
                    : _processSelectedClip,
                icon: _processing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_fix_high),
                label: Text(
                  _processing ? l10n.processing : l10n.generateProcessedCopy,
                ),
              ),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(_message!, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _processSelectedClip() async {
    final clip = _selectedClip;
    if (clip == null) {
      return;
    }
    setState(() {
      _processing = true;
      _message = null;
    });
    final ok = await widget.onProcess(
      clip: clip,
      gainDb: _gainDb,
      format: _format,
      mp3BitrateKbps: _mp3BitrateKbps,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _processing = false;
      _message = ok
          ? context.l10n.processingComplete
          : context.l10n.processingFailed;
    });
  }
}
