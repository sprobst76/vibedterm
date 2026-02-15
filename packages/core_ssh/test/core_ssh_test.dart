import 'dart:async';
import 'dart:io';

import 'package:core_ssh/core_ssh.dart';
import 'package:test/test.dart';

void main() {
  group('SshConnectionManager', () {
    test('connects and runs command via adapter', () async {
      final adapter = _FakeAdapter();
      final manager = SshConnectionManager(
        clientFactory: (_, log) async {
          log('factory-connect');
          return adapter;
        },
      );

      final logs = expectLater(
        manager.logs.take(7),
        emitsInOrder([
          contains('Connecting'),
          'factory-connect',
          contains('Connected'),
          contains('Running command'),
          contains('Command finished'),
          contains('Disconnecting'),
          contains('Disconnected'),
        ]),
      );

      await manager.connect(const SshTarget(host: 'example.com', username: 'root'));
      expect(manager.status, SshConnectionStatus.connected);

      final result = await manager.runCommand('echo hi');
      expect(result.stdout, 'ok');
      expect(adapter.commands, ['echo hi']);
      await manager.disconnect();
      expect(manager.status, SshConnectionStatus.disconnected);
      await logs;
    });

    test('maps socket errors to hostUnreachable', () async {
      final manager = SshConnectionManager(
        clientFactory: (_, __) async => throw const SocketException('no route'),
      );

      await expectLater(
        manager.connect(const SshTarget(host: 'bad', username: 'root')),
        throwsA(
          isA<SshException>().having(
            (e) => e.kind,
            'kind',
            SshErrorKind.hostUnreachable,
          ),
        ),
      );
      expect(manager.status, SshConnectionStatus.error);
    });

    test('shell session echoes writes to stdout stream', () async {
      final adapter = _FakeAdapter();
      final manager = SshConnectionManager(
        clientFactory: (_, __) async => adapter,
      );

      await manager.connect(const SshTarget(host: 'example.com', username: 'root'));
      final shell = await manager.startShell();
      final outputs = <String>[];
      final sub = shell.stdout.listen((data) {
        outputs.add(String.fromCharCodes(data));
      });

      await shell.writeString('hello');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await shell.close();
      await sub.cancel();
      await manager.disconnect();

      expect(outputs, contains('hello'));
    });
  });
}

class _FakeAdapter implements SshClientAdapter {
  final List<String> commands = [];
  final StreamController<List<int>> _shellOut =
      StreamController<List<int>>.broadcast();

  @override
  Future<SftpClient> openSftp() async {
    throw SshException(SshErrorKind.unknown, 'SFTP not supported in tests');
  }

  @override
  Future<SSHForwardChannel> forwardLocal(String remoteHost, int remotePort) async {
    throw SshException(SshErrorKind.unknown, 'Port forwarding not supported in tests');
  }

  @override
  Future<SSHRemoteForward?> forwardRemote({required String host, required int port}) async {
    throw SshException(SshErrorKind.unknown, 'Port forwarding not supported in tests');
  }

  @override
  Future<void> disconnect() async {
    if (!_shellOut.isClosed) {
      await _shellOut.close();
    }
  }

  @override
  Future<SshCommandResult> run(String command) async {
    commands.add(command);
    return const SshCommandResult(stdout: 'ok', stderr: '', exitCode: 0);
  }

  @override
  Future<SshShellSession> startShell({SshPtyConfig ptyConfig = const SshPtyConfig()}) async {
    return SshShellSession(
      stdout: _shellOut.stream,
      stderr: const Stream.empty(),
      write: (data) async => _shellOut.add(data),
      resize: (_, __) {},
      close: () async {
        if (!_shellOut.isClosed) {
          await _shellOut.close();
        }
      },
      done: Future.value(),
    );
  }
}
