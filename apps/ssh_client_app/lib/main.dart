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
          // Rotated VibedTerm branding
          const SizedBox(height: 12),
          SizedBox(
            height: 100,
            child: RotatedBox(
              quarterTurns: 3,
              child: Text(
                'VibedTerm',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  color: colorScheme.primary,
                ),
              ),
            ),
          ),
          const Spacer(),
          // Navigation icons
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
          // Settings icon at bottom
          Tooltip(
            message: 'Settings',
            preferBelow: false,
            child: InkWell(
              onTap: () {
                // Open settings - switch to vault screen which has settings
                _setIndex(0);
              },
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
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _handleConnectHost(VaultHost host, VaultIdentity? identity) {
    _vaultService.setPendingConnectHost(host, identity: identity);
    _setIndex(2);
  }
}

class _PageConfig {
  const _PageConfig(this.label, this.icon);

  final String label;
  final IconData icon;
}
