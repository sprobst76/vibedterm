import 'dart:async';

import 'package:core_vault/core_vault.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../services/sync_manager.dart';
import '../services/vault_service.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key, required this.service, required this.syncManager});

  final VaultServiceInterface service;
  final SyncManager syncManager;

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  VaultServiceInterface get service => widget.service;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ValueListenableBuilder<VaultState>(
          valueListenable: service.state,
          builder: (context, state, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Status: ${state.status.name}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  state.message.isEmpty
                      ? 'Create or unlock a vault file.'
                      : state.message,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    // Sync from cloud button (prominently placed)
                    StreamBuilder<CombinedSyncStatus>(
                      stream: widget.syncManager.statusStream,
                      initialData: widget.syncManager.status,
                      builder: (context, snapshot) {
                        final status = snapshot.data ?? CombinedSyncStatus.disconnected;
                        final isConfigured = widget.syncManager.isConfigured;
                        final isAuthenticated = status.isAuthenticated;

                        return FilledButton.icon(
                          onPressed: isConfigured && isAuthenticated
                              ? () => _syncFromCloud(context)
                              : () => _showSyncSetup(context),
                          icon: Icon(isAuthenticated ? Icons.cloud_download : Icons.cloud_outlined),
                          label: Text(isAuthenticated ? 'Sync from Cloud' : 'Setup Cloud Sync'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.tertiary,
                            foregroundColor: Theme.of(context).colorScheme.onTertiary,
                          ),
                        );
                      },
                    ),
                    FilledButton.icon(
                      onPressed: () => _pickAndUnlock(context),
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Open vault file'),
                    ),
                    FilledButton.icon(
                      onPressed: () => _quickCreateVault(context),
                      icon: const Icon(Icons.flash_on),
                      label: const Text('Create new vault'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (service.currentData != null) ...[
                  Text(
                    'Hosts: ${service.currentData!.hosts.length} | Identities: ${service.currentData!.identities.length}',
                  ),
                  if (service.lastPath != null)
                    Text('Last vault: ${service.lastPath}'),
                ],
                if (state.isBusy) ...[
                  const SizedBox(height: 12),
                  const CircularProgressIndicator(),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _pickAndUnlock(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select vault file',
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null) return;
    final passwordResult =
        await _promptForPassword(context, title: 'Unlock vault');
    if (passwordResult == null || passwordResult.password.isEmpty) return;
    await service.unlockVault(
      path: path,
      password: passwordResult.password,
      rememberPasswordForSession: passwordResult.rememberSession,
      rememberPasswordSecurely: passwordResult.rememberSecure,
    );
  }

  Future<void> _quickCreateVault(BuildContext context) async {
    final docs = await getApplicationDocumentsDirectory();
    final path = '${docs.path}/vibedterm_quick.vlt';
    final passwordResult =
        await _promptForPassword(context, title: 'Set vault password');
    if (passwordResult == null || passwordResult.password.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final payload = VaultPayload(
      data: VaultData(
        version: 1,
        revision: 1,
        deviceId: 'device-${DateTime.now().millisecondsSinceEpoch}',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await service.createVault(
      path: path,
      password: passwordResult.password,
      payload: payload,
      rememberPasswordForSession: passwordResult.rememberSession,
      rememberPasswordSecurely: passwordResult.rememberSecure,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Vault created at $path')),
      );
    }
  }

  Future<PasswordPromptResult?> _promptForPassword(
    BuildContext context, {
    required String title,
  }) async {
    final controller = TextEditingController();
    var rememberSession = false;
    var rememberSecure = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(labelText: 'Password'),
                    obscureText: true,
                    autofocus: true,
                    onSubmitted: (_) => Navigator.of(context).pop(true),
                  ),
                  Row(
                    children: [
                      Checkbox(
                        value: rememberSession,
                        onChanged: (value) {
                          setState(() {
                            rememberSession = value ?? false;
                          });
                        },
                      ),
                      const Expanded(child: Text('Remember for this session')),
                    ],
                  ),
                  Row(
                    children: [
                      Checkbox(
                        value: rememberSecure,
                        onChanged: (value) {
                          setState(() {
                            rememberSecure = value ?? false;
                          });
                        },
                      ),
                      const Expanded(child: Text('Remember securely (device)')),
                    ],
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
    if (ok != true) {
      return null;
    }
    // Note: Don't dispose controller here - dialog animation might still use it
    return PasswordPromptResult(
      controller.text,
      rememberSession: rememberSession,
      rememberSecure: rememberSecure,
    );
  }

  Future<void> _syncFromCloud(BuildContext context) async {
    // First ask for the vault password since we need to decrypt the downloaded vault
    final passwordResult = await _promptForPassword(
      context,
      title: 'Enter vault password',
    );
    if (passwordResult == null || passwordResult.password.isEmpty) return;

    // Get app documents directory for vault storage
    final docs = await getApplicationDocumentsDirectory();
    final vaultPath = '${docs.path}/vibedterm_synced.vlt';

    // Show progress dialog
    if (!context.mounted) return;
    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Downloading vault from cloud...'),
          ],
        ),
      ),
    ));

    try {
      // Download vault from server
      await widget.syncManager.forceDownload(vaultFilePath: vaultPath);

      // Close progress dialog
      if (context.mounted) Navigator.of(context).pop();

      // Unlock the downloaded vault
      await service.unlockVault(
        path: vaultPath,
        password: passwordResult.password,
        rememberPasswordForSession: passwordResult.rememberSession,
        rememberPasswordSecurely: passwordResult.rememberSecure,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vault synced from cloud')),
        );
      }
    } catch (e) {
      // Close progress dialog
      if (context.mounted) Navigator.of(context).pop();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e')),
        );
      }
    }
  }

  void _showSyncSetup(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _SyncSetupDialog(syncManager: widget.syncManager),
    );
  }
}

/// Dialog for quick sync server setup and login
class _SyncSetupDialog extends StatefulWidget {
  const _SyncSetupDialog({required this.syncManager});

  final SyncManager syncManager;

  @override
  State<_SyncSetupDialog> createState() => _SyncSetupDialogState();
}

class _SyncSetupDialogState extends State<_SyncSetupDialog> {
  final _serverController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isBusy = false;
  String? _error;
  bool _serverConfigured = false;

  @override
  void initState() {
    super.initState();
    _serverController.text = widget.syncManager.serverUrl;
    _serverConfigured = widget.syncManager.isConfigured;
  }

  @override
  void dispose() {
    _serverController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cloud Sync Setup'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error, color: Theme.of(context).colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Server URL
            Text('Sync Server', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _serverController,
                    enabled: !_serverConfigured,
                    decoration: const InputDecoration(
                      hintText: 'https://sync.example.com',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
                if (!_serverConfigured) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.check),
                    onPressed: _isBusy ? null : _configureServer,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),

            if (_serverConfigured) ...[
              // Email
              Text('Email', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  hintText: 'you@example.com',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),

              // Password
              Text('Password', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                obscureText: true,
                onSubmitted: (_) => _login(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (_serverConfigured)
          FilledButton(
            onPressed: _isBusy ? null : _login,
            child: _isBusy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Login'),
          ),
      ],
    );
  }

  Future<void> _configureServer() async {
    final url = _serverController.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Please enter a server URL');
      return;
    }

    setState(() {
      _isBusy = true;
      _error = null;
    });

    try {
      await widget.syncManager.configure(url);
      setState(() => _serverConfigured = true);
    } catch (e) {
      setState(() => _error = 'Failed to connect: $e');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter email and password');
      return;
    }

    setState(() {
      _isBusy = true;
      _error = null;
    });

    try {
      await widget.syncManager.login(
        email: email,
        password: password,
        deviceName: 'VibedTerm Mobile',
        deviceType: 'android',
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = 'Login failed: $e');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }
}

class PasswordPromptResult {
  PasswordPromptResult(
    this.password, {
    required this.rememberSession,
    required this.rememberSecure,
  });
  final String password;
  final bool rememberSession;
  final bool rememberSecure;
}
