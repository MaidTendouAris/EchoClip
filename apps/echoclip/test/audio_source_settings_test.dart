import 'package:echoclip/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AudioInputDevice.fromNative', () {
    test('uses safe defaults when native fields are absent', () {
      final device = AudioInputDevice.fromNative(const <Object?, Object?>{});

      expect(device.id, isEmpty);
      expect(device.name, isEmpty);
      expect(device.isDefault, isFalse);
    });

    test('accepts the legacy label field as the display name', () {
      final device = AudioInputDevice.fromNative(const <Object?, Object?>{
        'id': 'mic-1',
        'label': 'USB microphone',
      });

      expect(device.id, 'mic-1');
      expect(device.name, 'USB microphone');
      expect(device.isDefault, isFalse);
    });
  });

  group('AudioSourceSettings.fromNative', () {
    test('defaults to microphone-only with unsupported optional features', () {
      final settings = AudioSourceSettings.fromNative(
        const <Object?, Object?>{},
      );

      expect(settings.microphoneEnabled, isTrue);
      expect(settings.systemAudioEnabled, isFalse);
      expect(settings.microphoneDeviceId, isNull);
      expect(settings.systemAudioSupported, isFalse);
      expect(settings.inputDeviceSelectionSupported, isFalse);
    });

    test('parses all Windows capability and source fields', () {
      final settings = AudioSourceSettings.fromNative(const <Object?, Object?>{
        'microphoneEnabled': false,
        'systemAudioEnabled': true,
        'microphoneDeviceId': 'wasapi-mic-1',
        'systemAudioSupported': true,
        'inputDeviceSelectionSupported': true,
      });

      expect(settings.microphoneEnabled, isFalse);
      expect(settings.systemAudioEnabled, isTrue);
      expect(settings.microphoneDeviceId, 'wasapi-mic-1');
      expect(settings.systemAudioSupported, isTrue);
      expect(settings.inputDeviceSelectionSupported, isTrue);
    });
  });
}
