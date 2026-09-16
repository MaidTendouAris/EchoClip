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
typedef _ConfigureSyncNative =
    Int32 Function(Uint64, Int32, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _ConfigureSyncDart =
    int Function(int, int, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _TestSyncNative =
    Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _TestSyncDart =
    int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _CaptureCommandNative = Int32 Function(Uint64);
typedef _CaptureCommandDart = int Function(int);
typedef _AvailableMillisNative = Uint64 Function(Uint64);
typedef _AvailableMillisDart = int Function(int);
typedef _SaveLatestWavNative = Int32 Function(Uint64, Uint32, Pointer<Utf8>);
typedef _SaveLatestWavDart = int Function(int, int, Pointer<Utf8>);
typedef _SaveLatestNative =
    Int32 Function(Uint64, Uint32, Int32, Uint32, Pointer<Utf8>, Pointer<Utf8>);
typedef _SaveLatestDart =
    int Function(int, int, int, int, Pointer<Utf8>, Pointer<Utf8>);
typedef _SaveRangeNative =
    Int32 Function(
      Uint64,
      Pointer<Utf8>,
      Int32,
      Uint32,
      Pointer<Utf8>,
      Pointer<Utf8>,
    );
typedef _SaveRangeDart =
    int Function(int, Pointer<Utf8>, int, int, Pointer<Utf8>, Pointer<Utf8>);
typedef _SetStartupNative = Int32 Function(Uint64, Int32, Pointer<Utf8>);
typedef _SetStartupDart = int Function(int, int, Pointer<Utf8>);
typedef _SetGainsNative = Int32 Function(Uint64, Uint32, Uint32);
typedef _SetGainsDart = int Function(int, int, int);
typedef _ClearNative = Int32 Function(Uint64);
typedef _ClearDart = int Function(int);
typedef _StatusNative = Int32 Function(Uint64);
typedef _StatusDart = int Function(int);
typedef _StatusJsonNative = UintPtr Function(Uint64, Pointer<Uint8>, UintPtr);
typedef _StatusJsonDart = int Function(int, Pointer<Uint8>, int);
typedef _SchedulerConfigureNative =
    Int32 Function(Uint64, Pointer<Utf8>, Pointer<Utf8>);
typedef _SchedulerConfigureDart =
    int Function(int, Pointer<Utf8>, Pointer<Utf8>);
typedef _SchedulerStringCommandNative = Int32 Function(Uint64, Pointer<Utf8>);
typedef _SchedulerStringCommandDart = int Function(int, Pointer<Utf8>);
typedef _SchedulerSetEnabledNative =
    Int32 Function(Uint64, Pointer<Utf8>, Uint64, Int32);
typedef _SchedulerSetEnabledDart = int Function(int, Pointer<Utf8>, int, int);
typedef _TranscodeNative =
    Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Uint32);
typedef _TranscodeDart =
    int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int);
typedef _LastErrorNative = Pointer<Utf8> Function(Uint64);
typedef _LastErrorDart = Pointer<Utf8> Function(int);
typedef _SecretTransformNative =
    UintPtr Function(Pointer<Utf8>, Pointer<Uint8>, UintPtr);
typedef _SecretTransformDart = int Function(Pointer<Utf8>, Pointer<Uint8>, int);

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
      _configureSync = library
          .lookupFunction<_ConfigureSyncNative, _ConfigureSyncDart>(
            'ec_configure_sync',
          ),
      _configureSyncProtected = library
          .lookupFunction<_ConfigureSyncNative, _ConfigureSyncDart>(
            'ec_configure_sync_protected',
          ),
      _testSyncConnection = library
          .lookupFunction<_TestSyncNative, _TestSyncDart>(
            'ec_test_sync_connection',
          ),
      _testSyncConnectionProtected = library
          .lookupFunction<_TestSyncNative, _TestSyncDart>(
            'ec_test_sync_connection_protected',
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
      _saveRange = library.lookupFunction<_SaveRangeNative, _SaveRangeDart>(
        'ec_save_range',
      ),
      _bufferWindow = library
          .lookupFunction<_StatusJsonNative, _StatusJsonDart>(
            'ec_buffer_window_json',
          ),
      _setStartup = library.lookupFunction<_SetStartupNative, _SetStartupDart>(
        'ec_set_startup',
      ),
      _startupRegistered = library
          .lookupFunction<
            _SchedulerStringCommandNative,
            _SchedulerStringCommandDart
          >('ec_is_startup_registered'),
      _setGains = library.lookupFunction<_SetGainsNative, _SetGainsDart>(
        'ec_set_capture_gains',
      ),
      _clear = library.lookupFunction<_ClearNative, _ClearDart>('ec_clear'),
      _status = library.lookupFunction<_StatusNative, _StatusDart>('ec_status'),
      _statusJson = library.lookupFunction<_StatusJsonNative, _StatusJsonDart>(
        'ec_status_json',
      ),
      _schedulerConfigure = library
          .lookupFunction<_SchedulerConfigureNative, _SchedulerConfigureDart>(
            'ec_scheduler_configure_runtime',
          ),
      _schedulerSnapshot = library
          .lookupFunction<_StatusJsonNative, _StatusJsonDart>(
            'ec_scheduler_snapshot_json',
          ),
      _schedulerUpsert = library
          .lookupFunction<
            _SchedulerStringCommandNative,
            _SchedulerStringCommandDart
          >('ec_scheduler_upsert'),
      _schedulerDelete = library
          .lookupFunction<
            _SchedulerStringCommandNative,
            _SchedulerStringCommandDart
          >('ec_scheduler_delete'),
      _schedulerSetEnabled = library
          .lookupFunction<_SchedulerSetEnabledNative, _SchedulerSetEnabledDart>(
            'ec_scheduler_set_enabled',
          ),
      _transcode = library.lookupFunction<_TranscodeNative, _TranscodeDart>(
        'ec_transcode_wav_to_mp3',
      ),
      _lastError = library.lookupFunction<_LastErrorNative, _LastErrorDart>(
        'ec_last_error',
      ),
      _protectSecret = library
          .lookupFunction<_SecretTransformNative, _SecretTransformDart>(
            'ec_protect_secret',
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
  final _ConfigureSyncDart _configureSync;
  final _ConfigureSyncDart _configureSyncProtected;
  final _TestSyncDart _testSyncConnection;
  final _TestSyncDart _testSyncConnectionProtected;
  final _CaptureCommandDart _startCapture;
  final _CaptureCommandDart _stopCapture;
  final _AvailableMillisDart _availableMillis;
  final _SaveLatestWavDart _saveLatestWav;
  final _SaveLatestDart _saveLatest;
  final _SaveRangeDart _saveRange;
  final _StatusJsonDart _bufferWindow;
  final _SetStartupDart _setStartup;
  final _SchedulerStringCommandDart _startupRegistered;
  final _SetGainsDart _setGains;
  final _ClearDart _clear;
  final _StatusDart _status;
  final _StatusJsonDart _statusJson;
  final _SchedulerConfigureDart _schedulerConfigure;
  final _StatusJsonDart _schedulerSnapshot;
  final _SchedulerStringCommandDart _schedulerUpsert;
  final _SchedulerStringCommandDart _schedulerDelete;
  final _SchedulerSetEnabledDart _schedulerSetEnabled;
  final _TranscodeDart _transcode;
  final _LastErrorDart _lastError;
  final _SecretTransformDart _protectSecret;

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

  int configureSyncCode(
    int handle, {
    required bool enabled,
    String serverUrl = '',
    String uploadKey = '',
    String deviceId = '',
  }) {
    final server = serverUrl.toNativeUtf8(allocator: calloc);
    final key = uploadKey.toNativeUtf8(allocator: calloc);
    final device = deviceId.toNativeUtf8(allocator: calloc);
    try {
      return _configureSync(handle, enabled ? 1 : 0, server, key, device);
    } finally {
      calloc.free(server);
      calloc.free(key);
      calloc.free(device);
    }
  }

  int configureSyncProtectedCode(
    int handle, {
    required bool enabled,
    String serverUrl = '',
    String protectedUploadKey = '',
    String deviceId = '',
  }) {
    final server = serverUrl.toNativeUtf8(allocator: calloc);
    final key = protectedUploadKey.toNativeUtf8(allocator: calloc);
    final device = deviceId.toNativeUtf8(allocator: calloc);
    try {
      return _configureSyncProtected(
        handle,
        enabled ? 1 : 0,
        server,
        key,
        device,
      );
    } finally {
      calloc.free(server);
      calloc.free(key);
      calloc.free(device);
    }
  }

  int testSyncConnectionCode({
    required String serverUrl,
    required String uploadKey,
    required String deviceId,
  }) => _testSyncConnectionValues(
    serverUrl: serverUrl,
    uploadKey: uploadKey,
    deviceId: deviceId,
    test: _testSyncConnection,
  );

  int testSyncConnectionProtectedCode({
    required String serverUrl,
    required String protectedUploadKey,
    required String deviceId,
  }) => _testSyncConnectionValues(
    serverUrl: serverUrl,
    uploadKey: protectedUploadKey,
    deviceId: deviceId,
    test: _testSyncConnectionProtected,
  );

  int _testSyncConnectionValues({
    required String serverUrl,
    required String uploadKey,
    required String deviceId,
    required _TestSyncDart test,
  }) {
    final server = serverUrl.toNativeUtf8(allocator: calloc);
    final key = uploadKey.toNativeUtf8(allocator: calloc);
    final device = deviceId.toNativeUtf8(allocator: calloc);
    try {
      return test(server, key, device);
    } finally {
      calloc.free(server);
      calloc.free(key);
      calloc.free(device);
    }
  }

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
  /// [format] (0 = wav, 1 = mp3, 2 = flac, 3 = ogg, 4 = m4a, 5 = aac).
  /// Except for legacy WAV exports without FFmpeg, [ffmpegPath] is required and
  /// [mp3BitrateKbps] is honored; for wav exports FFmpeg is ignored.
  int saveLatestCode(
    int handle,
    int seconds,
    String outputPath, {
    int format = 0,
    int mp3BitrateKbps = 128,
    String? ffmpegPath,
    Map<String, Object?>? range,
  }) {
    final normalizedFfmpegPath = ffmpegPath?.trim();
    final outputPathUtf8 = outputPath.toNativeUtf8(allocator: calloc);
    final ffmpegPathUtf8 =
        normalizedFfmpegPath == null || normalizedFfmpegPath.isEmpty
        ? nullptr
        : normalizedFfmpegPath.toNativeUtf8(allocator: calloc);
    final rangeUtf8 = range == null
        ? nullptr
        : jsonEncode(range).toNativeUtf8(allocator: calloc);
    try {
      if (range != null) {
        return _saveRange(
          handle,
          rangeUtf8,
          format,
          mp3BitrateKbps,
          ffmpegPathUtf8,
          outputPathUtf8,
        );
      }
      return _saveLatest(
        handle,
        seconds,
        format,
        mp3BitrateKbps,
        ffmpegPathUtf8,
        outputPathUtf8,
      );
    } finally {
      if (rangeUtf8 != nullptr) calloc.free(rangeUtf8);
      calloc.free(outputPathUtf8);
      if (ffmpegPathUtf8 != nullptr) {
        calloc.free(ffmpegPathUtf8);
      }
    }
  }

  int setGainsCode(int handle, int microphone, int system) =>
      _setGains(handle, microphone, system);

  int clearCode(int handle) => _clear(handle);

  int statusCode(int handle) => _status(handle);

  String protectSecret(String secret) => _transformSecret(
    operation: 'ec_protect_secret',
    input: secret,
    transform: _protectSecret,
  );

  String _transformSecret({
    required String operation,
    required String input,
    required _SecretTransformDart transform,
  }) {
    final inputUtf8 = input.toNativeUtf8(allocator: calloc);
    try {
      var capacity = transform(inputUtf8, nullptr, 0);
      for (var attempt = 0; attempt < 3; attempt += 1) {
        if (capacity <= 1) {
          break;
        }
        final buffer = calloc<Uint8>(capacity);
        try {
          final required = transform(inputUtf8, buffer, capacity);
          if (required > capacity) {
            capacity = required;
            continue;
          }
          if (required > 1) {
            return buffer.cast<Utf8>().toDartString();
          }
        } finally {
          calloc.free(buffer);
        }
      }
      throw WindowsReplayFfiException(operation, coreError, lastError(0));
    } finally {
      calloc.free(inputUtf8);
    }
  }

  int setStartupCode(
    int handle,
    bool enabled,
    String executable, {
    bool silent = false,
  }) {
    final exe = executable.toNativeUtf8(allocator: calloc);
    try {
      return _setStartup(handle, enabled ? (silent ? 2 : 1) : 0, exe);
    } finally {
      calloc.free(exe);
    }
  }

  bool isStartupRegistered(int handle, String executable) {
    final exe = executable.toNativeUtf8(allocator: calloc);
    try {
      final result = _startupRegistered(handle, exe);
      if (result < 0) {
        throw WindowsReplayFfiException(
          'ec_is_startup_registered',
          coreError,
          lastError(handle),
        );
      }
      return result == 1;
    } finally {
      calloc.free(exe);
    }
  }

  Map<String, Object?> bufferWindowJson(int handle) =>
      _readJson(handle, _bufferWindow);
  Map<String, Object?> statusJson(int handle) => _readJson(handle, _statusJson);
  Map<String, Object?> _readJson(int handle, _StatusJsonDart read) {
    var capacity = read(handle, nullptr, 0);
    for (var attempt = 0; attempt < 4; attempt += 1) {
      if (capacity <= 1) {
        break;
      }
      final buffer = calloc<Uint8>(capacity);
      try {
        final required = read(handle, buffer, capacity);
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

  int configureSchedulerRuntimeCode(
    int handle, {
    String recordingDirectory = '',
    String ffmpegPath = '',
  }) {
    final recording = recordingDirectory.toNativeUtf8(allocator: calloc);
    final ffmpeg = ffmpegPath.toNativeUtf8(allocator: calloc);
    try {
      return _schedulerConfigure(handle, recording, ffmpeg);
    } finally {
      calloc.free(recording);
      calloc.free(ffmpeg);
    }
  }

  Map<String, Object?> schedulerSnapshotJson(int handle) {
    var capacity = _schedulerSnapshot(handle, nullptr, 0);
    for (var attempt = 0; attempt < 4; attempt += 1) {
      if (capacity <= 1) {
        break;
      }
      final buffer = calloc<Uint8>(capacity);
      try {
        final required = _schedulerSnapshot(handle, buffer, capacity);
        if (required <= 1) {
          break;
        }
        if (required > capacity) {
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
      'ec_scheduler_snapshot_json',
      coreError,
      lastError(handle),
    );
  }

  int schedulerUpsertCode(int handle, Map<String, Object?> task) {
    final json = jsonEncode(task).toNativeUtf8(allocator: calloc);
    try {
      return _schedulerUpsert(handle, json);
    } finally {
      calloc.free(json);
    }
  }

  int schedulerDeleteCode(int handle, String taskId) {
    final id = taskId.toNativeUtf8(allocator: calloc);
    try {
      return _schedulerDelete(handle, id);
    } finally {
      calloc.free(id);
    }
  }

  int schedulerSetEnabledCode(
    int handle,
    String taskId,
    int expectedRevision,
    bool enabled,
  ) {
    final id = taskId.toNativeUtf8(allocator: calloc);
    try {
      return _schedulerSetEnabled(
        handle,
        id,
        expectedRevision,
        enabled ? 1 : 0,
      );
    } finally {
      calloc.free(id);
    }
  }

  int transcodeWavToMp3Code({
    required String inputPath,
    required String outputPath,
    required String ffmpegPath,
    required int bitrateKbps,
  }) {
    final input = inputPath.toNativeUtf8(allocator: calloc);
    final output = outputPath.toNativeUtf8(allocator: calloc);
    final ffmpeg = ffmpegPath.toNativeUtf8(allocator: calloc);
    try {
      return _transcode(input, output, ffmpeg, bitrateKbps);
    } finally {
      calloc.free(input);
      calloc.free(output);
      calloc.free(ffmpeg);
    }
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
