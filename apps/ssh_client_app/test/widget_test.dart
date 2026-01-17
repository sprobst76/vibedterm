import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_client_app/main.dart';

void main() {
  testWidgets('VibedTerm app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const VibedTermApp());
    await tester.pump();

    // Verify the app starts without crashing
    expect(find.text('VibedTerm'), findsWidgets);
  });
}
