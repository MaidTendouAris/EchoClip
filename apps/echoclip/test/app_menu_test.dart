import 'dart:ui' show Tristate;

import 'package:echoclip/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'recording_library_design_test.dart' as fixture;
import 'fixtures/presentation_fixture.dart';

Finder surface() => find.byWidgetPredicate(
  (widget) =>
      widget is Material &&
      widget.type == MaterialType.card &&
      widget.elevation == 6,
);
Finder option<T>(T value) => find.byWidgetPredicate(
  (widget) => widget is AppMenuItem<T> && widget.value == value,
);

Future<void> open(WidgetTester tester, Finder trigger) async {
  await tester.pumpAndSettle();
  if (trigger.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      trigger,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(trigger);
  await tester.pumpAndSettle();
  await tester.tap(trigger);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'duration menus stay bounded and reopen on the selected last option',
    (tester) async {
      fixture.screen(tester, const Size(1000, 900));
      final signal = fixture.meter();
      addTearDown(signal.dispose);
      for (final lang in ['en', 'zh']) {
        for (final config in [(400.0, 1.0), (320.0, 2.0), (1000.0, 1.0)]) {
          final (width, scale) = config;
          tester.view.physicalSize = Size(width, 900);
          await tester.pumpWidget(
            fixture.shell(fixture.recorder(signal), lang: lang, scale: scale),
          );
          final trigger = find.byKey(const ValueKey('save.duration'));
          await open(tester, trigger);
          final rect = tester.getRect(surface());
          expect(rect.height, lessThanOrEqualTo(360));
          final anchor = tester.getRect(trigger);
          expect(
            rect.overlaps(anchor),
            isFalse,
            reason: 'The panel should leave its trigger visible',
          );
          expect(
            rect.width,
            closeTo(tester.getSize(trigger).width.clamp(200, 480), 1),
          );
          expect(rect.left, greaterThanOrEqualTo(8));
          expect(rect.right, lessThanOrEqualTo(width - 8));
          expect(rect.top, greaterThanOrEqualTo(8));
          expect(rect.bottom, lessThanOrEqualTo(892));
          await tester.ensureVisible(option<int>(86400));
          await tester.pumpAndSettle();
          await tester.tap(option<int>(86400));
          await tester.pumpAndSettle();
          expect(surface(), findsNothing);
          await open(tester, trigger);
          final selected = tester.widget<AppMenuItem<int>>(option<int>(86400));
          expect(selected.checked, isTrue);
          expect(
            tester
                .getRect(surface())
                .contains(tester.getCenter(option<int>(86400))),
            isTrue,
          );
          expect(
            tester.getSemantics(option<int>(86400)).flagsCollection.isSelected,
            Tristate.isTrue,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(surface(), findsNothing);
          expect(tester.takeException(), isNull, reason: '$lang $width $scale');
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    },
  );

  testWidgets(
    'keyboard selection skips disabled options and escape restores the trigger',
    (tester) async {
      fixture.screen(tester, const Size(800, 600));
      int? selected;
      await tester.pumpWidget(
        fixture.shell(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 280,
              child: AppDropdownField<int>(
                initialValue: 1,
                decoration: const InputDecoration(labelText: 'Input device'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('First microphone')),
                  DropdownMenuItem(
                    value: 2,
                    enabled: false,
                    child: Text('Unavailable'),
                  ),
                  DropdownMenuItem(value: 3, child: Text('Third microphone')),
                ],
                onChanged: (value) => selected = value,
              ),
            ),
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(surface(), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selected, 3);
      expect(surface(), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(surface(), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(surface(), findsNothing);
      expect(selected, 3);
    },
  );

  testWidgets('long device names wrap in the menu with large text', (
    tester,
  ) async {
    fixture.screen(tester, const Size(320, 700));
    const name = 'USB microphone with a long device name / 外置麦克风输入设备';
    await tester.pumpWidget(
      fixture.shell(
        Align(
          alignment: Alignment.topCenter,
          child: AppDropdownField<String>(
            initialValue: 'long',
            decoration: const InputDecoration(labelText: 'Microphone'),
            items: const [
              DropdownMenuItem(
                value: 'long',
                child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
            onChanged: (_) {},
          ),
        ),
        scale: 2,
      ),
    );
    await open(tester, find.byType(AppDropdownField<String>));
    final text = tester.widget<Text>(
      find.descendant(of: option<String>('long'), matching: find.text(name)),
    );
    expect(text.maxLines, isNull);
    expect(tester.getSize(option<String>('long')).height, greaterThan(80));
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(300, 650));
    await tester.pumpAndSettle();
    expect(surface(), findsNothing);
  });

  testWidgets(
    'disabled fields cannot open and updates select the new external value',
    (tester) async {
      fixture.screen(tester, const Size(800, 600));
      final value = ValueNotifier(1);
      final enabled = ValueNotifier(false);
      addTearDown(value.dispose);
      addTearDown(enabled.dispose);
      var changes = 0;
      await tester.pumpWidget(
        fixture.shell(
          Align(
            alignment: Alignment.topCenter,
            child: ValueListenableBuilder(
              valueListenable: enabled,
              builder: (_, active, _) => ValueListenableBuilder(
                valueListenable: value,
                builder: (_, number, _) => AppDropdownField<int>(
                  initialValue: number,
                  decoration: const InputDecoration(labelText: 'Format'),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('MP3')),
                    DropdownMenuItem(value: 2, child: Text('WAV')),
                  ],
                  onChanged: active ? (_) => changes++ : null,
                ),
              ),
            ),
          ),
        ),
      );
      final field = find.byType(AppDropdownField<int>);
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(surface(), findsNothing);
      enabled.value = true;
      value.value = 2;
      await tester.pumpAndSettle();
      await open(tester, field);
      expect(tester.widget<AppMenuItem<int>>(option<int>(2)).checked, isTrue);
      await tester.tapAt(const Offset(780, 580));
      await tester.pumpAndSettle();
      expect(changes, 0);
    },
  );

  testWidgets(
    'settings language, input, quality and lock trigger use the shared menu',
    (tester) async {
      fixture.screen(tester, const Size(1000, 900));
      for (final lang in ['en', 'zh']) {
        await tester.pumpWidget(
          fixture.shell(presentationSettings(desktop: true), lang: lang),
        );
        for (final field in [
          find.byType(AppDropdownField<UiLanguageMode>),
          find.descendant(
            of: find.byKey(const ValueKey('settings.inputDevice')),
            matching: find.byType(AppDropdownField<String>),
          ),
          find.byType(AppDropdownField<int>),
          find.byType(AppDropdownField<LockRecordingTrigger>),
        ]) {
          await open(tester, field);
          expect(surface(), findsOneWidget);
          expect(tester.getSize(surface()).height, lessThanOrEqualTo(360));
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('task format and bitrate choices reach the submitted action', (
    tester,
  ) async {
    fixture.screen(tester, const Size(400, 900));
    Map<String, Object?>? submitted;
    await tester.pumpWidget(
      fixture.shell(
        ScheduledTaskEditorPage(
          preset: const SchedulePresetModel(
            id: 'test',
            name: 'Test',
            enabled: true,
            trigger: {'type': 'countdown', 'delayMillis': 600000},
            actions: [
              {
                'type': 'save_recent',
                'seconds': 30,
                'format': 'mp3',
                'mp3BitrateKbps': 128,
              },
            ],
          ),
          onSubmit: (task) async {
            submitted = task;
            return false;
          },
        ),
      ),
    );
    final format = find.byType(AppDropdownField<String>);
    await open(tester, format);
    await tester.tap(option<String>('wav'));
    await tester.pumpAndSettle();
    expect(find.byType(AppDropdownField<int>), findsNothing);
    await open(tester, format);
    await tester.tap(option<String>('mp3'));
    await tester.pumpAndSettle();
    await open(tester, find.byType(AppDropdownField<int>));
    await tester.ensureVisible(option<int>(192));
    await tester.pumpAndSettle();
    await tester.tap(option<int>(192));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save task'));
    await tester.pumpAndSettle();
    final action = (submitted!['actions'] as List).single as Map;
    expect(action['format'], 'mp3');
    expect(action['mp3BitrateKbps'], 192);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion opens without a menu transition', (tester) async {
    fixture.screen(tester, const Size(800, 600));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: AppMenuButton<int>(
            onSelected: (_) {},
            itemBuilder: (_) => const [
              AppMenuItem(value: 1, child: Text('MP3')),
            ],
            child: const Text('Format'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Format'));
    await tester.pump();
    await tester.pump();
    expect(surface(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });
}
