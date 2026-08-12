import 'package:echoclip/l10n/app_localizations.dart';
import 'package:echoclip/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _desktopNavigationKey = ValueKey<String>('navigation.desktop');
const _recorderDestinationKey = ValueKey<String>('navigation.desktop.recorder');
const _desktopTestSizes = <Size>[
  Size(800, 700),
  Size(1440, 900),
];

void main() {
  testWidgets('desktop platforms keep one horizontal side navigation at '
      'narrow and wide widths', (
    tester,
  ) async {
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
          expect(find.byType(NavigationBar), findsNothing);

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
