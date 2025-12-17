import 'dart:io';

import 'package:core_vault/core_vault.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

enum VaultStatus { locked, unlocked, error }

@immutable
class VaultState {
  const VaultState({
    required this.status,
    this.message = '',
    this.filePath,
    this.isBusy = false,
  });

  final VaultStatus status;
  final String message;
  final String? filePath;
  final bool isBusy;

  VaultState copyWith({
    VaultStatus? status,
    String? message,
    String? filePath,
    bool? isBusy,
  }) {
    return VaultState(
      status: status ?? this.status,
      message: message ?? this.message,
      filePath: filePath ?? this.filePath,
      isBusy: isBusy ?? this.isBusy,
    );
  }
}

/// Minimal vault orchestrator for the demo screens.
class VaultService {
  VaultService();

  final _uuid = const Uuid();
  static const _lastPathKey = 'vibedterm.lastVaultPath';
  static const _lastPasswordKey = 'vibedterm.lastVaultPassword';
  final _secureStorage = const FlutterSecureStorage();

  static const _demoPassword = 'demo-password';
  static const _demoFileName = 'vibedterm_demo.vlt';
  final Map<String, String> _sessionPasswords = {};

  final ValueNotifier<VaultState> state = ValueNotifier<VaultState>(
    const VaultState(status: VaultStatus.locked),
  );

  VaultFile? _current;

  bool get isUnlocked => _current != null;
  String? get currentPath => _current?.file.path;
  String? _lastPath;
  String? _savedPassword;
  String? get lastPath => _lastPath;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _lastPath = prefs.getString(_lastPathKey);
    _savedPassword = await _secureStorage.read(key: _lastPasswordKey);
    if (_lastPath != null) {
      state.value = state.value.copyWith(filePath: _lastPath);
    }
  }

  Future<void> createDemoVault() async {
    try {
      final dir = await Directory.systemTemp.createTemp('vibedterm_demo_');
      final file = File('${dir.path}/$_demoFileName');
      final payload = VaultPayload(
        data: VaultData(
          version: 1,
          revision: 1,
          deviceId: 'demo-device',
          createdAt: DateTime.now().toUtc().toIso8601String(),
          updatedAt: DateTime.now().toUtc().toIso8601String(),
          settings: const VaultSettings(theme: 'system', fontSize: 14),
          snippets: const [
            VaultSnippet(
              id: 's1',
              title: 'List home',
              content: 'ls -la ~',
            ),
          ],
        ),
      );
      _current = await VaultFile.create(
        file: file,
        password: _demoPassword,
        payload: payload,
      );
      state.value = VaultState(
        status: VaultStatus.unlocked,
        message: 'Demo vault created at ${file.path}',
        filePath: file.path,
      );
    } on VaultException catch (e) {
      state.value = VaultState(
        status: VaultStatus.error,
        message: e.message,
      );
    } catch (e) {
      state.value = VaultState(
        status: VaultStatus.error,
        message: 'Failed to create vault: $e',
      );
    }
  }

  Future<void> unlockDemoVault(String filePath) async {
    try {
      final file = File(filePath);
      _current = await VaultFile.open(
        file: file,
        password: _demoPassword,
      );
      state.value = VaultState(
        status: VaultStatus.unlocked,
        message: 'Vault unlocked at $filePath',
        filePath: filePath,
      );
    } on VaultException catch (e) {
      state.value = VaultState(
        status: VaultStatus.error,
        message: e.message,
        filePath: filePath,
      );
    } catch (e) {
      state.value = VaultState(
        status: VaultStatus.error,
        message: 'Failed to unlock vault: $e',
        filePath: filePath,
      );
    }
  }

  Future<void> createVault({
    required String path,
    required String password,
    required VaultPayload payload,
    bool rememberPasswordForSession = false,
    bool rememberPasswordSecurely = false,
  }) async {
    state.value = state.value.copyWith(isBusy: true);
    try {
      _current = await VaultFile.create(
        file: File(path),
        password: password,
        payload: payload,
      );
      state.value = VaultState(
        status: VaultStatus.unlocked,
        message: 'Vault created at $path',
        filePath: path,
        isBusy: false,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastPathKey, path);
      _lastPath = path;
      if (rememberPasswordForSession) {
        _sessionPasswords[path] = password;
      }
      if (rememberPasswordSecurely) {
        await _secureStorage.write(key: _lastPasswordKey, value: password);
        _savedPassword = password;
      }
    } on VaultException catch (e) {
      state.value = VaultState(
        status: VaultStatus.error,
        message: e.message,
        filePath: path,
        isBusy: false,
      );
    } catch (e) {
      state.value = VaultState(
        status: VaultStatus.error,
        message: 'Failed to create vault: $e',
        filePath: path,
        isBusy: false,
      );
    }
  }

  Future<void> unlockVault({
    required String path,
    String? password,
    bool rememberPasswordForSession = false,
    bool rememberPasswordSecurely = false,
  }) async {
    state.value = state.value.copyWith(isBusy: true);
    try {
      final effectivePassword =
          password ?? _sessionPasswords[path] ?? _savedPassword;
      if (effectivePassword == null || effectivePassword.isEmpty) {
        throw VaultException('Password required to unlock vault.');
      }
      _current = await VaultFile.open(
        file: File(path),
        password: effectivePassword,
      );
      state.value = VaultState(
        status: VaultStatus.unlocked,
        message: 'Vault unlocked at $path',
        filePath: path,
        isBusy: false,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastPathKey, path);
      _lastPath = path;
      if (rememberPasswordForSession) {
        _sessionPasswords[path] = effectivePassword;
      }
      if (rememberPasswordSecurely) {
        await _secureStorage.write(
          key: _lastPasswordKey,
          value: effectivePassword,
        );
        _savedPassword = effectivePassword;
      }
    } on VaultException catch (e) {
      state.value = VaultState(
        status: VaultStatus.error,
        message: e.message,
        filePath: path,
        isBusy: false,
      );
    } catch (e) {
      state.value = VaultState(
        status: VaultStatus.error,
        message: 'Failed to unlock vault: $e',
        filePath: path,
        isBusy: false,
      );
    }
  }

  VaultData? get currentData => _current?.payload.data;

  Future<void> addHost({
    required String label,
    required String hostname,
    int port = 22,
    required String username,
    String? identityId,
  }) async {
    if (_current == null) {
      state.value = state.value.copyWith(
        status: VaultStatus.error,
        message: 'Unlock a vault first.',
      );
      return;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final host = VaultHost(
      id: _uuid.v4(),
      label: label,
      hostname: hostname,
      port: port,
      username: username,
      identityId: identityId,
      createdAt: now,
      updatedAt: now,
    );
    try {
      _current!.upsertHost(host);
      await _current!.save();
      state.value = state.value.copyWith(
        status: VaultStatus.unlocked,
        message: 'Host added.',
      );
    } on VaultException catch (e) {
      state.value = state.value.copyWith(
        status: VaultStatus.error,
        message: e.message,
      );
    }
  }

  Future<void> addIdentity({
    required String name,
    required String type,
    required String privateKey,
    String? passphrase,
  }) async {
    if (_current == null) {
      state.value = state.value.copyWith(
        status: VaultStatus.error,
        message: 'Unlock a vault first.',
      );
      return;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final identity = VaultIdentity(
      id: _uuid.v4(),
      name: name,
      type: type,
      privateKey: privateKey,
      passphrase: passphrase,
      createdAt: now,
      updatedAt: now,
    );
    try {
      _current!.upsertIdentity(identity);
      await _current!.save();
      state.value = state.value.copyWith(
        status: VaultStatus.unlocked,
        message: 'Identity added.',
      );
    } on VaultException catch (e) {
      state.value = state.value.copyWith(
        status: VaultStatus.error,
        message: e.message,
      );
    }
  }

  Future<void> updateHost(VaultHost updated) async {
    if (_current == null) return;
    try {
      _current!.upsertHost(updated);
      await _current!.save();
      state.value = state.value.copyWith(
        status: VaultStatus.unlocked,
        message: 'Host updated.',
      );
    } on VaultException catch (e) {
      state.value = state.value.copyWith(
        status: VaultStatus.error,
        message: e.message,
      );
    }
  }

  Future<void> deleteHost(String hostId) async {
    if (_current == null) return;
    _current!.removeHost(hostId);
    await _current!.save();
    state.value = state.value.copyWith(
      status: VaultStatus.unlocked,
      message: 'Host deleted.',
    );
  }

  Future<void> updateIdentity(VaultIdentity updated) async {
    if (_current == null) return;
    try {
      _current!.upsertIdentity(updated);
      await _current!.save();
      state.value = state.value.copyWith(
        status: VaultStatus.unlocked,
        message: 'Identity updated.',
      );
    } on VaultException catch (e) {
      state.value = state.value.copyWith(
        status: VaultStatus.error,
        message: e.message,
      );
    }
  }

  Future<void> deleteIdentity(String identityId) async {
    if (_current == null) return;
    _current!.removeIdentity(identityId);
    await _current!.save();
    state.value = state.value.copyWith(
      status: VaultStatus.unlocked,
      message: 'Identity deleted.',
    );
  }

  Map<String, Set<String>> trustedHostKeys() {
    final meta = _current?.payload.data.meta ?? const <String, dynamic>{};
    final raw = meta['trustedHostKeys'];
    if (raw is! Map) return {};
    final result = <String, Set<String>>{};
    raw.forEach((key, value) {
      final host = key.toString();
      if (value is Iterable) {
        result[host] = value.map((e) => e.toString()).toSet();
      }
    });
    return result;
  }

  Future<void> trustHostKey({
    required String host,
    required String fingerprint,
  }) async {
    if (_current == null) {
      state.value = state.value.copyWith(
        status: VaultStatus.error,
        message: 'Unlock a vault first.',
      );
      return;
    }
    final meta = Map<String, dynamic>.from(
      _current!.payload.data.meta,
    );
    final trusted = <String, Set<String>>{
      ...trustedHostKeys(),
    };
    final entries = trusted.putIfAbsent(host, () => <String>{});
    entries.add(fingerprint);
    meta['trustedHostKeys'] = trusted.map(
      (key, value) => MapEntry(key, value.toList()),
    );
    _current!.updateMeta(meta);
    await _current!.save();
    state.value = state.value.copyWith(
      status: VaultStatus.unlocked,
      message: 'Host key trusted for $host.',
    );
  }
}
