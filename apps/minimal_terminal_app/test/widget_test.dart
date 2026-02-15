import 'package:flutter_test/flutter_test.dart';

import 'package:minimal_terminal_app/main.dart';

void main() {
  testWidgets('MinimalTerminalApp renders without crashing', (tester) async {
    await tester.pumpWidget(const MinimalTerminalApp());
    expect(find.byType(MinimalTerminalApp), findsOneWidget);
  });
}
