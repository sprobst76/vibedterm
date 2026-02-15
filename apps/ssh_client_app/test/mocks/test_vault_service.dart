import 'package:core_vault/core_vault.dart';
import 'package:flutter/foundation.dart';
import 'package:ssh_client_app/services/vault_service_interface.dart';

/// Test implementation of VaultServiceInterface for widget testing.
/// Does not require actual file system or secure storage.
class TestVaultService implements VaultServiceInterface {
  TestVaultService();

  @override
  final ValueNotifier<VaultState> state = ValueNotifier<VaultState>(
    const VaultState(status: VaultStatus.locked),
  );

  VaultData? _currentData;
  String? _lastPath;
  VaultHost? _pendingConnectHost;
  VaultIdentity? _pendingConnectIdentity;
  final Map<String, Set<String>> _trustedHostKeys = {};

  @override
  bool get isUnlocked => state.value.status == VaultStatus.unlocked;

  @override
  String? get currentPath => _lastPath;

  @override
  String? get lastPath => _lastPath;

  @override
  VaultData? get currentData => _currentData;

  @override
  VaultHost? get pendingConnectHost => _pendingConnectHost;

  @override
  VaultIdentity? get pendingConnectIdentity => _pendingConnectIdentity;

  @override
  Future<void> init() async {
    // No-op for tests
  }

  @override
  Future<void> createDemoVault() async {
    final now = DateTime.now().toUtc().toIso8601String();
    _currentData = VaultData(
      version: 1,
      revision: 1,
      deviceId: 'test-device',
      createdAt: now,
      updatedAt: now,
      settings: const VaultSettings(theme: 'system', fontSize: 14),
    );
    _lastPath = '/tmp/test_vault.vlt';
    state.value = VaultState(
      status: VaultStatus.unlocked,
      message: 'Demo vault created',
      filePath: _lastPath,
    );
  }

  @override
  Future<void> unlockDemoVault(String filePath) async {
    _lastPath = filePath;
    final now = DateTime.now().toUtc().toIso8601String();
    _currentData = VaultData(
      version: 1,
      revision: 1,
      deviceId: 'test-device',
      createdAt: now,
      updatedAt: now,
    );
    state.value = VaultState(
      status: VaultStatus.unlocked,
      message: 'Vault unlocked at $filePath',
      filePath: filePath,
    );
  }

  @override
  Future<void> createVault({
    required String path,
    required String password,
    required VaultPayload payload,
    bool rememberPasswordForSession = false,
    bool rememberPasswordSecurely = false,
  }) async {
    _lastPath = path;
    _currentData = payload.data;
    state.value = VaultState(
      status: VaultStatus.unlocked,
      message: 'Vault created at $path',
      filePath: path,
    );
  }

  @override
  Future<void> unlockVault({
    required String path,
    String? password,
    bool rememberPasswordForSession = false,
    bool rememberPasswordSecurely = false,
  }) async {
    if (password == null || password.isEmpty) {
      state.value = VaultState(
        status: VaultStatus.error,
        message: 'Password required',
        filePath: path,
      );
      return;
    }
    _lastPath = path;
    final now = DateTime.now().toUtc().toIso8601String();
    _currentData = VaultData(
      version: 1,
      revision: 1,
      deviceId: 'test-device',
      createdAt: now,
      updatedAt: now,
    );
    state.value = VaultState(
      status: VaultStatus.unlocked,
      message: 'Vault unlocked at $path',
      filePath: path,
    );
  }

  @override
  Future<void> addHost({
    required String label,
    required String hostname,
    int port = 22,
    required String username,
    String? identityId,
    String? group,
    bool tmuxEnabled = false,
    String? tmuxSessionName,
  }) async {
    if (_currentData == null) {
      state.value = state.value.copyWith(
        status: VaultStatus.error,
        message: 'Unlock a vault first.',
      );
      return;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final host = VaultHost(
      id: 'host-${_currentData!.hosts.length + 1}',
      label: label,
      hostname: hostname,
      port: port,
      username: username,
      identityId: identityId,
      tmuxEnabled: tmuxEnabled,
      tmuxSessionName: tmuxSessionName,
      createdAt: now,
      updatedAt: now,
    );
    _currentData = VaultData(
      version: _currentData!.version,
      revision: _currentData!.revision + 1,
      deviceId: _currentData!.deviceId,
      createdAt: _currentData!.createdAt,
      updatedAt: now,
      hosts: [..._currentData!.hosts, host],
      identities: _currentData!.identities,
      snippets: _currentData!.snippets,
      settings: _currentData!.settings,
      meta: _currentData!.meta,
    );
    state.value = state.value.copyWith(
      status: VaultStatus.unlocked,
      message: 'Host added.',
    );
  }

  @override
  Future<void> addIdentity({
    required String name,
    required String type,
    required String privateKey,
    String? passphrase,
  }) async {
    if (_currentData == null) {
      state.value = state.value.copyWith(
        status: VaultStatus.error,
        message: 'Unlock a vault first.',
      );
      return;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final identity = VaultIdentity(
      id: 'id-${_currentData!.identities.length + 1}',
      name: name,
      type: type,
      privateKey: privateKey,
      passphrase: passphrase,
      createdAt: now,
      updatedAt: now,
    );
    _currentData = VaultData(
      version: _currentData!.version,
      revision: _currentData!.revision + 1,
      deviceId: _currentData!.deviceId,
      createdAt: _currentData!.createdAt,
      updatedAt: now,
      hosts: _currentData!.hosts,
      identities: [..._currentData!.identities, identity],
      snippets: _currentData!.snippets,
      settings: _currentData!.settings,
      meta: _currentData!.meta,
    );
    state.value = state.value.copyWith(
      status: VaultStatus.unlocked,
      message: 'Identity added.',
    );
  }

  @override
  Future<void> updateHost(VaultHost updated) async {
    if (_currentData == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final hosts = _currentData!.hosts
        .map((h) => h.id == updated.id ? updated : h)
        .toList();
    _currentData = VaultData(
      version: _currentData!.version,
      revision: _currentData!.revision + 1,
      deviceId: _currentData!.deviceId,
      createdAt: _currentData!.createdAt,
      updatedAt: now,
      hosts: hosts,
      identities: _currentData!.identities,
      snippets: _currentData!.snippets,
      settings: _currentData!.settings,
      meta: _currentData!.meta,
    );
    state.value = state.value.copyWith(
      status: VaultStatus.unlocked,
      message: 'Host updated.',
    );
  }

  @override
  Future<void> deleteHost(String hostId) async {
    if (_currentData == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final hosts = _currentData!.hosts.where((h) => h.id != hostId).toList();
    _currentData = VaultData(
      version: _currentData!.version,
      revision: _currentData!.revision + 1,
      deviceId: _currentData!.deviceId,
      createdAt: _currentData!.createdAt,
      updatedAt: now,
      hosts: hosts,
      identities: _currentData!.identities,
      snippets: _currentData!.snippets,
      settings: _currentData!.settings,
      meta: _currentData!.meta,
    );
    state.value = state.value.copyWith(
      status: VaultStatus.unlocked,
      message: 'Host deleted.',
    );
  }

  @override
  Future<void> updateIdentity(VaultIdentity updated) async {
    if (_currentData == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final identities = _currentData!.identities
        .map((i) => i.id == updated.id ? updated : i)
        .toList();
    _currentData = VaultData(
      version: _currentData!.version,
      revision: _currentData!.revision + 1,
      deviceId: _currentData!.deviceId,
      createdAt: _currentData!.createdAt,
      updatedAt: now,
      hosts: _currentData!.hosts,
      identities: identities,
      snippets: _currentData!.snippets,
      settings: _currentData!.settings,
      meta: _currentData!.meta,
    );
    state.value = state.value.copyWith(
      status: VaultStatus.unlocked,
      message: 'Identity updated.',
    );
  }

  @override
  Future<void> deleteIdentity(String identityId) async {
    if (_currentData == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final identities =
        _currentData!.identities.where((i) => i.id != identityId).toList();
    _currentData = VaultData(
      version: _currentData!.version,
      revision: _currentData!.revision + 1,
      deviceId: _currentData!.deviceId,
      createdAt: _currentData!.createdAt,
      updatedAt: now,
      hosts: _currentData!.hosts,
      identities: identities,
      snippets: _currentData!.snippets,
      settings: _currentData!.settings,
      meta: _currentData!.meta,
    );
    state.value = state.value.copyWith(
      status: VaultStatus.unlocked,
      message: 'Identity deleted.',
    );
  }

  @override
  Future<void> addSnippet({
    required String title,
    required String content,
    List<String> tags = const [],
  }) async {
    if (_currentData == null) {
      state.value = state.value.copyWith(
        status: VaultStatus.error,
        message: 'Unlock a vault first.',
      );
      return;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final snippet = VaultSnippet(
      id: 'snip-${_currentData!.snippets.length + 1}',
      title: title,
      content: content,
      tags: tags,
      createdAt: now,
      updatedAt: now,
    );
    _currentData = _currentData!.copyWith(
      snippets: [..._currentData!.snippets, snippet],
      revision: _currentData!.revision + 1,
      updatedAt: now,
    );
    state.value = state.value.copyWith(
      status: VaultStatus.unlocked,
      message: 'Snippet added.',
    );
  }

  @override
  Future<void> updateSnippet(VaultSnippet updated) async {
    if (_currentData == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final snippets = _currentData!.snippets
        .map((s) => s.id == updated.id ? updated : s)
        .toList();
    _currentData = _currentData!.copyWith(
      snippets: snippets,
      revision: _currentData!.revision + 1,
      updatedAt: now,
    );
    state.value = state.value.copyWith(
      status: VaultStatus.unlocked,
      message: 'Snippet updated.',
    );
  }

  @override
  Future<void> deleteSnippet(String snippetId) async {
    if (_currentData == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final snippets =
        _currentData!.snippets.where((s) => s.id != snippetId).toList();
    _currentData = _currentData!.copyWith(
      snippets: snippets,
      revision: _currentData!.revision + 1,
      updatedAt: now,
    );
    state.value = state.value.copyWith(
      status: VaultStatus.unlocked,
      message: 'Snippet deleted.',
    );
  }

  @override
  Future<void> updateSettings(VaultSettings settings) async {
    if (_currentData == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    _currentData = VaultData(
      version: _currentData!.version,
      revision: _currentData!.revision + 1,
      deviceId: _currentData!.deviceId,
      createdAt: _currentData!.createdAt,
      updatedAt: now,
      hosts: _currentData!.hosts,
      identities: _currentData!.identities,
      snippets: _currentData!.snippets,
      settings: settings,
      meta: _currentData!.meta,
    );
    state.value = state.value.copyWith(
      status: VaultStatus.unlocked,
      message: 'Settings updated.',
    );
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
  Map<String, Set<String>> trustedHostKeys() => Map.from(_trustedHostKeys);

  @override
  Future<void> trustHostKey({
    required String host,
    required String fingerprint,
  }) async {
    _trustedHostKeys.putIfAbsent(host, () => <String>{}).add(fingerprint);
    state.value = state.value.copyWith(
      message: 'Host key trusted for $host.',
    );
  }

  @override
  Future<void> untrustHostKey({
    required String host,
    required String fingerprint,
  }) async {
    _trustedHostKeys[host]?.remove(fingerprint);
    if (_trustedHostKeys[host]?.isEmpty ?? false) {
      _trustedHostKeys.remove(host);
    }
    state.value = state.value.copyWith(
      message: 'Removed trusted key for $host.',
    );
  }

  @override
  Future<void> untrustHost(String host) async {
    _trustedHostKeys.remove(host);
    state.value = state.value.copyWith(
      message: 'Removed trusted keys for $host.',
    );
  }

  // Test helper methods

  /// Set state for testing specific scenarios
  void setStateForTest(VaultState newState) {
    state.value = newState;
  }

  /// Set data for testing specific scenarios
  void setDataForTest(VaultData? data) {
    _currentData = data;
  }

  /// Add trusted keys for testing
  void addTrustedKeyForTest(String host, String fingerprint) {
    _trustedHostKeys.putIfAbsent(host, () => <String>{}).add(fingerprint);
  }
}
