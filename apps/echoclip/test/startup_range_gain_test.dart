import 'package:echoclip/main.dart';
import 'package:echoclip/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child, String language) => MaterialApp(
  locale: Locale(language),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

void main() {
  testWidgets('WAV range can move across a day but never exceed four hours', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const Scaffold(
          body: BufferRangeDialog(
            window: BufferWindow(
              bufferId: 'wav',
              sampleRate: 1,
              channels: 1,
              startSample: 0,
              endSample: 86400,
            ),
            maxSelectionSeconds: 14400,
          ),
        ),
        'en',
      ),
    );
    await tester.pumpAndSettle();
    var slider = tester.widget<RangeSlider>(find.byType(RangeSlider));
    expect(slider.max, 86400);
    expect(slider.values, const RangeValues(72000, 86400));
    slider.onChanged!(const RangeValues(0, 86400));
    await tester.pump();
    slider = tester.widget<RangeSlider>(find.byType(RangeSlider));
    expect(slider.values, const RangeValues(0, 14400));
    await tester.enterText(find.byKey(const ValueKey('save.rangeEnd.0')), '5');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save.rangeApply')));
    await tester.pump();
    expect(find.byType(BufferRangeDialog), findsOneWidget);
    expect(find.textContaining('4 GB'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('range coordinates are channel aligned and invalid input rejected', () {
    const window = BufferWindow(
      bufferId: 'a',
      sampleRate: 48000,
      channels: 2,
      startSample: 96000,
      endSample: 576000,
    );
    final selection = window.select(2, 4);
    expect(selection.toMap(), {
      'bufferId': 'a',
      'startSample': 288000,
      'endSample': 480000,
    });
    expect(() => window.select(1.5, 3), throwsFormatException);
    expect(() => window.select(1, 3.5), throwsFormatException);
    expect(() => window.select(2, 1), throwsFormatException);
    expect(() => window.select(0, 6), throwsFormatException);
    expect(() => window.select(double.nan, 2), throwsFormatException);
  });

  testWidgets('range slider and HMS fields stay linked in both languages', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final language in ['zh', 'en']) {
      for (final width in [360.0, 1100.0]) {
        tester.view.physicalSize = Size(width, 850);
        await tester.pumpWidget(
          app(
            const Scaffold(
              body: BufferRangeDialog(
                window: BufferWindow(
                  bufferId: 'a',
                  sampleRate: 1000,
                  channels: 1,
                  startSample: 0,
                  endSample: 60000,
                ),
              ),
            ),
            language,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNWidgets(6));
        await tester.enterText(
          find.byKey(const ValueKey('save.rangeEnd.1')),
          '00',
        );
        await tester.enterText(
          find.byKey(const ValueKey('save.rangeStart.2')),
          '10',
        );
        await tester.enterText(
          find.byKey(const ValueKey('save.rangeEnd.2')),
          '40',
        );
        await tester.pump();
        var slider = tester.widget<RangeSlider>(find.byType(RangeSlider));
        expect(slider.values, const RangeValues(10, 40));
        final rect = tester.getRect(find.byType(RangeSlider));
        await tester.dragFrom(
          Offset(rect.left + 24 + (rect.width - 48) / 6, rect.center.dy),
          const Offset(30, 0),
        );
        await tester.pumpAndSettle();
        slider = tester.widget<RangeSlider>(find.byType(RangeSlider));
        expect(slider.values.start, greaterThan(10));
        expect(
          double.parse(
            tester
                .widget<TextField>(
                  find.byKey(const ValueKey('save.rangeStart.2')),
                )
                .controller!
                .text,
          ),
          closeTo(slider.values.start, .001),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });

  testWidgets(
    'whole-second range supports hours and rejects invalid clock fields',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        app(
          const Scaffold(
            body: BufferRangeDialog(
              window: BufferWindow(
                bufferId: 'a',
                sampleRate: 1000,
                channels: 1,
                startSample: 1000,
                endSample: 3696800,
              ),
            ),
          ),
          'en',
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<RangeSlider>(find.byType(RangeSlider)).max, 3695);
      expect(find.text('01:01:35'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('save.rangeStart.0')),
        '1',
      );
      await tester.enterText(
        find.byKey(const ValueKey('save.rangeStart.2')),
        '5',
      );
      await tester.pump();
      expect(
        tester.widget<RangeSlider>(find.byType(RangeSlider)).values.start,
        3605,
      );
      await tester.enterText(
        find.byKey(const ValueKey('save.rangeEnd.2')),
        '60',
      );
      await tester.pump();
      expect(
        find.textContaining('Minutes and seconds must be 0–59'),
        findsOneWidget,
      );
      final slider = tester.widget<RangeSlider>(find.byType(RangeSlider));
      slider.onChanged!(const RangeValues(12.4, 20.6));
      await tester.pump();
      expect(
        tester.widget<RangeSlider>(find.byType(RangeSlider)).values,
        const RangeValues(12, 21),
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('save.rangeStart.2')))
            .controller!
            .text,
        '12',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'startup has only two switches and saves actions without activating',
    (tester) async {
      const channel = MethodChannel('com.echoclip/replay_service');
      final calls = <MethodCall>[];
      var recording = false, upload = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'upsertScheduledTask') {
              final args = (call.arguments as Map)['task'] as Map;
              recording = args['recordingEnabled'] == true;
              upload = args['uploadEnabled'] == true;
            }
            return {
              'ok': true,
              'startupEnabled': true,
              'startupActions': {
                'recordingEnabled': recording,
                'uploadEnabled': upload,
              },
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      for (final language in ['zh', 'en']) {
        await tester.pumpWidget(app(const StartupTasksPage(), language));
        await tester.pumpAndSettle();
        expect(find.byType(SwitchListTile), findsNWidgets(2));
        expect(find.byType(TextField), findsNothing);
        expect(find.byKey(const ValueKey('startup.add')), findsNothing);
        expect(find.byKey(const ValueKey('startup.enabled')), findsNothing);
      }
      await tester.tap(find.byKey(const ValueKey('startup.recording')));
      await tester.pumpAndSettle();
      expect(calls.last.method, 'upsertScheduledTask');
      expect((calls.last.arguments as Map)['task'], {
        'operation': 'set_startup_actions',
        'recordingEnabled': true,
        'uploadEnabled': true,
      });
      await tester.tap(find.byKey(const ValueKey('startup.upload')));
      await tester.pumpAndSettle();
      expect((calls.last.arguments as Map)['task'], {
        'operation': 'set_startup_actions',
        'recordingEnabled': true,
        'uploadEnabled': false,
      });
      expect(calls.any((call) => call.method == 'consumeStartupTasks'), false);
      expect(tester.takeException(), isNull);
    },
  );
}
