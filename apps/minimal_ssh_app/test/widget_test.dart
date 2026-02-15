import 'package:flutter_test/flutter_test.dart';

import 'package:minimal_ssh_app/main.dart';

void main() {
  testWidgets('MinimalSshApp renders without crashing', (tester) async {
    await tester.pumpWidget(const MinimalSshApp());
    expect(find.byType(MinimalSshApp), findsOneWidget);
  });
}
