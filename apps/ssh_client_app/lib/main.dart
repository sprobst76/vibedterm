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
          appBar: AppBar(
            title: const Text('VibedTerm'),
            actions: const [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.sync),
              ),
            ],
          ),
          body: isWide
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _index,
                      onDestinationSelected: _setIndex,
                      labelType: NavigationRailLabelType.all,
                      destinations: _pages
                          .map(
                            (page) => NavigationRailDestination(
                              icon: Icon(page.icon),
                              label: Text(page.label),
                            ),
                          )
                          .toList(),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: _buildPageStack()),
                  ],
                )
              : _buildPageStack(),
          bottomNavigationBar: isWide
              ? null
              : NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: _setIndex,
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
