part of '../core_sync.dart';

/// Configuration for the sync server connection.
@immutable
class SyncConfig {
  const SyncConfig({
    required this.serverUrl,
    this.connectTimeout = const Duration(seconds: 30),
    this.autoSync = false,
    this.syncInterval = const Duration(minutes: 5),
  });

  /// Base URL of the sync server (e.g., 'https://sync.vibedterm.com')
  final String serverUrl;

  /// Connection timeout for API requests
  final Duration connectTimeout;

  /// Whether to automatically sync in the background
  final bool autoSync;

  /// Interval between automatic sync attempts
  final Duration syncInterval;

  SyncConfig copyWith({
    String? serverUrl,
    Duration? connectTimeout,
    bool? autoSync,
    Duration? syncInterval,
  }) {
    return SyncConfig(
      serverUrl: serverUrl ?? this.serverUrl,
      connectTimeout: connectTimeout ?? this.connectTimeout,
      autoSync: autoSync ?? this.autoSync,
      syncInterval: syncInterval ?? this.syncInterval,
    );
  }
}

/// Current state of the sync service.
enum SyncState {
  /// Not connected to server
  disconnected,

  /// Connected and idle
  idle,

  /// Currently syncing
  syncing,

  /// Sync completed successfully
  synced,

  /// Conflict detected - user action required
  conflict,

  /// Error occurred
  error,
}

/// Detailed sync status information.
@immutable
class SyncStatus {
  const SyncStatus({
    required this.state,
    this.lastSyncAt,
    this.localRevision,
    this.serverRevision,
    this.errorMessage,
    this.conflictInfo,
  });

  final SyncState state;
  final DateTime? lastSyncAt;
  final int? localRevision;
  final int? serverRevision;
  final String? errorMessage;
  final SyncConflictInfo? conflictInfo;

  SyncStatus copyWith({
    SyncState? state,
    DateTime? lastSyncAt,
    int? localRevision,
    int? serverRevision,
    String? errorMessage,
    SyncConflictInfo? conflictInfo,
  }) {
    return SyncStatus(
      state: state ?? this.state,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      localRevision: localRevision ?? this.localRevision,
      serverRevision: serverRevision ?? this.serverRevision,
      errorMessage: errorMessage,
      conflictInfo: conflictInfo,
    );
  }

  static const disconnected = SyncStatus(state: SyncState.disconnected);
}

/// Information about a sync conflict.
@immutable
class SyncConflictInfo {
  const SyncConflictInfo({
    required this.localRevision,
    required this.serverRevision,
    required this.serverDeviceId,
    required this.serverUpdatedAt,
  });

  final int localRevision;
  final int serverRevision;
  final String serverDeviceId;
  final DateTime serverUpdatedAt;
}
