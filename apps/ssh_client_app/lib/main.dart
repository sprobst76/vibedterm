import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:core_sync/core_sync.dart';
import 'package:core_vault/core_vault.dart';
import 'package:flutter/material.dart';
import 'package:ui_terminal/ui_terminal.dart';

import 'screens/screens.dart';
import 'services/sync_manager.dart';
import 'services/vault_service.dart';

part 'home_shell.dart';
part 'settings_dialog.dart';

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
  final _syncManager = SyncManager();
  Timer? _syncDebounce;

  @override
  void initState() {
    super.initState();
    _vaultService.init();
    _syncManager.init();

    // Auto-sync: push to server after vault changes (debounced)
    _vaultService.onVaultSaved = _onVaultSaved;

    // Auto-reload: refresh in-memory vault after server pull
    _syncManager.onVaultPulled = () => _vaultService.reloadFromDisk();
  }

  void _onVaultSaved() {
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(seconds: 2), () {
      final path = _vaultService.currentPath;
      if (path != null && _syncManager.isAuthenticated) {
        _syncManager.syncVault(vaultFilePath: path);
      }
    });
  }

  @override
  void dispose() {
    _syncDebounce?.cancel();
    _syncManager.dispose();
    super.dispose();
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
          home: HomeShell(service: _vaultService, syncManager: _syncManager),
        );
      },
    );
  }
}
