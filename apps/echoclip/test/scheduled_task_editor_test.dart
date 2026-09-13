import 'package:echoclip/l10n/app_localizations.dart';
import 'package:echoclip/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _template = SchedulePresetModel(
  id: 'preset-1',
  name: 'Reusable',
  enabled: true,
  trigger: {'type': 'countdown', 'delayMillis': 600000},
  actions: [
    {'type': 'start_recording'},
  ],
);

Widget _app(Widget editor, String language) => MaterialApp(
  locale: Locale(language),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: editor,
);

Finder _wheel(String field) => find.descendant(
  of: find.byKey(ValueKey('schedule.countdown.$field')),
  matching: find.byType(ListWheelScrollView),
);

void main() {
  testWidgets(
    'mouse dragging changes time and separators share the selected row in both languages',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      try {
        for (final language in ['en', 'zh']) {
          for (final width in [400.0, 1440.0]) {
            tester.view.physicalSize = Size(width, 900);
            Map<String, Object?>? submitted;
            await tester.pumpWidget(
              _app(
                ScheduledTaskEditorPage(
                  preset: _template,
                  onSubmit: (task) async {
                    submitted = task;
                    return false;
                  },
                ),
                language,
              ),
            );
            await tester.pumpAndSettle();
            await tester.ensureVisible(_wheel('minutes'));
            await tester.pumpAndSettle();
            final wheel = tester.widget<ListWheelScrollView>(_wheel('minutes'));
            final controller = wheel.controller! as FixedExtentScrollController;
            final before = controller.selectedItem;
            final center = tester.getCenter(_wheel('minutes')).dy;
            for (final colon in find.text(':').evaluate()) {
              expect(
                tester.getCenter(find.byWidget(colon.widget)).dy,
                closeTo(center, 0.5),
              );
            }
            await tester.drag(
              _wheel('minutes'),
              const Offset(0, -88),
              kind: PointerDeviceKind.mouse,
            );
            await tester.pumpAndSettle();
            expect(controller.selectedItem, greaterThan(before));
            final minutes = controller.selectedItem;
            await tester.tap(
              find.text(language == 'en' ? 'Save task' : '保存任务'),
            );
            await tester.pumpAndSettle();
            expect(
              submitted,
              isNotNull,
              reason: 'blank names must be accepted',
            );
            expect(submitted!['name'], '');
            expect(submitted!['namePrefix'], language == 'en' ? 'Task' : '任务');
            expect(
              submitted!['id'],
              isNull,
              reason: 'using a preset creates a new task',
            );
            expect(
              (submitted!['trigger'] as Map)['delayMillis'],
              minutes * 60000,
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          }
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'action controls stay visible while disabled and retain edited values',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map<String, Object?>? submitted;
      await tester.pumpWidget(
        _app(
          ScheduledTaskEditorPage(
            onSubmit: (task) async {
              submitted = task;
              return false;
            },
          ),
          'en',
        ),
      );
      await tester.pumpAndSettle();
      final record = find.byKey(const ValueKey('schedule.action.recording'));
      final targets = find.descendant(
        of: record,
        matching: find.byType(SegmentedButton<bool>),
      );
      expect(find.text('Start recording'), findsOneWidget);
      expect(find.text('Stop recording'), findsOneWidget);
      expect(find.text('Enable upload'), findsOneWidget);
      expect(find.text('Disable upload'), findsOneWidget);
      expect(find.text('Save duration (seconds)'), findsOneWidget);
      expect(
        tester.widget<SegmentedButton<bool>>(targets).onSelectionChanged,
        isNull,
      );
      final toggle = find.descendant(of: record, matching: find.byType(Switch));
      await Scrollable.ensureVisible(tester.element(toggle), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop recording'));
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('Stop recording'), findsOneWidget);
      expect(tester.widget<SegmentedButton<bool>>(targets).selected, {false});
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('schedule.savePreset')));
      await tester.pumpAndSettle();
      expect(submitted!['operation'], 'save_preset');
      expect((submitted!['task'] as Map)['actions'], [
        {'type': 'stop_recording'},
      ]);
      expect((submitted!['task'] as Map)['namePrefix'], 'Preset');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'preset restores settings and ninth preset disables further saves',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map<String, Object?>? submitted;
      await tester.pumpWidget(
        _app(
          ScheduledTaskEditorPage(
            presetCount: 9,
            preset: const SchedulePresetModel(
              id: 'saved',
              name: 'Stop later',
              enabled: false,
              trigger: {'type': 'countdown', 'delayMillis': 3723000},
              actions: [
                {'type': 'set_upload_enabled', 'enabled': false},
                {'type': 'stop_recording'},
                {
                  'type': 'save_recent',
                  'seconds': 90,
                  'format': 'wav',
                  'mp3BitrateKbps': 192,
                  'allowPartial': false,
                },
              ],
            ),
            onSubmit: (task) async {
              submitted = task;
              return false;
            },
          ),
          'zh',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('schedule.savePreset')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('保存任务'));
      await tester.pumpAndSettle();
      expect(submitted!['enabled'], false);
      expect((submitted!['trigger'] as Map)['delayMillis'], 3723000);
      final actions = submitted!['actions'] as List;
      expect(actions.length, 3);
      expect((actions.last as Map)['format'], 'wav');
      expect((actions.last as Map)['seconds'], 90);
      expect((actions.last as Map)['allowPartial'], false);
      expect(submitted!['id'], isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('past time-point presets can open the calendar for correction', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _app(
        ScheduledTaskEditorPage(
          preset: const SchedulePresetModel(
            id: 'old',
            name: 'Old',
            enabled: true,
            trigger: {'type': 'time_point', 'dueAtUtcMillis': 1000},
            actions: [
              {'type': 'stop_recording'},
            ],
          ),
          onSubmit: (_) async => false,
        ),
        'en',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('schedule.timePoint.date')));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
