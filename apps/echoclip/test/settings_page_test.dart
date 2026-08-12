import 'dart:ui' show Tristate;

import 'package:echoclip/l10n/app_localizations.dart';
import 'package:echoclip/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _microphoneKey = ValueKey<String>('settings.microphone');
const _systemAudioKey = ValueKey<String>('settings.systemAudio');
const _inputDeviceKey = ValueKey<String>('settings.inputDevice');
const _refreshDevicesKey = ValueKey<String>('settings.refreshInputDevices');

void main() {
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
    final inputDevice = tester.widget<DropdownButtonFormField<String>>(
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
    final inputDevice = tester.widget<DropdownButtonFormField<String>>(
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
    await tester.tap(find.byKey(_systemAudioKey));
    await tester.pump();

    expect(updateCalls, 0);
    expect(
      find.text('Keep at least one audio source selected'),
      findsOneWidget,
    );
  });
}

Finder _inputDeviceDropdown() {
  return find.descendant(
    of: find.byKey(_inputDeviceKey),
    matching: find.byWidgetPredicate(
      (widget) => widget is DropdownButtonFormField<String>,
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
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SettingsPage(
        folderUri: null,
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
        onUpdateAudioSettings: ({sampleRate, bufferSeconds}) async {},
        onUpdateAudioSourceSettings:
            onUpdateAudioSourceSettings ??
            ({
              required microphoneEnabled,
              required systemAudioEnabled,
              microphoneDeviceId,
            }) async {},
        onRefreshAudioInputDevices: () async {},
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
