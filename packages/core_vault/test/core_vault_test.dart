import 'dart:io';

import 'package:core_vault/core_vault.dart';
import 'package:test/test.dart';

void main() {
  group('VaultFile', () {
    test('create → open roundtrip succeeds', () async {
      final dir = await Directory.systemTemp.createTemp('vibedterm_vault_');
      final file = File('${dir.path}/vault.vlt');
      const payload = VaultPayload(
        data: VaultData(
          version: 1,
          revision: 1,
          deviceId: 'test-device',
          createdAt: '2024-01-01T00:00:00Z',
          updatedAt: '2024-01-01T00:00:00Z',
        ),
      );

      final created = await VaultFile.create(
        file: file,
        password: 'correct horse battery staple',
        payload: payload,
      );
      expect(created.header.version, 1);
      expect(await file.exists(), isTrue);

      final opened = await VaultFile.open(
        file: file,
        password: 'correct horse battery staple',
      );
      expect(opened.payload.data.deviceId, 'test-device');
      expect(opened.payload.data.hosts, isEmpty);

      await dir.delete(recursive: true);
    });

    test('wrong password fails with VaultException', () async {
      final dir = await Directory.systemTemp.createTemp('vibedterm_vault_');
      final file = File('${dir.path}/vault.vlt');
      const payload = VaultPayload(
        data: VaultData(
          version: 1,
          revision: 1,
          deviceId: 'test-device',
          createdAt: '2024-01-01T00:00:00Z',
          updatedAt: '2024-01-01T00:00:00Z',
        ),
      );
      await VaultFile.create(
        file: file,
        password: 'correct horse battery staple',
        payload: payload,
      );

      await expectLater(
        VaultFile.open(file: file, password: 'wrong'),
        throwsA(isA<VaultException>()),
      );

      await dir.delete(recursive: true);
    });

    test('tampering is detected', () async {
      final dir = await Directory.systemTemp.createTemp('vibedterm_vault_');
      final file = File('${dir.path}/vault.vlt');
      const payload = VaultPayload(
        data: VaultData(
          version: 1,
          revision: 1,
          deviceId: 'test-device',
          createdAt: '2024-01-01T00:00:00Z',
          updatedAt: '2024-01-01T00:00:00Z',
        ),
      );
      await VaultFile.create(
        file: file,
        password: 'correct horse battery staple',
        payload: payload,
      );

      final bytes = await file.readAsBytes();
      bytes[bytes.length - 1] ^= 0xFF;
      await file.writeAsBytes(bytes, flush: true);

      await expectLater(
        VaultFile.open(file: file, password: 'correct horse battery staple'),
        throwsA(isA<VaultException>()),
      );

      await dir.delete(recursive: true);
    });

    test('CRUD operations update revision and data', () async {
      final dir = await Directory.systemTemp.createTemp('vibedterm_vault_');
      final file = File('${dir.path}/vault.vlt');
      const initialPayload = VaultPayload(
        data: VaultData(
          version: 1,
          revision: 1,
          deviceId: 'test-device',
          createdAt: '2024-01-01T00:00:00Z',
          updatedAt: '2024-01-01T00:00:00Z',
        ),
      );

      final vault = await VaultFile.create(
        file: file,
        password: 'pw',
        payload: initialPayload,
      );
      const host = VaultHost(
        id: 'h1',
        label: 'local',
        hostname: 'localhost',
        username: 'root',
      );
      vault.upsertHost(host);
      expect(vault.payload.data.hosts.length, 1);
      expect(vault.payload.data.revision, 2);

      vault.removeHost('h1');
      expect(vault.payload.data.hosts, isEmpty);
      expect(vault.payload.data.revision, 3);

      await dir.delete(recursive: true);
    });

    test('validation catches invalid host and identity links', () async {
      final dir = await Directory.systemTemp.createTemp('vibedterm_vault_');
      final file = File('${dir.path}/vault.vlt');
      const payload = VaultPayload(
        data: VaultData(
          version: 1,
          revision: 1,
          deviceId: 'test-device',
          createdAt: '2024-01-01T00:00:00Z',
          updatedAt: '2024-01-01T00:00:00Z',
        ),
      );
      final vault = await VaultFile.create(
        file: file,
        password: 'pw',
        payload: payload,
      );

      expect(
        () => vault.upsertHost(
          const VaultHost(
            id: 'h1',
            label: '',
            hostname: 'localhost',
            username: 'root',
          ),
        ),
        throwsA(isA<VaultValidationException>()),
      );

      expect(
        () => vault.upsertHost(
          const VaultHost(
            id: 'h2',
            label: 'bad identity',
            hostname: 'localhost',
            username: 'root',
            identityId: 'missing',
          ),
        ),
        throwsA(isA<VaultValidationException>()),
      );

      await dir.delete(recursive: true);
    });

    test('validation catches invalid private key format', () async {
      final dir = await Directory.systemTemp.createTemp('vibedterm_vault_');
      final file = File('${dir.path}/vault.vlt');
      const payload = VaultPayload(
        data: VaultData(
          version: 1,
          revision: 1,
          deviceId: 'test-device',
          createdAt: '2024-01-01T00:00:00Z',
          updatedAt: '2024-01-01T00:00:00Z',
        ),
      );
      final vault = await VaultFile.create(
        file: file,
        password: 'pw',
        payload: payload,
      );

      expect(
        () => vault.upsertIdentity(
          const VaultIdentity(
            id: 'id1',
            name: 'bad',
            type: 'ssh-ed25519',
            privateKey: 'not-a-pem',
          ),
        ),
        throwsA(isA<VaultValidationException>()),
      );

      await dir.delete(recursive: true);
    });

    test('updateMeta stores metadata and bumps revision', () async {
      final dir = await Directory.systemTemp.createTemp('vibedterm_vault_');
      final file = File('${dir.path}/vault.vlt');
      const payload = VaultPayload(
        data: VaultData(
          version: 1,
          revision: 1,
          deviceId: 'test-device',
          createdAt: '2024-01-01T00:00:00Z',
          updatedAt: '2024-01-01T00:00:00Z',
        ),
      );
      final vault = await VaultFile.create(
        file: file,
        password: 'pw',
        payload: payload,
      );

      vault.updateMeta({
        'trustedHostKeys': {
          'example.com': ['aa:bb:cc'],
        },
      });
      expect(vault.payload.data.meta['trustedHostKeys'], isNotNull);
      expect(vault.payload.data.revision, 2);

      await vault.save();
      final reopened = await VaultFile.open(file: file, password: 'pw');
      expect(
        reopened.payload.data.meta['trustedHostKeys']['example.com'],
        contains('aa:bb:cc'),
      );

      await dir.delete(recursive: true);
    });
  });
}
