/// Core SSH library for VibedTerm SSH client.
///
/// This library provides SSH connection management with support for:
/// - Password and key-based authentication
/// - Interactive shell sessions with PTY
/// - Remote command execution
/// - Host key verification
/// - Connection status events and logging
///
/// ## Usage
///
/// ```dart
/// final manager = SshConnectionManager();
///
/// // Connect to a server
/// await manager.connect(SshTarget(
///   host: 'example.com',
///   username: 'user',
///   privateKey: '-----BEGIN OPENSSH PRIVATE KEY-----...',
/// ));
///
/// // Start an interactive shell
/// final shell = await manager.startShell();
/// shell.stdout.listen((data) => print(utf8.decode(data)));
/// await shell.writeString('ls -la\n');
///
/// // Or run a single command
/// final result = await manager.runCommand('whoami');
/// print(result.stdout);
///
/// await manager.disconnect();
/// ```
library core_ssh;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:meta/meta.dart';

export 'package:dartssh2/dartssh2.dart'
    show SftpClient, SftpFileAttrs, SftpName, SftpFileOpenMode, SftpFile;

// =============================================================================
// Connection Target
// =============================================================================

/// Configuration for an SSH connection.
///
/// Specifies the target host, authentication credentials, and connection
/// options like keepalive interval and host key verification callback.
@immutable
class SshTarget {
  /// Creates an SSH connection target.
  ///
  /// - [host]: The hostname or IP address to connect to
  /// - [port]: SSH port (default: 22)
  /// - [username]: Username for authentication
  /// - [password]: Password for password authentication (optional)
  /// - [privateKey]: PEM/OpenSSH private key for key authentication (optional)
  /// - [passphrase]: Passphrase for encrypted private keys
  /// - [keepAliveInterval]: Interval for keepalive packets (null to disable)
  /// - [onHostKeyVerify]: Callback to verify host keys (return true to accept)
  const SshTarget({
    required this.host,
    this.port = 22,
    required this.username,
    this.password,
    this.privateKey,
    this.passphrase,
    this.keepAliveInterval = const Duration(seconds: 10),
    this.onHostKeyVerify,
  });

  /// Target hostname or IP address.
  final String host;

  /// SSH port (default: 22).
  final int port;

  /// Username for authentication.
  final String username;

  /// Password for password authentication.
  final String? password;

  /// PEM or OpenSSH formatted private key.
  final String? privateKey;

  /// Passphrase for encrypted private keys.
  final String? passphrase;

  /// Interval between keepalive packets (null to disable).
  final Duration? keepAliveInterval;

  /// Callback to verify host keys. Return true to accept the key.
  ///
  /// The callback receives the key type (e.g., "ssh-ed25519") and the
  /// fingerprint in colon-separated hex format.
  final FutureOr<bool> Function(String type, String fingerprint)? onHostKeyVerify;
}

// =============================================================================
// Status and Errors
// =============================================================================

/// High-level SSH connection status.
///
/// - [disconnected]: No active connection
/// - [connecting]: Connection in progress
/// - [connected]: Successfully connected
/// - [error]: Connection failed or was lost
enum SshConnectionStatus { disconnected, connecting, connected, error }

/// Classification of SSH errors for UI messaging.
///
/// Helps the UI display appropriate error messages and recovery options.
enum SshErrorKind {
  /// Authentication failed (wrong password or key rejected).
  authFailed,

  /// SSH protocol handshake failed.
  handshakeFailed,

  /// Host key verification failed or was rejected by user.
  hostKeyRejected,

  /// Could not reach the host (network error, DNS failure, etc.).
  hostUnreachable,

  /// Connection was lost or closed unexpectedly.
  disconnected,

  /// Unknown or unclassified error.
  unknown,
}

/// Exception thrown when SSH operations fail.
///
/// Contains a [kind] for classification, a human-readable [message],
/// and optionally the original [cause] exception.
class SshException implements Exception {
  /// Creates an SSH exception.
  SshException(this.kind, this.message, [this.cause]);

  /// Error classification for UI handling.
  final SshErrorKind kind;

  /// Human-readable error description.
  final String message;

  /// Original exception that caused this error.
  final Object? cause;

  @override
  String toString() => 'SshException($kind, $message)';
}

// =============================================================================
// Command and Shell Sessions
// =============================================================================

/// Result of executing a remote command via SSH.
class SshCommandResult {
  /// Creates a command result.
  const SshCommandResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });

  /// Standard output from the command.
  final String stdout;

  /// Standard error from the command.
  final String stderr;

  /// Exit code (null if not available).
  final int? exitCode;
}

/// Handle to an interactive SSH shell session.
///
/// Provides streams for stdout/stderr, methods for writing input,
/// resizing the terminal, and closing the session.
class SshShellSession {
  /// Creates a shell session handle.
  SshShellSession({
    required this.stdout,
    required this.stderr,
    required this.write,
    required this.resize,
    required this.close,
    required this.done,
  });

  /// Stream of stdout data from the remote shell.
  final Stream<List<int>> stdout;

  /// Stream of stderr data from the remote shell.
  final Stream<List<int>> stderr;

  /// Writes raw bytes to the shell's stdin.
  final Future<void> Function(List<int> data) write;

  /// Closes the shell session.
  final Future<void> Function() close;

  /// Resizes the PTY to the given dimensions.
  final void Function(int width, int height) resize;

  /// Future that completes when the shell session ends.
  final Future<void> done;

  /// Writes a string to the shell's stdin.
  Future<void> writeString(String text) => write(utf8.encode(text));
}

/// PTY (pseudo-terminal) configuration for shell sessions.
@immutable
class SshPtyConfig {
  /// Creates PTY configuration.
  const SshPtyConfig({
    this.term = 'xterm-256color',
    this.width = 80,
    this.height = 24,
    this.pixelWidth = 0,
    this.pixelHeight = 0,
  });

  /// Terminal type (default: "xterm-256color").
  final String term;

  /// Terminal width in columns.
  final int width;

  /// Terminal height in rows.
  final int height;

  /// Terminal width in pixels (optional, for graphical terminals).
  final int pixelWidth;

  /// Terminal height in pixels (optional, for graphical terminals).
  final int pixelHeight;

  /// Converts to dartssh2's PTY config format.
  SSHPtyConfig toSsh() => SSHPtyConfig(
        type: term,
        width: width,
        height: height,
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
      );
}

// =============================================================================
// Connection Manager
// =============================================================================

/// Interface for SSH client implementations.
///
/// Allows mocking the SSH client for testing purposes.
abstract class SshClientAdapter {
  /// Executes a command and returns the result.
  Future<SshCommandResult> run(String command);

  /// Starts an interactive shell session.
  Future<SshShellSession> startShell({SshPtyConfig ptyConfig});

  /// Opens an SFTP session for file operations.
  Future<SftpClient> openSftp();

  /// Disconnects and cleans up resources.
  Future<void> disconnect();
}

/// Factory function for creating SSH client adapters.
typedef SshClientFactory = Future<SshClientAdapter> Function(
  SshTarget target,
  void Function(String message) log,
);

/// High-level SSH connection manager.
///
/// Wraps the dartssh2 library and provides:
/// - Connection lifecycle management
/// - Status change notifications via [statusStream]
/// - Debug logging via [logs]
/// - Error mapping to [SshException]
///
/// ## Example
///
/// ```dart
/// final manager = SshConnectionManager();
///
/// // Listen to status changes
/// manager.statusStream.listen((status) {
///   print('Status: $status');
/// });
///
/// // Connect and start a shell
/// await manager.connect(target);
/// final shell = await manager.startShell();
/// ```
class SshConnectionManager {
  SshConnectionManager({SshClientFactory? clientFactory})
      : _clientFactory = clientFactory ?? _defaultClientFactory;

  final SshClientFactory _clientFactory;
  SshClientAdapter? _client;

  final StreamController<String> _logController =
      StreamController<String>.broadcast();
  final StreamController<SshConnectionStatus> _statusController =
      StreamController<SshConnectionStatus>.broadcast()
        ..add(SshConnectionStatus.disconnected);

  Stream<String> get logs => _logController.stream;
  Stream<SshConnectionStatus> get statusStream => _statusController.stream;
  SshConnectionStatus _status = SshConnectionStatus.disconnected;

  SshConnectionStatus get status => _status;

  Future<void> connect(SshTarget target) async {
    await disconnect();
    _setStatus(SshConnectionStatus.connecting);
    try {
      _log('Connecting to ${target.username}@${target.host}:${target.port}...');
      _client = await _clientFactory(target, _log);
      _setStatus(SshConnectionStatus.connected);
      _log('Connected.');
    } catch (e) {
      _setStatus(SshConnectionStatus.error);
      throw _mapError(e);
    }
  }

  Future<SshCommandResult> runCommand(String command) async {
    final client = _client;
    if (client == null) {
      throw SshException(
        SshErrorKind.disconnected,
        'Not connected.',
      );
    }
    _log('Running command: $command');
    final result = await client.run(command);
    _log('Command finished (exit ${result.exitCode ?? 'unknown'}).');
    return result;
  }

  Future<SshShellSession> startShell({SshPtyConfig ptyConfig = const SshPtyConfig()}) async {
    final client = _client;
    if (client == null) {
      throw SshException(
        SshErrorKind.disconnected,
        'Not connected.',
      );
    }
    return client.startShell(ptyConfig: ptyConfig);
  }

  Future<SftpClient> openSftp() async {
    final client = _client;
    if (client == null) {
      throw SshException(
        SshErrorKind.disconnected,
        'Not connected.',
      );
    }
    _log('Opening SFTP session...');
    return client.openSftp();
  }

  Future<void> disconnect() async {
    if (_client == null) {
      _setStatus(SshConnectionStatus.disconnected);
      return;
    }
    _log('Disconnecting...');
    await _client!.disconnect();
    _client = null;
    _setStatus(SshConnectionStatus.disconnected);
    _log('Disconnected.');
  }

  void dispose() {
    _logController.close();
    _statusController.close();
  }

  void _log(String message) {
    if (!_logController.isClosed) {
      _logController.add(message);
    }
  }

  void _setStatus(SshConnectionStatus value) {
    _status = value;
    if (!_statusController.isClosed) {
      _statusController.add(value);
    }
  }
}

SshException _mapError(Object error) {
  if (error is SshException) return error;
  if (error is SSHAuthError) {
    return SshException(
      SshErrorKind.authFailed,
      error.message,
      error,
    );
  }
  if (error is SSHHandshakeError) {
    return SshException(
      SshErrorKind.handshakeFailed,
      error.message,
      error,
    );
  }
  if (error is SSHHostkeyError) {
    return SshException(
      SshErrorKind.hostKeyRejected,
      error.message,
      error,
    );
  }
  if (error is SSHSocketError || error is SocketException) {
    return SshException(
      SshErrorKind.hostUnreachable,
      'Host unreachable or network error.',
      error,
    );
  }
  return SshException(
    SshErrorKind.unknown,
    error.toString(),
    error,
  );
}

Future<SshClientAdapter> _defaultClientFactory(
  SshTarget target,
  void Function(String message) log,
) async {
  final socket = await SSHSocket.connect(target.host, target.port);
  final identities = <SSHKeyPair>[];
  if (target.privateKey != null && target.privateKey!.isNotEmpty) {
    try {
      identities.addAll(
        SSHKeyPair.fromPem(target.privateKey!, target.passphrase),
      );
      log('Loaded ${identities.length} key(s) from private key');
    } catch (e) {
      log('Failed to parse private key: $e');
      // Continue without key auth - will fall back to password if available
    }
  }

  final hasPassword = target.password != null && target.password!.isNotEmpty;
  log('Auth methods: key=${identities.isNotEmpty}, password=$hasPassword');

  final client = SSHClient(
    socket,
    username: target.username,
    identities: identities.isEmpty ? null : identities,
    onPasswordRequest: hasPassword ? () async => target.password! : null,
    keepAliveInterval: target.keepAliveInterval,
    printDebug: (msg) => log(msg ?? ''),
    onVerifyHostKey: target.onHostKeyVerify == null
        ? null
        : (type, fp) async =>
            target.onHostKeyVerify!(type, _formatFingerprint(fp)),
  );
  return _DartSshClientAdapter(client);
}

String _formatFingerprint(Uint8List bytes) {
  final buffer = StringBuffer();
  for (var i = 0; i < bytes.length; i++) {
    if (i > 0) buffer.write(':');
    buffer.write(bytes[i].toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

class _DartSshClientAdapter implements SshClientAdapter {
  _DartSshClientAdapter(this._client);

  final SSHClient _client;

  @override
  Future<SshCommandResult> run(String command) async {
    final session = await _client.execute(command);
    final stdoutBuilder = BytesBuilder();
    final stderrBuilder = BytesBuilder();

    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();

    session.stdout.listen(
      (data) => stdoutBuilder.add(data),
      onDone: () => stdoutDone.complete(),
      onError: stderrDone.completeError,
    );
    session.stderr.listen(
      (data) => stderrBuilder.add(data),
      onDone: () => stderrDone.complete(),
      onError: stderrDone.completeError,
    );

    await stdoutDone.future;
    await stderrDone.future;
    await session.done;
    session.close();

    return SshCommandResult(
      stdout: utf8.decode(stdoutBuilder.takeBytes()),
      stderr: utf8.decode(stderrBuilder.takeBytes()),
      exitCode: session.exitCode,
    );
  }

  @override
  Future<SftpClient> openSftp() async => _client.sftp();

  @override
  Future<SshShellSession> startShell({SshPtyConfig ptyConfig = const SshPtyConfig()}) async {
    final session = await _client.shell(pty: ptyConfig.toSsh());
    return SshShellSession(
      stdout: session.stdout,
      stderr: session.stderr,
      write: (data) async => session.stdin.add(Uint8List.fromList(data)),
      resize: (width, height) => session.resizeTerminal(width, height),
      close: () async {
        session.close();
        await session.done.catchError((_) {});
      },
      done: session.done,
    );
  }

  @override
  Future<void> disconnect() async {
    _client.close();
    await _client.done.catchError((_) {});
  }
}

// -----------------------------------------------------------------------------
// SSH Key Fingerprint Utilities
// -----------------------------------------------------------------------------

/// Calculates the SHA256 fingerprint of an SSH private key.
///
/// Returns the fingerprint in the format "SHA256:base64_hash" or null if
/// the key cannot be parsed.
String? calculateKeyFingerprint(String privateKeyPem, {String? passphrase}) {
  try {
    final keyPairs = SSHKeyPair.fromPem(privateKeyPem, passphrase);
    if (keyPairs.isEmpty) return null;

    // Get the first key pair's public key
    final keyPair = keyPairs.first;

    // The public key blob is what we hash for the fingerprint
    // SSHKeyPair exposes the public key which has the encoded blob
    final publicKey = keyPair.toPublicKey();
    final publicKeyBlob = publicKey.encode();

    // Calculate SHA256 hash
    final hash = sha256.convert(publicKeyBlob);

    // Format as SHA256:base64 (standard OpenSSH format)
    final base64Hash = base64Encode(hash.bytes);
    // Remove trailing '=' padding for cleaner output
    final cleanHash = base64Hash.replaceAll(RegExp(r'=+$'), '');

    return 'SHA256:$cleanHash';
  } catch (e) {
    return null;
  }
}

/// Returns the key type from a private key PEM.
///
/// Returns values like "ssh-rsa", "ssh-ed25519", "ecdsa-sha2-nistp256", etc.
String? getKeyType(String privateKeyPem, {String? passphrase}) {
  try {
    final keyPairs = SSHKeyPair.fromPem(privateKeyPem, passphrase);
    if (keyPairs.isEmpty) return null;
    return keyPairs.first.type;
  } catch (e) {
    return null;
  }
}
