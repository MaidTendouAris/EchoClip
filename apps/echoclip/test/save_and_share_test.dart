import 'dart:async';
import 'package:echoclip/main.dart';
import 'package:echoclip/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const channel = MethodChannel('com.echoclip/replay_service');
final save = find.byKey(const ValueKey('save.submit'));

void main() {
  for (final lang in ['zh', 'en']) {
    testWidgets(
      'paused save reports actual progress without moving content ($lang)',
      (tester) async {
        final backend = Backend();
        await mount(tester, backend, lang);
        final l10n = lookupAppLocalizations(Locale(lang));
        final meterTop = tester.getTopLeft(find.byType(LoudnessMeter));
        final buttonRect = tester.getRect(save);
        final refreshes = backend.refreshes;
        await tester.tap(save);
        await tester.pump();
        expect(backend.starts, 1);
        expect(
          tester
              .widget<CircularProgressIndicator>(
                find.byKey(const ValueKey('save.progress')),
              )
              .value,
          isNull,
        );
        expect(tester.getRect(save), buttonRect);
        backend.phase = 'CopyingToSaf';
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump();
        expect(find.text(l10n.saveWritingProgress(40)), findsOneWidget);
        expect(
          tester
              .widget<CircularProgressIndicator>(
                find.byKey(const ValueKey('save.progress')),
              )
              .value,
          .4,
        );
        expect(
          backend.refreshes,
          refreshes,
          reason: 'no guessed completion delay',
        );
        backend.phase = 'Finished';
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump();
        expect(backend.refreshes, refreshes + 1);
        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.text(l10n.clipSaved),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('save.status')),
            matching: find.text(l10n.clipSaved),
          ),
          findsOneWidget,
        );
        expect(tester.getTopLeft(find.byType(LoudnessMeter)), meterTop);
        expect(tester.getRect(save), buttonRect);
        await tester.pump(const Duration(seconds: 4));
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text(l10n.clipSaved), findsNothing);
        expect(find.text(l10n.saveRecentLabel), findsOneWidget);
        expect(tester.getRect(save), buttonRect);
        await finish(tester);
      },
    );

    testWidgets('second click cancels pending and copying jobs ($lang)', (
      tester,
    ) async {
      final backend = Backend()..gate = Completer<void>();
      await mount(tester, backend, lang);
      final l10n = lookupAppLocalizations(Locale(lang));
      await tester.tap(save);
      await tester.pump();
      await tester.tap(save);
      await tester.pump();
      expect(find.text(l10n.saveCanceling), findsOneWidget);
      expect(backend.starts, 1);
      expect(backend.cancels, 0);
      backend.gate!.complete();
      await tester.pump();
      expect(backend.cancels, 1);
      expect(backend.canceledId, 17);
      expect(find.text(l10n.saveCanceled), findsOneWidget);
      backend.gate = null;
      backend.phase = 'CopyingToSaf';
      await tester.tap(save);
      await tester.pump();
      await tester.tap(save);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(backend.starts, 2);
      expect(backend.cancels, 2);
      expect(find.byKey(const ValueKey('save.progress')), findsNothing);
      await finish(tester);
    });

    testWidgets(
      'share uses the selected audio URI and reports permission errors ($lang)',
      (tester) async {
        final backend = Backend();
        await mount(tester, backend, lang);
        final l10n = lookupAppLocalizations(Locale(lang));
        await tester.tap(find.byType(NavigationDestination).at(1));
        await tester.pumpAndSettle();
        for (final name in ['sample.mp3', 'sample.wav']) {
          await tester.tap(
            find.byKey(ValueKey('library.actions.content://recordings/$name')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text(l10n.shareRecording));
          await tester.pumpAndSettle();
          expect(backend.share?['uri'], 'content://recordings/$name');
          expect(backend.share?['name'], name);
          expect(backend.share?['title'], l10n.shareRecording);
        }
        backend.shareOk = false;
        await tester.tap(
          find.byKey(
            const ValueKey('library.actions.content://recordings/sample.mp3'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.shareRecording));
        await tester.pumpAndSettle();
        expect(find.text(l10n.shareRecordingFailed), findsOneWidget);
        await finish(tester);
      },
    );
  }

  testWidgets(
    'an immediate export result stays successful if list refresh fails',
    (tester) async {
      final backend = Backend()..pending = false;
      await mount(tester, backend, 'en');
      backend.failRefresh = true;
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.tap(save);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(l10n.clipSaved), findsOneWidget);
      expect(find.byKey(const ValueKey('save.progress')), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      await finish(tester);
    },
  );

  testWidgets(
    'a new save clears old feedback and owns its full expiry interval',
    (tester) async {
      final backend = Backend()..phase = 'Finished';
      await mount(tester, backend, 'en');
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.tap(save);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      backend.phase = 'Exporting';
      await tester.tap(save);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(l10n.clipSaved), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('save.status')),
          matching: find.text(l10n.saveStarted),
        ),
        findsOneWidget,
      );
      backend.phase = 'Finished';
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.text(l10n.clipSaved), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(l10n.saveRecentLabel), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      await finish(tester);
    },
  );

  testWidgets(
    'inline errors retain details, expire, and are cleared on retry',
    (tester) async {
      final backend = Backend()..phase = 'Failed';
      await mount(tester, backend, 'en');
      final l10n = lookupAppLocalizations(const Locale('en'));
      final buttonRect = tester.getRect(save);
      await tester.tap(save);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(l10n.saveFailedStatus), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      final status = find.byKey(const ValueKey('save.status'));
      final semantics = tester.widget<Semantics>(status);
      expect(semantics.properties.liveRegion, isTrue);
      expect(semantics.properties.label, contains('write_failed'));
      final tooltip = tester.widget<Tooltip>(
        find.descendant(of: status, matching: find.byType(Tooltip)),
      );
      expect(tooltip.message, contains('write_failed'));
      await tester.pump(const Duration(seconds: 7));
      expect(find.text(l10n.saveFailedStatus), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(l10n.saveRecentLabel), findsOneWidget);
      backend.phase = 'Finished';
      await tester.tap(save);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(l10n.clipSaved), findsOneWidget);
      expect(tester.getRect(save), buttonRect);
      await finish(tester);
    },
  );

  testWidgets(
    'save completion on another page remains in the home status line',
    (tester) async {
      final backend = Backend();
      await mount(tester, backend, 'zh');
      final l10n = lookupAppLocalizations(const Locale('zh'));
      await tester.tap(save);
      await tester.pump();
      await tester.tap(find.byType(NavigationDestination).at(1));
      await tester.pump(const Duration(milliseconds: 400));
      backend.phase = 'Finished';
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);
      await tester.tap(find.byType(NavigationDestination).at(0));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(l10n.clipSaved), findsOneWidget);
      await finish(tester);
    },
  );

  testWidgets('late cancel error cannot reactivate a finished save', (
    tester,
  ) async {
    final backend = Backend()..cancelGate = Completer<Object?>();
    await mount(tester, backend, 'en');
    await tester.tap(save);
    await tester.pump();
    await tester.tap(save);
    await tester.pump();
    backend.phase = 'Finished';
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.byKey(const ValueKey('save.progress')), findsNothing);
    backend.cancelGate!.completeError(PlatformException(code: 'late_reply'));
    await tester.pump();
    expect(find.byKey(const ValueKey('save.progress')), findsNothing);
    await finish(tester);
  });

  testWidgets(
    'failed save can retry and changing tabs does not create another job',
    (tester) async {
      final backend = Backend();
      await mount(tester, backend, 'en');
      await tester.tap(save);
      await tester.pump();
      await tester.tap(find.byType(NavigationDestination).at(1));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byType(NavigationDestination).at(0));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('save.progress')), findsOneWidget);
      expect(backend.starts, 1);
      backend.phase = 'Failed';
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(find.byKey(const ValueKey('save.progress')), findsNothing);
      backend.phase = 'Finished';
      await tester.tap(save);
      await tester.pump();
      expect(backend.starts, 2);
      await finish(tester);
    },
  );
}

Future<void> finish(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 200));
  debugDefaultTargetPlatformOverride = null;
}

Future<void> mount(WidgetTester tester, Backend backend, String lang) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  tester.view.physicalSize = const Size(400, 1100);
  tester.view.devicePixelRatio = 1;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, backend.call);
  addTearDown(() {
    debugDefaultTargetPlatformOverride = null;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(lang),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: EchoClipHome(
        languageMode: UiLanguageMode.system,
        onLanguageModeChanged: (_) async {},
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.ensureVisible(save);
}

class Backend {
  String phase = 'Exporting';
  bool pending = true;
  bool failRefresh = false;
  int starts = 0, cancels = 0, refreshes = 0;
  int? canceledId;
  Completer<void>? gate;
  Completer<Object?>? cancelGate;
  Map? share;
  bool shareOk = true;
  Future<Object?> call(MethodCall call) async {
    switch (call.method) {
      case 'getRecordingFolder':
        return {'selected': true, 'uri': 'content://recordings'};
      case 'listGroups':
        if (failRefresh) throw PlatformException(code: 'list_unavailable');
        return <Object?>[];
      case 'listRecordings':
        refreshes++;
        return [
          for (final name in ['sample.mp3', 'sample.wav'])
            {
              'name': name,
              'uri': 'content://recordings/$name',
              'lastModified': 1,
              'size': 50000,
            },
        ];
      case 'getReplayStatus':
      case 'getMeterStatus':
        return {
          'running': false,
          'serviceActive': false,
          'serviceState': 'stopped',
          'availableMillis': 300000,
        };
      case 'saveReplayClip':
        starts++;
        await gate?.future;
        return {'saved': true, 'pending': pending, 'jobId': 17};
      case 'getSaveJob':
        return {
          'state': phase,
          'progress': .4,
          'error': phase == 'Failed' ? 'write_failed' : null,
        };
      case 'cancelSaveJob':
        cancels++;
        canceledId = (call.arguments as Map)['jobId'] as int;
        if (cancelGate != null) return cancelGate!.future;
        phase = 'Canceled';
        return {'canceled': true};
      case 'shareRecording':
        share = call.arguments as Map;
        return {'ok': shareOk};
      default:
        return <String, Object?>{};
    }
  }
}
