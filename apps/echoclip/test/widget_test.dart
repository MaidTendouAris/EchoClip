import 'package:echoclip/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('EchoClip home renders core controls', (tester) async {
    await tester.pumpWidget(const EchoClipApp());

    expect(find.text('EchoClip'), findsOneWidget);
    expect(find.text('保存 30 秒'), findsOneWidget);
    expect(find.byType(LoudnessMeter), findsOneWidget);
  });
}
