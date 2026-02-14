import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'crypto.dart';
import 'exceptions.dart';
import 'models.dart';
import 'validation.dart';
import 'vault_header.dart';

/// Main entry point for creating, opening, and saving encrypted vault files.
///
/// A vault file consists of a binary header (unencrypted, but authenticated)
/// followed by the encrypted JSON payload containing hosts, identities, and
/// settings.
class VaultFile {
  VaultFile({
    required this.file,
    required VaultHeader header,
    required VaultPayload payload,
    required SecretKey key,
  })  : _header = header,
        _key = key,
        _payload = payload;

  final File file;
  VaultHeader _header;
  VaultPayload _payload;
  final SecretKey _key;

  VaultHeader get header => _header;
  VaultPayload get payload => _payload;

  /// Validate the current payload; throws [VaultValidationException] on issues.
  void validate() {
    final identityIds = _payload.data.identities.map((i) => i.id).toSet();
    checkDuplicates(_payload.data.hosts.map((h) => h.id), 'Host id');
    checkDuplicates(_payload.data.identities.map((i) => i.id), 'Identity id');
    checkDuplicates(_payload.data.snippets.map((s) => s.id), 'Snippet id');
    checkDuplicates(_payload.data.hosts.map((h) => h.label), 'Host label');
    for (final host in _payload.data.hosts) {
      validateHost(host, identityIds: identityIds);
    }
    for (final identity in _payload.data.identities) {
      validateIdentity(identity);
    }
    for (final snippet in _payload.data.snippets) {
      validateSnippet(snippet);
    }
  }

  /// Create a new vault on disk with the given password.
  static Future<VaultFile> create({
    required File file,
    required String password,
    required VaultPayload payload,
    VaultCreateConfig config = const VaultCreateConfig(),
  }) async {
    if (password.isEmpty) {
      throw VaultException('Password must not be empty.');
    }
    final cipher = cipherForKind(config.cipherKind);
    final nonce = cipher.newNonce();
    final saltKey = SecretKeyData.random(length: defaultSaltLength);
    final salt = await saltKey.extractBytes();
    final header = VaultHeader(
      version: 1,
      kdf: config.kdfKind,
      kdfMemoryKiB: config.kdfMemoryKiB,
      kdfIterations: config.kdfIterations,
      kdfParallelism: config.kdfParallelism,
      kdfSalt: salt,
      cipher: config.cipherKind,
      nonce: nonce,
      payloadLength: payload.toBytes().length,
    );
    final key = await deriveKey(
      password: password,
      kind: config.kdfKind,
      memoryKiB: config.kdfMemoryKiB,
      iterations: config.kdfIterations,
      parallelism: config.kdfParallelism,
      salt: salt,
    );

    final vault = VaultFile(
      file: file,
      header: header,
      payload: payload,
      key: key,
    );
    vault.validate();
    await vault._write();
    return vault;
  }

  /// Open an existing vault file with the given password.
  static Future<VaultFile> open({
    required File file,
    required String password,
  }) async {
    if (!await file.exists()) {
      throw VaultException('Vault file not found: ${file.path}');
    }
    final bytes = await file.readAsBytes();
    final header = VaultHeader.parse(bytes);
    if (header.version != 1) {
      throw VaultException('Unsupported vault version ${header.version}.');
    }
    final headerLength = header.encodedLength;
    if (bytes.length <= headerLength) {
      throw VaultException('Vault data is truncated.');
    }
    final headerBytes = Uint8List.sublistView(bytes, 0, headerLength);
    final ciphertext =
        Uint8List.sublistView(bytes, headerLength, bytes.length);
    final key = await deriveKey(
      password: password,
      kind: header.kdf,
      memoryKiB: header.kdfMemoryKiB,
      iterations: header.kdfIterations,
      parallelism: header.kdfParallelism,
      salt: header.kdfSalt,
    );
    final cipher = cipherForKind(header.cipher);
    final macLength = cipher.macAlgorithm.macLength;
    if (ciphertext.length <= macLength) {
      throw VaultException('Vault data is truncated.');
    }
    try {
        final clear = await cipher.decrypt(
          SecretBox(
            ciphertext.sublist(
              0,
              ciphertext.length - macLength,
            ),
            nonce: header.nonce,
            mac: Mac(ciphertext.sublist(
              ciphertext.length - macLength,
            )),
          ),
          secretKey: key,
          aad: headerBytes,
        );
      if (clear.length != header.payloadLength) {
        throw VaultException('Payload length mismatch.');
      }
      final payload = VaultPayload.fromBytes(Uint8List.fromList(clear));
      final vault = VaultFile(
        file: file,
        header: header,
        payload: payload,
        key: key,
      );
      vault.validate();
      return vault;
    } on SecretBoxAuthenticationError {
      throw VaultException('Invalid password or vault is corrupted.');
    }
  }

  /// Save changes back to disk using the existing key.
  Future<void> save() async {
    final cipher = cipherForKind(_header.cipher);
    final nonce = cipher.newNonce();
    _header = _header.copyWith(
      nonce: nonce,
      payloadLength: _payload.toBytes().length,
    );
    await _write();
  }

  /// Upsert a host entry and bump revision/updatedAt.
  void upsertHost(VaultHost host) {
    final current = _payload.data;
    final identityIds = current.identities.map((i) => i.id).toSet();
    validateHost(host, identityIds: identityIds);
    final hosts = [...current.hosts];
    final idx = hosts.indexWhere((h) => h.id == host.id);
    if (idx >= 0) {
      hosts[idx] = host;
    } else {
      hosts.add(host);
    }
    _setData(current.copyWith(
      hosts: hosts,
      revision: current.revision + 1,
      updatedAt: nowIso(),
    ));
  }

  /// Remove a host by id and bump revision if found.
  void removeHost(String hostId) {
    final current = _payload.data;
    final hosts = current.hosts.where((h) => h.id != hostId).toList();
    if (hosts.length == current.hosts.length) {
      return;
    }
    _setData(current.copyWith(
      hosts: hosts,
      revision: current.revision + 1,
      updatedAt: nowIso(),
    ));
  }

  /// Upsert an identity and bump revision/updatedAt.
  void upsertIdentity(VaultIdentity identity) {
    final current = _payload.data;
    validateIdentity(identity);
    final identities = [...current.identities];
    final idx = identities.indexWhere((i) => i.id == identity.id);
    if (idx >= 0) {
      identities[idx] = identity;
    } else {
      identities.add(identity);
    }
    _setData(current.copyWith(
      identities: identities,
      revision: current.revision + 1,
      updatedAt: nowIso(),
    ));
  }

  void removeIdentity(String identityId) {
    final current = _payload.data;
    final identities =
        current.identities.where((i) => i.id != identityId).toList();
    if (identities.length == current.identities.length) {
      return;
    }
    final hosts = current.hosts
        .map((h) => h.identityId == identityId ? h.copyWith(identityId: null) : h)
        .toList();
    _setData(current.copyWith(
      identities: identities,
      hosts: hosts,
      revision: current.revision + 1,
      updatedAt: nowIso(),
    ));
  }

  /// Upsert a snippet and bump revision/updatedAt.
  void upsertSnippet(VaultSnippet snippet) {
    final current = _payload.data;
    validateSnippet(snippet);
    final snippets = [...current.snippets];
    final idx = snippets.indexWhere((s) => s.id == snippet.id);
    if (idx >= 0) {
      snippets[idx] = snippet;
    } else {
      snippets.add(snippet);
    }
    _setData(current.copyWith(
      snippets: snippets,
      revision: current.revision + 1,
      updatedAt: nowIso(),
    ));
  }

  /// Remove a snippet by id and bump revision if found.
  void removeSnippet(String snippetId) {
    final current = _payload.data;
    final snippets = current.snippets.where((s) => s.id != snippetId).toList();
    if (snippets.length == current.snippets.length) {
      return;
    }
    _setData(current.copyWith(
      snippets: snippets,
      revision: current.revision + 1,
      updatedAt: nowIso(),
    ));
  }

  /// Update arbitrary metadata map and bump revision/updatedAt.
  void updateMeta(Map<String, dynamic> meta) {
    final current = _payload.data;
    _setData(
      current.copyWith(
        meta: meta,
        revision: current.revision + 1,
        updatedAt: nowIso(),
      ),
    );
  }

  /// Update vault settings and bump revision/updatedAt.
  void updateSettings(VaultSettings settings) {
    final current = _payload.data;
    _setData(
      current.copyWith(
        settings: settings,
        revision: current.revision + 1,
        updatedAt: nowIso(),
      ),
    );
  }

  void _setData(VaultData data) {
    _payload = VaultPayload(data: data);
  }

  Future<void> _write() async {
    final cipher = cipherForKind(_header.cipher);
    final headerBytes = _header.toBytes();
    final plaintext = _payload.toBytes();
    final secretBox = await cipher.encrypt(
      plaintext,
      secretKey: _key,
      nonce: _header.nonce,
      aad: headerBytes,
    );
    final bytes = Uint8List(
      headerBytes.length +
          secretBox.cipherText.length +
          secretBox.mac.bytes.length,
    );
    bytes.setAll(0, headerBytes);
    bytes.setAll(headerBytes.length, secretBox.cipherText);
    bytes.setAll(
      headerBytes.length + secretBox.cipherText.length,
      secretBox.mac.bytes,
    );
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
  }
}
