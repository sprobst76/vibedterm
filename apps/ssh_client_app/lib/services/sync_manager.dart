import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core_sync/core_sync.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages cloud sync for the vault.
///
/// This class orchestrates the AuthService and SyncService from core_sync
/// to provide vault synchronization with the server.
class SyncManager {
  SyncManager({
    SyncConfig? config,
  }) : _config = config ?? const SyncConfig(serverUrl: '');

  SyncConfig _config;
  SyncApiClient? _apiClient;
  AuthService? _authService;
  SyncService? _syncService;

  static const _serverUrlKey = 'vibedterm.sync.serverUrl';
  static const _localRevisionKey = 'vibedterm.sync.localRevision';
  static const _deviceIdKey = 'vibedterm.sync.deviceId';

  final _combinedStatusController = StreamController<CombinedSyncStatus>.broadcast();
  CombinedSyncStatus _combinedStatus = CombinedSyncStatus.disconnected;

  /// Stream of combined sync status changes.
  Stream<CombinedSyncStatus> get statusStream => _combinedStatusController.stream;

  /// Current combined sync status.
  CombinedSyncStatus get status => _combinedStatus;

  /// Whether sync is configured (server URL is set).
  bool get isConfigured => _config.serverUrl.isNotEmpty;

  /// Whether user is authenticated.
  bool get isAuthenticated => _authService?.isAuthenticated ?? false;

  /// Current server URL.
  String get serverUrl => _config.serverUrl;

  /// Auth service for login/logout operations.
  AuthService? get authService => _authService;

  /// Sync service for vault sync operations.
  SyncService? get syncService => _syncService;

  void _updateStatus(CombinedSyncStatus status) {
    _combinedStatus = status;
    _combinedStatusController.add(status);
  }

  /// Initialize sync manager from stored settings.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString(_serverUrlKey);
    final localRevision = prefs.getInt(_localRevisionKey);
    final deviceId = prefs.getString(_deviceIdKey);

    if (serverUrl != null && serverUrl.isNotEmpty) {
      _config = _config.copyWith(serverUrl: serverUrl);
      await _initializeServices(
        localRevision: localRevision,
        deviceId: deviceId,
      );
    }
  }

  /// Configure the sync server URL.
  Future<void> configure(String serverUrl) async {
    if (serverUrl.isEmpty) {
      await disconnect();
      return;
    }

    _config = _config.copyWith(serverUrl: serverUrl);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverUrlKey, serverUrl);

    await _initializeServices();
  }

  Future<void> _initializeServices({
    int? localRevision,
    String? deviceId,
  }) async {
    _apiClient = SyncApiClient(config: _config);
    _authService = AuthService(apiClient: _apiClient!);
    _syncService = SyncService(
      apiClient: _apiClient!,
      authService: _authService!,
    );

    // Listen to auth status changes
    _authService!.statusStream.listen((authStatus) {
      _updateStatus(CombinedSyncStatus(
        authState: authStatus.state,
        syncState: _syncService?.status.state ?? SyncState.disconnected,
        user: authStatus.user,
        lastSyncAt: _syncService?.status.lastSyncAt,
        errorMessage: authStatus.errorMessage,
      ));
    });

    // Listen to sync status changes
    _syncService!.statusStream.listen((syncStatus) {
      _updateStatus(CombinedSyncStatus(
        authState: _authService?.status.state ?? AuthState.unauthenticated,
        syncState: syncStatus.state,
        user: _authService?.currentUser,
        lastSyncAt: syncStatus.lastSyncAt,
        localRevision: syncStatus.localRevision,
        serverRevision: syncStatus.serverRevision,
        errorMessage: syncStatus.errorMessage,
        conflictInfo: syncStatus.conflictInfo,
      ));
    });

    // Initialize services
    await _authService!.init();
    await _syncService!.init(
      localRevision: localRevision,
      deviceId: deviceId,
    );

    _updateStatus(CombinedSyncStatus(
      authState: _authService!.status.state,
      syncState: _syncService!.status.state,
      user: _authService!.currentUser,
    ));
  }

  /// Register a new account.
  Future<void> register({
    required String email,
    required String password,
  }) async {
    if (_authService == null) {
      throw SyncException('Sync not configured');
    }
    await _authService!.register(email: email, password: password);
  }

  /// Login to the sync server.
  Future<void> login({
    required String email,
    required String password,
    required String deviceName,
    required String deviceType,
  }) async {
    if (_authService == null) {
      throw SyncException('Sync not configured');
    }
    await _authService!.login(
      email: email,
      password: password,
      deviceName: deviceName,
      deviceType: deviceType,
    );

    // Save device ID
    if (_authService!.deviceId != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_deviceIdKey, _authService!.deviceId!);
    }
  }

  /// Complete login with TOTP code.
  Future<void> verifyTOTP(String code) async {
    if (_authService == null) {
      throw SyncException('Sync not configured');
    }
    await _authService!.verifyTOTP(code);

    // Save device ID
    if (_authService!.deviceId != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_deviceIdKey, _authService!.deviceId!);
    }
  }

  /// Logout from the sync server.
  Future<void> logout() async {
    await _authService?.logout();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_localRevisionKey);
    await prefs.remove(_deviceIdKey);
  }

  /// Sync the vault with the server.
  ///
  /// [vaultFilePath] is the path to the local vault file.
  /// [vaultPassword] is used to re-encrypt if needed after merge.
  Future<SyncResult> syncVault({
    required String vaultFilePath,
  }) async {
    if (_syncService == null || !isAuthenticated) {
      return const SyncResult(
        action: SyncAction.skipped,
        reason: 'Not authenticated',
      );
    }

    final result = await _syncService!.sync(
      getLocalVault: () async {
        final file = File(vaultFilePath);
        if (!await file.exists()) {
          throw SyncException('Vault file not found');
        }
        final bytes = await file.readAsBytes();
        return base64Encode(bytes);
      },
      loadServerVault: (vaultBlob, revision) async {
        final bytes = base64Decode(vaultBlob);

        // Write to temp file first, then rename (atomic)
        final tmpFile = File('$vaultFilePath.sync.tmp');
        await tmpFile.writeAsBytes(bytes, flush: true);
        await tmpFile.rename(vaultFilePath);

        // Save the new revision
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_localRevisionKey, revision);
      },
    );

    if (result.newRevision != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_localRevisionKey, result.newRevision!);
      _syncService!.setLocalRevision(result.newRevision!);
    }

    return result;
  }

  /// Force push local vault to server, overwriting server version.
  Future<void> forceUpload({required String vaultFilePath}) async {
    if (_syncService == null || !isAuthenticated) {
      throw SyncException('Not authenticated');
    }

    final file = File(vaultFilePath);
    if (!await file.exists()) {
      throw SyncException('Vault file not found');
    }

    final bytes = await file.readAsBytes();
    final vaultBlob = base64Encode(bytes);

    final response = await _syncService!.forceOverwrite(vaultBlob: vaultBlob);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_localRevisionKey, response.revision);
    _syncService!.setLocalRevision(response.revision);
  }

  /// Force download server vault, overwriting local version.
  Future<void> forceDownload({required String vaultFilePath}) async {
    if (_syncService == null || !isAuthenticated) {
      throw SyncException('Not authenticated');
    }

    final response = await _syncService!.pull();
    final bytes = base64Decode(response.vaultBlob);

    // Write to temp file first, then rename (atomic)
    final tmpFile = File('$vaultFilePath.sync.tmp');
    await tmpFile.writeAsBytes(bytes, flush: true);
    await tmpFile.rename(vaultFilePath);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_localRevisionKey, response.revision);
    _syncService!.setLocalRevision(response.revision);
  }

  /// Set local vault revision (call after vault changes).
  Future<void> setLocalRevision(int revision) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_localRevisionKey, revision);
    _syncService?.setLocalRevision(revision);
  }

  /// Get sync history.
  Future<List<Map<String, dynamic>>> getHistory() async {
    if (_syncService == null || !isAuthenticated) {
      return [];
    }
    return _syncService!.getHistory();
  }

  /// Clear conflict state after user resolution.
  void clearConflict() {
    _syncService?.clearConflict();
  }

  /// Disconnect and clear sync configuration.
  Future<void> disconnect() async {
    await _authService?.logout();
    _authService?.dispose();
    _syncService?.dispose();
    _apiClient?.dispose();

    _apiClient = null;
    _authService = null;
    _syncService = null;
    _config = _config.copyWith(serverUrl: '');

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_serverUrlKey);
    await prefs.remove(_localRevisionKey);
    await prefs.remove(_deviceIdKey);

    _updateStatus(CombinedSyncStatus.disconnected);
  }

  /// Dispose resources.
  void dispose() {
    _authService?.dispose();
    _syncService?.dispose();
    _apiClient?.dispose();
    _combinedStatusController.close();
  }
}

/// Combined status from auth and sync services.
@immutable
class CombinedSyncStatus {
  const CombinedSyncStatus({
    required this.authState,
    required this.syncState,
    this.user,
    this.lastSyncAt,
    this.localRevision,
    this.serverRevision,
    this.errorMessage,
    this.conflictInfo,
  });

  final AuthState authState;
  final SyncState syncState;
  final SyncUser? user;
  final DateTime? lastSyncAt;
  final int? localRevision;
  final int? serverRevision;
  final String? errorMessage;
  final SyncConflictInfo? conflictInfo;

  bool get isAuthenticated => authState == AuthState.authenticated;
  bool get isSyncing => syncState == SyncState.syncing;
  bool get hasConflict => syncState == SyncState.conflict;
  bool get hasError =>
      authState == AuthState.error || syncState == SyncState.error;

  static const disconnected = CombinedSyncStatus(
    authState: AuthState.unauthenticated,
    syncState: SyncState.disconnected,
  );
}
