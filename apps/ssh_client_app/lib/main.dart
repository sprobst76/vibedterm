import 'package:core_vault/core_vault.dart';
import 'package:flutter/material.dart';

import 'screens/screens.dart';
import 'services/vault_service.dart';

void main() {
  runApp(const VibedTermApp());
}

class VibedTermApp extends StatelessWidget {
  const VibedTermApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VibedTerm',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final _vaultService = VaultService();
  String? _lastMessage;

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
    _vaultService.init();
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
