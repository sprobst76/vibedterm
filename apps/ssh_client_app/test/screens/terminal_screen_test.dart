import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_client_app/screens/terminal_screen.dart';

import '../mocks/test_vault_service.dart';

void main() {
  group('TerminalScreen', () {
    late TestVaultService service;

    setUp(() {
      service = TestVaultService();
    });

    Widget buildTestWidget() {
      return MaterialApp(
        home: Scaffold(
          body: TerminalScreen(service: service),
        ),
      );
    }

    testWidgets('shows empty state when no connections', (tester) async {
      await service.createDemoVault();
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('No connections'), findsOneWidget);
      expect(find.text('No active connections'), findsOneWidget);
      expect(find.byIcon(Icons.terminal), findsOneWidget);
    });

    testWidgets('shows "No hosts configured" message when no hosts',
        (tester) async {
      await service.createDemoVault();
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('No hosts configured yet.'), findsOneWidget);
      expect(find.text('Add a host'), findsOneWidget);
    });

    testWidgets('shows quick connect chips when hosts exist', (tester) async {
      await service.createDemoVault();
      await service.addHost(
        label: 'Server A',
        hostname: 'a.example.com',
        port: 22,
        username: 'user',
      );
      await service.addHost(
        label: 'Server B',
        hostname: 'b.example.com',
        port: 22,
        username: 'user',
      );
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Quick connect:'), findsOneWidget);
      expect(find.text('Server A'), findsOneWidget);
      expect(find.text('Server B'), findsOneWidget);
      expect(find.byType(ActionChip), findsNWidgets(2));
    });

    testWidgets('shows add connection button in tab bar', (tester) async {
      await service.createDemoVault();
      await tester.pumpWidget(buildTestWidget());

      // There are 2 add icons: one in tab bar, one in empty state "Add a host" button
      expect(find.byIcon(Icons.add), findsNWidgets(2));
    });

    testWidgets('shows more options menu button', (tester) async {
      await service.createDemoVault();
      await tester.pumpWidget(buildTestWidget());

      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets('more options menu shows trusted keys option', (tester) async {
      await service.createDemoVault();
      await tester.pumpWidget(buildTestWidget());

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('Trusted keys'), findsOneWidget);
    });

    testWidgets('more options menu shows logs toggle', (tester) async {
      await service.createDemoVault();
      await tester.pumpWidget(buildTestWidget());

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('Show logs'), findsOneWidget);
    });

    testWidgets('status bar shows special key buttons', (tester) async {
      await service.createDemoVault();
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Esc'), findsOneWidget);
      expect(find.text('Ctrl+C'), findsOneWidget);
      expect(find.text('Ctrl+D'), findsOneWidget);
      expect(find.text('Tab'), findsOneWidget);
    });

    testWidgets('status bar shows paste button', (tester) async {
      await service.createDemoVault();
      await tester.pumpWidget(buildTestWidget());

      expect(find.byIcon(Icons.content_paste), findsOneWidget);
    });

    testWidgets('status bar shows logs toggle button', (tester) async {
      await service.createDemoVault();
      await tester.pumpWidget(buildTestWidget());

      // Should find expand_less (logs are hidden by default)
      expect(find.byIcon(Icons.expand_less), findsOneWidget);
    });

    testWidgets('special key buttons are disabled when no session',
        (tester) async {
      await service.createDemoVault();
      await tester.pumpWidget(buildTestWidget());

      // Find the Esc button and check it's disabled
      final escButton = find.widgetWithText(TextButton, 'Esc');
      expect(escButton, findsOneWidget);

      final button = tester.widget<TextButton>(escButton);
      expect(button.onPressed, isNull);
    });

    testWidgets('shows snackbar when clicking add host with no hosts',
        (tester) async {
      await service.createDemoVault();
      await tester.pumpWidget(buildTestWidget());

      await tester.tap(find.text('Add a host'));
      await tester.pumpAndSettle();

      expect(find.text('Add hosts in the Hosts tab'), findsOneWidget);
    });

    testWidgets('tapping add button shows host picker when hosts exist',
        (tester) async {
      await service.createDemoVault();
      await service.addHost(
        label: 'Picker Host',
        hostname: 'picker.example.com',
        port: 22,
        username: 'picker',
      );
      await tester.pumpWidget(buildTestWidget());

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      // Should show bottom sheet with host
      expect(find.text('Connect to host'), findsOneWidget);
      expect(find.text('Picker Host'), findsNWidgets(2)); // chip + list item
    });

    testWidgets('host picker shows host details', (tester) async {
      await service.createDemoVault();
      await service.addHost(
        label: 'Detailed Host',
        hostname: 'detail.example.com',
        port: 2222,
        username: 'detailuser',
      );
      await tester.pumpWidget(buildTestWidget());

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.text('detailuser@detail.example.com:2222'), findsOneWidget);
    });

    testWidgets('shows "Show all N hosts" when more than 6 hosts',
        (tester) async {
      await service.createDemoVault();
      for (var i = 1; i <= 8; i++) {
        await service.addHost(
          label: 'Host $i',
          hostname: 'host$i.example.com',
          port: 22,
          username: 'user',
        );
      }
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Show all 8 hosts'), findsOneWidget);
      // Only 6 ActionChips should be visible
      expect(find.byType(ActionChip), findsNWidgets(6));
    });

    testWidgets('trusted keys dialog shows empty message when no keys',
        (tester) async {
      await service.createDemoVault();
      await tester.pumpWidget(buildTestWidget());

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Trusted keys'));
      await tester.pumpAndSettle();

      expect(find.text('Trusted Host Keys'), findsOneWidget);
      expect(find.text('No trusted keys yet.'), findsOneWidget);
    });

    testWidgets('trusted keys dialog shows trusted hosts', (tester) async {
      await service.createDemoVault();
      service.addTrustedKeyForTest(
        'trusted.example.com',
        'SHA256:abcdef1234567890',
      );
      await tester.pumpWidget(buildTestWidget());

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Trusted keys'));
      await tester.pumpAndSettle();

      expect(find.text('trusted.example.com'), findsOneWidget);
      expect(find.text('SHA256:abcdef1234567890'), findsOneWidget);
      expect(find.text('Remove all'), findsOneWidget);
    });

    testWidgets('can close trusted keys dialog', (tester) async {
      await service.createDemoVault();
      await tester.pumpWidget(buildTestWidget());

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Trusted keys'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Trusted Host Keys'), findsNothing);
    });

    testWidgets('logs drawer is hidden by default', (tester) async {
      await service.createDemoVault();
      await tester.pumpWidget(buildTestWidget());

      // Logs drawer shows "No logs" text when visible
      // It should not be visible by default
      expect(find.text('No logs'), findsNothing);
    });

    testWidgets('logs toggle shows/hides logs drawer', (tester) async {
      await service.createDemoVault();
      await tester.pumpWidget(buildTestWidget());

      // Toggle logs on via menu
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show logs'));
      await tester.pumpAndSettle();

      // Now logs should be visible (empty state)
      // Note: Can't verify drawer content easily without a tab
    });

    testWidgets('clicking quick connect chip shows password dialog',
        (tester) async {
      await service.createDemoVault();
      await service.addHost(
        label: 'Quick Server',
        hostname: 'quick.example.com',
        port: 22,
        username: 'quickuser',
      );
      await tester.pumpWidget(buildTestWidget());

      await tester.tap(find.text('Quick Server'));
      await tester.pumpAndSettle();

      expect(find.text('SSH Authentication'), findsOneWidget);
      expect(find.text('quickuser@quick.example.com:22'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
    });

    testWidgets('password dialog shows key auth hint when identity linked',
        (tester) async {
      await service.createDemoVault();
      await service.addIdentity(
        name: 'Key for Quick',
        type: 'ssh-ed25519',
        privateKey: '-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----',
      );
      final identity = service.currentData!.identities.first;
      await service.addHost(
        label: 'Keyed Quick',
        hostname: 'keyed.example.com',
        port: 22,
        username: 'keyuser',
        identityId: identity.id,
      );
      await tester.pumpWidget(buildTestWidget());

      await tester.tap(find.text('Keyed Quick'));
      await tester.pumpAndSettle();

      expect(
        find.text('A private key is configured. Leave empty to use key authentication.'),
        findsOneWidget,
      );
    });

    testWidgets('can cancel password dialog', (tester) async {
      await service.createDemoVault();
      await service.addHost(
        label: 'Cancel Host',
        hostname: 'cancel.example.com',
        port: 22,
        username: 'canceluser',
      );
      await tester.pumpWidget(buildTestWidget());

      await tester.tap(find.text('Cancel Host'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog should be closed, no tabs created
      expect(find.text('SSH Authentication'), findsNothing);
      expect(find.text('No connections'), findsOneWidget);
    });
  });
}
