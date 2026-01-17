import 'dart:async';

import 'package:core_sync/core_sync.dart';
import 'package:ssh_client_app/services/sync_manager.dart';

/// Test implementation of SyncManager for widget tests.
class TestSyncManager extends SyncManager {
  TestSyncManager() : super();

  final _statusController = StreamController<CombinedSyncStatus>.broadcast();

  @override
  Stream<CombinedSyncStatus> get statusStream => _statusController.stream;

  @override
  CombinedSyncStatus get status => CombinedSyncStatus.disconnected;

  @override
  bool get isConfigured => false;

  @override
  bool get isAuthenticated => false;

  @override
  String get serverUrl => '';

  @override
  void dispose() {
    _statusController.close();
  }
}
