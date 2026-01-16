import 'dart:io';

import 'package:core_vault/core_vault.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'vault_service_interface.dart';

export 'vault_service_interface.dart' show VaultStatus, VaultState, VaultServiceInterface;

/// Minimal vault orchestrator for the demo screens.
class VaultService implements VaultServiceInterface {
  VaultService();

  final _uuid = const Uuid();
  static const _lastPathKey = 'vibedterm.lastVaultPath';
  static const _lastPasswordKey = 'vibedterm.lastVaultPassword';
  final _secureStorage = const FlutterSecureStorage();

  static const _demoPassword = 'demo-password';
  static const _demoFileName = 'vibedterm_demo.vlt';
  final Map<String, String> _sessionPasswords = {};
  VaultHost? _pendingConnectHost;
  VaultIdentity? _pendingConnectIdentity;

  @override
  final ValueNotifier<VaultState> state = ValueNotifier<VaultState>(
    const VaultState(status: VaultStatus.locked),
  );

  VaultFile? _current;

  @override
  bool get isUnlocked => _current != null;
  @override
  String? get currentPath => _current?.file.path;
  String? _lastPath;
  String? _savedPassword;
  @override
  String? get lastPath => _lastPath;

  @override
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _lastPath = prefs.getString(_lastPathKey);
    _savedPassword = await _secureStorage.read(key: _lastPasswordKey);
    if (_lastPath != null) {
      state.value = state.value.copyWith(filePath: _lastPath);
      // Auto-unlock if password is saved
      if (_savedPassword != null && _savedPassword!.isNotEmpty) {
        final file = File(_lastPath!);
        if (await file.exists()) {
          await unlockVault(path: _lastPath!);
        }
      }
    }
  }

  @override
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

  @override
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

  @override
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

  @override
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

  @override
  VaultData? get currentData => _current?.payload.data;

  @override
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

  @override
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

  @override
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

  @override
  Future<void> deleteHost(String hostId) async {
    if (_current == null) return;
    _current!.removeHost(hostId);
    await _current!.save();
    state.value = state.value.copyWith(
      status: VaultStatus.unlocked,
      message: 'Host deleted.',
    );
  }

  @override
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

  @override
  Future<void> deleteIdentity(String identityId) async {
    if (_current == null) return;
    _current!.removeIdentity(identityId);
    await _current!.save();
    state.value = state.value.copyWith(
      status: VaultStatus.unlocked,
      message: 'Identity deleted.',
    );
  }

  @override
  Future<void> updateSettings(VaultSettings settings) async {
    if (_current == null) {
      state.value = state.value.copyWith(
        status: VaultStatus.error,
        message: 'Unlock a vault first.',
      );
      return;
    }
    try {
      _current!.updateSettings(settings);
      await _current!.save();
      state.value = state.value.copyWith(
        status: VaultStatus.unlocked,
        message: 'Settings updated.',
      );
    } on VaultException catch (e) {
      state.value = state.value.copyWith(
        status: VaultStatus.error,
        message: e.message,
      );
    }
  }

  @override
  void setPendingConnectHost(VaultHost? host, {VaultIdentity? identity}) {
    _pendingConnectHost = host;
    _pendingConnectIdentity = identity;
  }

  @override
  void clearPendingConnect() {
    _pendingConnectHost = null;
    _pendingConnectIdentity = null;
  }

  @override
  VaultHost? get pendingConnectHost => _pendingConnectHost;
  @override
  VaultIdentity? get pendingConnectIdentity => _pendingConnectIdentity;

  @override
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

  @override
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

  @override
  Future<void> untrustHostKey({
    required String host,
    required String fingerprint,
  }) async {
    if (_current == null) return;
    final trusted = trustedHostKeys();
    final set = trusted[host];
    if (set == null || !set.remove(fingerprint)) return;
    if (set.isEmpty) {
      trusted.remove(host);
    }
    final meta = Map<String, dynamic>.from(_current!.payload.data.meta);
    meta['trustedHostKeys'] = trusted.map(
      (key, value) => MapEntry(key, value.toList()),
    );
    _current!.updateMeta(meta);
    await _current!.save();
    state.value = state.value.copyWith(
      status: VaultStatus.unlocked,
      message: 'Removed trusted key for $host.',
    );
  }

  @override
  Future<void> untrustHost(String host) async {
    if (_current == null) return;
    final meta = Map<String, dynamic>.from(_current!.payload.data.meta);
    final trusted = trustedHostKeys();
    trusted.remove(host);
    meta['trustedHostKeys'] = trusted.map(
      (key, value) => MapEntry(key, value.toList()),
    );
    _current!.updateMeta(meta);
    await _current!.save();
    state.value = state.value.copyWith(
      status: VaultStatus.unlocked,
      message: 'Removed trusted keys for $host.',
    );
  }
}
