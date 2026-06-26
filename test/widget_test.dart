import 'package:flutter_test/flutter_test.dart';

import 'package:attend_ease/main.dart';

void main() {
  testWidgets('App shows the START button', (WidgetTester tester) async {
    await tester.pumpWidget(const AttendEaseApp());
    await tester.pump();
    expect(find.text('START'), findsOneWidget);
    expect(find.text('AttendEase'), findsOneWidget);
  });
}
