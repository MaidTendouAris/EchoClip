import 'package:echoclip/main.dart';
import 'package:echoclip/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fixtures/presentation_fixture.dart';

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
  String status = '',
}) => RecorderPage(
  isBuffering: false,
  platformStatus: status,
  meterSnapshot: signal,
  folderSelected: true,
  onSave: (_) async {},
  onChooseFolder: () async {},
);
void screen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder scrollable(String page) => find
    .descendant(
      of: find.byKey(ValueKey(page)),
      matching: find.byType(Scrollable),
    )
    .first;

void main() {
  testWidgets(
    'schedule summaries keep time, remaining duration and format in their translated positions',
    (tester) async {
      screen(tester, const Size(400, 1000));
      for (final lang in ['zh', 'en']) {
        await tester.pumpWidget(
          shell(presentationTasks(populated: true, lang: lang), lang: lang),
        );
        final nextPrefix = lang == 'zh'
            ? '下次执行：2026-09-13 09:00:00'
            : 'Next run: 2026-09-13 09:00:00';
        final duePrefix = lang == 'zh'
            ? '计划 2026-09-13 09:00:00'
            : 'Scheduled 2026-09-13 09:00:00';
        expect(find.textContaining(nextPrefix), findsOneWidget);
        expect(find.textContaining(duePrefix), findsOneWidget);
        final saveLabel = lang == 'zh'
            ? '保存最近 30 秒 · MP3'
            : 'Save recent 30 s · MP3';
        await tester.scrollUntilVisible(
          find.text(saveLabel),
          200,
          scrollable: scrollable('schedule.page'),
        );
        expect(find.text(saveLabel), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'all redesigned pages fit narrow, wide and enlarged bilingual layouts throughout scrolling',
    (tester) async {
      screen(tester, const Size(400, 800));
      final signal = meter();
      addTearDown(signal.dispose);
      for (final lang in ['zh', 'en']) {
        for (final width in [320.0, 400.0, 1000.0]) {
          for (final scale in [1.0, 2.0]) {
            tester.view.physicalSize = Size(width, 800);
            for (final page in [
              'recorder',
              'settings',
              'schedule',
              'scheduleEmpty',
            ]) {
              final child = switch (page) {
                'recorder' => recorder(signal),
                'settings' => presentationSettings(desktop: width == 1000),
                _ => presentationTasks(
                  populated: page == 'schedule',
                  lang: lang,
                ),
              };
              await tester.pumpWidget(shell(child, lang: lang, scale: scale));
              await tester.pump();
              final list = scrollable(
                '${page == 'scheduleEmpty' ? 'schedule' : page}.page',
              );
              final state = tester.state<ScrollableState>(list);
              var steps = 0;
              while (true) {
                expect(
                  tester.takeException(),
                  isNull,
                  reason:
                      '$page $lang $width $scale scroll ${state.position.pixels}',
                );
                if (state.position.extentAfter < 1) break;
                expect(steps++, lessThan(50));
                state.position.jumpTo(
                  (state.position.pixels + 450).clamp(
                    0,
                    state.position.maxScrollExtent,
                  ),
                );
                await tester.pump();
              }
              await tester.pumpWidget(const SizedBox.shrink());
            }
          }
        }
      }
    },
  );

  testWidgets(
    'home omits repeated recording status but keeps actionable detail',
    (tester) async {
      screen(tester, const Size(400, 800));
      final signal = meter();
      addTearDown(signal.dispose);
      for (final lang in ['zh', 'en']) {
        final l10n = lookupAppLocalizations(Locale(lang));
        await tester.pumpWidget(
          shell(
            recorder(signal, status: l10n.recordingStatusPaused),
            lang: lang,
          ),
        );
        expect(find.text(l10n.recordingPaused), findsOneWidget);
        expect(find.text(l10n.recordingStatusPaused), findsNothing);
        final error = l10n.serviceError('permission_denied');
        await tester.pumpWidget(
          shell(recorder(signal, status: error), lang: lang),
        );
        expect(find.text(error), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'settings displays a readable Android folder and retains the change action',
    (tester) async {
      screen(tester, const Size(320, 800));
      var changes = 0;
      for (final lang in ['zh', 'en']) {
        await tester.pumpWidget(
          shell(
            presentationSettings(
              chooseFolder: () async {
                changes++;
              },
            ),
            lang: lang,
            scale: 2,
          ),
        );
        final label = lang == 'zh'
            ? '内部存储 / EchoClip'
            : 'Internal storage / EchoClip';
        expect(find.text(label), findsOneWidget);
        expect(
          find.byTooltip(
            'content://com.android.externalstorage.documents/tree/primary%3AEchoClip',
          ),
          findsOneWidget,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('settings.chooseFolder')),
        );
        await tester.tap(find.byKey(const ValueKey('settings.chooseFolder')));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
      expect(changes, 2);
    },
  );

  testWidgets(
    'task switch and saved preset still invoke their original actions',
    (tester) async {
      screen(tester, const Size(400, 900));
      final updates = <String>[];
      await tester.pumpWidget(
        shell(
          presentationTasks(
            populated: true,
            setEnabled: (task, enabled) async {
              updates.add('${task.id}:$enabled');
              return true;
            },
          ),
        ),
      );
      final toggle = find.descendant(
        of: find.byKey(const ValueKey('schedule.task.task:1')),
        matching: find.byType(Switch),
      );
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pump();
      expect(updates, ['task:1:false']);
      await tester.ensureVisible(find.text('Meeting recording'));
      await tester.tap(find.text('Meeting recording'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('schedule.editor.page')),
        findsOneWidget,
      );
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty,
      );
      final minutesWheel = tester.widget<ListWheelScrollView>(
        find.byType(ListWheelScrollView).at(1),
      );
      expect(
        (minutesWheel.controller! as FixedExtentScrollController).selectedItem,
        15,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'desktop shell stays aligned across sections while mobile keeps one page heading',
    (tester) async {
      screen(tester, const Size(400, 800));
      try {
        for (final config in [
          (TargetPlatform.iOS, 400.0, false, 1.0),
          (TargetPlatform.linux, 800.0, true, 1.0),
          (TargetPlatform.linux, 1200.0, true, 1.0),
          (TargetPlatform.iOS, 1200.0, true, 1.0),
          (TargetPlatform.iOS, 320.0, false, 2.0),
          (TargetPlatform.linux, 800.0, true, 2.0),
        ]) {
          final (platform, width, desktop, scale) = config;
          final showTopBar = platform == TargetPlatform.linux;
          debugDefaultTargetPlatformOverride = platform;
          tester.view.physicalSize = Size(width, 800);
          for (final lang in ['zh', 'en']) {
            final l10n = lookupAppLocalizations(Locale(lang));
            await tester.pumpWidget(
              MaterialApp(
                locale: Locale(lang),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: EchoClipHome(
                  languageMode: UiLanguageMode.system,
                  onLanguageModeChanged: (_) async {},
                ),
              ),
            );
            final page = find.byKey(const ValueKey('navigation.page'));
            final sidebar = find.byKey(const ValueKey('navigation.desktop'));
            final initialPageTop = tester.getTopLeft(page).dy;
            final initialSidebar = desktop ? tester.getRect(sidebar) : null;
            final initialHeader = showTopBar
                ? tester.getRect(find.byType(AppBar))
                : null;
            double? mobileTitleTop;
            for (final section in [
              'library',
              'scheduledTasks',
              'settings',
              'recorder',
            ]) {
              final nav = desktop
                  ? find.byKey(ValueKey('navigation.desktop.$section'))
                  : find
                        .byType(NavigationDestination)
                        .at(
                          {
                            'recorder': 0,
                            'library': 1,
                            'scheduledTasks': 2,
                            'settings': 3,
                          }[section]!,
                        );
              await tester.tap(nav);
              await tester.pump(const Duration(milliseconds: 400));
              expect(
                find.byType(AppBar),
                showTopBar ? findsOneWidget : findsNothing,
              );
              if (desktop) {
                expect(tester.getRect(sidebar), initialSidebar);
              }
              expect(tester.getTopLeft(page).dy, initialPageTop);
              if (showTopBar) {
                expect(tester.getRect(find.byType(AppBar)), initialHeader);
                final divider = tester.getRect(
                  find.byKey(const ValueKey('navigation.divider')),
                );
                expect(divider.top, 0);
                expect(divider.bottom, 800);
                expect(tester.getTopLeft(page).dy, 0);
                expect(
                  initialHeader!.right,
                  lessThanOrEqualTo(initialSidebar!.right),
                );
                expect(
                  find.descendant(
                    of: find.byType(AppBar),
                    matching: find.text(l10n.appTitle),
                  ),
                  findsOneWidget,
                );
              }
              if (section == 'library') {
                expect(l10n.navLibrary, l10n.libraryTitle);
              }
              // Recording controls remain home-specific; page actions stay in their own page.
              expect(
                find.byKey(const ValueKey('recording.modeMenu')),
                section == 'recorder' ? findsOneWidget : findsNothing,
              );
              final title = switch (section) {
                'library' => l10n.libraryTitle,
                'scheduledTasks' => l10n.scheduledTasksTitle,
                'settings' => l10n.settingsTitle,
                _ => l10n.recordingPaused,
              };
              final content = find.byType(switch (section) {
                'library' => LibraryPage,
                'scheduledTasks' => ScheduledTasksPage,
                'settings' => SettingsPage,
                _ => RecorderPage,
              });
              expect(
                find.descendant(of: content, matching: find.text(title)),
                findsOneWidget,
              );
              if (!showTopBar) {
                final top = tester
                    .getTopLeft(
                      find.descendant(of: content, matching: find.text(title)),
                    )
                    .dy;
                mobileTitleTop ??= top;
                expect(
                  top,
                  closeTo(mobileTitleTop, 0.1),
                  reason: 'mobile titles align: $section $width $lang $scale',
                );
              }
              if (section == 'recorder') {
                final mode = find.byKey(const ValueKey('recording.modeMenu'));
                final status = find.byKey(
                  const ValueKey('server.connectionIndicator'),
                );
                expect(
                  find.descendant(of: content, matching: mode),
                  findsOneWidget,
                );
                expect(
                  find.descendant(of: content, matching: status),
                  findsOneWidget,
                );
                final titleCenter = tester
                    .getCenter(
                      find.descendant(of: content, matching: find.text(title)),
                    )
                    .dy;
                if (scale == 1 && showTopBar) {
                  expect(tester.getCenter(mode).dy, closeTo(titleCenter, 1));
                  expect(tester.getCenter(status).dy, closeTo(titleCenter, 1));
                } else if (scale > 1) {
                  expect(tester.getCenter(mode).dy, greaterThan(titleCenter));
                }
                expect(
                  tester.takeException(),
                  isNull,
                  reason: 'home header $width $lang $scale',
                );
                await tester.tap(status);
                await tester.pumpAndSettle();
                expect(
                  tester.takeException(),
                  isNull,
                  reason: 'connection details $width $lang $scale',
                );
                expect(find.text(l10n.serverConnectionDetails), findsOneWidget);
                await tester.tap(find.text(l10n.close));
                await tester.pumpAndSettle();
                await tester.tap(mode);
                await tester.pumpAndSettle();
                expect(
                  tester.takeException(),
                  isNull,
                  reason: 'recording mode menu $width $lang $scale',
                );
                expect(
                  find.byType(AppMenuItem<RecordingMode>),
                  findsNWidgets(2),
                );
                await tester.tap(
                  find.byWidgetPredicate(
                    (widget) =>
                        widget is PopupMenuItem<RecordingMode> &&
                        widget.value == RecordingMode.standard,
                  ),
                );
                await tester.pumpAndSettle();
              }
              expect(
                tester.takeException(),
                isNull,
                reason: '$platform $width $lang $section',
              );
            }
            await tester.pumpWidget(const SizedBox.shrink());
          }
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
