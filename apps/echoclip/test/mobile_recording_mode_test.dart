import 'dart:async';

import 'package:echoclip/l10n/app_localizations.dart';
import 'package:echoclip/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('com.echoclip/replay_service');
const _modeKey = ValueKey('recording.modeMenu');

void main() {
  for (final language in ['en', 'zh']) {
    testWidgets(
      'mobile lock mode stops and switches back with scheduler alive ($language)',
      (tester) async {
        final backend = _MobileBackend();
        await _mount(tester, backend, language);
        await _selectMode(tester, RecordingMode.lockscreen);
        expect(
          _buttonIcon(tester),
          Icons.play_arrow,
          reason: 'a resident scheduler is not armed lock recording',
        );
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pump();
        expect(backend.starts, 1);
        expect(_buttonIcon(tester), Icons.pause);
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(backend.stops, 1);
        expect(
          _buttonIcon(tester),
          Icons.play_arrow,
          reason: 'polling a scheduler-only service must not restore pause',
        );
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pump();
        expect(
          backend.starts,
          2,
          reason: 'the stopped lock session must be restartable',
        );
        await _selectMode(tester, RecordingMode.standard);
        await tester.pump(const Duration(seconds: 1));
        final menu = tester.widget<PopupMenuButton<RecordingMode>>(
          find.byKey(_modeKey),
        );
        expect(menu.initialValue, RecordingMode.standard);
        expect(_buttonIcon(tester), Icons.play_arrow);
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pump();
        expect(backend.running, isTrue);
        expect(backend.mode, 'standard');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets('late old status and meter replies cannot undo a mode change', (
    tester,
  ) async {
    final backend = _MobileBackend();
    await _mount(tester, backend, 'en');
    await _selectMode(tester, RecordingMode.lockscreen);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    final old = backend.snapshot;
    backend.holdPolls = true;
    await tester.pump(const Duration(seconds: 1));
    expect(
      backend.polls.keys,
      containsAll(['getReplayStatus', 'getMeterStatus']),
    );
    await _selectMode(tester, RecordingMode.standard);
    backend.holdPolls = false;
    for (final pending in backend.polls.values) {
      pending.complete(old);
    }
    await tester.pump();
    expect(
      tester
          .widget<PopupMenuButton<RecordingMode>>(find.byKey(_modeKey))
          .initialValue,
      RecordingMode.standard,
    );
    expect(_buttonIcon(tester), Icons.play_arrow);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'pending start blocks duplicate commands until permission response',
    (tester) async {
      final backend = _MobileBackend();
      await _mount(tester, backend, 'en');
      await _selectMode(tester, RecordingMode.lockscreen);
      backend.startGate = Completer<void>();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      expect(
        tester
            .widget<FloatingActionButton>(find.byType(FloatingActionButton))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<PopupMenuButton<RecordingMode>>(find.byKey(_modeKey))
            .enabled,
        isFalse,
      );
      expect(backend.starts, 1);
      backend.startGate!.complete();
      await tester.pump();
      expect(_buttonIcon(tester), Icons.pause);
      expect(
        tester
            .widget<FloatingActionButton>(find.byType(FloatingActionButton))
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );
}

Future<void> _mount(
  WidgetTester tester,
  _MobileBackend backend,
  String language,
) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, backend.call);
  addTearDown(() {
    debugDefaultTargetPlatformOverride = null;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(language),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: EchoClipHome(
        languageMode: language == 'zh'
            ? UiLanguageMode.chinese
            : UiLanguageMode.english,
        onLanguageModeChanged: (_) async {},
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _selectMode(WidgetTester tester, RecordingMode mode) async {
  await tester.tap(find.byKey(_modeKey));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.tap(
    find.byWidgetPredicate(
      (widget) =>
          widget is PopupMenuItem<RecordingMode> && widget.value == mode,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

IconData? _buttonIcon(WidgetTester tester) => tester
    .widget<Icon>(
      find.descendant(
        of: find.byType(FloatingActionButton),
        matching: find.byType(Icon),
      ),
    )
    .icon;

class _MobileBackend {
  String mode = 'standard';
  String evidence = 'off';
  bool running = false;
  int starts = 0;
  int stops = 0;
  bool holdPolls = false;
  final polls = <String, Completer<Map<String, Object?>>>{};
  Completer<void>? startGate;

  Map<String, Object?> get snapshot => {
    'running': running,
    'serviceActive': true, // The scheduler intentionally remains resident.
    'recordingMode': mode,
    'lockRecordingTrigger': 'screen_off',
    'evidenceState': evidence,
    'serviceState': mode == 'standard'
        ? (running ? 'standard_recording' : 'standard_paused')
        : (evidence == 'armed' ? 'lockscreen_armed' : 'stopped'),
    'availableMillis': 0,
  };

  Future<Object?> call(MethodCall call) async {
    switch (call.method) {
      case 'getRecordingFolder':
        return {'selected': true, 'uri': 'content://test/recordings'};
      case 'listRecordings':
      case 'listGroups':
        return <Object?>[];
      case 'getRecordingModeSettings':
        return {'mode': mode, 'trigger': 'screen_off'};
      case 'setRecordingModeSettings':
        mode = (call.arguments as Map)['mode'] as String;
        running = false;
        evidence = 'off';
        return snapshot;
      case 'getReplayStatus':
      case 'getMeterStatus':
        if (holdPolls && !polls.containsKey(call.method)) {
          return (polls[call.method] ??= Completer<Map<String, Object?>>())
              .future;
        }
        return snapshot;
      case 'startReplay':
        starts++;
        await startGate?.future;
        running = mode == 'standard';
        evidence = mode == 'lockscreen' ? 'armed' : 'off';
        return snapshot;
      case 'stopReplay':
        stops++;
        running = false;
        evidence = 'off';
        return snapshot;
      default:
        return <String, Object?>{};
    }
  }
}
