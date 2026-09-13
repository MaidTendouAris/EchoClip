part of '../main.dart';

class LoudnessMeter extends StatefulWidget {
  const LoudnessMeter({
    super.key,
    required this.level,
    required this.peakLevel,
    required this.isRecording,
  });

  final double level;
  final double peakLevel;
  final bool isRecording;

  @override
  State<LoudnessMeter> createState() => _LoudnessMeterState();
}

class _LoudnessMeterState extends State<LoudnessMeter>
    with SingleTickerProviderStateMixin {
  final _signal = LoudnessMeterModel();
  late final Ticker _ticker;
  Duration? _lastTick;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final delta = elapsed - (_lastTick ?? elapsed);
      _lastTick = elapsed;
      _signal.advance(delta, animate: !_reduceMotion);
    });
    _updateInput();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void didUpdateWidget(covariant LoudnessMeter oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateInput();
  }

  void _updateInput() {
    _signal.setInput(
      widget.level,
      widget.peakLevel,
      recording: widget.isRecording,
    );
    if (widget.isRecording && !_ticker.isActive) {
      _lastTick = null;
      _ticker.start();
    } else if (!widget.isRecording && _ticker.isActive) {
      _ticker.stop();
      _lastTick = null;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _signal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return RepaintBoundary(
      child: Container(
        key: const ValueKey('loudness.panel'),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F7F5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFDCE6E0)),
        ),
        child: ValueListenableBuilder<MeterReading>(
          valueListenable: _signal.reading,
          builder: (context, reading, _) {
            const accent = Color(0xFF267B69);
            final status = reading.active
                ? l10n.loudnessRecordingLabel
                : l10n.notRecordingLabel;
            return Semantics(
              label: l10n.loudnessTitle,
              value:
                  '$status, ${MeterReading.format(reading.level)} dBFS, '
                  '${l10n.peakLabel} ${MeterReading.format(reading.peak)} dBFS',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        Text(
                          l10n.loudnessTitle,
                          style: const TextStyle(
                            color: Color(0xFF294A3E),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(
                              alpha: reading.active ? 0.1 : 0.04,
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: reading.active
                                      ? accent
                                      : const Color(0xFF7B8F85),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  status,
                                  key: const ValueKey('loudness.status'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: reading.active
                                        ? accent
                                        : const Color(0xFF657D70),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 13),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide =
                          constraints.maxWidth >= 540 &&
                          MediaQuery.textScalerOf(context).scale(1) < 1.5;
                      final readout = _readout(reading, accent, wide: wide);
                      final trace = _trace(l10n, wide: wide);
                      return wide
                          ? Row(
                              children: [
                                SizedBox(width: 184, child: readout),
                                Container(
                                  width: 1,
                                  height: 64,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  color: const Color(0xFFDCE6E0),
                                ),
                                Expanded(child: trace),
                              ],
                            )
                          : Column(
                              children: [
                                readout,
                                const SizedBox(height: 10),
                                trace,
                              ],
                            );
                    },
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 32,
                    width: double.infinity,
                    child: CustomPaint(
                      key: const ValueKey('loudness.scale'),
                      painter: _LoudnessScalePainter(
                        _signal,
                        Theme.of(context).textTheme.labelSmall!.copyWith(
                          fontSize: 10,
                          color: const Color(0xFF6A8075),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _readout(MeterReading reading, Color accent, {required bool wide}) {
    final current = Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          reading.active ? MeterReading.format(reading.level) : '—',
          key: const ValueKey('loudness.value'),
          style: TextStyle(
            fontSize: wide ? 46 : 40,
            height: 1.1,
            fontWeight: FontWeight.w500,
            letterSpacing: -1.5,
            color: reading.active
                ? const Color(0xFF173D34)
                : const Color(0xFF7B8F85),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'dBFS',
          style: TextStyle(fontSize: 11, color: Color(0xFF657D70)),
        ),
      ],
    );
    final peak = Text(
      '${context.l10n.peakLabel}  '
      '${reading.active ? MeterReading.format(reading.peak) : '—'} dBFS',
      key: const ValueKey('loudness.peak'),
      style: TextStyle(
        fontSize: 11,
        color: reading.active ? accent : const Color(0xFF657D70),
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    if (wide || MediaQuery.textScalerOf(context).scale(1) >= 1.5) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: current,
          ),
          const SizedBox(height: 8),
          peak,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          flex: 3,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: current,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: peak,
          ),
        ),
      ],
    );
  }

  Widget _trace(AppLocalizations l10n, {required bool wide}) {
    final textScaler = MediaQuery.textScalerOf(context);
    final labelStyle = Theme.of(context).textTheme.labelSmall!.copyWith(
      fontSize: 10,
      color: const Color(0xFF6A8075),
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Semantics(
      label: '${l10n.loudnessHistoryLabel}, −60 – 0 dBFS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.loudnessHistoryLabel, style: labelStyle),
          const SizedBox(height: 4),
          SizedBox(
            height: (wide ? 82 : 76) + (textScaler.scale(10) - 10) * 3,
            width: double.infinity,
            child: CustomPaint(
              key: const ValueKey('loudness.history'),
              painter: _LoudnessHistoryPainter(
                _signal,
                labelStyle,
                textScaler,
                [
                  for (final seconds in [-6, -4, -2, 0])
                    l10n.secondsShort(seconds).replaceAll('-', '−'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoudnessScalePainter extends CustomPainter {
  _LoudnessScalePainter(this.signal, this.scaleStyle) : super(repaint: signal);
  final LoudnessMeterModel signal;
  final TextStyle scaleStyle;
  static Color colorAt(double position) => position >= 0.95
      ? const Color(0xFFC97564)
      : position >= 0.8
      ? const Color(0xFFC19C56)
      : const Color(0xFF398775);

  @override
  void paint(Canvas canvas, Size size) {
    final count = (size.width / 7).floor().clamp(24, 96);
    final cell = size.width / count;
    final fill = LoudnessMeterModel.position(signal.levelDb);
    for (var i = 0; i < count; i++) {
      final ratio = (i + 0.5) / count;
      final lit = signal.active && ratio <= fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * cell, 0, cell - 2, 12),
          const Radius.circular(1.5),
        ),
        Paint()..color = colorAt(ratio).withValues(alpha: lit ? 1 : 0.12),
      );
    }
    if (signal.active && signal.peakDb > LoudnessMeterModel.floorDb) {
      final x = (size.width * LoudnessMeterModel.position(signal.peakDb)).clamp(
        1.0,
        size.width - 1,
      );
      canvas.drawLine(
        Offset(x, -2),
        Offset(x, 14),
        Paint()
          ..color = const Color(0xFF173D34)
          ..strokeWidth = 2,
      );
    }
    final marks = size.width < 400
        ? [-60, -36, -12, 0]
        : [-60, -48, -36, -24, -12, 0];
    for (final db in marks) {
      final text = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(text: db == 0 ? '0' : '−${db.abs()}', style: scaleStyle),
      )..layout();
      final x =
          (size.width * LoudnessMeterModel.position(db.toDouble()) -
                  text.width / 2)
              .clamp(0.0, size.width - text.width);
      text.paint(canvas, Offset(x, 20));
    }
  }

  @override
  bool shouldRepaint(covariant _LoudnessScalePainter oldDelegate) =>
      oldDelegate.signal != signal || oldDelegate.scaleStyle != scaleStyle;
}

class _LoudnessHistoryPainter extends CustomPainter {
  _LoudnessHistoryPainter(
    this.signal,
    this.labelStyle,
    this.textScaler,
    this.timeLabels,
  ) : super(repaint: signal);

  final LoudnessMeterModel signal;
  final TextStyle labelStyle;
  final TextScaler textScaler;
  final List<String> timeLabels;

  TextPainter _label(String value) => TextPainter(
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
    text: TextSpan(text: value, style: labelStyle),
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final levelLabels = [
      for (final value in ['0', '−30', '−60']) _label(value),
    ];
    final times = [for (final value in timeLabels) _label(value)];
    final labelHeight = levelLabels.first.height;
    final labelWidth = levelLabels.last.width;
    final plot = Rect.fromLTRB(
      labelWidth + 9,
      labelHeight / 2 + 1,
      size.width - 3,
      size.height - times.first.height - 8,
    );
    if (plot.isEmpty) return;
    double yFor(double db) =>
        plot.bottom - plot.height * LoudnessMeterModel.position(db);
    final grid = Paint()
      ..color = const Color(0xFFDCE6E0)
      ..strokeWidth = 1;
    for (var i = 0; i < levelLabels.length; i++) {
      final y = yFor(-30.0 * i);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      final label = levelLabels[i];
      label.paint(
        canvas,
        Offset(plot.left - 9 - label.width, y - label.height / 2),
      );
    }
    final widestTimeLabel = times.fold<double>(
      0,
      (width, label) => label.width > width ? label.width : width,
    );
    // Endpoint labels are inset, so adjacent centered labels need extra room.
    final showInteriorTimes = plot.width >= widestTimeLabel * 4.5 + 24;
    for (var i = 0; i < times.length; i++) {
      final x = plot.left + plot.width * i / (times.length - 1);
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), grid);
      if (!showInteriorTimes && i != 0 && i != times.length - 1) continue;
      final label = times[i];
      label.paint(
        canvas,
        Offset(
          (x - label.width / 2).clamp(plot.left, size.width - label.width),
          plot.bottom + 8,
        ),
      );
    }
    if (signal.history.isEmpty) return;

    // The viewport is exactly 6 seconds (120 intervals). Two guard samples
    // preserve the curve crossing its left edge when old history is discarded.
    final points = <Offset>[];
    final step = plot.width / LoudnessMeterModel.historyIntervals;
    for (var i = 0; i < signal.history.length; i++) {
      final x =
          plot.right -
          (signal.history.length - 1 - i + signal.historyPhase) * step;
      points.add(Offset(x, yFor(signal.history[i])));
    }
    if (signal.active && signal.historyPhase > 0) {
      points.add(Offset(plot.right, yFor(signal.currentDb)));
    }
    final trace = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final point = points[i];
      final mid = (previous.dx + point.dx) / 2;
      trace.cubicTo(mid, previous.dy, mid, point.dy, point.dx, point.dy);
    }
    final tint = signal.active
        ? const Color(0xFF267B69)
        : const Color(0xFF91A89C);
    final fill = Path.from(trace)
      ..lineTo(points.last.dx, plot.bottom)
      ..lineTo(points.first.dx, plot.bottom)
      ..close();
    canvas.save();
    canvas.clipRect(plot);
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tint.withValues(alpha: 0.16), tint.withValues(alpha: 0.015)],
        ).createShader(plot),
    );
    canvas.drawPath(
      trace,
      Paint()
        ..color = tint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
    if (signal.active) {
      canvas.drawCircle(points.last, 2.7, Paint()..color = tint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LoudnessHistoryPainter oldDelegate) =>
      oldDelegate.signal != signal ||
      oldDelegate.labelStyle != labelStyle ||
      oldDelegate.textScaler != textScaler ||
      !listEquals(oldDelegate.timeLabels, timeLabels);
}
