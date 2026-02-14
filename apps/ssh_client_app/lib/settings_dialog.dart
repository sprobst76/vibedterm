part of 'main.dart';

// -----------------------------------------------------------------------------
// Settings Dialog
// -----------------------------------------------------------------------------

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({
    required this.initialSettings,
    required this.syncManager,
    required this.vaultPath,
    required this.onSave,
  });

  final VaultSettings initialSettings;
  final SyncManager syncManager;
  final String? vaultPath;
  final Future<void> Function(VaultSettings) onSave;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Terminal settings
  late String _terminalTheme;
  late double _terminalFontSize;
  late String? _terminalFontFamily;
  late double _terminalOpacity;
  late String _terminalCursorStyle;

  // SSH settings
  late int _sshKeepaliveInterval;
  late int _sshConnectionTimeout;
  late int _sshDefaultPort;
  late bool _sshAutoReconnect;

  // Sync settings
  final _serverUrlController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _totpController = TextEditingController();
  bool _isRegistering = false;
  bool _isSyncBusy = false;
  String? _syncError;
  CombinedSyncStatus? _syncStatus;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    final s = widget.initialSettings;
    _terminalTheme = s.terminalTheme;
    _terminalFontSize = s.terminalFontSize;
    _terminalFontFamily =
        s.terminalFontFamily == 'monospace' ? null : s.terminalFontFamily;
    _terminalOpacity = s.terminalOpacity;
    _terminalCursorStyle = s.terminalCursorStyle;

    _sshKeepaliveInterval = s.sshKeepaliveInterval;
    _sshConnectionTimeout = s.sshConnectionTimeout;
    _sshDefaultPort = s.sshDefaultPort;
    _sshAutoReconnect = s.sshAutoReconnect;

    // Sync settings
    _serverUrlController.text = widget.syncManager.serverUrl;
    _syncStatus = widget.syncManager.status;
    widget.syncManager.statusStream.listen((status) {
      if (mounted) {
        setState(() => _syncStatus = status);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _serverUrlController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _totpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 500;

    // Responsive sizing
    final dialogWidth = isSmallScreen ? screenSize.width * 0.95 : 450.0;
    final dialogHeight = isSmallScreen ? screenSize.height * 0.8 : 480.0;

    return AlertDialog(
      title: const Text('Settings'),
      contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
      insetPadding: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 8 : 40,
        vertical: isSmallScreen ? 24 : 24,
      ),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              // Use icons only on small screens
              tabs: isSmallScreen
                  ? const [
                      Tab(icon: Icon(Icons.palette_outlined)),
                      Tab(icon: Icon(Icons.terminal)),
                      Tab(icon: Icon(Icons.cloud_outlined)),
                    ]
                  : const [
                      Tab(text: 'Appearance', icon: Icon(Icons.palette_outlined)),
                      Tab(text: 'SSH', icon: Icon(Icons.terminal)),
                      Tab(text: 'Sync', icon: Icon(Icons.cloud_outlined)),
                    ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildAppearanceTab(),
                  _buildSshTab(),
                  _buildSyncTab(),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saveSettings,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _buildAppearanceTab() {
    final themeNames = TerminalThemePresets.themeNames;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Theme selector
          Text('Color Theme', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _terminalTheme,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: themeNames
                .map((name) => DropdownMenuItem(
                      value: name,
                      child: Text(_formatThemeName(name)),
                    ))
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _terminalTheme = value);
            },
          ),
          const SizedBox(height: 16),

          // Font size slider
          Text('Font Size: ${_terminalFontSize.toInt()}',
              style: Theme.of(context).textTheme.titleSmall),
          Slider(
            value: _terminalFontSize,
            min: 10,
            max: 24,
            divisions: 14,
            label: '${_terminalFontSize.toInt()}',
            onChanged: (value) => setState(() => _terminalFontSize = value),
          ),
          const SizedBox(height: 8),

          // Font family
          Text('Font Family', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: _terminalFontFamily ?? '',
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'monospace (default)',
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onChanged: (value) {
              _terminalFontFamily = value.isEmpty ? null : value;
            },
          ),
          const SizedBox(height: 16),

          // Opacity slider
          Text('Background Opacity: ${(_terminalOpacity * 100).toInt()}%',
              style: Theme.of(context).textTheme.titleSmall),
          Slider(
            value: _terminalOpacity,
            min: 0.5,
            max: 1.0,
            divisions: 10,
            label: '${(_terminalOpacity * 100).toInt()}%',
            onChanged: (value) => setState(() => _terminalOpacity = value),
          ),
          const SizedBox(height: 8),

          // Cursor style
          Text('Cursor Style', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'block', label: Text('Block')),
              ButtonSegment(value: 'underline', label: Text('Underline')),
              ButtonSegment(value: 'bar', label: Text('Bar')),
            ],
            selected: {_terminalCursorStyle},
            onSelectionChanged: (selection) {
              setState(() => _terminalCursorStyle = selection.first);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSshTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Keepalive interval
          Text('Keepalive Interval: ${_sshKeepaliveInterval}s',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Send keepalive packets to prevent disconnection (0 = disabled)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Slider(
            value: _sshKeepaliveInterval.toDouble(),
            min: 0,
            max: 120,
            divisions: 24,
            label: '${_sshKeepaliveInterval}s',
            onChanged: (value) =>
                setState(() => _sshKeepaliveInterval = value.toInt()),
          ),
          const SizedBox(height: 16),

          // Connection timeout
          Text('Connection Timeout: ${_sshConnectionTimeout}s',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Maximum time to wait for connection',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Slider(
            value: _sshConnectionTimeout.toDouble(),
            min: 5,
            max: 120,
            divisions: 23,
            label: '${_sshConnectionTimeout}s',
            onChanged: (value) =>
                setState(() => _sshConnectionTimeout = value.toInt()),
          ),
          const SizedBox(height: 16),

          // Default port
          Text('Default Port', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: _sshDefaultPort.toString(),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            keyboardType: TextInputType.number,
            onChanged: (value) {
              final port = int.tryParse(value);
              if (port != null && port > 0 && port <= 65535) {
                _sshDefaultPort = port;
              }
            },
          ),
          const SizedBox(height: 16),

          // Auto-reconnect
          SwitchListTile(
            title: const Text('Auto-reconnect'),
            subtitle: const Text('Automatically reconnect on connection loss'),
            value: _sshAutoReconnect,
            contentPadding: EdgeInsets.zero,
            onChanged: (value) => setState(() => _sshAutoReconnect = value),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncTab() {
    final status = _syncStatus;
    final isConfigured = widget.syncManager.isConfigured;
    final isAuthenticated = status?.isAuthenticated ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Server URL
          Text('Sync Server', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _serverUrlController,
                  enabled: !isAuthenticated,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'https://sync.example.com',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (!isAuthenticated)
                FilledButton.tonal(
                  onPressed: _isSyncBusy ? null : _configureServer,
                  child: const Text('Connect'),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Show error if any
          if (_syncError != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline,
                      color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _syncError!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _syncError = null),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Show different UI based on auth state
          if (!isConfigured)
            _buildNotConfiguredView()
          else if (status?.authState == AuthState.totpRequired)
            _buildTotpView()
          else if (status?.authState == AuthState.pendingApproval)
            _buildPendingApprovalView()
          else if (isAuthenticated)
            _buildAuthenticatedView(status!)
          else
            _buildLoginView(),
        ],
      ),
    );
  }

  Widget _buildNotConfiguredView() {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 32),
          Icon(Icons.cloud_off,
              size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            'Cloud sync not configured',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Enter a sync server URL above to enable vault synchronization',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildLoginView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Toggle between login and register
        Row(
          children: [
            ChoiceChip(
              label: const Text('Login'),
              selected: !_isRegistering,
              onSelected: (selected) {
                if (selected) setState(() => _isRegistering = false);
              },
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Register'),
              selected: _isRegistering,
              onSelected: (selected) {
                if (selected) setState(() => _isRegistering = true);
              },
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Email field
        Text('Email', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        TextFormField(
          controller: _emailController,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'you@example.com',
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
        ),
        const SizedBox(height: 12),

        // Password field
        Text('Password', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        TextFormField(
          controller: _passwordController,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          obscureText: true,
          onFieldSubmitted: (_) => _isRegistering ? _register() : _login(),
        ),
        const SizedBox(height: 16),

        // Login/Register button
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _isSyncBusy
                ? null
                : (_isRegistering ? _register : _login),
            child: _isSyncBusy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isRegistering ? 'Register' : 'Login'),
          ),
        ),
      ],
    );
  }

  Widget _buildTotpView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.security, size: 48),
        const SizedBox(height: 16),
        Text(
          'Two-Factor Authentication',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Enter the 6-digit code from your authenticator app',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),

        TextFormField(
          controller: _totpController,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '000000',
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          keyboardType: TextInputType.number,
          maxLength: 6,
          autofocus: true,
          onFieldSubmitted: (_) => _verifyTotp(),
        ),
        const SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: _isSyncBusy ? null : _verifyTotp,
                child: _isSyncBusy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Verify'),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () async {
                await widget.syncManager.disconnect();
                setState(() {});
              },
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPendingApprovalView() {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 24),
          // Animated hourglass
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(seconds: 2),
            builder: (context, value, child) {
              return Transform.rotate(
                angle: value * 3.14159 * 2,
                child: child,
              );
            },
            onEnd: () {
              // Restart animation
              setState(() {});
            },
            child: const Icon(
              Icons.hourglass_empty,
              size: 56,
              color: Colors.orange,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Account Pending Approval',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Your account is waiting for administrator approval. '
              'You will be notified once an admin has reviewed your registration.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          // Check Status button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isSyncBusy ? null : _checkApprovalStatus,
              icon: _isSyncBusy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: Text(_isSyncBusy ? 'Checking...' : 'Check Status'),
            ),
          ),
          const SizedBox(height: 12),
          // Use different account button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _isSyncBusy
                  ? null
                  : () async {
                      await widget.syncManager.disconnect();
                      setState(() {});
                    },
              child: const Text('Use Different Account'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _checkApprovalStatus() async {
    setState(() {
      _isSyncBusy = true;
      _syncError = null;
    });

    try {
      await widget.syncManager.refreshAuthStatus();
      // Check if we're now authenticated
      final status = widget.syncManager.status;
      if (status.isAuthenticated) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Your account has been approved!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else if (status.authState == AuthState.pendingApproval) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Still waiting for admin approval'),
            ),
          );
        }
      }
    } on SyncException catch (e) {
      setState(() => _syncError = e.message);
    } catch (e) {
      setState(() => _syncError = 'Failed to check status: $e');
    } finally {
      if (mounted) setState(() => _isSyncBusy = false);
    }
  }

  Widget _buildAuthenticatedView(CombinedSyncStatus status) {
    final lastSync = status.lastSyncAt;
    final syncStateText = _getSyncStateText(status.syncState);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // User info
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Icon(Icons.person,
                color: Theme.of(context).colorScheme.onPrimaryContainer),
          ),
          title: Text(status.user?.email ?? 'Logged in'),
          subtitle: Text(syncStateText),
          trailing: IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _isSyncBusy ? null : _logout,
          ),
        ),
        const Divider(),
        const SizedBox(height: 8),

        // Sync status
        Row(
          children: [
            Icon(
              _getSyncStateIcon(status.syncState),
              size: 20,
              color: _getSyncStateColor(status.syncState),
            ),
            const SizedBox(width: 8),
            Text(syncStateText),
            const Spacer(),
            if (lastSync != null)
              Text(
                'Last sync: ${_formatTime(lastSync)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        const SizedBox(height: 16),

        // Sync button
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isSyncBusy ? null : _syncNow,
            icon: _isSyncBusy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            label: Text(_isSyncBusy ? 'Syncing...' : 'Sync Now'),
          ),
        ),
        const SizedBox(height: 8),

        // Conflict resolution (if in conflict state)
        if (status.hasConflict) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning,
                        color:
                            Theme.of(context).colorScheme.onTertiaryContainer),
                    const SizedBox(width: 8),
                    Text(
                      'Sync Conflict',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color:
                            Theme.of(context).colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Your local vault and the server have conflicting changes.',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onTertiaryContainer),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSyncBusy ? null : _forceUpload,
                        child: const Text('Keep Local'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSyncBusy ? null : _forceDownload,
                        child: const Text('Use Server'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _getSyncStateText(SyncState state) {
    switch (state) {
      case SyncState.disconnected:
        return 'Disconnected';
      case SyncState.idle:
        return 'Ready to sync';
      case SyncState.syncing:
        return 'Syncing...';
      case SyncState.synced:
        return 'Synced';
      case SyncState.conflict:
        return 'Conflict detected';
      case SyncState.error:
        return 'Sync error';
    }
  }

  IconData _getSyncStateIcon(SyncState state) {
    switch (state) {
      case SyncState.disconnected:
        return Icons.cloud_off;
      case SyncState.idle:
        return Icons.cloud_queue;
      case SyncState.syncing:
        return Icons.sync;
      case SyncState.synced:
        return Icons.cloud_done;
      case SyncState.conflict:
        return Icons.warning;
      case SyncState.error:
        return Icons.error;
    }
  }

  Color _getSyncStateColor(SyncState state) {
    final colorScheme = Theme.of(context).colorScheme;
    switch (state) {
      case SyncState.disconnected:
        return colorScheme.outline;
      case SyncState.idle:
        return colorScheme.primary;
      case SyncState.syncing:
        return colorScheme.primary;
      case SyncState.synced:
        return Colors.green;
      case SyncState.conflict:
        return colorScheme.tertiary;
      case SyncState.error:
        return colorScheme.error;
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Future<void> _configureServer() async {
    final url = _serverUrlController.text.trim();
    if (url.isEmpty) {
      setState(() => _syncError = 'Please enter a server URL');
      return;
    }

    setState(() {
      _isSyncBusy = true;
      _syncError = null;
    });

    try {
      await widget.syncManager.configure(url);
    } on SyncException catch (e) {
      setState(() => _syncError = e.message);
    } catch (e) {
      setState(() => _syncError = 'Failed to connect: $e');
    } finally {
      if (mounted) setState(() => _isSyncBusy = false);
    }
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _syncError = 'Please enter email and password');
      return;
    }

    setState(() {
      _isSyncBusy = true;
      _syncError = null;
    });

    try {
      await widget.syncManager.login(
        email: email,
        password: password,
        deviceName: _getDeviceName(),
        deviceType: _getDeviceType(),
      );
      _emailController.clear();
      _passwordController.clear();
    } on SyncException catch (e) {
      setState(() => _syncError = e.message);
    } catch (e) {
      setState(() => _syncError = 'Login failed: $e');
    } finally {
      if (mounted) setState(() => _isSyncBusy = false);
    }
  }

  Future<void> _register() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _syncError = 'Please enter email and password');
      return;
    }

    if (password.length < 8) {
      setState(() => _syncError = 'Password must be at least 8 characters');
      return;
    }

    setState(() {
      _isSyncBusy = true;
      _syncError = null;
    });

    try {
      await widget.syncManager.register(email: email, password: password);
      _emailController.clear();
      _passwordController.clear();
    } on SyncException catch (e) {
      setState(() => _syncError = e.message);
    } catch (e) {
      setState(() => _syncError = 'Registration failed: $e');
    } finally {
      if (mounted) setState(() => _isSyncBusy = false);
    }
  }

  Future<void> _verifyTotp() async {
    final code = _totpController.text.trim();
    if (code.length != 6) {
      setState(() => _syncError = 'Please enter a 6-digit code');
      return;
    }

    setState(() {
      _isSyncBusy = true;
      _syncError = null;
    });

    try {
      await widget.syncManager.verifyTOTP(code);
      _totpController.clear();
    } on SyncException catch (e) {
      setState(() => _syncError = e.message);
    } catch (e) {
      setState(() => _syncError = 'Verification failed: $e');
    } finally {
      if (mounted) setState(() => _isSyncBusy = false);
    }
  }

  Future<void> _logout() async {
    setState(() {
      _isSyncBusy = true;
      _syncError = null;
    });

    try {
      await widget.syncManager.logout();
    } catch (e) {
      setState(() => _syncError = 'Logout failed: $e');
    } finally {
      if (mounted) setState(() => _isSyncBusy = false);
    }
  }

  Future<void> _syncNow() async {
    if (widget.vaultPath == null) {
      setState(() => _syncError = 'No vault path available');
      return;
    }

    setState(() {
      _isSyncBusy = true;
      _syncError = null;
    });

    try {
      final result =
          await widget.syncManager.syncVault(vaultFilePath: widget.vaultPath!);
      if (!result.isSuccess && result.reason != null) {
        setState(() => _syncError = result.reason);
      }
    } on SyncException catch (e) {
      setState(() => _syncError = e.message);
    } catch (e) {
      setState(() => _syncError = 'Sync failed: $e');
    } finally {
      if (mounted) setState(() => _isSyncBusy = false);
    }
  }

  Future<void> _forceUpload() async {
    if (widget.vaultPath == null) return;

    setState(() {
      _isSyncBusy = true;
      _syncError = null;
    });

    try {
      await widget.syncManager.forceUpload(vaultFilePath: widget.vaultPath!);
      widget.syncManager.clearConflict();
    } on SyncException catch (e) {
      setState(() => _syncError = e.message);
    } catch (e) {
      setState(() => _syncError = 'Upload failed: $e');
    } finally {
      if (mounted) setState(() => _isSyncBusy = false);
    }
  }

  Future<void> _forceDownload() async {
    if (widget.vaultPath == null) return;

    setState(() {
      _isSyncBusy = true;
      _syncError = null;
    });

    try {
      await widget.syncManager.forceDownload(vaultFilePath: widget.vaultPath!);
      widget.syncManager.clearConflict();
    } on SyncException catch (e) {
      setState(() => _syncError = e.message);
    } catch (e) {
      setState(() => _syncError = 'Download failed: $e');
    } finally {
      if (mounted) setState(() => _isSyncBusy = false);
    }
  }

  String _getDeviceName() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'VibedTerm Device';
    }
  }

  String _getDeviceType() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isAndroid) return 'android';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }

  String _formatThemeName(String name) {
    return name
        .split('-')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  Future<void> _saveSettings() async {
    final newSettings = widget.initialSettings.copyWith(
      terminalTheme: _terminalTheme,
      terminalFontSize: _terminalFontSize,
      terminalFontFamily: _terminalFontFamily ?? 'monospace',
      terminalOpacity: _terminalOpacity,
      terminalCursorStyle: _terminalCursorStyle,
      sshKeepaliveInterval: _sshKeepaliveInterval,
      sshConnectionTimeout: _sshConnectionTimeout,
      sshDefaultPort: _sshDefaultPort,
      sshAutoReconnect: _sshAutoReconnect,
    );
    await widget.onSave(newSettings);
    if (mounted) {
      Navigator.pop(context);
    }
  }
}
