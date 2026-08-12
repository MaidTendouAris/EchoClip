import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;

typedef _CreateNative = Uint64 Function(Pointer<Utf8>, Uint32, Uint32);
typedef _CreateDart = int Function(Pointer<Utf8>, int, int);
typedef _DestroyNative = Void Function(Uint64);
typedef _DestroyDart = void Function(int);
typedef _AudioDevicesJsonNative = UintPtr Function(Pointer<Uint8>, UintPtr);
typedef _AudioDevicesJsonDart = int Function(Pointer<Uint8>, int);
typedef _ConfigureCaptureNative =
    Int32 Function(Uint64, Int32, Int32, Pointer<Utf8>);
typedef _ConfigureCaptureDart = int Function(int, int, int, Pointer<Utf8>);
typedef _CaptureCommandNative = Int32 Function(Uint64);
typedef _CaptureCommandDart = int Function(int);
typedef _AvailableMillisNative = Uint64 Function(Uint64);
typedef _AvailableMillisDart = int Function(int);
typedef _SaveLatestWavNative = Int32 Function(Uint64, Uint32, Pointer<Utf8>);
typedef _SaveLatestWavDart = int Function(int, int, Pointer<Utf8>);
typedef _SaveLatestNative = Int32 Function(
  Uint64,
  Uint32,
  Int32,
  Uint32,
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef _SaveLatestDart = int Function(
  int,
  int,
  int,
  int,
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef _ClearNative = Int32 Function(Uint64);
typedef _ClearDart = int Function(int);
typedef _StatusNative = Int32 Function(Uint64);
typedef _StatusDart = int Function(int);
typedef _StatusJsonNative = UintPtr Function(Uint64, Pointer<Uint8>, UintPtr);
typedef _StatusJsonDart = int Function(int, Pointer<Uint8>, int);
typedef _LastErrorNative = Pointer<Utf8> Function(Uint64);
typedef _LastErrorDart = Pointer<Utf8> Function(int);

/// Thin, synchronous binding for `echoclip_windows_ffi.dll`.
///
/// The opaque handles are process-local rather than isolate-local. Long calls
/// such as WAV export may therefore be made from a worker isolate while the
/// DLL's native capture thread continues feeding the same Rust recorder.
final class WindowsReplayFfi {
  WindowsReplayFfi._(DynamicLibrary library)
    : _create = library.lookupFunction<_CreateNative, _CreateDart>('ec_create'),
      _destroy = library.lookupFunction<_DestroyNative, _DestroyDart>(
        'ec_destroy',
      ),
      _audioDevicesJson = library
          .lookupFunction<_AudioDevicesJsonNative, _AudioDevicesJsonDart>(
            'ec_audio_devices_json',
          ),
      _configureCapture = library
          .lookupFunction<_ConfigureCaptureNative, _ConfigureCaptureDart>(
            'ec_configure_capture',
          ),
      _startCapture = library
          .lookupFunction<_CaptureCommandNative, _CaptureCommandDart>(
            'ec_start_capture',
          ),
      _stopCapture = library
          .lookupFunction<_CaptureCommandNative, _CaptureCommandDart>(
            'ec_stop_capture',
          ),
      _availableMillis = library
          .lookupFunction<_AvailableMillisNative, _AvailableMillisDart>(
            'ec_available_millis',
          ),
      _saveLatestWav = library
          .lookupFunction<_SaveLatestWavNative, _SaveLatestWavDart>(
            'ec_save_latest_wav',
          ),
      _saveLatest = library.lookupFunction<_SaveLatestNative, _SaveLatestDart>(
        'ec_save_latest',
      ),
      _clear = library.lookupFunction<_ClearNative, _ClearDart>('ec_clear'),
      _status = library.lookupFunction<_StatusNative, _StatusDart>('ec_status'),
      _statusJson = library.lookupFunction<_StatusJsonNative, _StatusJsonDart>(
        'ec_status_json',
      ),
      _lastError = library.lookupFunction<_LastErrorNative, _LastErrorDart>(
        'ec_last_error',
      );

  static const String libraryName = 'echoclip_windows_ffi.dll';

  static const int ok = 0;
  static const int invalidArgument = 1;
  static const int coreError = 2;
  static const int queueFull = 3;
  static const int stopped = 4;
  static const int panic = 5;

  final _CreateDart _create;
  final _DestroyDart _destroy;
  final _AudioDevicesJsonDart _audioDevicesJson;
  final _ConfigureCaptureDart _configureCapture;
  final _CaptureCommandDart _startCapture;
  final _CaptureCommandDart _stopCapture;
  final _AvailableMillisDart _availableMillis;
  final _SaveLatestWavDart _saveLatestWav;
  final _SaveLatestDart _saveLatest;
  final _ClearDart _clear;
  final _StatusDart _status;
  final _StatusJsonDart _statusJson;
  final _LastErrorDart _lastError;

  factory WindowsReplayFfi.open() {
    return WindowsReplayFfi._(_openLibrary());
  }

  int create({
    required String workDirectory,
    required int sampleRate,
    required int bufferSeconds,
  }) {
    final workDirectoryUtf8 = workDirectory.toNativeUtf8(allocator: calloc);
    try {
      final handle = _create(workDirectoryUtf8, sampleRate, bufferSeconds);
      if (handle == 0) {
        throw WindowsReplayFfiException('ec_create', coreError, lastError(0));
      }
      return handle;
    } finally {
      calloc.free(workDirectoryUtf8);
    }
  }

  void destroy(int handle) {
    if (handle != 0) {
      _destroy(handle);
    }
  }

  List<Object?> audioInputDevicesJson() {
    var capacity = _audioDevicesJson(nullptr, 0);
    for (var attempt = 0; attempt < 4; attempt += 1) {
      if (capacity <= 1) {
        break;
      }
      final buffer = calloc<Uint8>(capacity);
      try {
        final required = _audioDevicesJson(buffer, capacity);
        if (required <= 1) {
          break;
        }
        if (required > capacity) {
          capacity = required;
          continue;
        }
        final decoded = jsonDecode(buffer.cast<Utf8>().toDartString());
        return decoded is List ? List<Object?>.from(decoded) : const [];
      } finally {
        calloc.free(buffer);
      }
    }
    throw WindowsReplayFfiException(
      'ec_audio_devices_json',
      coreError,
      lastError(0),
    );
  }

  int configureCaptureCode(
    int handle, {
    required bool microphoneEnabled,
    required bool systemAudioEnabled,
    String? microphoneDeviceId,
  }) {
    final normalizedDeviceId = microphoneDeviceId?.trim();
    Pointer<Utf8> deviceIdUtf8 = nullptr;
    try {
      if (normalizedDeviceId != null && normalizedDeviceId.isNotEmpty) {
        deviceIdUtf8 = normalizedDeviceId.toNativeUtf8(allocator: calloc);
      }
      return _configureCapture(
        handle,
        microphoneEnabled ? 1 : 0,
        systemAudioEnabled ? 1 : 0,
        deviceIdUtf8,
      );
    } finally {
      if (deviceIdUtf8 != nullptr) {
        calloc.free(deviceIdUtf8);
      }
    }
  }

  int startCaptureCode(int handle) => _startCapture(handle);

  int stopCaptureCode(int handle) => _stopCapture(handle);

  int availableMillis(int handle) => _availableMillis(handle);

  int saveLatestWavCode(int handle, int seconds, String outputPath) {
    final outputPathUtf8 = outputPath.toNativeUtf8(allocator: calloc);
    try {
      return _saveLatestWav(handle, seconds, outputPathUtf8);
    } finally {
      calloc.free(outputPathUtf8);
    }
  }

  /// Exports the most recent buffer to `outputPath` with the requested
  /// [format] (0 = wav, 1 = mp3). For mp3 exports [ffmpegPath] is required and
  /// [mp3BitrateKbps] is honored; for wav exports FFmpeg is ignored.
  int saveLatestCode(
    int handle,
    int seconds,
    String outputPath, {
    int format = 0,
    int mp3BitrateKbps = 128,
    String? ffmpegPath,
  }) {
    final normalizedFfmpegPath = ffmpegPath?.trim();
    final outputPathUtf8 = outputPath.toNativeUtf8(allocator: calloc);
    final ffmpegPathUtf8 =
        normalizedFfmpegPath == null || normalizedFfmpegPath.isEmpty
        ? nullptr
        : normalizedFfmpegPath.toNativeUtf8(allocator: calloc);
    try {
      return _saveLatest(
        handle,
        seconds,
        format,
        mp3BitrateKbps,
        ffmpegPathUtf8,
        outputPathUtf8,
      );
    } finally {
      calloc.free(outputPathUtf8);
      if (ffmpegPathUtf8 != nullptr) {
        calloc.free(ffmpegPathUtf8);
      }
    }
  }

  int clearCode(int handle) => _clear(handle);

  int statusCode(int handle) => _status(handle);

  Map<String, Object?> statusJson(int handle) {
    var capacity = _statusJson(handle, nullptr, 0);
    for (var attempt = 0; attempt < 4; attempt += 1) {
      if (capacity <= 1) {
        break;
      }
      final buffer = calloc<Uint8>(capacity);
      try {
        final required = _statusJson(handle, buffer, capacity);
        if (required <= 1) {
          break;
        }
        if (required > capacity) {
          // Status counters can grow between the size query and the copy.
          // Rust returns the new required capacity without writing a partial
          // JSON document, so retry with the larger buffer.
          capacity = required;
          continue;
        }
        final decoded = jsonDecode(buffer.cast<Utf8>().toDartString());
        return decoded is Map
            ? Map<String, Object?>.from(decoded)
            : const <String, Object?>{};
      } finally {
        calloc.free(buffer);
      }
    }
    throw WindowsReplayFfiException(
      'ec_status_json',
      coreError,
      lastError(handle),
    );
  }

  String? lastError(int handle) {
    final pointer = _lastError(handle);
    if (pointer == nullptr) {
      return null;
    }
    final value = pointer.toDartString();
    return value.isEmpty ? null : value;
  }

  WindowsReplayFfiException errorFor(String operation, int code, int handle) {
    return WindowsReplayFfiException(operation, code, lastError(handle));
  }

  static DynamicLibrary _openLibrary() {
    final executableDirectory = path.dirname(Platform.resolvedExecutable);
    final candidates = <String>[
      path.join(executableDirectory, libraryName),
      path.join(executableDirectory, 'data', 'flutter_assets', libraryName),
      path.join(Directory.current.path, libraryName),
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        return DynamicLibrary.open(candidate);
      }
    }
    // Let Windows' normal DLL search produce the most useful load error.
    return DynamicLibrary.open(libraryName);
  }
}

final class WindowsReplayFfiException implements Exception {
  const WindowsReplayFfiException(
    this.operation,
    this.code,
    this.nativeMessage,
  );

  final String operation;
  final int code;
  final String? nativeMessage;

  @override
  String toString() {
    final detail = nativeMessage;
    return detail == null || detail.isEmpty
        ? '$operation failed (code $code)'
        : '$operation failed (code $code): $detail';
  }
}
