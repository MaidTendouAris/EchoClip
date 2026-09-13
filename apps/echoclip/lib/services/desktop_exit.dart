import 'dart:async';

/// Coordinates explicit application exit, independently of recording commands.
class DesktopExitCoordinator {
  DesktopExitCoordinator({
    this.backendTimeout = const Duration(seconds: 2),
    this.platformTimeout = const Duration(milliseconds: 300),
  });

  final Duration backendTimeout;
  final Duration platformTimeout;
  Future<void>? _pending;

  Future<void> run({
    required Future<void> Function() hideWindow,
    required Future<void> Function() shutdownBackend,
    required List<Future<void> Function()> releaseDesktopResources,
    required Future<void> Function() closeWindow,
    required void Function() forceExit,
  }) => _pending ??= _run(
    hideWindow,
    shutdownBackend,
    releaseDesktopResources,
    closeWindow,
    forceExit,
  );

  Future<void> _run(
    Future<void> Function() hideWindow,
    Future<void> Function() shutdownBackend,
    List<Future<void> Function()> cleanup,
    Future<void> Function() closeWindow,
    void Function() forceExit,
  ) async {
    // Hiding, tray/hotkey removal and backend shutdown can proceed together.
    final desktop = Future.wait([
      _bounded(hideWindow, platformTimeout),
      for (final action in cleanup) _bounded(action, platformTimeout),
    ]);
    final stopped = await _bounded(shutdownBackend, backendTimeout);
    await desktop;
    if (!stopped || !await _bounded(closeWindow, platformTimeout)) {
      // Future.timeout does not cancel a native FFI call. Do not ask engine
      // teardown to wait indefinitely for that isolate after a failed shutdown.
      forceExit();
    }
  }

  Future<bool> _bounded(
    Future<void> Function() action,
    Duration timeout,
  ) async {
    try {
      await Future<void>.sync(action).timeout(timeout);
      return true;
    } catch (_) {
      return false;
    }
  }
}
