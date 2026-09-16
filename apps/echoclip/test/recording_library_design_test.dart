import 'package:echoclip/main.dart';
import 'package:echoclip/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fixtures/library_fixture.dart';

Widget shell(Widget child, {String lang = 'en', double scale = 1}) =>
    MaterialApp(
      locale: Locale(lang),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, body) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: body!,
      ),
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(20), child: child),
      ),
    );
ValueNotifier<MeterSnapshot> meter() => ValueNotifier(
  MeterSnapshot(
    running: false,
    recordedMillis: 300000,
    sessionRecordedMillis: 0,
    sessionStartedAt: DateTime(2026, 9, 11, 12),
    level: 0,
    peakLevel: 0,
  ),
);
RecorderPage recorder(
  ValueNotifier<MeterSnapshot> signal, {
  Future<void> Function(int)? onSave,
  Future<void> Function(BufferSelection)? onSaveRange,
}) => RecorderPage(
  isBuffering: false,
  platformStatus: '',
  meterSnapshot: signal,
  folderSelected: true,
  onSave: onSave ?? (_) async {},
  onSaveRange: onSaveRange,
  onGetBufferWindow: () async => const BufferWindow(
    bufferId: 'test',
    sampleRate: 100,
    channels: 1,
    startSample: 1000,
    endSample: 7000,
  ),
  onChooseFolder: () async {},
);
Future<void> durationMenu(WidgetTester tester, int value) async {
  await tester.ensureVisible(find.byKey(const ValueKey('save.duration')));
  await tester.tap(find.byKey(const ValueKey('save.duration')));
  await tester.pumpAndSettle();
  final option = find.byWidgetPredicate(
    (widget) => widget is AppMenuItem<int> && widget.value == value,
  );
  await tester.ensureVisible(option);
  await tester.pumpAndSettle();
  await tester.tap(option);
  await tester.pumpAndSettle();
}

Future<void> clipMenu(WidgetTester tester, String value) async {
  await tester.tap(
    find.byKey(const ValueKey('library.actions.clip:interview')),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byWidgetPredicate(
      (widget) => widget is PopupMenuItem<String> && widget.value == value,
    ),
  );
  await tester.pumpAndSettle();
}

void screen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets(
    'save controls have equal dimensions in both languages and layouts',
    (tester) async {
      screen(tester, const Size(1000, 900));
      final signal = meter();
      addTearDown(signal.dispose);
      for (final lang in ['zh', 'en']) {
        for (final width in [320.0, 400.0, 1000.0]) {
          for (final scale in [1.0, 2.0]) {
            tester.view.physicalSize = Size(width, 900);
            await tester.pumpWidget(
              shell(recorder(signal), lang: lang, scale: scale),
            );
            await tester.scrollUntilVisible(
              find.byKey(const ValueKey('save.submit')),
              250,
              scrollable: find.descendant(
                of: find.byKey(const ValueKey('recorder.page')),
                matching: find.byType(Scrollable),
              ),
            );
            final field = tester.getRect(
              find.byKey(const ValueKey('save.duration')),
            );
            final button = tester.getRect(
              find.byKey(const ValueKey('save.submit')),
            );
            expect(field.height, closeTo(button.height, .1));
            expect(field.width, closeTo(button.width, .1));
            expect(
              tester.takeException(),
              isNull,
              reason: '$lang $width $scale',
            );
            await tester.pumpWidget(const SizedBox.shrink());
          }
        }
      }
    },
  );
  testWidgets('custom range validates and exports fixed sample positions', (
    tester,
  ) async {
    final signal = meter();
    addTearDown(signal.dispose);
    final saved = <BufferSelection>[];
    await tester.pumpWidget(
      shell(recorder(signal, onSaveRange: (range) async => saved.add(range))),
    );
    await durationMenu(tester, 60);
    await durationMenu(tester, -1);
    await tester.enterText(find.byKey(const ValueKey('save.rangeEnd.1')), '00');
    for (final value in ['0', '61', '60']) {
      await tester.enterText(
        find.byKey(const ValueKey('save.rangeEnd.2')),
        value,
      );
      await tester.tap(find.byKey(const ValueKey('save.rangeApply')));
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
    }
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Save 1 min'), findsOneWidget);
    await durationMenu(tester, -1);
    await tester.enterText(
      find.byKey(const ValueKey('save.rangeStart.2')),
      '12',
    );
    await tester.enterText(find.byKey(const ValueKey('save.rangeEnd.1')), '00');
    await tester.enterText(find.byKey(const ValueKey('save.rangeEnd.2')), '37');
    await tester.tap(find.byKey(const ValueKey('save.rangeApply')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('save.submit')));
    await tester.tap(find.byKey(const ValueKey('save.submit')));
    await tester.pump();
    expect(saved.single.startSample, 2200);
    expect(saved.single.endSample, 4700);
    expect(find.text('Save selection'), findsOneWidget);
    await durationMenu(tester, 30);
    expect(find.text('Save 30s'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'library fits populated, empty and player layouts with large text',
    (tester) async {
      screen(tester, const Size(1000, 700));
      for (final lang in ['zh', 'en']) {
        for (final width in [320.0, 400.0, 1000.0]) {
          for (final scale in [1.0, 2.0]) {
            tester.view.physicalSize = Size(width, 700);
            await tester.pumpWidget(
              shell(
                testLibrary(playback: samplePlayback),
                lang: lang,
                scale: scale,
              ),
            );
            await tester.pump();
            expect(
              find.byKey(const ValueKey('library.player')),
              findsOneWidget,
            );
            expect(
              tester.takeException(),
              isNull,
              reason: '$lang $width $scale player',
            );
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpWidget(
              shell(
                testLibrary(clips: [], groups: []),
                lang: lang,
                scale: scale,
              ),
            );
            expect(
              tester.takeException(),
              isNull,
              reason: '$lang $width $scale empty',
            );
            await tester.pumpWidget(const SizedBox.shrink());
          }
        }
      }
    },
  );
  testWidgets('search and group filters scope selection and batch deletion', (
    tester,
  ) async {
    screen(tester, const Size(1000, 900));
    final deleted = <ClipItem>[];
    await tester.pumpWidget(
      shell(testLibrary(onDeleteClips: (clips) async => deleted.addAll(clips))),
    );
    await tester.tap(find.byKey(const ValueKey('library.group.group:work')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('library.clip.clip:notes')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('library.search')),
      'INTERVIEW',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('library.clip.clip:review')),
      findsNothing,
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select all'));
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.text('Delete selected'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(deleted.map((clip) => clip.uri), ['clip:interview']);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    await tester.tap(find.text('Edit'));
    await tester.pump();
    await tester.tap(find.text('Select all'));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('library.group.all')));
    await tester.pump();
    expect(find.text('0 selected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('player remains available when a filter hides its recording', (
    tester,
  ) async {
    screen(tester, const Size(1000, 900));
    var playback = idlePlayback;
    final calls = <String>[];
    await tester.pumpWidget(
      shell(
        StatefulBuilder(
          builder: (context, setState) => testLibrary(
            playback: playback,
            onPlay: (clip) async => setState(() {
              calls.add('play');
              playback = samplePlayback.copyWith(paused: false, playing: true);
            }),
            onPause: () async => setState(() {
              calls.add('pause');
              playback = playback.copyWith(paused: true, playing: false);
            }),
            onResume: () async => setState(() {
              calls.add('resume');
              playback = playback.copyWith(paused: false, playing: true);
            }),
            onStop: () async => setState(() {
              calls.add('stop');
              playback = idlePlayback;
            }),
            onSeek: (value) async => calls.add('seek'),
            onSpeed: (value) async => setState(() {
              calls.add('speed');
              playback = playback.copyWith(speed: value);
            }),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('library.play.clip:interview')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('library.group.library:ungrouped')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('library.clip.clip:interview')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('library.player')), findsOneWidget);
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    await tester.tap(find.byTooltip('Resume'));
    await tester.pump();
    await tester.drag(
      find.byKey(const ValueKey('library.seek')),
      const Offset(50, 0),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('library.speed')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('2.0x').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('2.0x').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Stop'));
    await tester.pump();
    expect(
      calls,
      containsAll(['play', 'pause', 'resume', 'seek', 'speed', 'stop']),
    );
    expect(find.byKey(const ValueKey('library.player')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'sorting changes list order and empty groups retain management actions',
    (tester) async {
      screen(tester, const Size(1000, 900));
      await tester.pumpWidget(shell(testLibrary()));
      double top(String uri) =>
          tester.getTopLeft(find.byKey(ValueKey('library.clip.$uri'))).dy;
      expect(top('clip:interview'), lessThan(top('clip:ideas')));
      await tester.tap(find.byKey(const ValueKey('library.sort')));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .ancestor(
              of: find.text('Oldest first'),
              matching: find.byWidgetPredicate(
                (widget) => widget is AppMenuItem,
              ),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(top('clip:ideas'), lessThan(top('clip:interview')));
      await tester.tap(find.byKey(const ValueKey('library.sort')));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .ancestor(
              of: find.text('File name').last,
              matching: find.byWidgetPredicate(
                (widget) => widget is AppMenuItem,
              ),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(top('clip:notes'), lessThan(top('clip:interview')));
      await tester.tap(find.byKey(const ValueKey('library.group.group:empty')));
      await tester.pumpAndSettle();
      expect(find.text('No recordings'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('library.groupActions')));
      await tester.pumpAndSettle();
      expect(find.text('Rename group'), findsOneWidget);
      expect(find.text('Delete group'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('recording menus still rename, move and convert', (tester) async {
    screen(tester, const Size(1000, 900));
    final calls = <String>[];
    await tester.pumpWidget(
      shell(
        testLibrary(
          onRename: (clip, name) async => calls.add('rename:$name'),
          onMove: (clip, group) async => calls.add('move:${group?.uri}'),
          onConvert: (clip, bitrate) async {
            calls.add('convert:$bitrate');
            return true;
          },
        ),
      ),
    );
    await clipMenu(tester, 'rename');
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Renamed.wav',
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await clipMenu(tester, 'move');
    await tester.tap(find.text('Ideas'));
    await tester.pumpAndSettle();
    await clipMenu(tester, 'convert_mp3');
    await tester.tap(find.text('128 kbps'));
    await tester.pumpAndSettle();
    expect(calls, ['rename:Renamed.wav', 'move:group:ideas', 'convert:128']);
    expect(tester.takeException(), isNull);
  });
}
