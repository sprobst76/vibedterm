import 'package:core_vault/core_vault.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_client_app/screens/vault_screen.dart';
import 'package:ssh_client_app/services/vault_service.dart';

import '../mocks/test_sync_manager.dart';
import '../mocks/test_vault_service.dart';

void main() {
  group('VaultScreen', () {
    late TestVaultService service;
    late TestSyncManager syncManager;

    setUp(() {
      service = TestVaultService();
      syncManager = TestSyncManager();
    });

    Widget buildTestWidget() {
      return MaterialApp(
        home: Scaffold(
          body: VaultScreen(service: service, syncManager: syncManager),
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

      // New simplified UI buttons
      expect(find.text('Setup Cloud Sync'), findsOneWidget);
      expect(find.text('Open vault file'), findsOneWidget);
      expect(find.text('Create new vault'), findsOneWidget);
    });

    testWidgets('shows setup cloud sync when not authenticated', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      // When not authenticated, shows setup button
      expect(find.text('Setup Cloud Sync'), findsOneWidget);
    });

    testWidgets('shows host and identity count when unlocked', (tester) async {
      // Set state to unlocked with mock data
      final now = DateTime.now().toUtc().toIso8601String();
      service.setDataForTest(VaultData(
        version: 1,
        revision: 1,
        deviceId: 'test-device',
        createdAt: now,
        updatedAt: now,
      ));
      service.setStateForTest(const VaultState(
        status: VaultStatus.unlocked,
        message: 'Vault unlocked',
      ));

      await tester.pumpWidget(buildTestWidget());
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
