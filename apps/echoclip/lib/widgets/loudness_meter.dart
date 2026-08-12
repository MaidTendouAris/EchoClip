part of '../main.dart';

class LoudnessMeter extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalizedLevel = isRecording
        ? level.clamp(0.0, 1.0).toDouble()
        : 0.0;
    final normalizedPeak = isRecording
        ? math.max(peakLevel, normalizedLevel).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final dbText = normalizedLevel <= 0.001
        ? '-∞ dB'
        : '${(20 * math.log(normalizedLevel) / math.ln10).clamp(-60, 0).toStringAsFixed(0)} dB';

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: normalizedLevel),
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOutCubic,
      builder: (context, animatedLevel, _) {
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: normalizedPeak),
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          builder: (context, animatedPeak, _) {
            return _buildMeter(
              context: context,
              theme: theme,
              dbText: dbText,
              level: animatedLevel,
              peakLevel: animatedPeak,
            );
          },
        );
      },
    );
  }

  Widget _buildMeter({
    required BuildContext context,
    required ThemeData theme,
    required String dbText,
    required double level,
    required double peakLevel,
  }) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4F3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0E7E5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.graphic_eq, color: Color(0xFF1B7F79)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.loudnessTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text(
                dbText,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF52615E),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          RepaintBoundary(
            child: SizedBox(
              height: 46,
              width: double.infinity,
              child: CustomPaint(
                painter: _LoudnessMeterPainter(
                  level: level,
                  peakLevel: peakLevel,
                  active: isRecording,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoudnessMeterPainter extends CustomPainter {
  const _LoudnessMeterPainter({
    required this.level,
    required this.peakLevel,
    required this.active,
  });

  final double level;
  final double peakLevel;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final track = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(8),
    );
    canvas.drawRRect(track, Paint()..color = Colors.white);

    final segmentWidth = 5.0;
    final gap = 3.0;
    final segmentCount = math.max(
      1,
      (size.width / (segmentWidth + gap)).floor(),
    );
    final activeCount = (segmentCount * level).round();
    final peakIndex = (segmentCount * peakLevel).round().clamp(0, segmentCount);

    for (var index = 0; index < segmentCount; index++) {
      final ratio = index / math.max(1, segmentCount - 1);
      final x = index * (segmentWidth + gap);
      final segmentHeight = size.height * (0.36 + ratio * 0.54);
      final top = (size.height - segmentHeight) / 2;
      final isLit = active && index < activeCount;
      final paint = Paint()
        ..color = isLit ? _levelColor(ratio) : const Color(0xFFD9E1DF);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, top, segmentWidth, segmentHeight),
          const Radius.circular(3),
        ),
        paint,
      );
    }

    if (active && peakIndex > 0) {
      final x = ((peakIndex - 1) * (segmentWidth + gap)).clamp(
        0.0,
        size.width - 2,
      );
      final peakPaint = Paint()
        ..color = const Color(0xFF171A1D)
        ..strokeWidth = 2;
      canvas.drawLine(Offset(x, 4), Offset(x, size.height - 4), peakPaint);
    }
  }

  Color _levelColor(double ratio) {
    if (ratio > 0.82) {
      return const Color(0xFFD94B3D);
    }
    if (ratio > 0.62) {
      return const Color(0xFFE3A72F);
    }
    return const Color(0xFF1B7F79);
  }

  @override
  bool shouldRepaint(covariant _LoudnessMeterPainter oldDelegate) {
    return oldDelegate.level != level ||
        oldDelegate.peakLevel != peakLevel ||
        oldDelegate.active != active;
  }
}
