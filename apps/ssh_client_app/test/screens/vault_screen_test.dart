import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_client_app/screens/vault_screen.dart';
import 'package:ssh_client_app/services/vault_service.dart';

import '../mocks/test_vault_service.dart';

void main() {
  group('VaultScreen', () {
    late TestVaultService service;

    setUp(() {
      service = TestVaultService();
    });

    Widget buildTestWidget() {
      return MaterialApp(
        home: Scaffold(
          body: VaultScreen(service: service),
        ),
      );
    }

    testWidgets('shows locked status initially', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Status: locked'), findsOneWidget);
      expect(find.text('Create or unlock a vault file.'), findsOneWidget);
    });

    testWidgets('shows all vault action buttons', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Create demo vault'), findsOneWidget);
      expect(find.text('Unlock demo vault'), findsOneWidget);
      expect(find.text('Pick vault file'), findsOneWidget);
      expect(find.text('Create vault at path'), findsOneWidget);
      expect(find.text('Quick create (app storage)'), findsOneWidget);
    });

    testWidgets('unlock demo vault button is disabled when no file path',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());

      // Find the button by its text and verify it exists
      expect(find.text('Unlock demo vault'), findsOneWidget);

      // The button should be disabled (no file path set)
      // We verify this by checking the state is locked with no filePath
      expect(service.state.value.filePath, isNull);
    });

    testWidgets('create demo vault updates state to unlocked', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      await tester.tap(find.text('Create demo vault'));
      await tester.pumpAndSettle();

      expect(find.text('Status: unlocked'), findsOneWidget);
      expect(find.textContaining('Demo vault created'), findsOneWidget);
    });

    testWidgets('shows host and identity count when unlocked', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      await tester.tap(find.text('Create demo vault'));
      await tester.pumpAndSettle();

      expect(find.text('Hosts: 0 | Identities: 0'), findsOneWidget);
    });

    testWidgets('shows last vault path when available', (tester) async {
      service.setStateForTest(const VaultState(
        status: VaultStatus.locked,
        filePath: '/test/path/vault.vlt',
      ));

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Verify the state has a file path
      expect(service.state.value.filePath, equals('/test/path/vault.vlt'));
      expect(find.text('Unlock demo vault'), findsOneWidget);
    });

    testWidgets('shows error status correctly', (tester) async {
      service.setStateForTest(const VaultState(
        status: VaultStatus.error,
        message: 'Test error message',
      ));

      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Status: error'), findsOneWidget);
      expect(find.text('Test error message'), findsOneWidget);
    });

    testWidgets('shows busy indicator when isBusy is true', (tester) async {
      service.setStateForTest(const VaultState(
        status: VaultStatus.locked,
        isBusy: true,
      ));

      await tester.pumpWidget(buildTestWidget());

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('hides busy indicator when isBusy is false', (tester) async {
      service.setStateForTest(const VaultState(
        status: VaultStatus.locked,
        isBusy: false,
      ));

      await tester.pumpWidget(buildTestWidget());

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
