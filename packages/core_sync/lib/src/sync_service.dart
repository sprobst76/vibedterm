part of '../core_sync.dart';

/// Callback type for vault data operations.
typedef VaultBlobCallback = Future<String> Function();
typedef VaultLoadCallback = Future<void> Function(String vaultBlob, int revision);

/// Manages vault synchronization with the server.
class SyncService {
  SyncService({
    required SyncApiClient apiClient,
    required AuthService authService,
  })  : _api = apiClient,
        _auth = authService;

  final SyncApiClient _api;
  final AuthService _auth;

  final _statusController = StreamController<SyncStatus>.broadcast();
  SyncStatus _status = SyncStatus.disconnected;

  Timer? _autoSyncTimer;
  int? _localRevision;
  String? _deviceId;

  /// Stream of sync status changes.
  Stream<SyncStatus> get statusStream => _statusController.stream;

  /// Current sync status.
  SyncStatus get status => _status;

  /// Local vault revision number.
  int? get localRevision => _localRevision;

  void _updateStatus(SyncStatus status) {
    _status = status;
    _statusController.add(status);
  }

  /// Initialize the sync service.
  Future<void> init({int? localRevision, String? deviceId}) async {
    _localRevision = localRevision;
    _deviceId = deviceId ?? _auth.deviceId;

    if (_auth.isAuthenticated) {
      _updateStatus(const SyncStatus(state: SyncState.idle));
    } else {
      _updateStatus(SyncStatus.disconnected);
    }

    // Listen to auth changes
    _auth.statusStream.listen((authStatus) {
      if (authStatus.isAuthenticated) {
        _deviceId = authStatus.deviceId;
        _updateStatus(const SyncStatus(state: SyncState.idle));
      } else {
        _stopAutoSync();
        _updateStatus(SyncStatus.disconnected);
      }
    });
  }

  /// Set the local vault revision.
  void setLocalRevision(int revision) {
    _localRevision = revision;
    _updateStatus(_status.copyWith(localRevision: revision));
  }

  /// Check vault status on server.
  Future<VaultStatusResponse> checkStatus() async {
    if (!_auth.isAuthenticated) {
      throw SyncException('Not authenticated');
    }

    _updateStatus(_status.copyWith(state: SyncState.syncing));

    try {
      final status = await _api.getVaultStatus();
      _updateStatus(_status.copyWith(
        state: SyncState.idle,
        serverRevision: status.revision,
      ));
      return status;
    } on SyncException catch (e) {
      _updateStatus(_status.copyWith(
        state: SyncState.error,
        errorMessage: e.message,
      ));
      rethrow;
    }
  }

  /// Pull vault from server.
  /// Returns the vault blob (base64 encoded) and revision.
  Future<VaultPullResponse> pull() async {
    if (!_auth.isAuthenticated) {
      throw SyncException('Not authenticated');
    }

    _updateStatus(_status.copyWith(state: SyncState.syncing));

    try {
      final response = await _api.pullVault();
      _updateStatus(_status.copyWith(
        state: SyncState.synced,
        serverRevision: response.revision,
        lastSyncAt: DateTime.now(),
      ));
      return response;
    } on SyncException catch (e) {
      _updateStatus(_status.copyWith(
        state: SyncState.error,
        errorMessage: e.message,
      ));
      rethrow;
    }
  }

  /// Push vault to server.
  /// [vaultBlob] should be base64-encoded encrypted vault data.
  Future<VaultPushResponse> push({
    required String vaultBlob,
    required int revision,
  }) async {
    if (!_auth.isAuthenticated) {
      throw SyncException('Not authenticated');
    }

    if (_deviceId == null) {
      throw SyncException('Device ID not set');
    }

    _updateStatus(_status.copyWith(state: SyncState.syncing));

    try {
      final response = await _api.pushVault(
        vaultBlob: vaultBlob,
        revision: revision,
        deviceId: _deviceId!,
      );

      _localRevision = response.revision;
      _updateStatus(_status.copyWith(
        state: SyncState.synced,
        localRevision: response.revision,
        serverRevision: response.revision,
        lastSyncAt: DateTime.now(),
      ));

      return response;
    } on SyncException catch (e) {
      if (e.isConflict) {
        // Fetch conflict details
        try {
          final serverStatus = await _api.getVaultStatus();
          final serverVault = await _api.pullVault();

          _updateStatus(_status.copyWith(
            state: SyncState.conflict,
            serverRevision: serverStatus.revision,
            conflictInfo: SyncConflictInfo(
              localRevision: revision,
              serverRevision: serverStatus.revision,
              serverDeviceId: serverVault.updatedByDevice ?? '',
              serverUpdatedAt: serverVault.updatedAt,
            ),
          ));
        } catch (_) {
          _updateStatus(_status.copyWith(
            state: SyncState.conflict,
            errorMessage: 'Conflict detected',
          ));
        }
      } else {
        _updateStatus(_status.copyWith(
          state: SyncState.error,
          errorMessage: e.message,
        ));
      }
      rethrow;
    }
  }

  /// Force overwrite server vault with local version.
  Future<VaultPushResponse> forceOverwrite({
    required String vaultBlob,
  }) async {
    if (!_auth.isAuthenticated) {
      throw SyncException('Not authenticated');
    }

    if (_deviceId == null) {
      throw SyncException('Device ID not set');
    }

    _updateStatus(_status.copyWith(state: SyncState.syncing));

    try {
      final response = await _api.forceOverwriteVault(
        vaultBlob: vaultBlob,
        deviceId: _deviceId!,
      );

      _localRevision = response.revision;
      _updateStatus(_status.copyWith(
        state: SyncState.synced,
        localRevision: response.revision,
        serverRevision: response.revision,
        lastSyncAt: DateTime.now(),
        conflictInfo: null,
      ));

      return response;
    } on SyncException catch (e) {
      _updateStatus(_status.copyWith(
        state: SyncState.error,
        errorMessage: e.message,
      ));
      rethrow;
    }
  }

  /// Perform a full sync cycle.
  /// [getLocalVault] should return the current encrypted vault blob (base64).
  /// [loadServerVault] is called when server has newer version.
  Future<SyncResult> sync({
    required VaultBlobCallback getLocalVault,
    required VaultLoadCallback loadServerVault,
  }) async {
    if (!_auth.isAuthenticated) {
      return const SyncResult(
        action: SyncAction.skipped,
        reason: 'Not authenticated',
      );
    }

    _updateStatus(_status.copyWith(state: SyncState.syncing));

    try {
      // Check server status
      final serverStatus = await _api.getVaultStatus();

      if (!serverStatus.hasVault) {
        // No vault on server - push local
        if (_localRevision != null && _localRevision! > 0) {
          final vaultBlob = await getLocalVault();
          final response = await push(vaultBlob: vaultBlob, revision: 0);
          return SyncResult(
            action: SyncAction.pushed,
            newRevision: response.revision,
          );
        }
        return const SyncResult(
          action: SyncAction.skipped,
          reason: 'No local vault to push',
        );
      }

      // Compare revisions
      if (_localRevision == null || _localRevision == 0) {
        // No local vault - pull from server
        final response = await pull();
        await loadServerVault(response.vaultBlob, response.revision);
        _localRevision = response.revision;
        return SyncResult(
          action: SyncAction.pulled,
          newRevision: response.revision,
        );
      }

      if (serverStatus.revision > _localRevision!) {
        // Server has newer version - pull
        final response = await pull();
        await loadServerVault(response.vaultBlob, response.revision);
        _localRevision = response.revision;
        return SyncResult(
          action: SyncAction.pulled,
          newRevision: response.revision,
        );
      }

      if (serverStatus.revision == _localRevision) {
        // In sync
        _updateStatus(_status.copyWith(
          state: SyncState.synced,
          lastSyncAt: DateTime.now(),
        ));
        return const SyncResult(action: SyncAction.upToDate);
      }

      // Local is newer - push
      final vaultBlob = await getLocalVault();
      final response = await push(
        vaultBlob: vaultBlob,
        revision: serverStatus.revision,
      );
      return SyncResult(
        action: SyncAction.pushed,
        newRevision: response.revision,
      );
    } on SyncException catch (e) {
      if (e.isConflict) {
        return const SyncResult(
          action: SyncAction.conflict,
          reason: 'Server has conflicting changes',
        );
      }
      return SyncResult(
        action: SyncAction.error,
        reason: e.message,
      );
    }
  }

  /// Start automatic sync at configured interval.
  void startAutoSync({
    required Duration interval,
    required VaultBlobCallback getLocalVault,
    required VaultLoadCallback loadServerVault,
  }) {
    _stopAutoSync();
    _autoSyncTimer = Timer.periodic(interval, (_) async {
      if (_auth.isAuthenticated && _status.state != SyncState.syncing) {
        await sync(
          getLocalVault: getLocalVault,
          loadServerVault: loadServerVault,
        );
      }
    });
  }

  void _stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  /// Get sync history.
  Future<List<Map<String, dynamic>>> getHistory() async {
    return _api.getVaultHistory();
  }

  /// Clear conflict state (after resolution).
  void clearConflict() {
    if (_status.state == SyncState.conflict) {
      _updateStatus(_status.copyWith(
        state: SyncState.idle,
        conflictInfo: null,
      ));
    }
  }

  /// Dispose resources.
  void dispose() {
    _stopAutoSync();
    _statusController.close();
  }
}

/// Action taken during sync.
enum SyncAction {
  /// Vault pulled from server
  pulled,

  /// Vault pushed to server
  pushed,

  /// Local and server are in sync
  upToDate,

  /// Conflict detected
  conflict,

  /// Sync was skipped
  skipped,

  /// Error occurred
  error,
}

/// Result of a sync operation.
@immutable
class SyncResult {
  const SyncResult({
    required this.action,
    this.newRevision,
    this.reason,
  });

  final SyncAction action;
  final int? newRevision;
  final String? reason;

  bool get isSuccess =>
      action == SyncAction.pulled ||
      action == SyncAction.pushed ||
      action == SyncAction.upToDate;

  bool get isConflict => action == SyncAction.conflict;
}
