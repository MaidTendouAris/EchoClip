import 'package:echoclip/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('EchoClip home renders core controls', (tester) async {
    await tester.pumpWidget(const EchoClipApp());

    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Recording paused'), findsOneWidget);
    expect(find.text('No previous recording time'), findsOneWidget);
    expect(find.textContaining('1970'), findsNothing);
    expect(find.byType(LoudnessMeter), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('save.submit')),
      250,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('recorder.page')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Save 30s'), findsOneWidget);
  });
}
