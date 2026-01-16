import 'package:core_vault/core_vault.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_client_app/screens/hosts_screen.dart';

import '../mocks/test_vault_service.dart';

void main() {
  group('HostsScreen', () {
    late TestVaultService service;
    VaultHost? connectedHost;

    setUp(() {
      service = TestVaultService();
      connectedHost = null;
    });

    Widget buildTestWidget() {
      return MaterialApp(
        home: Scaffold(
          body: HostsScreen(
            service: service,
            onConnectHost: (host, identity) {
              connectedHost = host;
            },
          ),
        ),
      );
    }

    testWidgets('shows message when vault is locked', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(
        find.text('Unlock or create a vault to manage hosts and identities.'),
        findsOneWidget,
      );
    });

    testWidgets('shows action buttons when vault is unlocked', (tester) async {
      await service.createDemoVault();
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Add identity'), findsOneWidget);
      expect(find.text('Add host'), findsOneWidget);
    });

    testWidgets('shows empty identity and host sections when unlocked',
        (tester) async {
      await service.createDemoVault();
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Identities (0)'), findsOneWidget);
      expect(find.text('Hosts (0)'), findsOneWidget);
    });

    testWidgets('shows identity count after adding identity', (tester) async {
      await service.createDemoVault();
      await service.addIdentity(
        name: 'Test Key',
        type: 'ssh-ed25519',
        privateKey: '-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----',
      );
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Identities (1)'), findsOneWidget);
      expect(find.text('Test Key'), findsOneWidget);
    });

    testWidgets('shows host count after adding host', (tester) async {
      await service.createDemoVault();
      await service.addHost(
        label: 'Test Server',
        hostname: 'test.example.com',
        port: 22,
        username: 'testuser',
      );
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Hosts (1)'), findsOneWidget);
      expect(find.text('Test Server'), findsOneWidget);
      expect(find.textContaining('test.example.com:22'), findsOneWidget);
    });

    testWidgets('shows add host dialog when button tapped', (tester) async {
      await service.createDemoVault();
      await tester.pumpWidget(buildTestWidget());

      await tester.tap(find.text('Add host'));
      await tester.pumpAndSettle();

      expect(find.text('Add host'), findsNWidgets(2)); // Button + dialog title
      expect(find.text('Label'), findsOneWidget);
      expect(find.text('Hostname'), findsOneWidget);
      expect(find.text('Port'), findsOneWidget);
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('shows add identity dialog when button tapped', (tester) async {
      await service.createDemoVault();
      await tester.pumpWidget(buildTestWidget());

      await tester.tap(find.text('Add identity'));
      await tester.pumpAndSettle();

      expect(find.text('Add identity'), findsNWidgets(2)); // Button + dialog title
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Type'), findsOneWidget);
      expect(find.text('Private key (PEM/OpenSSH)'), findsOneWidget);
      expect(find.text('Load key from file'), findsOneWidget);
      expect(find.text('Paste'), findsOneWidget);
    });

    testWidgets('can cancel add host dialog', (tester) async {
      await service.createDemoVault();
      await tester.pumpWidget(buildTestWidget());

      await tester.tap(find.text('Add host'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog should be closed
      expect(find.text('Label'), findsNothing);
    });

    testWidgets('shows edit and delete buttons for hosts', (tester) async {
      await service.createDemoVault();
      await service.addHost(
        label: 'Server 1',
        hostname: 'server1.example.com',
        port: 22,
        username: 'admin',
      );
      await tester.pumpWidget(buildTestWidget());

      // Find the edit and delete icon buttons
      expect(find.byIcon(Icons.edit), findsOneWidget);
      expect(find.byIcon(Icons.delete), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget); // Connect button
    });

    testWidgets('shows edit and delete buttons for identities', (tester) async {
      await service.createDemoVault();
      await service.addIdentity(
        name: 'My Key',
        type: 'ssh-rsa',
        privateKey: '-----BEGIN RSA PRIVATE KEY-----\ntest\n-----END RSA PRIVATE KEY-----',
      );
      await tester.pumpWidget(buildTestWidget());

      // Should have 2 edit and 2 delete buttons if both identity and host exist
      // But we only have identity, so 1 of each
      expect(find.byIcon(Icons.edit), findsOneWidget);
      expect(find.byIcon(Icons.delete), findsOneWidget);
    });

    testWidgets('can delete host', (tester) async {
      await service.createDemoVault();
      await service.addHost(
        label: 'To Delete',
        hostname: 'delete.me',
        port: 22,
        username: 'user',
      );
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Hosts (1)'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete).first);
      await tester.pumpAndSettle();

      expect(find.text('Hosts (0)'), findsOneWidget);
      expect(find.text('To Delete'), findsNothing);
    });

    testWidgets('can delete identity', (tester) async {
      await service.createDemoVault();
      await service.addIdentity(
        name: 'To Delete',
        type: 'ssh-ed25519',
        privateKey: '-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----',
      );
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Identities (1)'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete).first);
      await tester.pumpAndSettle();

      expect(find.text('Identities (0)'), findsOneWidget);
      expect(find.text('To Delete'), findsNothing);
    });

    testWidgets('connect button triggers onConnectHost callback',
        (tester) async {
      await service.createDemoVault();
      await service.addHost(
        label: 'Connect Me',
        hostname: 'connect.example.com',
        port: 2222,
        username: 'connector',
      );
      await tester.pumpWidget(buildTestWidget());

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();

      expect(connectedHost, isNotNull);
      expect(connectedHost!.label, equals('Connect Me'));
      expect(connectedHost!.hostname, equals('connect.example.com'));
      expect(connectedHost!.port, equals(2222));
      expect(connectedHost!.username, equals('connector'));
    });

    testWidgets('shows identity dropdown in host dialog when identities exist',
        (tester) async {
      await service.createDemoVault();
      await service.addIdentity(
        name: 'Available Key',
        type: 'ssh-ed25519',
        privateKey: '-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----',
      );
      await tester.pumpWidget(buildTestWidget());

      await tester.tap(find.text('Add host'));
      await tester.pumpAndSettle();

      expect(find.text('Identity'), findsOneWidget);
    });

    testWidgets('host displays linked identity id when set', (tester) async {
      await service.createDemoVault();
      await service.addIdentity(
        name: 'Linked Key',
        type: 'ssh-ed25519',
        privateKey: '-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----',
      );
      final identity = service.currentData!.identities.first;
      await service.addHost(
        label: 'Host With Key',
        hostname: 'keyed.example.com',
        port: 22,
        username: 'keyuser',
        identityId: identity.id,
      );
      await tester.pumpWidget(buildTestWidget());

      expect(find.textContaining('key: ${identity.id}'), findsOneWidget);
    });
  });
}
