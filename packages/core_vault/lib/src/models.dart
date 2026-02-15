import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'exceptions.dart';

/// Key derivation function algorithms supported by the vault.
///
/// - [argon2id]: Memory-hard KDF resistant to GPU/ASIC attacks (recommended)
/// - [scrypt]: Alternative memory-hard KDF (not currently implemented)
enum KdfKind { argon2id, scrypt }

/// Symmetric cipher algorithms for encrypting the vault payload.
///
/// - [xchacha20Poly1305]: Extended-nonce ChaCha20 with Poly1305 MAC (recommended)
/// - [aes256Gcm]: AES-256 in Galois/Counter Mode
enum CipherKind { xchacha20Poly1305, aes256Gcm }

/// An SSH identity (private key) stored in the vault.
///
/// Identities can be linked to hosts via [VaultHost.identityId] for automatic
/// key-based authentication.
@immutable
class VaultIdentity {
  /// Creates a new vault identity.
  const VaultIdentity({
    required this.id,
    required this.name,
    required this.type,
    required this.privateKey,
    this.passphrase,
    this.createdAt,
    this.updatedAt,
  });

  /// Unique identifier for this identity.
  final String id;

  /// Human-readable display name.
  final String name;

  /// SSH key type (e.g., "ssh-rsa", "ssh-ed25519", "ecdsa").
  final String type;

  /// PEM or OpenSSH formatted private key.
  final String privateKey;

  /// Optional passphrase if the private key is encrypted.
  final String? passphrase;

  /// ISO 8601 timestamp when this identity was created.
  final String? createdAt;

  /// ISO 8601 timestamp when this identity was last updated.
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

/// A reusable command snippet stored in the vault.
///
/// Snippets allow users to save frequently used commands or text templates
/// for quick insertion into terminal sessions.
@immutable
class VaultSnippet {
  /// Creates a new snippet.
  const VaultSnippet({
    required this.id,
    required this.title,
    required this.content,
    this.tags = const <String>[],
    this.createdAt,
    this.updatedAt,
  });

  /// Unique identifier for this snippet.
  final String id;

  /// Display title for the snippet.
  final String title;

  /// The actual snippet content/command.
  final String content;

  /// Optional tags for categorization and search.
  final List<String> tags;

  /// ISO 8601 timestamp when this snippet was created.
  final String? createdAt;

  /// ISO 8601 timestamp when this snippet was last updated.
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

  VaultSnippet copyWith({
    String? id,
    String? title,
    String? content,
    List<String>? tags,
    String? createdAt,
    String? updatedAt,
  }) {
    return VaultSnippet(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// User preferences and settings stored in the vault.
///
/// Settings are synced across devices when using cloud sync, ensuring
/// a consistent experience everywhere.
@immutable
class VaultSettings {
  /// Creates vault settings with default values.
  const VaultSettings({
    this.theme = 'system',
    this.fontSize = 14,
    this.extraKeys = false,
    this.terminalTheme = 'default',
    this.terminalFontSize = 14.0,
    this.terminalFontFamily = 'monospace',
    this.terminalOpacity = 1.0,
    this.terminalCursorStyle = 'block',
    this.sshKeepaliveInterval = 30,
    this.sshConnectionTimeout = 30,
    this.sshDefaultPort = 22,
    this.sshAutoReconnect = false,
  });

  /// App theme mode: "system", "light", or "dark".
  final String theme;

  /// Base font size for UI elements.
  final int fontSize;

  /// Whether to show extra keys toolbar on mobile.
  final bool extraKeys;

  /// Terminal color theme name (e.g., "default", "solarized-dark", "monokai").
  final String terminalTheme;

  /// Terminal font size in points.
  final double terminalFontSize;

  /// Terminal font family (e.g., "monospace", "Cascadia Code", "Fira Code").
  final String terminalFontFamily;

  /// Terminal background opacity (0.0 - 1.0).
  final double terminalOpacity;

  /// Cursor style: "block", "underline", or "bar".
  final String terminalCursorStyle;

  /// SSH keepalive interval in seconds (0 = disabled).
  final int sshKeepaliveInterval;

  /// SSH connection timeout in seconds.
  final int sshConnectionTimeout;

  /// Default SSH port for new hosts.
  final int sshDefaultPort;

  /// Whether to automatically reconnect on connection loss.
  final bool sshAutoReconnect;

  Map<String, dynamic> toJson() => {
        'theme': theme,
        'fontSize': fontSize,
        'extraKeys': extraKeys,
        'terminalTheme': terminalTheme,
        'terminalFontSize': terminalFontSize,
        'terminalFontFamily': terminalFontFamily,
        'terminalOpacity': terminalOpacity,
        'terminalCursorStyle': terminalCursorStyle,
        'sshKeepaliveInterval': sshKeepaliveInterval,
        'sshConnectionTimeout': sshConnectionTimeout,
        'sshDefaultPort': sshDefaultPort,
        'sshAutoReconnect': sshAutoReconnect,
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
      sshKeepaliveInterval: (json['sshKeepaliveInterval'] as int?) ?? 30,
      sshConnectionTimeout: (json['sshConnectionTimeout'] as int?) ?? 30,
      sshDefaultPort: (json['sshDefaultPort'] as int?) ?? 22,
      sshAutoReconnect: (json['sshAutoReconnect'] as bool?) ?? false,
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
    int? sshKeepaliveInterval,
    int? sshConnectionTimeout,
    int? sshDefaultPort,
    bool? sshAutoReconnect,
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
      sshKeepaliveInterval: sshKeepaliveInterval ?? this.sshKeepaliveInterval,
      sshConnectionTimeout: sshConnectionTimeout ?? this.sshConnectionTimeout,
      sshDefaultPort: sshDefaultPort ?? this.sshDefaultPort,
      sshAutoReconnect: sshAutoReconnect ?? this.sshAutoReconnect,
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
        terminalCursorStyle == other.terminalCursorStyle &&
        sshKeepaliveInterval == other.sshKeepaliveInterval &&
        sshConnectionTimeout == other.sshConnectionTimeout &&
        sshDefaultPort == other.sshDefaultPort &&
        sshAutoReconnect == other.sshAutoReconnect;
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
      terminalCursorStyle.hashCode ^
      sshKeepaliveInterval.hashCode ^
      sshConnectionTimeout.hashCode ^
      sshDefaultPort.hashCode ^
      sshAutoReconnect.hashCode;
}

/// Handles version upgrades of vault data.
///
/// When the vault format changes in future versions, this class will contain
/// the migration logic to upgrade older vaults to the current format.
abstract class VaultMigrator {
  /// Applies any necessary migrations to [data] and returns a compatible version.
  ///
  /// Throws [VaultException] if the data version is not supported.
  static VaultData migrate(VaultData data) {
    if (data.version != 1) {
      throw VaultException('Unsupported vault data version ${data.version}.');
    }
    return data;
  }
}

/// An SSH host entry stored in the vault.
///
/// Hosts define connection targets with their hostname, port, username,
/// and optionally a linked identity for key-based authentication.
@immutable
class VaultHost {
  /// Creates a new host entry.
  const VaultHost({
    required this.id,
    required this.label,
    required this.hostname,
    this.port = 22,
    required this.username,
    this.identityId,
    this.group,
    this.tags = const <String>[],
    this.tmuxEnabled = false,
    this.tmuxSessionName,
    this.createdAt,
    this.updatedAt,
  });

  /// Unique identifier for this host.
  final String id;

  /// Human-readable display name.
  final String label;

  /// Server hostname or IP address.
  final String hostname;

  /// SSH port (default: 22).
  final int port;

  /// Username for SSH authentication.
  final String username;

  /// Optional reference to a [VaultIdentity.id] for key-based authentication.
  final String? identityId;

  /// Optional group/folder name for organizing hosts.
  final String? group;

  /// Optional tags for categorization and filtering.
  final List<String> tags;

  /// Whether to automatically attach to tmux on connect.
  final bool tmuxEnabled;

  /// Custom tmux session name (uses default if null).
  final String? tmuxSessionName;

  /// ISO 8601 timestamp when this host was created.
  final String? createdAt;

  /// ISO 8601 timestamp when this host was last updated.
  final String? updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'hostname': hostname,
        'port': port,
        'username': username,
        if (identityId != null) 'identityId': identityId,
        if (group != null) 'group': group,
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
      group: json['group'] as String?,
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
    String? group,
    bool clearGroup = false,
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
      group: clearGroup ? null : (group ?? this.group),
      tags: tags ?? this.tags,
      tmuxEnabled: tmuxEnabled ?? this.tmuxEnabled,
      tmuxSessionName: tmuxSessionName ?? this.tmuxSessionName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// The main data container stored in the encrypted vault payload.
///
/// Contains all hosts, identities, snippets, and settings along with
/// sync metadata (revision, deviceId, timestamps).
@immutable
class VaultData {
  /// Creates a new vault data container.
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

  /// Data format version (currently 1).
  final int version;

  /// Monotonically increasing revision number for sync conflict detection.
  final int revision;

  /// Unique identifier for the device that created this vault.
  final String deviceId;

  /// ISO 8601 timestamp when this vault was created.
  final String createdAt;

  /// ISO 8601 timestamp when this vault was last updated.
  final String updatedAt;

  /// List of SSH host entries.
  final List<VaultHost> hosts;

  /// List of SSH identities (private keys).
  final List<VaultIdentity> identities;

  /// List of command snippets.
  final List<VaultSnippet> snippets;

  /// User preferences and settings.
  final VaultSettings settings;

  /// Arbitrary metadata (e.g., trusted host keys).
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

/// Wrapper around [VaultData] for serialization to/from bytes.
///
/// The payload is the decrypted JSON content stored in the vault file.
/// It handles serialization and applies any necessary migrations when
/// loading older vault formats.
@immutable
class VaultPayload {
  /// Creates a payload containing the given [data].
  const VaultPayload({
    required this.data,
  });

  /// The vault data contained in this payload.
  final VaultData data;

  /// Deserializes a payload from decrypted bytes.
  ///
  /// Applies any necessary migrations to upgrade older vault formats.
  factory VaultPayload.fromBytes(Uint8List bytes) {
    final decoded = json.decode(utf8.decode(bytes)) as Map<String, dynamic>;
    final data = VaultMigrator.migrate(VaultData.fromJson(decoded));
    return VaultPayload(data: data);
  }

  /// Serializes the payload to bytes for encryption.
  Uint8List toBytes() => Uint8List.fromList(utf8.encode(rawJson));

  /// The raw JSON string representation of the payload.
  String get rawJson => json.encode(data.toJson());
}

/// Configuration options for creating a new vault.
///
/// Allows customizing the KDF parameters and cipher algorithm. The defaults
/// provide a good balance of security and performance on modern devices.
class VaultCreateConfig {
  /// Creates a vault configuration with the given parameters.
  const VaultCreateConfig({
    this.kdfKind = KdfKind.argon2id,
    this.kdfMemoryKiB = 65536,
    this.kdfIterations = 3,
    this.kdfParallelism = 1,
    this.cipherKind = CipherKind.xchacha20Poly1305,
  });

  /// Key derivation function algorithm.
  final KdfKind kdfKind;

  /// Memory usage for KDF in kibibytes (default: 64 MiB).
  final int kdfMemoryKiB;

  /// Number of KDF iterations (default: 3).
  final int kdfIterations;

  /// KDF parallelism/lanes (default: 1).
  final int kdfParallelism;

  /// Cipher algorithm for payload encryption.
  final CipherKind cipherKind;
}
