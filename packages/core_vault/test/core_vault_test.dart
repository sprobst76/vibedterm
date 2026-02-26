import 'dart:io';
import 'dart:typed_data';

import 'package:core_vault/core_vault.dart';
import 'package:test/test.dart';

/// A minimal valid OpenSSH private key (for testing PEM validation).
const _validOpenSshKey = '''-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACBfRkM1dkdGWjhXRGhKTlNaa0FLVFZ0UlJNMTJGYm1KUEEAAAAA
-----END OPENSSH PRIVATE KEY-----''';

const _validRsaKey = '''-----BEGIN RSA PRIVATE KEY-----
MIIBogIBAAJBALMBmzORlmAKYADJV3VmNKn3dyAu8BnVVZNRbfOjmUvBGFnfGUfK
xlPSGk7WEFMzblkmvMkOBuTmSEKxB3/rHEMCAwEAAQJAEz4M/u7MHFiID5LdOSkc
-----END RSA PRIVATE KEY-----''';

const _validEcKey = '''-----BEGIN EC PRIVATE KEY-----
MHQCAQEEIPbFdKz1dIClVtjbzfEWwjjqFE3bSMFaGfKLJ1dR8bSgoAcGBSuBBAAi
oWQDYgAEXMAG38C9bkHrUHiMunG+aJJy/nGhB8M9JDsxWp9MSaeEkj8CDTUTLRB0
-----END EC PRIVATE KEY-----''';

VaultPayload _emptyPayload() => const VaultPayload(
      data: VaultData(
        version: 1,
        revision: 1,
        deviceId: 'test-device',
        createdAt: '2024-01-01T00:00:00Z',
        updatedAt: '2024-01-01T00:00:00Z',
      ),
    );

Future<(VaultFile, Directory)> _createVault({
  String password = 'pw',
  VaultCreateConfig config = const VaultCreateConfig(),
}) async {
  final dir = await Directory.systemTemp.createTemp('vibedterm_vault_');
  final file = File('${dir.path}/vault.vlt');
  final vault = await VaultFile.create(
    file: file,
    password: password,
    payload: _emptyPayload(),
    config: config,
  );
  return (vault, dir);
}

void main() {
  // ── VaultFile basic operations ──────────────────────────────────────

  group('VaultFile', () {
    test('create → open roundtrip succeeds', () async {
      final (vault, dir) = await _createVault(
        password: 'correct horse battery staple',
      );
      expect(vault.header.version, 1);
      expect(await vault.file.exists(), isTrue);

      final opened = await VaultFile.open(
        file: vault.file,
        password: 'correct horse battery staple',
      );
      expect(opened.payload.data.deviceId, 'test-device');
      expect(opened.payload.data.hosts, isEmpty);
      await dir.delete(recursive: true);
    });

    test('wrong password fails with VaultException', () async {
      final (vault, dir) = await _createVault(
        password: 'correct horse battery staple',
      );
      await expectLater(
        VaultFile.open(file: vault.file, password: 'wrong'),
        throwsA(isA<VaultException>()),
      );
      await dir.delete(recursive: true);
    });

    test('empty password throws VaultException', () async {
      final dir = await Directory.systemTemp.createTemp('vibedterm_vault_');
      final file = File('${dir.path}/vault.vlt');
      await expectLater(
        VaultFile.create(
          file: file,
          password: '',
          payload: _emptyPayload(),
        ),
        throwsA(isA<VaultException>()),
      );
      await dir.delete(recursive: true);
    });

    test('tampering is detected', () async {
      final (vault, dir) = await _createVault(
        password: 'correct horse battery staple',
      );
      final bytes = await vault.file.readAsBytes();
      bytes[bytes.length - 1] ^= 0xFF;
      await vault.file.writeAsBytes(bytes, flush: true);

      await expectLater(
        VaultFile.open(
            file: vault.file, password: 'correct horse battery staple'),
        throwsA(isA<VaultException>()),
      );
      await dir.delete(recursive: true);
    });

    test('CRUD operations update revision and data', () async {
      final (vault, dir) = await _createVault();
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

    test('updateMeta stores metadata and bumps revision', () async {
      final (vault, dir) = await _createVault();
      vault.updateMeta({
        'trustedHostKeys': {
          'example.com': ['aa:bb:cc'],
        },
      });
      expect(vault.payload.data.meta['trustedHostKeys'], isNotNull);
      expect(vault.payload.data.revision, 2);

      await vault.save();
      final reopened =
          await VaultFile.open(file: vault.file, password: 'pw');
      expect(
        reopened.payload.data.meta['trustedHostKeys']['example.com'],
        contains('aa:bb:cc'),
      );
      await dir.delete(recursive: true);
    });
  });

  // ── AES-256-GCM cipher path ─────────────────────────────────────────

  group('AES-256-GCM', () {
    test('create → open roundtrip with AES-256-GCM', () async {
      final (vault, dir) = await _createVault(
        password: 'aes-test-password',
        config: const VaultCreateConfig(
          cipherKind: CipherKind.aes256Gcm,
          kdfMemoryKiB: 1024,
          kdfIterations: 1,
        ),
      );
      vault.upsertHost(const VaultHost(
        id: 'h1',
        label: 'aes-host',
        hostname: 'example.com',
        username: 'user',
      ));
      await vault.save();

      final opened = await VaultFile.open(
        file: vault.file,
        password: 'aes-test-password',
      );
      expect(opened.payload.data.hosts.length, 1);
      expect(opened.payload.data.hosts.first.label, 'aes-host');
      expect(opened.header.cipher, CipherKind.aes256Gcm);
      await dir.delete(recursive: true);
    });

    test('tampering detected with AES-256-GCM', () async {
      final (vault, dir) = await _createVault(
        password: 'aes-tamper',
        config: const VaultCreateConfig(
          cipherKind: CipherKind.aes256Gcm,
          kdfMemoryKiB: 1024,
          kdfIterations: 1,
        ),
      );
      final bytes = await vault.file.readAsBytes();
      bytes[bytes.length - 1] ^= 0xFF;
      await vault.file.writeAsBytes(bytes, flush: true);

      await expectLater(
        VaultFile.open(file: vault.file, password: 'aes-tamper'),
        throwsA(isA<VaultException>()),
      );
      await dir.delete(recursive: true);
    });
  });

  // ── VaultHeader binary format ───────────────────────────────────────

  group('VaultHeader', () {
    test('toBytes → parse roundtrip preserves all fields', () {
      final salt = List<int>.generate(16, (i) => i + 1);
      final nonce = List<int>.generate(24, (i) => i + 100);
      final header = VaultHeader(
        version: 1,
        kdf: KdfKind.argon2id,
        kdfMemoryKiB: 65536,
        kdfIterations: 3,
        kdfParallelism: 1,
        kdfSalt: salt,
        cipher: CipherKind.xchacha20Poly1305,
        nonce: nonce,
        payloadLength: 42,
      );

      final bytes = header.toBytes();
      final parsed = VaultHeader.parse(bytes);

      expect(parsed.version, 1);
      expect(parsed.kdf, KdfKind.argon2id);
      expect(parsed.kdfMemoryKiB, 65536);
      expect(parsed.kdfIterations, 3);
      expect(parsed.kdfParallelism, 1);
      expect(parsed.kdfSalt, salt);
      expect(parsed.cipher, CipherKind.xchacha20Poly1305);
      expect(parsed.nonce, nonce);
      expect(parsed.payloadLength, 42);
    });

    test('roundtrip with AES-GCM cipher', () {
      final salt = List<int>.generate(16, (i) => i);
      final nonce = List<int>.generate(12, (i) => i); // AES-GCM uses 12-byte nonce
      final header = VaultHeader(
        version: 1,
        kdf: KdfKind.argon2id,
        kdfMemoryKiB: 1024,
        kdfIterations: 1,
        kdfParallelism: 1,
        kdfSalt: salt,
        cipher: CipherKind.aes256Gcm,
        nonce: nonce,
        payloadLength: 999,
      );

      final bytes = header.toBytes();
      final parsed = VaultHeader.parse(bytes);
      expect(parsed.cipher, CipherKind.aes256Gcm);
      expect(parsed.nonce.length, 12);
      expect(parsed.payloadLength, 999);
    });

    test('invalid magic bytes throws VaultException', () {
      final bytes = Uint8List(64);
      bytes[0] = 0x00; // Wrong magic
      bytes[1] = 0x00;
      bytes[2] = 0x00;
      bytes[3] = 0x00;
      expect(
        () => VaultHeader.parse(bytes),
        throwsA(isA<VaultException>()),
      );
    });

    test('truncated header throws VaultException', () {
      final bytes = Uint8List(10); // Too short
      expect(
        () => VaultHeader.parse(bytes),
        throwsA(isA<VaultException>()),
      );
    });

    test('unknown KDF id throws VaultException', () {
      // Build a valid-ish header with wrong KDF id
      final salt = List<int>.generate(16, (i) => i);
      final header = VaultHeader(
        version: 1,
        kdf: KdfKind.argon2id,
        kdfMemoryKiB: 1024,
        kdfIterations: 1,
        kdfParallelism: 1,
        kdfSalt: salt,
        cipher: CipherKind.xchacha20Poly1305,
        nonce: List<int>.generate(24, (i) => 0),
        payloadLength: 0,
      );
      final bytes = header.toBytes();
      bytes[5] = 0xFF; // Invalid KDF id
      expect(
        () => VaultHeader.parse(bytes),
        throwsA(isA<VaultException>()),
      );
    });

    test('unknown cipher id throws VaultException', () {
      final salt = List<int>.generate(16, (i) => i);
      final header = VaultHeader(
        version: 1,
        kdf: KdfKind.argon2id,
        kdfMemoryKiB: 1024,
        kdfIterations: 1,
        kdfParallelism: 1,
        kdfSalt: salt,
        cipher: CipherKind.xchacha20Poly1305,
        nonce: List<int>.generate(24, (i) => 0),
        payloadLength: 0,
      );
      final bytes = header.toBytes();
      bytes[34] = 0xFF; // Invalid cipher id
      expect(
        () => VaultHeader.parse(bytes),
        throwsA(isA<VaultException>()),
      );
    });
  });

  // ── Validation ──────────────────────────────────────────────────────

  group('Validation', () {
    test('valid OpenSSH key accepted', () async {
      final (vault, dir) = await _createVault();
      vault.upsertIdentity(const VaultIdentity(
        id: 'id1',
        name: 'test-key',
        type: 'ssh-ed25519',
        privateKey: _validOpenSshKey,
      ));
      expect(vault.payload.data.identities.length, 1);
      await dir.delete(recursive: true);
    });

    test('valid RSA PEM key accepted', () async {
      final (vault, dir) = await _createVault();
      vault.upsertIdentity(const VaultIdentity(
        id: 'id1',
        name: 'rsa-key',
        type: 'ssh-rsa',
        privateKey: _validRsaKey,
      ));
      expect(vault.payload.data.identities.length, 1);
      await dir.delete(recursive: true);
    });

    test('valid EC PEM key accepted', () async {
      final (vault, dir) = await _createVault();
      vault.upsertIdentity(const VaultIdentity(
        id: 'id1',
        name: 'ec-key',
        type: 'ecdsa',
        privateKey: _validEcKey,
      ));
      expect(vault.payload.data.identities.length, 1);
      await dir.delete(recursive: true);
    });

    test('invalid key rejected', () async {
      final (vault, dir) = await _createVault();
      expect(
        () => vault.upsertIdentity(const VaultIdentity(
          id: 'id1',
          name: 'bad',
          type: 'ssh-ed25519',
          privateKey: 'not-a-pem',
        )),
        throwsA(isA<VaultValidationException>()),
      );
      await dir.delete(recursive: true);
    });

    test('key missing END marker rejected', () async {
      final (vault, dir) = await _createVault();
      expect(
        () => vault.upsertIdentity(const VaultIdentity(
          id: 'id1',
          name: 'no-end',
          type: 'ssh-ed25519',
          privateKey:
              '-----BEGIN OPENSSH PRIVATE KEY-----\nAAAAAAAAAAAAAAAA\n',
        )),
        throwsA(isA<VaultValidationException>()),
      );
      await dir.delete(recursive: true);
    });

    test('empty string key rejected', () async {
      final (vault, dir) = await _createVault();
      expect(
        () => vault.upsertIdentity(const VaultIdentity(
          id: 'id1',
          name: 'empty',
          type: 'ssh-ed25519',
          privateKey: '',
        )),
        throwsA(isA<VaultValidationException>()),
      );
      await dir.delete(recursive: true);
    });

    test('duplicate host labels rejected by validate()', () async {
      final (vault, dir) = await _createVault();
      vault.upsertHost(const VaultHost(
        id: 'h1',
        label: 'server',
        hostname: 'a.com',
        username: 'root',
      ));
      // upsertHost doesn't check cross-host duplicates, but validate() does
      vault.upsertHost(const VaultHost(
        id: 'h2',
        label: 'server', // duplicate label
        hostname: 'b.com',
        username: 'root',
      ));
      expect(
        () => vault.validate(),
        throwsA(isA<VaultValidationException>()),
      );
      await dir.delete(recursive: true);
    });

    test('dangling identity reference rejected', () async {
      final (vault, dir) = await _createVault();
      expect(
        () => vault.upsertHost(const VaultHost(
          id: 'h1',
          label: 'bad-ref',
          hostname: 'example.com',
          username: 'root',
          identityId: 'nonexistent',
        )),
        throwsA(isA<VaultValidationException>()),
      );
      await dir.delete(recursive: true);
    });

    test('empty host label rejected', () async {
      final (vault, dir) = await _createVault();
      expect(
        () => vault.upsertHost(const VaultHost(
          id: 'h1',
          label: '',
          hostname: 'example.com',
          username: 'root',
        )),
        throwsA(isA<VaultValidationException>()),
      );
      await dir.delete(recursive: true);
    });
  });

  // ── VaultMigrator ───────────────────────────────────────────────────

  group('VaultMigrator', () {
    test('version 1 passes through unchanged', () {
      const data = VaultData(
        version: 1,
        revision: 5,
        deviceId: 'dev1',
        createdAt: '2024-01-01T00:00:00Z',
        updatedAt: '2024-06-01T00:00:00Z',
      );
      final migrated = VaultMigrator.migrate(data);
      expect(migrated.version, 1);
      expect(migrated.revision, 5);
      expect(migrated.deviceId, 'dev1');
    });

    test('unsupported version throws VaultException', () {
      const data = VaultData(
        version: 2,
        revision: 1,
        deviceId: 'dev1',
        createdAt: '2024-01-01T00:00:00Z',
        updatedAt: '2024-01-01T00:00:00Z',
      );
      expect(
        () => VaultMigrator.migrate(data),
        throwsA(isA<VaultException>()),
      );
    });
  });

  // ── Model JSON serialization ────────────────────────────────────────

  group('VaultHost JSON', () {
    test('full roundtrip', () {
      const host = VaultHost(
        id: 'h1',
        label: 'Production',
        hostname: 'prod.example.com',
        port: 2222,
        username: 'deploy',
        identityId: 'id1',
        group: 'Production',
        tags: ['web', 'important'],
        tmuxEnabled: true,
        tmuxSessionName: 'main',
        createdAt: '2024-01-01T00:00:00Z',
        updatedAt: '2024-06-01T00:00:00Z',
      );
      final json = host.toJson();
      final restored = VaultHost.fromJson(json);
      expect(restored.id, 'h1');
      expect(restored.label, 'Production');
      expect(restored.hostname, 'prod.example.com');
      expect(restored.port, 2222);
      expect(restored.username, 'deploy');
      expect(restored.identityId, 'id1');
      expect(restored.group, 'Production');
      expect(restored.tags, ['web', 'important']);
      expect(restored.tmuxEnabled, true);
      expect(restored.tmuxSessionName, 'main');
    });

    test('minimal host with defaults', () {
      final json = {
        'id': 'h1',
        'label': 'test',
        'hostname': 'localhost',
        'username': 'root',
      };
      final host = VaultHost.fromJson(json);
      expect(host.port, 22); // default
      expect(host.identityId, isNull);
      expect(host.group, isNull);
      expect(host.tags, isEmpty);
      expect(host.tmuxEnabled, false);
      expect(host.tmuxSessionName, isNull);
    });

    test('optional fields omitted when null/default', () {
      const host = VaultHost(
        id: 'h1',
        label: 'test',
        hostname: 'localhost',
        username: 'root',
      );
      final json = host.toJson();
      expect(json.containsKey('identityId'), false);
      expect(json.containsKey('group'), false);
      expect(json.containsKey('tags'), false);
      expect(json.containsKey('tmuxEnabled'), false);
      expect(json.containsKey('tmuxSessionName'), false);
    });

    test('copyWith clearGroup works', () {
      const host = VaultHost(
        id: 'h1',
        label: 'test',
        hostname: 'localhost',
        username: 'root',
        group: 'MyGroup',
      );
      final cleared = host.copyWith(clearGroup: true);
      expect(cleared.group, isNull);
      expect(cleared.label, 'test'); // unchanged
    });
  });

  group('VaultIdentity JSON', () {
    test('roundtrip with passphrase', () {
      const identity = VaultIdentity(
        id: 'id1',
        name: 'My Key',
        type: 'ssh-ed25519',
        privateKey: _validOpenSshKey,
        passphrase: 'secret',
      );
      final json = identity.toJson();
      final restored = VaultIdentity.fromJson(json);
      expect(restored.passphrase, 'secret');
      expect(restored.name, 'My Key');
    });

    test('passphrase omitted when null', () {
      const identity = VaultIdentity(
        id: 'id1',
        name: 'No Pass',
        type: 'ssh-rsa',
        privateKey: _validRsaKey,
      );
      final json = identity.toJson();
      expect(json.containsKey('passphrase'), false);
    });
  });

  group('VaultSettings JSON', () {
    test('default roundtrip', () {
      const settings = VaultSettings();
      final json = settings.toJson();
      final restored = VaultSettings.fromJson(json);
      expect(restored, settings);
    });

    test('partial JSON applies defaults', () {
      final restored = VaultSettings.fromJson({
        'theme': 'dark',
        'sshDefaultPort': 2222,
      });
      expect(restored.theme, 'dark');
      expect(restored.sshDefaultPort, 2222);
      // All other fields should have defaults
      expect(restored.fontSize, 14);
      expect(restored.terminalTheme, 'default');
      expect(restored.sshKeepaliveInterval, 30);
      expect(restored.sshAutoReconnect, false);
    });

    test('empty JSON uses all defaults', () {
      final restored = VaultSettings.fromJson({});
      expect(restored, const VaultSettings());
    });

    test('equality works', () {
      const a = VaultSettings(theme: 'dark');
      const b = VaultSettings(theme: 'dark');
      const c = VaultSettings(theme: 'light');
      expect(a, b);
      expect(a, isNot(c));
    });
  });

  group('VaultSnippet JSON', () {
    test('roundtrip with tags', () {
      const snippet = VaultSnippet(
        id: 's1',
        title: 'Deploy',
        content: 'git pull && make deploy',
        tags: ['deploy', 'production'],
      );
      final json = snippet.toJson();
      final restored = VaultSnippet.fromJson(json);
      expect(restored.title, 'Deploy');
      expect(restored.tags, ['deploy', 'production']);
    });

    test('tags omitted when empty', () {
      const snippet = VaultSnippet(
        id: 's1',
        title: 'Test',
        content: 'echo hello',
      );
      final json = snippet.toJson();
      expect(json.containsKey('tags'), false);
    });

    test('null tags in JSON defaults to empty list', () {
      final restored = VaultSnippet.fromJson({
        'id': 's1',
        'title': 'Test',
        'content': 'echo hello',
      });
      expect(restored.tags, isEmpty);
    });
  });

  group('VaultData', () {
    test('copyWith preserves unmodified fields', () {
      const data = VaultData(
        version: 1,
        revision: 5,
        deviceId: 'dev1',
        createdAt: '2024-01-01T00:00:00Z',
        updatedAt: '2024-01-01T00:00:00Z',
        hosts: [
          VaultHost(
            id: 'h1',
            label: 'test',
            hostname: 'localhost',
            username: 'root',
          ),
        ],
      );
      final modified = data.copyWith(revision: 6);
      expect(modified.revision, 6);
      expect(modified.version, 1); // unchanged
      expect(modified.deviceId, 'dev1'); // unchanged
      expect(modified.hosts.length, 1); // unchanged
    });

    test('JSON roundtrip with all content', () {
      const data = VaultData(
        version: 1,
        revision: 3,
        deviceId: 'dev1',
        createdAt: '2024-01-01T00:00:00Z',
        updatedAt: '2024-06-01T00:00:00Z',
        hosts: [
          VaultHost(
            id: 'h1',
            label: 'server',
            hostname: 'example.com',
            username: 'root',
          ),
        ],
        snippets: [
          VaultSnippet(id: 's1', title: 'cmd', content: 'ls -la'),
        ],
        settings: VaultSettings(theme: 'dark'),
        meta: {'key': 'value'},
      );
      final json = data.toJson();
      final restored = VaultData.fromJson(json);
      expect(restored.version, 1);
      expect(restored.revision, 3);
      expect(restored.hosts.length, 1);
      expect(restored.snippets.length, 1);
      expect(restored.settings.theme, 'dark');
      expect(restored.meta['key'], 'value');
    });
  });

  // ── VaultPayload ────────────────────────────────────────────────────

  group('VaultPayload', () {
    test('toBytes → fromBytes roundtrip', () {
      const data = VaultData(
        version: 1,
        revision: 1,
        deviceId: 'dev1',
        createdAt: '2024-01-01T00:00:00Z',
        updatedAt: '2024-01-01T00:00:00Z',
        hosts: [
          VaultHost(
            id: 'h1',
            label: 'test',
            hostname: 'example.com',
            username: 'root',
          ),
        ],
      );
      const payload = VaultPayload(data: data);
      final bytes = payload.toBytes();
      final restored = VaultPayload.fromBytes(bytes);
      expect(restored.data.hosts.length, 1);
      expect(restored.data.hosts.first.hostname, 'example.com');
    });
  });
}
