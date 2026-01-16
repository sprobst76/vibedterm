library core_vault;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:meta/meta.dart';

const _magic = [0x56, 0x42, 0x54, 0x31]; // ASCII "VBT1"
const _headerFixedBytes = 36; // up to and including nonce length byte.
const _payloadLengthBytes = 4;
const _defaultSaltLength = 16;
const _defaultKeyLength = 32;

/// Supported KDF algorithms.
enum KdfKind { argon2id, scrypt }

/// Supported ciphers for the vault payload.
enum CipherKind { xchacha20Poly1305, aes256Gcm }

/// Errors thrown when vault operations fail.
class VaultException implements Exception {
  VaultException(this.message);
  final String message;

  @override
  String toString() => 'VaultException: $message';
}

/// Validation errors for vault data.
class VaultValidationException extends VaultException {
  VaultValidationException(super.message);
}

/// Header metadata defined in docs/vault_spec_v1.md.
@immutable
class VaultHeader {
  const VaultHeader({
    required this.version,
    required this.kdf,
    required this.kdfMemoryKiB,
    required this.kdfIterations,
    required this.kdfParallelism,
    required this.kdfSalt,
    required this.cipher,
    required this.nonce,
    required this.payloadLength,
  });

  final int version;
  final KdfKind kdf;
  final int kdfMemoryKiB;
  final int kdfIterations;
  final int kdfParallelism;
  final List<int> kdfSalt;
  final CipherKind cipher;
  final List<int> nonce;
  final int payloadLength;

  int get encodedLength => _headerFixedBytes + nonce.length + _payloadLengthBytes;

  VaultHeader copyWith({
    List<int>? nonce,
    int? payloadLength,
  }) {
    return VaultHeader(
      version: version,
      kdf: kdf,
      kdfMemoryKiB: kdfMemoryKiB,
      kdfIterations: kdfIterations,
      kdfParallelism: kdfParallelism,
      kdfSalt: kdfSalt,
      cipher: cipher,
      nonce: nonce ?? this.nonce,
      payloadLength: payloadLength ?? this.payloadLength,
    );
  }

  Uint8List toBytes() {
    final bytes = Uint8List(encodedLength);
    final view = ByteData.view(bytes.buffer);

    bytes.setAll(0, _magic);
    view.setUint8(4, version);
    view.setUint8(5, _kdfToId(kdf));
    view.setUint32(6, kdfMemoryKiB, Endian.little);
    view.setUint32(10, kdfIterations, Endian.little);
    view.setUint32(14, kdfParallelism, Endian.little);
    if (kdfSalt.length != _defaultSaltLength) {
      throw VaultException('kdfSalt must be $_defaultSaltLength bytes.');
    }
    bytes.setAll(18, kdfSalt);
    view.setUint8(34, _cipherToId(cipher));
    view.setUint8(35, nonce.length);
    bytes.setAll(36, nonce);
    view.setUint32(36 + nonce.length, payloadLength, Endian.little);
    return bytes;
  }

  static VaultHeader parse(Uint8List bytes) {
    if (bytes.length < _headerFixedBytes + _payloadLengthBytes) {
      throw VaultException('Header too short.');
    }
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) {
        throw VaultException('Invalid magic header.');
      }
    }
    final view = ByteData.view(bytes.buffer);
    final version = view.getUint8(4);
    final kdfId = view.getUint8(5);
    final kdf = _kdfFromId(kdfId);
    final kdfMemoryKiB = view.getUint32(6, Endian.little);
    final kdfIterations = view.getUint32(10, Endian.little);
    final kdfParallelism = view.getUint32(14, Endian.little);
    final salt = bytes.sublist(18, 34);
    if (salt.length != _defaultSaltLength) {
      throw VaultException('Invalid salt length.');
    }
    final cipherId = view.getUint8(34);
    final cipher = _cipherFromId(cipherId);
    final nonceLength = view.getUint8(35);
    final headerLength = _headerFixedBytes + nonceLength + _payloadLengthBytes;
    if (bytes.length < headerLength) {
      throw VaultException('Header truncated.');
    }
    final nonce = bytes.sublist(36, 36 + nonceLength);
    final payloadLength =
        view.getUint32(36 + nonceLength, Endian.little);
    return VaultHeader(
      version: version,
      kdf: kdf,
      kdfMemoryKiB: kdfMemoryKiB,
      kdfIterations: kdfIterations,
      kdfParallelism: kdfParallelism,
      kdfSalt: List<int>.unmodifiable(salt),
      cipher: cipher,
      nonce: List<int>.unmodifiable(nonce),
      payloadLength: payloadLength,
    );
  }
}

/// Represents a host identity (SSH key).
@immutable
class VaultIdentity {
  const VaultIdentity({
    required this.id,
    required this.name,
    required this.type,
    required this.privateKey,
    this.passphrase,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String type; // e.g., "ssh-rsa", "ssh-ed25519".
  final String privateKey; // PEM or OpenSSH private key.
  final String? passphrase;
  final String? createdAt;
  final String? updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'privateKey': privateKey,
        if (passphrase != null) 'passphrase': passphrase,
        if (createdAt != null) 'createdAt': createdAt,
        if (updatedAt != null) 'updatedAt': updatedAt,
      };

  factory VaultIdentity.fromJson(Map<String, dynamic> json) {
    return VaultIdentity(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      privateKey: json['privateKey'] as String,
      passphrase: json['passphrase'] as String?,
      createdAt: json['createdAt'] as String?,
      updatedAt: json['updatedAt'] as String?,
    );
  }

  VaultIdentity copyWith({
    String? name,
    String? type,
    String? privateKey,
    String? passphrase,
    String? createdAt,
    String? updatedAt,
  }) {
    return VaultIdentity(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      privateKey: privateKey ?? this.privateKey,
      passphrase: passphrase ?? this.passphrase,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Reusable snippets stored in the vault (e.g., command templates).
@immutable
class VaultSnippet {
  const VaultSnippet({
    required this.id,
    required this.title,
    required this.content,
    this.tags = const <String>[],
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String content;
  final List<String> tags;
  final String? createdAt;
  final String? updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        if (tags.isNotEmpty) 'tags': tags,
        if (createdAt != null) 'createdAt': createdAt,
        if (updatedAt != null) 'updatedAt': updatedAt,
      };

  factory VaultSnippet.fromJson(Map<String, dynamic> json) {
    return VaultSnippet(
      id: json['id'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      tags: (json['tags'] as List?)?.cast<String>() ?? const <String>[],
      createdAt: json['createdAt'] as String?,
      updatedAt: json['updatedAt'] as String?,
    );
  }
}

/// User preferences/settings stored in the vault.
@immutable
class VaultSettings {
  const VaultSettings({
    this.theme = 'system',
    this.fontSize = 14,
    this.extraKeys = false,
    this.terminalTheme = 'default',
    this.terminalFontSize = 14.0,
    this.terminalFontFamily = 'monospace',
    this.terminalOpacity = 1.0,
    this.terminalCursorStyle = 'block',
  });

  final String theme; // e.g., system/light/dark (app theme)
  final int fontSize;
  final bool extraKeys;

  // Terminal-specific settings
  final String terminalTheme; // e.g., default, solarized-dark, solarized-light, monokai, dracula
  final double terminalFontSize;
  final String terminalFontFamily; // e.g., monospace, Cascadia Code, Fira Code
  final double terminalOpacity; // 0.0 - 1.0
  final String terminalCursorStyle; // block, underline, bar

  Map<String, dynamic> toJson() => {
        'theme': theme,
        'fontSize': fontSize,
        'extraKeys': extraKeys,
        'terminalTheme': terminalTheme,
        'terminalFontSize': terminalFontSize,
        'terminalFontFamily': terminalFontFamily,
        'terminalOpacity': terminalOpacity,
        'terminalCursorStyle': terminalCursorStyle,
      };

  factory VaultSettings.fromJson(Map<String, dynamic> json) {
    return VaultSettings(
      theme: json['theme'] as String? ?? 'system',
      fontSize: (json['fontSize'] as int?) ?? 14,
      extraKeys: (json['extraKeys'] as bool?) ?? false,
      terminalTheme: json['terminalTheme'] as String? ?? 'default',
      terminalFontSize: (json['terminalFontSize'] as num?)?.toDouble() ?? 14.0,
      terminalFontFamily: json['terminalFontFamily'] as String? ?? 'monospace',
      terminalOpacity: (json['terminalOpacity'] as num?)?.toDouble() ?? 1.0,
      terminalCursorStyle: json['terminalCursorStyle'] as String? ?? 'block',
    );
  }

  const VaultSettings.defaultValue() : this();

  VaultSettings copyWith({
    String? theme,
    int? fontSize,
    bool? extraKeys,
    String? terminalTheme,
    double? terminalFontSize,
    String? terminalFontFamily,
    double? terminalOpacity,
    String? terminalCursorStyle,
  }) {
    return VaultSettings(
      theme: theme ?? this.theme,
      fontSize: fontSize ?? this.fontSize,
      extraKeys: extraKeys ?? this.extraKeys,
      terminalTheme: terminalTheme ?? this.terminalTheme,
      terminalFontSize: terminalFontSize ?? this.terminalFontSize,
      terminalFontFamily: terminalFontFamily ?? this.terminalFontFamily,
      terminalOpacity: terminalOpacity ?? this.terminalOpacity,
      terminalCursorStyle: terminalCursorStyle ?? this.terminalCursorStyle,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is VaultSettings &&
        theme == other.theme &&
        fontSize == other.fontSize &&
        extraKeys == other.extraKeys &&
        terminalTheme == other.terminalTheme &&
        terminalFontSize == other.terminalFontSize &&
        terminalFontFamily == other.terminalFontFamily &&
        terminalOpacity == other.terminalOpacity &&
        terminalCursorStyle == other.terminalCursorStyle;
  }

  @override
  int get hashCode =>
      theme.hashCode ^
      fontSize.hashCode ^
      extraKeys.hashCode ^
      terminalTheme.hashCode ^
      terminalFontSize.hashCode ^
      terminalFontFamily.hashCode ^
      terminalOpacity.hashCode ^
      terminalCursorStyle.hashCode;
}

/// Handles version upgrades of vault payloads.
abstract class VaultMigrator {
  /// Applies migrations and returns a payload compatible with the current code.
  static VaultData migrate(VaultData data) {
    // Only v1 is supported today; future versions would branch here.
    if (data.version != 1) {
      throw VaultException('Unsupported vault data version ${data.version}.');
    }
    return data;
  }
}

/// Represents a host entry.
@immutable
class VaultHost {
  const VaultHost({
    required this.id,
    required this.label,
    required this.hostname,
    this.port = 22,
    required this.username,
    this.identityId,
    this.tags = const <String>[],
    this.tmuxEnabled = false,
    this.tmuxSessionName,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String label;
  final String hostname;
  final int port;
  final String username;
  final String? identityId; // references VaultIdentity.id
  final List<String> tags;
  /// Whether to auto-attach to tmux on connect.
  final bool tmuxEnabled;
  /// Optional tmux session name (uses default if null).
  final String? tmuxSessionName;
  final String? createdAt;
  final String? updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'hostname': hostname,
        'port': port,
        'username': username,
        if (identityId != null) 'identityId': identityId,
        if (tags.isNotEmpty) 'tags': tags,
        if (tmuxEnabled) 'tmuxEnabled': tmuxEnabled,
        if (tmuxSessionName != null) 'tmuxSessionName': tmuxSessionName,
        if (createdAt != null) 'createdAt': createdAt,
        if (updatedAt != null) 'updatedAt': updatedAt,
      };

  factory VaultHost.fromJson(Map<String, dynamic> json) {
    return VaultHost(
      id: json['id'] as String,
      label: json['label'] as String,
      hostname: json['hostname'] as String,
      port: (json['port'] ?? 22) as int,
      username: json['username'] as String,
      identityId: json['identityId'] as String?,
      tags: (json['tags'] as List?)?.cast<String>() ?? const <String>[],
      tmuxEnabled: (json['tmuxEnabled'] as bool?) ?? false,
      tmuxSessionName: json['tmuxSessionName'] as String?,
      createdAt: json['createdAt'] as String?,
      updatedAt: json['updatedAt'] as String?,
    );
  }

  VaultHost copyWith({
    String? label,
    String? hostname,
    int? port,
    String? username,
    String? identityId,
    List<String>? tags,
    bool? tmuxEnabled,
    String? tmuxSessionName,
    String? createdAt,
    String? updatedAt,
  }) {
    return VaultHost(
      id: id,
      label: label ?? this.label,
      hostname: hostname ?? this.hostname,
      port: port ?? this.port,
      username: username ?? this.username,
      identityId: identityId ?? this.identityId,
      tags: tags ?? this.tags,
      tmuxEnabled: tmuxEnabled ?? this.tmuxEnabled,
      tmuxSessionName: tmuxSessionName ?? this.tmuxSessionName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Vault data container with metadata and collections.
@immutable
class VaultData {
  const VaultData({
    required this.version,
    required this.revision,
    required this.deviceId,
    required this.createdAt,
    required this.updatedAt,
    this.hosts = const <VaultHost>[],
    this.identities = const <VaultIdentity>[],
    this.snippets = const <VaultSnippet>[],
    this.settings = const VaultSettings(),
    this.meta = const <String, dynamic>{},
  });

  final int version;
  final int revision;
  final String deviceId;
  final String createdAt;
  final String updatedAt;
  final List<VaultHost> hosts;
  final List<VaultIdentity> identities;
  final List<VaultSnippet> snippets;
  final VaultSettings settings;
  final Map<String, dynamic> meta;

  VaultData copyWith({
    int? revision,
    String? updatedAt,
    List<VaultHost>? hosts,
    List<VaultIdentity>? identities,
    List<VaultSnippet>? snippets,
    VaultSettings? settings,
    Map<String, dynamic>? meta,
  }) {
    return VaultData(
      version: version,
      revision: revision ?? this.revision,
      deviceId: deviceId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      hosts: hosts ?? this.hosts,
      identities: identities ?? this.identities,
      snippets: snippets ?? this.snippets,
      settings: settings ?? this.settings,
      meta: meta ?? this.meta,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'revision': revision,
        'deviceId': deviceId,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'hosts': hosts.map((h) => h.toJson()).toList(),
        'identities': identities.map((i) => i.toJson()).toList(),
      if (snippets.isNotEmpty)
        'snippets': snippets.map((s) => s.toJson()).toList(),
      if (settings != const VaultSettings()) 'settings': settings.toJson(),
      if (meta.isNotEmpty) 'meta': meta,
    };

  factory VaultData.fromJson(Map<String, dynamic> json) {
    return VaultData(
      version: (json['version'] ?? 1) as int,
      revision: (json['revision'] ?? 1) as int,
      deviceId: json['deviceId'] as String,
      createdAt: json['createdAt'] as String,
      updatedAt: json['updatedAt'] as String,
      hosts: (json['hosts'] as List? ?? const <dynamic>[])
          .map((e) => VaultHost.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      identities: (json['identities'] as List? ?? const <dynamic>[])
          .map(
            (e) => VaultIdentity.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
      snippets: (json['snippets'] as List? ?? const <dynamic>[])
          .map((e) => VaultSnippet.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      settings: json['settings'] != null
          ? VaultSettings.fromJson(
              Map<String, dynamic>.from(json['settings'] as Map),
            )
          : const VaultSettings(),
      meta: Map<String, dynamic>.from(
        json['meta'] as Map? ?? const <String, dynamic>{},
      ),
    );
  }
}

/// Holds vault contents in memory.
@immutable
class VaultPayload {
  const VaultPayload({
    required this.data,
  });

  final VaultData data;

  factory VaultPayload.fromBytes(Uint8List bytes) {
    final decoded = json.decode(utf8.decode(bytes)) as Map<String, dynamic>;
    final data = VaultMigrator.migrate(VaultData.fromJson(decoded));
    return VaultPayload(data: data);
  }

  Uint8List toBytes() => Uint8List.fromList(utf8.encode(rawJson));

  String get rawJson => json.encode(data.toJson());
}

/// Configuration for creating a new vault.
class VaultCreateConfig {
  const VaultCreateConfig({
    this.kdfKind = KdfKind.argon2id,
    this.kdfMemoryKiB = 65536,
    this.kdfIterations = 3,
    this.kdfParallelism = 1,
    this.cipherKind = CipherKind.xchacha20Poly1305,
  });

  final KdfKind kdfKind;
  final int kdfMemoryKiB;
  final int kdfIterations;
  final int kdfParallelism;
  final CipherKind cipherKind;
}

/// Main entry point to create/open/save vault files.
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
    _checkDuplicates(_payload.data.hosts.map((h) => h.id), 'Host id');
    _checkDuplicates(_payload.data.identities.map((i) => i.id), 'Identity id');
    _checkDuplicates(_payload.data.snippets.map((s) => s.id), 'Snippet id');
    _checkDuplicates(_payload.data.hosts.map((h) => h.label), 'Host label');
    for (final host in _payload.data.hosts) {
      _validateHost(host, identityIds: identityIds);
    }
    for (final identity in _payload.data.identities) {
      _validateIdentity(identity);
    }
    for (final snippet in _payload.data.snippets) {
      _validateSnippet(snippet);
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
    final cipher = _cipherForKind(config.cipherKind);
    final nonce = cipher.newNonce();
    final saltKey = SecretKeyData.random(length: _defaultSaltLength);
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
    final key = await _deriveKey(
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
    final key = await _deriveKey(
      password: password,
      kind: header.kdf,
      memoryKiB: header.kdfMemoryKiB,
      iterations: header.kdfIterations,
      parallelism: header.kdfParallelism,
      salt: header.kdfSalt,
    );
    final cipher = _cipherForKind(header.cipher);
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
    final cipher = _cipherForKind(_header.cipher);
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
    _validateHost(host, identityIds: identityIds);
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
      updatedAt: _nowIso(),
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
      updatedAt: _nowIso(),
    ));
  }

  /// Upsert an identity and bump revision/updatedAt.
  void upsertIdentity(VaultIdentity identity) {
    final current = _payload.data;
    _validateIdentity(identity);
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
      updatedAt: _nowIso(),
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
      updatedAt: _nowIso(),
    ));
  }

  /// Update arbitrary metadata map and bump revision/updatedAt.
  void updateMeta(Map<String, dynamic> meta) {
    final current = _payload.data;
    _setData(
      current.copyWith(
        meta: meta,
        revision: current.revision + 1,
        updatedAt: _nowIso(),
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
        updatedAt: _nowIso(),
      ),
    );
  }

  void _setData(VaultData data) {
    _payload = VaultPayload(data: data);
  }

  Future<void> _write() async {
    final cipher = _cipherForKind(_header.cipher);
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

int _kdfToId(KdfKind kind) {
  switch (kind) {
    case KdfKind.argon2id:
      return 0x01;
    case KdfKind.scrypt:
      return 0x02;
  }
}

KdfKind _kdfFromId(int id) {
  switch (id) {
    case 0x01:
      return KdfKind.argon2id;
    case 0x02:
      return KdfKind.scrypt;
    default:
      throw VaultException('Unsupported KDF id: $id');
  }
}

int _cipherToId(CipherKind kind) {
  switch (kind) {
    case CipherKind.xchacha20Poly1305:
      return 0x01;
    case CipherKind.aes256Gcm:
      return 0x02;
  }
}

CipherKind _cipherFromId(int id) {
  switch (id) {
    case 0x01:
      return CipherKind.xchacha20Poly1305;
    case 0x02:
      return CipherKind.aes256Gcm;
    default:
      throw VaultException('Unsupported cipher id: $id');
  }
}

Future<SecretKey> _deriveKey({
  required String password,
  required KdfKind kind,
  required int memoryKiB,
  required int iterations,
  required int parallelism,
  required List<int> salt,
}) async {
  switch (kind) {
    case KdfKind.argon2id:
      final kdf = Argon2id(
        parallelism: parallelism,
        memory: memoryKiB,
        iterations: iterations,
        hashLength: _defaultKeyLength,
      );
      return kdf.deriveKey(
        secretKey: SecretKey(utf8.encode(password)),
        nonce: salt,
      );
    case KdfKind.scrypt:
      throw VaultException('scrypt is not implemented.');
  }
}

Cipher _cipherForKind(CipherKind kind) {
  switch (kind) {
    case CipherKind.xchacha20Poly1305:
      return Xchacha20.poly1305Aead();
    case CipherKind.aes256Gcm:
      return AesGcm.with256bits();
  }
}

String _nowIso() => DateTime.now().toUtc().toIso8601String();

void _validateHost(VaultHost host, {Set<String>? identityIds}) {
  if (host.id.isEmpty) {
    throw VaultValidationException('Host id is required.');
  }
  if (host.label.isEmpty) {
    throw VaultValidationException('Host label is required.');
  }
  if (host.hostname.isEmpty) {
    throw VaultValidationException('Host hostname is required.');
  }
  if (host.port <= 0 || host.port > 65535) {
    throw VaultValidationException('Host port must be between 1 and 65535.');
  }
  if (host.username.isEmpty) {
    throw VaultValidationException('Host username is required.');
  }
  if (host.identityId != null &&
      identityIds != null &&
      !identityIds.contains(host.identityId)) {
    throw VaultValidationException(
      'Host identityId does not match any identity.',
    );
  }
}

void _validateIdentity(VaultIdentity identity) {
  if (identity.id.isEmpty) {
    throw VaultValidationException('Identity id is required.');
  }
  if (identity.name.isEmpty) {
    throw VaultValidationException('Identity name is required.');
  }
  if (identity.type.isEmpty) {
    throw VaultValidationException('Identity type is required.');
  }
  if (identity.privateKey.isEmpty) {
    throw VaultValidationException('Identity privateKey is required.');
  }
  if (!_looksLikePem(identity.privateKey)) {
    throw VaultValidationException('Identity privateKey must be PEM/OpenSSH formatted.');
  }
}

void _validateSnippet(VaultSnippet snippet) {
  if (snippet.id.isEmpty) {
    throw VaultValidationException('Snippet id is required.');
  }
  if (snippet.title.isEmpty) {
    throw VaultValidationException('Snippet title is required.');
  }
  if (snippet.content.isEmpty) {
    throw VaultValidationException('Snippet content is required.');
  }
}

void _checkDuplicates(Iterable<String> values, String label) {
  final seen = <String>{};
  for (final v in values) {
    if (seen.contains(v)) {
      throw VaultValidationException('$label duplicates are not allowed.');
    }
    seen.add(v);
  }
}

bool _looksLikePem(String key) {
  final trimmed = key.trim();
  if (!trimmed.startsWith('-----BEGIN') ||
      !trimmed.contains('PRIVATE KEY') ||
      !trimmed.contains('-----END')) {
    return false;
  }
  final lines = trimmed.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);
  if (lines.length < 3) {
    return false;
  }
  final start = lines.first;
  final end = lines.last;
  if (!start.startsWith('-----BEGIN') || !end.startsWith('-----END')) {
    return false;
  }
  final body = lines
      .skip(1)
      .take(lines.length - 2)
      .join();
  // Basic base64 sanity: length divisible by 4 and only valid chars.
  final base64Pattern = RegExp(r'^[A-Za-z0-9+/=\r\n]+$');
  if (!base64Pattern.hasMatch(body)) {
    return false;
  }
  return body.length >= 16 && body.length % 4 == 0;
}
