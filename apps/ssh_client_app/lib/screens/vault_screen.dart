import 'package:core_vault/core_vault.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../services/vault_service.dart';

class VaultScreen extends StatelessWidget {
  const VaultScreen({super.key, required this.service});

  final VaultService service;

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
                    FilledButton.icon(
                      onPressed: service.createDemoVault,
                      icon: const Icon(Icons.add),
                      label: const Text('Create demo vault'),
                    ),
                    FilledButton.icon(
                      onPressed: state.filePath == null
                          ? null
                          : () => service.unlockDemoVault(state.filePath!),
                      icon: const Icon(Icons.lock_open),
                      label: const Text('Unlock demo vault'),
                    ),
                    FilledButton.icon(
                      onPressed: () => _pickAndUnlock(context),
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Pick vault file'),
                    ),
                    FilledButton.icon(
                      onPressed: () => _pickAndCreate(context),
                      icon: const Icon(Icons.note_add),
                      label: const Text('Create vault at path'),
                    ),
                    FilledButton.icon(
                      onPressed: () => _quickCreateVault(context),
                      icon: const Icon(Icons.flash_on),
                      label: const Text('Quick create (app storage)'),
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

  Future<void> _pickAndCreate(BuildContext context) async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Choose vault path',
      fileName: 'vibedterm.vlt',
      type: FileType.any,
    );
    var path = result;
    if (path == null) {
      final docs = await getApplicationDocumentsDirectory();
      path = '${docs.path}/vibedterm.vlt';
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No path chosen, creating at $path')),
        );
      }
    }
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
