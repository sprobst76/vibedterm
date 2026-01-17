import 'dart:convert';
import 'dart:io';
import 'package:core_vault/core_vault.dart';
import 'package:flutter/material.dart';
import 'package:ui_terminal/ui_terminal.dart';

import 'screens/screens.dart';
import 'services/vault_service.dart';

void main() {
  runApp(const VibedTermApp());
}

class VibedTermApp extends StatefulWidget {
  const VibedTermApp({super.key});

  @override
  State<VibedTermApp> createState() => _VibedTermAppState();
}

class _VibedTermAppState extends State<VibedTermApp> {
  final _vaultService = VaultService();

  @override
  void initState() {
    super.initState();
    _vaultService.init();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VaultState>(
      valueListenable: _vaultService.state,
      builder: (context, state, _) {
        // Get terminal theme from settings
        final themeName = _vaultService.currentData?.settings.terminalTheme ?? 'default';
        final terminalTheme = TerminalThemePresets.getTheme(themeName);
        final appTheme = TerminalThemeConverter.toFlutterTheme(terminalTheme);

        return MaterialApp(
          title: 'VibedTerm',
          theme: appTheme,
          darkTheme: appTheme,
          themeMode: ThemeMode.light, // Always use our custom theme
          home: HomeShell(service: _vaultService),
        );
      },
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.service});

  final VaultService service;

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
      final password = (map['password'] as String?) ?? '';
      final keyfile = (map['privateKeyFile'] as String?) ?? '';

      // Build a VaultHost instance (not persisted) and request connection.
      final vh = VaultHost(
        id: 'cfg-default',
        label: '${username}@${host}',
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
                  selectedIndex: _index,
                  onDestinationSelected: _setIndex,
                  height: 60,
                  destinations: _pages
                      .map(
                        (page) => NavigationDestination(
                          icon: Icon(page.icon),
                          label: page.label,
                        ),
                      )
                      .toList(),
                ),
        );
      },
    );
  }

  Widget _buildPageStack() {
    return IndexedStack(
      index: _index,
      children: [
        VaultScreen(service: _vaultService),
        HostsScreen(
          service: _vaultService,
          onConnectHost: _handleConnectHost,
        ),
        TerminalScreen(service: _vaultService),
      ],
    );
  }

  Widget _buildSidebar(ColorScheme colorScheme) {
    return Container(
      width: 56,
      decoration: BoxDecoration(
        color: Color.lerp(colorScheme.surface, Colors.black, 0.15),
        border: Border(
          right: BorderSide(
            color: colorScheme.outline.withOpacity(0.2),
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
                        ? colorScheme.primary.withOpacity(0.15)
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
                        : colorScheme.onSurface.withOpacity(0.6),
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
                  color: colorScheme.onSurface.withOpacity(0.5),
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

// -----------------------------------------------------------------------------
// Settings Dialog
// -----------------------------------------------------------------------------

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({
    required this.initialSettings,
    required this.onSave,
  });

  final VaultSettings initialSettings;
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

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
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Settings'),
      contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
      content: SizedBox(
        width: 450,
        height: 420,
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Appearance', icon: Icon(Icons.palette_outlined)),
                Tab(text: 'SSH', icon: Icon(Icons.terminal)),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildAppearanceTab(),
                  _buildSshTab(),
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
            value: _terminalTheme,
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
