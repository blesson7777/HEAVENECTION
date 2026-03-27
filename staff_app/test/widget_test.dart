import 'package:flutter_test/flutter_test.dart';
import 'package:heavenection/main.dart';

void main() {
  testWidgets('shows the Heavenection login screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const HeavenectionApp());

    expect(find.text('HEAVENECTION'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
  });
}
