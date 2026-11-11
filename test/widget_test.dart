import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/main.dart';

void main() {
  testWidgets('App root initializes without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.byType(MyApp), findsOneWidget);
  });
}
