library core_ssh;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:meta/meta.dart';

/// Represents a single SSH connection configuration.
@immutable
class SshTarget {
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

  final String host;
  final int port;
  final String username;
  final String? password;
  final String? privateKey;
  final String? passphrase;
  final Duration? keepAliveInterval;
  final FutureOr<bool> Function(String type, String fingerprint)? onHostKeyVerify;
}

/// High-level connection status.
enum SshConnectionStatus { disconnected, connecting, connected, error }

/// Error classification to simplify UI messaging.
enum SshErrorKind {
  authFailed,
  handshakeFailed,
  hostKeyRejected,
  hostUnreachable,
  disconnected,
  unknown,
}

/// Structured SSH errors with a user-friendly message.
class SshException implements Exception {
  SshException(this.kind, this.message, [this.cause]);

  final SshErrorKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() => 'SshException($kind, $message)';
}

/// Result of a remote command execution.
class SshCommandResult {
  const SshCommandResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });

  final String stdout;
  final String stderr;
  final int? exitCode;
}

/// Interactive shell session handle.
class SshShellSession {
  SshShellSession({
    required this.stdout,
    required this.stderr,
    required this.write,
    required this.resize,
    required this.close,
    required this.done,
  });

  final Stream<List<int>> stdout;
  final Stream<List<int>> stderr;
  final Future<void> Function(List<int> data) write;
  final Future<void> Function() close;
  final void Function(int width, int height) resize;
  final Future<void> done;

  Future<void> writeString(String text) => write(utf8.encode(text));
}

/// Minimal PTY configuration wrapper for shells.
@immutable
class SshPtyConfig {
  const SshPtyConfig({
    this.term = 'xterm-256color',
    this.width = 80,
    this.height = 24,
    this.pixelWidth = 0,
    this.pixelHeight = 0,
  });

  final String term;
  final int width;
  final int height;
  final int pixelWidth;
  final int pixelHeight;

  SSHPtyConfig toSsh() => SSHPtyConfig(
        type: term,
        width: width,
        height: height,
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
      );
}

/// Adapter interface to abstract the underlying SSH client implementation.
abstract class SshClientAdapter {
  Future<SshCommandResult> run(String command);
  Future<SshShellSession> startShell({SshPtyConfig ptyConfig});
  Future<void> disconnect();
}

typedef SshClientFactory = Future<SshClientAdapter> Function(
  SshTarget target,
  void Function(String message) log,
);

/// Connection manager that wraps dartssh2 and exposes higher level events.
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
    identities.addAll(
      SSHKeyPair.fromPem(target.privateKey!, target.passphrase),
    );
  }
  final client = SSHClient(
    socket,
    username: target.username,
    identities: identities.isEmpty ? null : identities,
    onPasswordRequest:
        target.password != null ? () async => target.password : null,
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
