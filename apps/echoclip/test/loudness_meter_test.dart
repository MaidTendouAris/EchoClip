import 'dart:ui' as ui;
import 'package:echoclip/main.dart';
import 'package:echoclip/l10n/app_localizations.dart';
import 'package:echoclip/widgets/loudness_meter_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'linear amplitudes have calibrated dB values and useful low-level positions',
    () {
      expect(LoudnessMeterModel.amplitudeToDb(0.1), closeTo(-20, 0.001));
      expect(LoudnessMeterModel.amplitudeToDb(0.5), closeTo(-6.0206, 0.001));
      expect(LoudnessMeterModel.amplitudeToDb(1), 0);
      expect(LoudnessMeterModel.position(-30), 0.5);
      expect(LoudnessMeterModel.position(-60), 0);
      expect(
        LoudnessMeterModel.amplitudeToDb(double.nan),
        double.negativeInfinity,
      );
      expect(LoudnessMeterModel.amplitudeToDb(0), double.negativeInfinity);
    },
  );

  test(
    'meter rises quickly, releases gently and holds the independent peak',
    () {
      final model = LoudnessMeterModel();
      addTearDown(model.dispose);
      model.setInput(0.1, 1, recording: true);
      model.advance(const Duration(milliseconds: 100));
      expect(model.levelDb, greaterThan(-23));
      expect(model.peakDb, 0);
      model.setInput(0.001, 0.001, recording: true);
      model.advance(const Duration(milliseconds: 100));
      expect(model.levelDb, greaterThan(-40));
      expect(model.peakDb, 0);
      for (var i = 0; i < 12; i++) {
        model.advance(const Duration(milliseconds: 100));
      }
      expect(model.peakDb, lessThan(0));
      expect(model.peakDb, greaterThan(model.levelDb));
    },
  );

  test('history uses time samples, stays bounded, and freezes on pause', () {
    final model = LoudnessMeterModel();
    addTearDown(model.dispose);
    model.setInput(0.1, 0.2, recording: true);
    for (var i = 0; i < 160; i++) {
      model.advance(const Duration(milliseconds: 50));
    }
    expect(model.history.length, 122);
    expect(model.history.every((db) => (db + 20).abs() < 0.001), isTrue);
    model.advance(const Duration(milliseconds: 25));
    expect(model.historyPhase, closeTo(0.5, 0.001));
    final history = List.of(model.history);
    model.setInput(1, 1, recording: false);
    model.advance(const Duration(seconds: 1));
    expect(model.history, history);
    expect(model.reading.value.active, isFalse);
    expect(model.levelDb, -60);
    model.setInput(0.01, 0.1, recording: true);
    expect(model.history, isEmpty);
    model.advance(const Duration(milliseconds: 50), animate: false);
    expect(model.levelDb, closeTo(-40, 0.001));
    model.advance(const Duration(seconds: 8));
    expect(
      model.history.length,
      1,
      reason: 'unknown offscreen time must not fabricate a trace',
    );
  });

  testWidgets(
    'meter fits Chinese and English narrow, wide and enlarged layouts',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final lang in ['zh', 'en']) {
        for (final width in [280.0, 400.0, 960.0]) {
          for (final scale in [1.0, 2.0]) {
            tester.view.physicalSize = Size(width, 700);
            await tester.pumpWidget(
              MaterialApp(
                locale: Locale(lang),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: const Scaffold(
                    body: Padding(
                      padding: EdgeInsets.all(12),
                      child: LoudnessMeter(
                        level: 0.1,
                        peakLevel: 0.5,
                        isRecording: true,
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pump(const Duration(milliseconds: 200));
            expect(find.text('dBFS'), findsOneWidget);
            expect(
              tester.takeException(),
              isNull,
              reason: '$lang, $width, text scale $scale',
            );
            await tester.pumpWidget(const SizedBox.shrink());
          }
        }
      }
    },
  );

  testWidgets('status depends only on recording in both languages', (
    tester,
  ) async {
    for (final lang in ['zh', 'en']) {
      for (final recording in [true, false]) {
        for (final level in [0.0, 0.001, 0.1, 1.0]) {
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(lang),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: LoudnessMeter(
                  level: level,
                  peakLevel: level,
                  isRecording: recording,
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 150));
          final expected = lang == 'zh'
              ? (recording ? '录制中' : '未录制')
              : (recording ? 'Recording' : 'Not recording');
          expect(
            tester
                .widget<Text>(find.byKey(const ValueKey('loudness.status')))
                .data,
            expected,
          );
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
    'left curve edge stays fixed through scrolling and sample eviction',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: LoudnessMeter(level: 0.1, peakLevel: 0.2, isRecording: true),
          ),
        ),
      );
      for (var i = 0; i < 160; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      // Include a gutter outside the painter to detect strokes/fill leaking into
      // labels and adjacent content, as well as a gap inside the plot boundary.
      Future<List<int>> captureLeftEdge() async {
        final finder = find.byKey(const ValueKey('loudness.history'));
        final widget = tester.widget<CustomPaint>(finder);
        final size = tester.getSize(finder);
        return (await tester.runAsync(() async {
          final recorder = ui.PictureRecorder();
          final canvas = ui.Canvas(recorder)..translate(30, 0);
          widget.painter!.paint(canvas, size);
          final picture = recorder.endRecording();
          final image = await picture.toImage(
            size.width.ceil() + 60,
            size.height.ceil(),
          );
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
          final pixels = <int>[];
          for (var y = 0; y < image.height; y++) {
            pixels.addAll(
              bytes.sublist(y * image.width * 4, (y * image.width + 130) * 4),
            );
          }
          image.dispose();
          picture.dispose();
          return pixels;
        }))!;
      }

      final reference = await captureLeftEdge();
      // Fractional scroll phases on either side of repeated 50 ms rollovers.
      for (final milliseconds in [13, 24, 12, 1, 17, 32, 1, 25, 25]) {
        await tester.pump(Duration(milliseconds: milliseconds));
        final actual = await captureLeftEdge();
        var changed = 0;
        for (var i = 0; i < reference.length; i++) {
          if (reference[i] != actual[i]) changed++;
        }
        expect(
          changed,
          0,
          reason: 'a constant signal must not move the left edge',
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('paused meter is neutral and schedules no continuing animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: LoudnessMeter(level: 1, peakLevel: 1, isRecording: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Not recording'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
