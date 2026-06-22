import 'package:echoclip/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('EchoClip home renders core controls', (tester) async {
    await tester.pumpWidget(const EchoClipApp());

    expect(find.text('EchoClip'), findsOneWidget);
    expect(find.text('Save 30s'), findsOneWidget);
    expect(find.byType(LoudnessMeter), findsOneWidget);
  });
}
