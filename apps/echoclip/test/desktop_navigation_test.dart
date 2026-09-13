import 'package:echoclip/l10n/app_localizations.dart';
import 'package:echoclip/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _desktopNavigationKey = ValueKey<String>('navigation.desktop');
const _recorderDestinationKey = ValueKey<String>('navigation.desktop.recorder');
const _serverIndicatorKey = ValueKey<String>('server.connectionIndicator');
const _recordingModeKey = ValueKey<String>('recording.modeMenu');
const _desktopTestSizes = <Size>[Size(800, 700), Size(1440, 900)];

void main() {
  testWidgets('desktop platforms keep one horizontal side navigation at '
      'narrow and wide widths', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    try {
      for (final platform in const [
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        for (final size in _desktopTestSizes) {
          tester.view.physicalSize = size;
          await tester.pumpWidget(_testApp());

          expect(find.byKey(_desktopNavigationKey), findsOneWidget);
          expect(find.text('Scheduled tasks'), findsOneWidget);
          expect(find.text('Processing'), findsNothing);
          expect(find.byType(NavigationBar), findsNothing);
          expect(
            tester.getCenter(find.byKey(_serverIndicatorKey)).dx,
            lessThan(tester.getCenter(find.byKey(_recordingModeKey)).dx),
            reason: 'server state dot must remain left of the mode switch',
          );
          final serverIndicator = find.byKey(_serverIndicatorKey);
          expect(
            find.descendant(of: serverIndicator, matching: find.byType(Text)),
            findsNothing,
            reason: 'the home indicator must not keep a status label visible',
          );
          final dot = tester.widget<Container>(
            find.descendant(
              of: serverIndicator,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Container &&
                    widget.constraints?.maxWidth == 12 &&
                    widget.constraints?.maxHeight == 12,
              ),
            ),
          );
          expect((dot.decoration! as BoxDecoration).shape, BoxShape.circle);

          final destination = find.byKey(_recorderDestinationKey);
          final icon = find.descendant(
            of: destination,
            matching: find.byType(Icon),
          );
          final label = find.descendant(
            of: destination,
            matching: find.text('Home'),
          );
          expect(destination, findsOneWidget);
          expect(
            find.descendant(of: destination, matching: find.byType(Row)),
            findsOneWidget,
          );
          expect(icon, findsOneWidget);
          expect(label, findsOneWidget);
          expect(
            (tester.getCenter(icon).dy - tester.getCenter(label).dy).abs(),
            lessThan(1),
            reason: '$platform at $size must keep icon and label inline',
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '$platform at $size must render without overflow',
          );

          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop scheduled task editor opens as a second-level page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    try {
      await tester.pumpWidget(_testApp());
      await tester.tap(find.text('Scheduled tasks'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('New task'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.byKey(const ValueKey<String>('schedule.editor.page')),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.text('Run time'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('schedule.countdown.wheels')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('mobile portrait keeps the bottom navigation', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    try {
      await tester.pumpWidget(_testApp());

      expect(find.byKey(_desktopNavigationKey), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(
        tester.getCenter(find.byKey(_serverIndicatorKey)).dx,
        lessThan(tester.getCenter(find.byKey(_recordingModeKey)).dx),
      );
      expect(
        find.descendant(
          of: find.byKey(_serverIndicatorKey),
          matching: find.byType(Text),
        ),
        findsNothing,
      );
      await tester.tap(find.text('Scheduled tasks'));
      await tester.pump();
      expect(find.text('New task'), findsOneWidget);
      expect(
        find.text(
          'Run recording, save, and live-upload actions after a countdown '
          'or at a chosen time',
        ),
        findsNothing,
      );
      expect(find.textContaining('Scheduling precision:'), findsNothing);
      expect(find.text('Recording folder ready'), findsNothing);
      await tester.tap(find.text('New task'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('schedule.editor.page')),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Countdown'), findsOneWidget);
      expect(find.text('Time point'), findsOneWidget);
      expect(find.text('Recording action'), findsOneWidget);
      expect(find.text('Live upload'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('schedule.countdown.hours')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('schedule.countdown.minutes')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('schedule.countdown.seconds')),
        findsOneWidget,
      );
      expect(
        _wheelItemCount(tester, 'schedule.countdown.hours'),
        24,
        reason: 'countdown hours must be limited to 0-23',
      );
      expect(_wheelItemCount(tester, 'schedule.countdown.minutes'), 60);
      expect(_wheelItemCount(tester, 'schedule.countdown.seconds'), 60);
      expect(
        find.byKey(const ValueKey<String>('schedule.action.recording')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('schedule.action.upload')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('schedule.action.saveRecent')),
        findsOneWidget,
      );

      final recordingSwitch = find.descendant(
        of: find.byKey(const ValueKey<String>('schedule.action.recording')),
        matching: find.byType(Switch),
      );
      final editorList = find.descendant(
        of: find.byKey(const ValueKey<String>('schedule.editor.page')),
        matching: find.byType(ListView),
      );
      await Scrollable.ensureVisible(
        tester.element(recordingSwitch),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(recordingSwitch);
      await tester.pumpAndSettle();
      expect(find.text('Start recording'), findsOneWidget);
      expect(find.text('Stop recording'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final uploadSwitch = find.descendant(
        of: find.byKey(const ValueKey<String>('schedule.action.upload')),
        matching: find.byType(Switch),
      );
      await Scrollable.ensureVisible(
        tester.element(uploadSwitch),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(uploadSwitch);
      await tester.pumpAndSettle();
      expect(find.text('Enable upload'), findsOneWidget);
      expect(find.text('Disable upload'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final saveSwitch = find.descendant(
        of: find.byKey(const ValueKey<String>('schedule.action.saveRecent')),
        matching: find.byType(Switch),
      );
      await Scrollable.ensureVisible(
        tester.element(saveSwitch),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(saveSwitch);
      await tester.pumpAndSettle();
      expect(find.text('Save duration (seconds)'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.drag(editorList, const Offset(0, 1600));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Time point'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('schedule.countdown.wheels')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('schedule.timePoint.date')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('schedule.timePoint.hours')),
        findsOneWidget,
      );
      expect(_wheelItemCount(tester, 'schedule.timePoint.hours'), 24);
      expect(_wheelItemCount(tester, 'schedule.timePoint.minutes'), 60);
      expect(_wheelItemCount(tester, 'schedule.timePoint.seconds'), 60);
      expect(
        tester.takeException(),
        isNull,
        reason: 'mobile portrait must render without overflow',
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Widget _testApp() {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: EchoClipHome(
      languageMode: UiLanguageMode.english,
      onLanguageModeChanged: (_) async {},
    ),
  );
}

int? _wheelItemCount(WidgetTester tester, String key) {
  final wheel = tester.widget<ListWheelScrollView>(
    find.descendant(
      of: find.byKey(ValueKey<String>(key)),
      matching: find.byType(ListWheelScrollView),
    ),
  );
  return (wheel.childDelegate as ListWheelChildBuilderDelegate).childCount;
}
