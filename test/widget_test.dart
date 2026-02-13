import 'package:flutter_test/flutter_test.dart';
import 'package:speakmate/app.dart';

void main() {
  testWidgets('App renders home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const SpeakMateApp());
    expect(find.text('SpeakMate'), findsOneWidget);
  });
}
