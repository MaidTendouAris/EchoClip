import 'dart:async';
import 'package:flutter/services.dart';
import 'dart:ui' show Tristate;

import 'package:echoclip/l10n/app_localizations.dart';
import 'package:echoclip/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const _microphoneKey = ValueKey<String>('settings.microphone');
const _systemAudioKey = ValueKey<String>('settings.systemAudio');
const _inputDeviceKey = ValueKey<String>('settings.inputDevice');
const _refreshDevicesKey = ValueKey<String>('settings.refreshInputDevices');

void main() {
  testWidgets('settings exposes startup switch before opening task details', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = MethodChannel('com.echoclip/replay_service');
    final updates = <bool>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getStartupSettings') {
            return {'ok': true, 'startupEnabled': false};
          }
          if (call.method == 'setStartupEnabled') {
            final enabled = (call.arguments as Map)['enabled'] as bool;
            updates.add(enabled);
            return {'ok': true, 'startupEnabled': enabled};
          }
          return <String, Object?>{};
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    await tester.pumpWidget(_settingsApp());
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('settings.startupEnabled'));
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(updates, [true]);
    expect(tester.widget<SwitchListTile>(toggle).value, true);
    expect(find.byKey(const ValueKey('settings.startup')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('volume slider loads persisted gain and saves mute', (
    tester,
  ) async {
    const channel = MethodChannel('com.echoclip/replay_service');
    final writes = <Map<dynamic, dynamic>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getAudioGains') {
            return {'microphone': 175, 'system': 100};
          }
          if (call.method == 'setAudioGains') {
            writes.add(call.arguments as Map);
            return {'ok': true};
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    await tester.pumpWidget(_settingsApp());
    await tester.pumpAndSettle();
    final finder = find.byKey(const ValueKey('settings.microphoneVolume'));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(finder).value, 175);
    final rect = tester.getRect(finder);
    await tester.dragFrom(
      Offset(rect.left + 24 + (rect.width - 48) * 175 / 300, rect.center.dy),
      Offset(-rect.width, 0),
    );
    await tester.pumpAndSettle();
    expect(writes.single, {'microphone': 0});
    expect(tester.widget<Slider>(finder).value, 0);
  });

  testWidgets('volume drag stays local and precise edits are serialized', (
    tester,
  ) async {
    const channel = MethodChannel('com.echoclip/replay_service');
    final writes = <Map<dynamic, dynamic>>[];
    final pending = <Completer<Map<String, bool>>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getAudioGains') {
            return {'microphone': 100};
          }
          if (call.method == 'setAudioGains') {
            writes.add(call.arguments as Map);
            final reply = Completer<Map<String, bool>>();
            pending.add(reply);
            return reply.future;
          }
          return <String, Object?>{};
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    await tester.pumpWidget(_settingsApp());
    await tester.pumpAndSettle();
    final slider = find.byKey(const ValueKey('settings.microphoneVolume'));
    final field = find.byKey(const ValueKey('settings.microphoneVolumeInput'));
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(slider).divisions, isNull);
    final rect = tester.getRect(slider);
    final drag = await tester.startGesture(
      Offset(rect.left + 24 + (rect.width - 48) / 3, rect.center.dy),
    );
    await drag.moveBy(const Offset(50, 0));
    await tester.pump();
    await drag.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(writes, isEmpty);
    await drag.up();
    await tester.pump();
    expect(writes, hasLength(1));
    expect(tester.widget<Slider>(slider).onChanged, isNotNull);
    await tester.enterText(field, '300');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.enterText(field, '225');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(writes, hasLength(1));
    pending.first.complete({'ok': true});
    await tester.pump();
    await tester.pump();
    expect(writes.last, {'microphone': 225});
    pending.last.complete({'ok': true});
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(slider).value, 225);
    await tester.enterText(field, '301');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('Enter a whole number from 0 to 300.'), findsOneWidget);
    expect(writes, hasLength(2));
  });

  testWidgets('settings footer reads the installed build version', (
    tester,
  ) async {
    const channel = MethodChannel('com.echoclip/app_info');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => {'version': '0.7.1', 'buildNumber': '12'},
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    await tester.pumpWidget(_settingsApp());
    await tester.pumpAndSettle();
    final footer = find.byKey(const ValueKey('settings.version'));
    await tester.scrollUntilVisible(
      footer,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Version · EchoClip 0.7.1 (12)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Windows audio source capabilities enable their controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      _settingsApp(
        systemAudioSupported: true,
        inputDeviceSelectionSupported: true,
        audioInputDevices: const [
          AudioInputDevice(
            id: 'wasapi-mic-1',
            name: 'USB microphone',
            isDefault: true,
          ),
        ],
      ),
    );

    final systemAudio = tester.widget<CheckboxListTile>(
      find.byKey(_systemAudioKey),
    );
    final inputDevice = tester.widget<AppDropdownField<String>>(
      _inputDeviceDropdown(),
    );
    final refreshDevices = tester.widget<IconButton>(
      find.byKey(_refreshDevicesKey),
    );

    expect(systemAudio.onChanged, isNotNull);
    expect(inputDevice.onChanged, isNotNull);
    expect(refreshDevices.onPressed, isNotNull);
  });

  testWidgets('unsupported audio capabilities render disabled controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      _settingsApp(
        systemAudioSupported: false,
        inputDeviceSelectionSupported: false,
      ),
    );

    final systemAudio = tester.widget<CheckboxListTile>(
      find.byKey(_systemAudioKey),
    );
    final inputDevice = tester.widget<AppDropdownField<String>>(
      _inputDeviceDropdown(),
    );
    final refreshDevices = tester.widget<IconButton>(
      find.byKey(_refreshDevicesKey),
    );

    expect(systemAudio.onChanged, isNull);
    expect(inputDevice.onChanged, isNull);
    expect(refreshDevices.onPressed, isNull);

    final systemAudioSemantics = tester.getSemantics(
      find.byKey(_systemAudioKey),
    );
    expect(systemAudioSemantics.flagsCollection.isEnabled, Tristate.isFalse);
  });

  testWidgets('a disconnected selected input is shown as unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      _settingsApp(
        microphoneDeviceId: 'wasapi:disconnected-microphone',
        systemAudioSupported: true,
        inputDeviceSelectionSupported: true,
      ),
    );

    expect(
      find.text('Selected input device is currently unavailable'),
      findsOneWidget,
    );
  });

  testWidgets('the final enabled microphone source cannot be unchecked', (
    tester,
  ) async {
    var updateCalls = 0;
    await tester.pumpWidget(
      _settingsApp(
        microphoneEnabled: true,
        systemAudioEnabled: false,
        systemAudioSupported: true,
        inputDeviceSelectionSupported: true,
        onUpdateAudioSourceSettings:
            ({
              required microphoneEnabled,
              required systemAudioEnabled,
              microphoneDeviceId,
            }) async {
              updateCalls += 1;
            },
      ),
    );

    await tester.ensureVisible(find.byKey(_microphoneKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_microphoneKey));
    await tester.pump();

    expect(updateCalls, 0);
    expect(
      find.text('Keep at least one audio source selected'),
      findsOneWidget,
    );
  });

  testWidgets('the final enabled system source cannot be unchecked', (
    tester,
  ) async {
    var updateCalls = 0;
    await tester.pumpWidget(
      _settingsApp(
        microphoneEnabled: false,
        systemAudioEnabled: true,
        systemAudioSupported: true,
        inputDeviceSelectionSupported: true,
        onUpdateAudioSourceSettings:
            ({
              required microphoneEnabled,
              required systemAudioEnabled,
              microphoneDeviceId,
            }) async {
              updateCalls += 1;
            },
      ),
    );

    await tester.ensureVisible(find.byKey(_systemAudioKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_systemAudioKey));
    await tester.pump();

    expect(updateCalls, 0);
    expect(
      find.text('Keep at least one audio source selected'),
      findsOneWidget,
    );
  });

  testWidgets('buffer duration clamps to 5 through 1440 minutes', (
    tester,
  ) async {
    final saved = <int>[];
    await tester.pumpWidget(
      _settingsApp(
        onUpdateAudioSettings: ({sampleRate, bufferSeconds}) async {
          if (bufferSeconds != null) saved.add(bufferSeconds);
        },
      ),
    );
    final field = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Buffer duration (minutes)',
    );
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    expect(find.text('5 to 1440 minutes'), findsOneWidget);
    for (final entry in {'1': 300, '2000': 86400, '5': 300}.entries) {
      await tester.enterText(field, entry.key);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(saved.last, entry.value);
      expect(
        tester.widget<TextField>(field).controller!.text,
        (entry.value ~/ 60).toString(),
      );
    }
  });

  testWidgets('44.1 kHz can be selected without losing rate precision', (
    tester,
  ) async {
    int? saved;
    await tester.pumpWidget(
      _settingsApp(
        onUpdateAudioSettings: ({sampleRate, bufferSeconds}) async {
          saved = sampleRate;
        },
      ),
    );
    final field = find.byWidgetPredicate(
      (widget) =>
          widget is AppDropdownField<int> &&
          widget.decoration.labelText == 'Sample rate',
    );
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(find.text('44.1 kHz'), findsOneWidget);
    await tester.tap(find.text('44.1 kHz'));
    await tester.pumpAndSettle();
    expect(saved, 44100);
  });

  testWidgets('all six save formats are selectable and WAV shows its limit', (
    tester,
  ) async {
    String? saved;
    await tester.pumpWidget(
      _settingsApp(
        exportFormat: 'wav',
        onExportFormatChanged: (value) async {
          saved = value;
        },
      ),
    );
    final field = find.byKey(const ValueKey('settings.exportFormat'));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    expect(find.textContaining('4 GB'), findsOneWidget);
    await tester.tap(field);
    await tester.pumpAndSettle();
    for (final value in ['MP3', 'FLAC', 'OGG', 'M4A', 'AAC']) {
      expect(find.text(value), findsOneWidget);
    }
    await tester.tap(find.text('FLAC'));
    await tester.pumpAndSettle();
    expect(saved, 'flac');
  });

  testWidgets(
    'Android startup is unavailable and does not expose startup actions',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.pumpWidget(_settingsApp());
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('settings.startupEnabled'));
      expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
      expect(
        find.text('Launch at startup is not supported on this platform yet.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings.startupSilent')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('settings.startup')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('silent startup requires startup and resets when disabled', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = MethodChannel('com.echoclip/replay_service');
    var enabled = false, silent = false;
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'setStartupEnabled') {
            enabled = (call.arguments as Map)['enabled'] == true;
            silent = false;
          }
          if (call.method == 'setStartupSilent') {
            silent = (call.arguments as Map)['silent'] == true;
          }
          return {
            'ok': true,
            'startupSupported': true,
            'startupEnabled': enabled,
            'startupSilent': silent,
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    await tester.pumpWidget(_settingsApp());
    await tester.pumpAndSettle();
    final start = find.byKey(const ValueKey('settings.startupEnabled'));
    final quiet = find.byKey(const ValueKey('settings.startupSilent'));
    expect(tester.widget<SwitchListTile>(quiet).onChanged, isNull);
    await tester.ensureVisible(start);
    await tester.pumpAndSettle();
    await tester.tap(start);
    await tester.pumpAndSettle();
    await tester.ensureVisible(quiet);
    await tester.pumpAndSettle();
    await tester.tap(quiet);
    await tester.pumpAndSettle();
    expect(silent, true);
    expect(tester.widget<SwitchListTile>(quiet).value, true);
    await tester.ensureVisible(start);
    await tester.pumpAndSettle();
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(quiet).value, false);
    expect(tester.widget<SwitchListTile>(quiet).onChanged, isNull);
    expect(calls.where((value) => value == 'setStartupSilent').length, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}

Finder _inputDeviceDropdown() {
  return find.descendant(
    of: find.byKey(_inputDeviceKey),
    matching: find.byWidgetPredicate(
      (widget) => widget is AppDropdownField<String>,
    ),
  );
}

Widget _settingsApp({
  List<AudioInputDevice> audioInputDevices = const [],
  bool microphoneEnabled = true,
  bool systemAudioEnabled = false,
  String? microphoneDeviceId,
  bool systemAudioSupported = false,
  bool inputDeviceSelectionSupported = false,
  Future<void> Function({
    required bool microphoneEnabled,
    required bool systemAudioEnabled,
    String? microphoneDeviceId,
  })?
  onUpdateAudioSourceSettings,
  Future<void> Function({int? sampleRate, int? bufferSeconds})?
  onUpdateAudioSettings,
  String exportFormat = "mp3",
  Future<void> Function(String)? onExportFormatChanged,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SettingsPage(
        folderUri: null,
        exportFormat: exportFormat,
        onExportFormatChanged: onExportFormatChanged,
        sampleRate: 16000,
        bufferSeconds: 1800,
        audioInputDevices: audioInputDevices,
        microphoneEnabled: microphoneEnabled,
        systemAudioEnabled: systemAudioEnabled,
        microphoneDeviceId: microphoneDeviceId,
        systemAudioSupported: systemAudioSupported,
        inputDeviceSelectionSupported: inputDeviceSelectionSupported,
        audioSourceSettingsBusy: false,
        cacheBytes: 0,
        lockRecordingTrigger: LockRecordingTrigger.screenOff,
        languageMode: UiLanguageMode.system,
        onChooseFolder: () async {},
        onUpdateAudioSettings:
            onUpdateAudioSettings ?? ({sampleRate, bufferSeconds}) async {},
        onUpdateAudioSourceSettings:
            onUpdateAudioSourceSettings ??
            ({
              required microphoneEnabled,
              required systemAudioEnabled,
              microphoneDeviceId,
            }) async {},
        onRefreshAudioInputDevices: () async {},
        onOpenServerSettings: () async {},
        onLockRecordingTriggerChanged: (_) async {},
        onClearCache: () async => const <String, Object?>{
          'ok': true,
          'deletedBytes': 0,
        },
        onLanguageModeChanged: (_) async {},
        onOpenUrl: (_) async {},
      ),
    ),
  );
}
