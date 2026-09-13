import 'dart:async';
import 'package:echoclip/services/desktop_exit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'exit cleans up concurrently and only closes after backend finishes',
    () async {
      final backend = Completer<void>();
      final events = <String>[];
      final coordinator = DesktopExitCoordinator();
      Future<void> run() => coordinator.run(
        hideWindow: () async {
          events.add('hide');
        },
        shutdownBackend: () {
          events.add('backend');
          return backend.future;
        },
        releaseDesktopResources: [
          () async {
            events.add('tray');
          },
        ],
        closeWindow: () async {
          events.add('close');
        },
        forceExit: () {
          events.add('force');
        },
      );
      final first = run();
      final second = run();
      expect(identical(first, second), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(events, containsAll(['hide', 'backend', 'tray']));
      expect(events, isNot(contains('close')));
      backend.complete();
      await first;
      expect(events.last, 'close');
      expect(events, isNot(contains('force')));
      expect(events.where((e) => e == 'backend').length, 1);
    },
  );

  test(
    'stuck native work and plugins cannot make their waits accumulate',
    () async {
      final stuck = Completer<void>();
      final coordinator = DesktopExitCoordinator(
        backendTimeout: const Duration(milliseconds: 60),
        platformTimeout: const Duration(milliseconds: 30),
      );
      var forced = false;
      var closed = false;
      final watch = Stopwatch()..start();
      await coordinator.run(
        hideWindow: () => stuck.future,
        shutdownBackend: () => stuck.future,
        releaseDesktopResources: [() => stuck.future, () => stuck.future],
        closeWindow: () async {
          closed = true;
        },
        forceExit: () {
          forced = true;
        },
      );
      expect(forced, isTrue);
      expect(
        closed,
        isFalse,
        reason: 'engine teardown must not wait for a blocked FFI isolate',
      );
      expect(watch.elapsed, lessThan(const Duration(milliseconds: 300)));
      stuck.complete();
    },
  );

  test('failed tray cleanup does not prevent a graceful exit', () async {
    var closed = false;
    await DesktopExitCoordinator().run(
      hideWindow: () async => throw StateError('window detached'),
      shutdownBackend: () async {},
      releaseDesktopResources: [() async => throw StateError('tray detached')],
      closeWindow: () async {
        closed = true;
      },
      forceExit: () =>
          fail('backend completed: normal window close must be used'),
    );
    expect(closed, isTrue);
  });

  test(
    'unresponsive window close has a fallback after successful flush',
    () async {
      var forced = false;
      await DesktopExitCoordinator(
        platformTimeout: const Duration(milliseconds: 20),
      ).run(
        hideWindow: () async {},
        shutdownBackend: () async {},
        releaseDesktopResources: [],
        closeWindow: () => Completer<void>().future,
        forceExit: () {
          forced = true;
        },
      );
      expect(forced, isTrue);
    },
  );
}
