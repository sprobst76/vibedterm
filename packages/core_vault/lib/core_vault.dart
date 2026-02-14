/// Core vault library for VibedTerm SSH client.
///
/// This library provides encrypted vault functionality for storing SSH credentials,
/// host configurations, and user settings. It implements a zero-knowledge
/// architecture where all sensitive data is encrypted client-side before storage.
///
/// ## Features
///
/// - **Strong encryption**: Uses Argon2id for key derivation and XChaCha20-Poly1305
///   or AES-256-GCM for authenticated encryption
/// - **Binary vault format**: Compact header with KDF parameters followed by
///   encrypted JSON payload
/// - **Atomic writes**: Uses temp file + rename pattern to prevent data corruption
/// - **Version migration**: Built-in support for upgrading vault formats
///
/// ## Usage
///
/// ```dart
/// // Create a new vault
/// final vault = await VaultFile.create(
///   file: File('my_vault.vlt'),
///   password: 'secure_password',
///   payload: VaultPayload(data: VaultData(...)),
/// );
///
/// // Open an existing vault
/// final vault = await VaultFile.open(
///   file: File('my_vault.vlt'),
///   password: 'secure_password',
/// );
///
/// // Add a host and save
/// vault.upsertHost(VaultHost(...));
/// await vault.save();
/// ```
///
/// ## Binary Format
///
/// See `docs/vault_spec_v1.md` for the complete binary format specification.
library core_vault;

export 'src/exceptions.dart';
export 'src/models.dart';
export 'src/vault_file.dart';
export 'src/vault_header.dart';
