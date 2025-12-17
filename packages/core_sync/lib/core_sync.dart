library core_sync;

import 'package:meta/meta.dart';

/// Status of a vault sync cycle.
enum SyncState { idle, syncing, error }

/// Basic sync configuration. Will grow to support providers and polling intervals.
@immutable
class SyncConfig {
  const SyncConfig({
    required this.vaultPath,
    this.autoSync = false,
    this.pollInterval = const Duration(seconds: 30),
  });

  final String vaultPath;
  final bool autoSync;
  final Duration pollInterval;
}

/// File-based sync placeholder. Intended to be wired to file watchers on desktop
/// and polling on Android.
class FileSyncStrategy {
  FileSyncStrategy(this.config);

  final SyncConfig config;
  SyncState _state = SyncState.idle;

  SyncState get state => _state;

  Future<void> sync() async {
    _state = SyncState.syncing;
    // Placeholder for sync logic (compare lastModified, reload prompt, etc.).
    await Future<void>.delayed(const Duration(milliseconds: 10));
    _state = SyncState.idle;
  }

  Stream<void> watch() => const Stream.empty();
}
