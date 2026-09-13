import 'package:echoclip/l10n/app_localizations.dart';
import 'package:echoclip/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('server sync native status accepts Rust snake-case fields and logs', () {
    final settings = ServerSyncSettings.fromNative({
      'enabled': true,
      'serverHost': '192.168.1.231',
      'uploadPort': 32581,
      'deviceId': 'desktop-1',
      'keyConfigured': true,
      'status': {
        'running': true,
        'connected': false,
        'server_url': 'http://192.168.1.231:32581',
        'key_id': 'abc123',
        'lag_samples': 320,
        'reconnect_count': 2,
        'last_error': 'connection refused',
        'logs': [
          {
            'unix_seconds': 1724131200,
            'event': 'disconnected',
            'message': 'connection refused',
          },
        ],
      },
    });

    expect(settings.configured, isTrue);
    expect(settings.serverHost, '192.168.1.231');
    expect(settings.uploadPort, 32581);
    expect(settings.serverUrl, 'http://192.168.1.231:32581');
    expect(settings.status?.lagSamples, 320);
    expect(settings.status?.reconnectCount, 2);
    expect(settings.status?.logs.single.event, 'disconnected');
  });

  test('legacy full URL is split during native settings migration', () {
    final settings = ServerSyncSettings.fromNative({
      'enabled': false,
      'serverUrl': 'http://legacy.example:4567',
      'deviceId': 'legacy-device',
      'keyConfigured': false,
    });

    expect(settings.serverHost, 'legacy.example');
    expect(settings.uploadPort, 4567);
  });
  testWidgets('upload switch applies independently from save settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var enabled = false;
    var toggleCalls = 0;
    var saveCalls = 0;
    var testCalls = 0;
    ServerSyncSettings current() => ServerSyncSettings(
      enabled: enabled,
      serverHost: '192.168.1.231',
      uploadPort: 32581,
      deviceId: 'desktop-1',
      keyConfigured: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ServerSettingsPage(
          initialSettings: current(),
          onEnabledChanged: (value) async {
            toggleCalls += 1;
            enabled = value;
            return current();
          },
          onSave:
              ({
                required serverHost,
                required uploadPort,
                uploadKey,
                clearKey = false,
              }) async {
                saveCalls += 1;
                return current();
              },
          onRefresh: () async => current(),
          onTestConnection: ({serverHost, uploadPort, uploadKey}) async {
            testCalls += 1;
            return ServerConnectionTestResult(
              success: true,
              testedAtUnixSeconds: 1724131200,
              serverUrl: 'http://$serverHost:$uploadPort',
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('serverSettings.enabled')));
    await tester.pumpAndSettle();
    expect(enabled, isTrue);
    expect(toggleCalls, 1);
    expect(saveCalls, 0);

    await tester.tap(find.byKey(const ValueKey('serverSettings.save')));
    await tester.pumpAndSettle();
    expect(enabled, isTrue);
    expect(toggleCalls, 1);
    expect(saveCalls, 1);

    await tester.tap(
      find.byKey(const ValueKey('serverSettings.testConnection')),
    );
    await tester.pumpAndSettle();
    expect(testCalls, 1);
    expect(find.text('Server connection succeeded'), findsOneWidget);
  });

  testWidgets(
    'secondary server page keeps the protected key hidden and shows disconnects',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const settings = ServerSyncSettings(
        enabled: true,
        serverHost: '192.168.1.231',
        uploadPort: 32581,
        deviceId: 'desktop-1',
        keyConfigured: true,
        status: ServerSyncStatus(
          running: true,
          connected: false,
          serverUrl: 'http://192.168.1.231:32581',
          keyId: 'abc123',
          localTotalSamples: 16000,
          remoteNextSample: 15680,
          lagSamples: 320,
          lastSuccessUnixSeconds: 1724131200,
          reconnectCount: 2,
          lastError: 'connection refused',
          logs: [
            ServerConnectionLog(
              unixSeconds: 1724131200,
              event: 'disconnected',
              message: 'connection refused',
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ServerSettingsPage(
            initialSettings: settings,
            onEnabledChanged: (_) async => settings,
            onSave:
                ({
                  required serverHost,
                  required uploadPort,
                  uploadKey,
                  clearKey = false,
                }) async => settings,
            onRefresh: () async => settings,
            onTestConnection: ({serverHost, uploadPort, uploadKey}) async =>
                const ServerConnectionTestResult(
                  success: false,
                  testedAtUnixSeconds: 1724131200,
                  serverUrl: 'http://192.168.1.231:32581',
                  error: 'connection refused',
                ),
          ),
        ),
      );

      final keyField = tester.widget<TextField>(
        find.byKey(const ValueKey('serverSettings.key')),
      );
      expect(keyField.controller?.text, isEmpty);
      expect(find.byKey(const ValueKey('serverSettings.host')), findsOneWidget);
      expect(find.byKey(const ValueKey('serverSettings.port')), findsOneWidget);
      expect(find.byKey(const ValueKey('serverSettings.url')), findsNothing);
      expect(
        find.byKey(const ValueKey('serverSettings.bufferMinutes')),
        findsNothing,
      );
      expect(
        find.text('Connection logs and disconnect history'),
        findsOneWidget,
      );
      expect(find.text('Disconnected'), findsOneWidget);
      expect(find.text('connection refused'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
