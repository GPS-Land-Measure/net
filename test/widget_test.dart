import 'package:flutter_test/flutter_test.dart';

import 'package:my_first_app/main.dart';

void main() {
  testWidgets('GPS Measure app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const GpsMeasureApp());
    expect(find.text('GPS Measure'), findsOneWidget);
  });
}
