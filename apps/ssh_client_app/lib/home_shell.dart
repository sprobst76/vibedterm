part of 'main.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.service, required this.syncManager});

  final VaultService service;
  final SyncManager syncManager;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  String? _lastMessage;

  VaultService get _vaultService => widget.service;

  static const _pages = [
    _PageConfig('Vault', Icons.lock_outline),
    _PageConfig('Hosts', Icons.dns_outlined),
    _PageConfig('Terminal', Icons.terminal),
  ];

  void _setIndex(int value) {
    setState(() {
      _index = value;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadDefaultConfig();
  }

  void _loadDefaultConfig() async {
    try {
      final file = File(
          '${Directory.current.path.replaceAll('\\', '/')}/apps/ssh_client_app/config.json');
      if (!await file.exists()) return;
      final raw = await file.readAsString();
      final map = json.decode(raw) as Map<String, dynamic>;
      final host = map['host'] as String?;
      if (host == null || host.isEmpty) return;
      final port = (map['port'] as num?)?.toInt() ?? 22;
      final username = map['username'] as String? ?? '';
      final keyfile = (map['privateKeyFile'] as String?) ?? '';

      // Build a VaultHost instance (not persisted) and request connection.
      final vh = VaultHost(
        id: 'cfg-default',
        label: '$username@$host',
        hostname: host,
        port: port,
        username: username,
      );

      VaultIdentity? identity;
      if (keyfile.isNotEmpty) {
        final kf = File(keyfile);
        if (await kf.exists()) {
          final pem = await kf.readAsString();
          identity = VaultIdentity(
            id: 'cfg-identity',
            name: 'default',
            type: 'ssh',
            privateKey: pem,
          );
        }
      }

      // Trigger a pending connect and switch to Terminal tab.
      _vaultService.setPendingConnectHost(vh, identity: identity);
      _setIndex(2);
    } catch (_) {
      // ignore failures silently
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 700;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ValueListenableBuilder<VaultState>(
      valueListenable: _vaultService.state,
      builder: (context, state, child) {
        if (state.message.isNotEmpty && state.message != _lastMessage) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
          });
          _lastMessage = state.message;
        }

        return Scaffold(
          body: Row(
            children: [
              // Custom vertical sidebar (only on wide screens)
              if (isWide)
                _buildSidebar(colorScheme),
              // Main content
              Expanded(child: _buildPageStack()),
            ],
          ),
          // Only show bottom nav on small screens
          bottomNavigationBar: isWide
              ? null
              : NavigationBar(
                  selectedIndex: _index < 3 ? _index : 0,
                  onDestinationSelected: (idx) {
                    if (idx == 3) {
                      _showSettingsDialog();
                    } else {
                      _setIndex(idx);
                    }
                  },
                  height: 60,
                  destinations: [
                    ..._pages.map(
                      (page) => NavigationDestination(
                        icon: Icon(page.icon),
                        label: page.label,
                      ),
                    ),
                    NavigationDestination(
                      icon: _buildMobileSyncIcon(colorScheme),
                      label: 'Settings',
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildPageStack() {
    return SafeArea(
      child: IndexedStack(
        index: _index,
        children: [
          VaultScreen(service: _vaultService, syncManager: widget.syncManager),
          HostsScreen(
            service: _vaultService,
            onConnectHost: _handleConnectHost,
          ),
          TerminalScreen(service: _vaultService),
        ],
      ),
    );
  }

  Widget _buildSidebar(ColorScheme colorScheme) {
    return Container(
      width: 56,
      decoration: BoxDecoration(
        color: Color.lerp(colorScheme.surface, Colors.black, 0.15),
        border: Border(
          right: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          // Navigation icons at top
          ..._pages.asMap().entries.map((entry) {
            final idx = entry.key;
            final page = entry.value;
            final isSelected = _index == idx;
            return Tooltip(
              message: page.label,
              preferBelow: false,
              waitDuration: const Duration(milliseconds: 500),
              child: InkWell(
                onTap: () => _setIndex(idx),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.primary.withValues(alpha: 0.15)
                        : Colors.transparent,
                    border: Border(
                      left: BorderSide(
                        color: isSelected
                            ? colorScheme.primary
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                  child: Icon(
                    page.icon,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurface.withValues(alpha: 0.6),
                    size: 24,
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          // Rotated VibedTerm branding above settings
          SizedBox(
            height: 120,
            child: RotatedBox(
              quarterTurns: 3,
              child: Text(
                'VibedTerm',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3,
                  color: colorScheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Sync status indicator
          _buildSyncIndicator(colorScheme),
          const SizedBox(height: 4),
          // Settings icon at bottom
          Tooltip(
            message: 'Settings',
            preferBelow: false,
            child: InkWell(
              onTap: _showSettingsDialog,
              child: SizedBox(
                width: 56,
                height: 48,
                child: Icon(
                  Icons.settings_outlined,
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                  size: 20,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildSyncIndicator(ColorScheme colorScheme) {
    return StreamBuilder<CombinedSyncStatus>(
      stream: widget.syncManager.statusStream,
      initialData: widget.syncManager.status,
      builder: (context, snapshot) {
        final status = snapshot.data ?? CombinedSyncStatus.disconnected;
        final syncState = status.syncState;
        final isConfigured = widget.syncManager.isConfigured;

        // Determine icon and color based on state
        IconData icon;
        Color color;
        String tooltip;

        if (!isConfigured) {
          icon = Icons.cloud_off_outlined;
          color = colorScheme.onSurface.withValues(alpha: 0.3);
          tooltip = 'Sync not configured';
        } else if (status.authState == AuthState.pendingApproval) {
          icon = Icons.hourglass_empty;
          color = Colors.orange;
          tooltip = 'Account pending admin approval';
        } else if (!status.isAuthenticated) {
          icon = Icons.cloud_off_outlined;
          color = colorScheme.onSurface.withValues(alpha: 0.5);
          tooltip = 'Not logged in';
        } else {
          switch (syncState) {
            case SyncState.disconnected:
              icon = Icons.cloud_off_outlined;
              color = colorScheme.onSurface.withValues(alpha: 0.5);
              tooltip = 'Disconnected';
            case SyncState.idle:
              icon = Icons.cloud_outlined;
              color = colorScheme.primary;
              tooltip = 'Ready to sync';
            case SyncState.syncing:
              icon = Icons.cloud_sync_outlined;
              color = colorScheme.primary;
              tooltip = 'Syncing...';
            case SyncState.synced:
              icon = Icons.cloud_done_outlined;
              color = Colors.green;
              tooltip = 'Synced';
            case SyncState.conflict:
              icon = Icons.cloud_outlined;
              color = Colors.orange;
              tooltip = 'Conflict - tap to resolve';
            case SyncState.error:
              icon = Icons.cloud_off_outlined;
              color = colorScheme.error;
              tooltip = status.errorMessage ?? 'Sync error';
          }
        }

        return Tooltip(
          message: tooltip,
          preferBelow: false,
          child: InkWell(
            onTap: _showSettingsDialog,
            child: SizedBox(
              width: 56,
              height: 40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(icon, color: color, size: 20),
                  // Show spinning indicator when syncing
                  if (syncState == SyncState.syncing)
                    Positioned(
                      right: 14,
                      top: 8,
                      child: SizedBox(
                        width: 8,
                        height: 8,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  // Show badge for pending approval
                  if (status.authState == AuthState.pendingApproval)
                    Positioned(
                      right: 14,
                      top: 8,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.orange,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  // Show badge for conflict or error
                  if (status.authState != AuthState.pendingApproval &&
                      (syncState == SyncState.conflict ||
                      syncState == SyncState.error))
                    Positioned(
                      right: 14,
                      top: 8,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: syncState == SyncState.conflict
                              ? Colors.orange
                              : colorScheme.error,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMobileSyncIcon(ColorScheme colorScheme) {
    return StreamBuilder<CombinedSyncStatus>(
      stream: widget.syncManager.statusStream,
      initialData: widget.syncManager.status,
      builder: (context, snapshot) {
        final status = snapshot.data ?? CombinedSyncStatus.disconnected;
        final isPending = status.authState == AuthState.pendingApproval;
        final hasIssue = status.syncState == SyncState.conflict ||
            status.syncState == SyncState.error;

        return Stack(
          children: [
            const Icon(Icons.settings),
            if (status.isAuthenticated && status.syncState == SyncState.syncing)
              Positioned(
                right: 0,
                top: 0,
                child: SizedBox(
                  width: 8,
                  height: 8,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            if (isPending)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.orange,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            if (!isPending && hasIssue)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: status.syncState == SyncState.conflict
                        ? Colors.orange
                        : colorScheme.error,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _handleConnectHost(VaultHost host, VaultIdentity? identity) {
    _vaultService.setPendingConnectHost(host, identity: identity);
    _setIndex(2);
  }

  void _showSettingsDialog() {
    final currentSettings = _vaultService.currentData?.settings;
    if (currentSettings == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unlock a vault first to access settings')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => _SettingsDialog(
        initialSettings: currentSettings,
        syncManager: widget.syncManager,
        vaultPath: _vaultService.currentPath,
        onSave: (settings) async {
          await _vaultService.updateSettings(settings);
          if (mounted) setState(() {});
        },
      ),
    );
  }
}

class _PageConfig {
  const _PageConfig(this.label, this.icon);

  final String label;
  final IconData icon;
}
