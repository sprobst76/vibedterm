import 'package:core_vault/core_vault.dart';
import 'package:flutter/foundation.dart';

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

  void setPendingConnectHost(VaultHost? host, {VaultIdentity? identity});
  void clearPendingConnect();

  Map<String, Set<String>> trustedHostKeys();
  Future<void> trustHostKey({required String host, required String fingerprint});
  Future<void> untrustHostKey({required String host, required String fingerprint});
  Future<void> untrustHost(String host);
}
