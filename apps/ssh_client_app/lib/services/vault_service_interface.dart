import 'package:core_vault/core_vault.dart';
import 'package:flutter/foundation.dart';

enum VaultStatus { locked, unlocked, error }

/// Status of cloud sync.
enum CloudSyncStatus {
  /// Sync not configured
  disabled,

  /// Not logged in
  unauthenticated,

  /// Logged in, ready to sync
  idle,

  /// Currently syncing
  syncing,

  /// Sync completed
  synced,

  /// Conflict detected
  conflict,

  /// Error occurred
  error,
}

@immutable
class VaultState {
  const VaultState({
    required this.status,
    this.message = '',
    this.filePath,
    this.isBusy = false,
    this.syncStatus = CloudSyncStatus.disabled,
    this.syncMessage,
    this.lastSyncAt,
  });

  final VaultStatus status;
  final String message;
  final String? filePath;
  final bool isBusy;
  final CloudSyncStatus syncStatus;
  final String? syncMessage;
  final DateTime? lastSyncAt;

  VaultState copyWith({
    VaultStatus? status,
    String? message,
    String? filePath,
    bool? isBusy,
    CloudSyncStatus? syncStatus,
    String? syncMessage,
    DateTime? lastSyncAt,
  }) {
    return VaultState(
      status: status ?? this.status,
      message: message ?? this.message,
      filePath: filePath ?? this.filePath,
      isBusy: isBusy ?? this.isBusy,
      syncStatus: syncStatus ?? this.syncStatus,
      syncMessage: syncMessage ?? this.syncMessage,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    );
  }
}

/// Abstract interface for vault service to enable testing.
abstract class VaultServiceInterface {
  ValueNotifier<VaultState> get state;

  bool get isUnlocked;
  String? get currentPath;
  String? get lastPath;
  VaultData? get currentData;

  VaultHost? get pendingConnectHost;
  VaultIdentity? get pendingConnectIdentity;

  Future<void> init();
  Future<void> createDemoVault();
  Future<void> unlockDemoVault(String filePath);

  Future<void> createVault({
    required String path,
    required String password,
    required VaultPayload payload,
    bool rememberPasswordForSession,
    bool rememberPasswordSecurely,
  });

  Future<void> unlockVault({
    required String path,
    String? password,
    bool rememberPasswordForSession,
    bool rememberPasswordSecurely,
  });

  Future<void> addHost({
    required String label,
    required String hostname,
    int port,
    required String username,
    String? identityId,
    String? group,
    bool tmuxEnabled,
    String? tmuxSessionName,
  });

  Future<void> addIdentity({
    required String name,
    required String type,
    required String privateKey,
    String? passphrase,
  });

  Future<void> updateHost(VaultHost updated);
  Future<void> deleteHost(String hostId);
  Future<void> updateIdentity(VaultIdentity updated);
  Future<void> deleteIdentity(String identityId);
  Future<void> updateSettings(VaultSettings settings);

  Future<void> addSnippet({
    required String title,
    required String content,
    List<String> tags,
  });
  Future<void> updateSnippet(VaultSnippet updated);
  Future<void> deleteSnippet(String snippetId);

  void setPendingConnectHost(VaultHost? host, {VaultIdentity? identity});
  void clearPendingConnect();

  Map<String, Set<String>> trustedHostKeys();
  Future<void> trustHostKey({required String host, required String fingerprint});
  Future<void> untrustHostKey({required String host, required String fingerprint});
  Future<void> untrustHost(String host);
}
