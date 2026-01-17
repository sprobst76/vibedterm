import 'dart:io';

import 'package:core_ssh/core_ssh.dart' show calculateKeyFingerprint;
import 'package:core_vault/core_vault.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/vault_service.dart';

class HostsScreen extends StatelessWidget {
  const HostsScreen({
    super.key,
    required this.service,
    required this.onConnectHost,
  });

  final VaultServiceInterface service;
  final void Function(VaultHost host, VaultIdentity? identity) onConnectHost;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VaultState>(
      valueListenable: service.state,
      builder: (context, state, _) {
        final data = service.currentData;
        if (state.status != VaultStatus.unlocked || data == null) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Unlock or create a vault to manage hosts and identities.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: () => _promptAddIdentity(context),
                  icon: const Icon(Icons.vpn_key),
                  label: const Text('Add identity'),
                ),
                if (!Platform.isAndroid && !Platform.isIOS)
                  OutlinedButton.icon(
                    onPressed: () => _promptImportFromSsh(context),
                    icon: const Icon(Icons.download),
                    label: const Text('Import from ~/.ssh'),
                  ),
                FilledButton.icon(
                  onPressed: () => _promptAddHost(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add host'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Identities (${data.identities.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ...data.identities.map(
              (id) {
                final fingerprint = calculateKeyFingerprint(
                  id.privateKey,
                  passphrase: id.passphrase,
                );
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.vpn_key),
                    title: Text(id.name),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(id.type),
                        if (fingerprint != null)
                          Text(
                            fingerprint,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                      ],
                    ),
                    isThreeLine: fingerprint != null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.copy),
                          tooltip: 'Copy fingerprint',
                          onPressed: fingerprint != null
                              ? () {
                                  Clipboard.setData(
                                      ClipboardData(text: fingerprint));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content:
                                            Text('Fingerprint copied to clipboard')),
                                  );
                                }
                              : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit),
                          tooltip: 'Edit identity',
                          onPressed: () =>
                              _promptAddIdentity(context, existing: id),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          tooltip: 'Delete identity',
                          onPressed: () => service.deleteIdentity(id.id),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Text(
              'Hosts (${data.hosts.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ...data.hosts.map(
              (host) => Card(
                child: ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: Text(host.label),
                  subtitle: Text(
                    '${host.hostname}:${host.port} • ${host.username}'
                    '${host.identityId != null ? ' • key: ${host.identityId}' : ''}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () =>
                            _promptAddHost(context, existing: host),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () => service.deleteHost(host.id),
                      ),
                      IconButton(
                        tooltip: 'Connect',
                        icon: const Icon(Icons.play_arrow),
                        onPressed: () => _connectHost(host),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _promptAddHost(BuildContext context,
      {VaultHost? existing}) async {
    final labelController = TextEditingController(text: existing?.label ?? '');
    final hostController =
        TextEditingController(text: existing?.hostname ?? '');
    final userController =
        TextEditingController(text: existing?.username ?? 'root');
    final portController =
        TextEditingController(text: (existing?.port ?? 22).toString());
    final tmuxSessionController =
        TextEditingController(text: existing?.tmuxSessionName ?? '');
    String? selectedIdentityId = existing?.identityId;
    bool tmuxEnabled = existing?.tmuxEnabled ?? false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(existing == null ? 'Add host' : 'Edit host'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: labelController,
                      decoration: const InputDecoration(labelText: 'Label'),
                      autofocus: true,
                    ),
                    TextField(
                      controller: hostController,
                      decoration: const InputDecoration(labelText: 'Hostname'),
                    ),
                    TextField(
                      controller: portController,
                      decoration: const InputDecoration(labelText: 'Port'),
                      keyboardType: TextInputType.number,
                    ),
                    TextField(
                      controller: userController,
                      decoration: const InputDecoration(labelText: 'Username'),
                    ),
                    if (service.currentData?.identities.isNotEmpty ??
                        false) ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String?>(
                        initialValue: selectedIdentityId,
                        decoration: const InputDecoration(labelText: 'Identity'),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('None'),
                          ),
                          ...service.currentData!.identities.map(
                            (id) => DropdownMenuItem<String?>(
                              value: id.id,
                              child: Text(id.name),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          selectedIdentityId = value;
                        },
                      ),
                    ],
                    const SizedBox(height: 16),
                    const Divider(),
                    CheckboxListTile(
                      title: const Text('Auto-attach tmux'),
                      subtitle: const Text('Start or attach to tmux session'),
                      value: tmuxEnabled,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (value) {
                        setDialogState(() => tmuxEnabled = value ?? false);
                      },
                    ),
                    if (tmuxEnabled)
                      TextField(
                        controller: tmuxSessionController,
                        decoration: const InputDecoration(
                          labelText: 'Session name (optional)',
                          hintText: 'Leave empty for default',
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != true) return;
    final port = int.tryParse(portController.text) ?? 22;
    final tmuxSession = tmuxSessionController.text.trim();
    if (existing == null) {
      await service.addHost(
        label: labelController.text.trim(),
        hostname: hostController.text.trim(),
        port: port,
        username: userController.text.trim(),
        identityId: selectedIdentityId,
        tmuxEnabled: tmuxEnabled,
        tmuxSessionName: tmuxSession.isEmpty ? null : tmuxSession,
      );
    } else {
      await service.updateHost(
        existing.copyWith(
          label: labelController.text.trim(),
          hostname: hostController.text.trim(),
          port: port,
          username: userController.text.trim(),
          identityId: selectedIdentityId,
          tmuxEnabled: tmuxEnabled,
          tmuxSessionName: tmuxSession.isEmpty ? null : tmuxSession,
        ),
      );
    }
  }

  Future<void> _promptAddIdentity(BuildContext context,
      {VaultIdentity? existing}) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final typeController =
        TextEditingController(text: existing?.type ?? 'ssh-ed25519');
    final keyController =
        TextEditingController(text: existing?.privateKey ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(existing == null ? 'Add identity' : 'Edit identity'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                autofocus: true,
              ),
              TextField(
                controller: typeController,
                decoration: const InputDecoration(labelText: 'Type'),
              ),
              TextField(
                controller: keyController,
                decoration: const InputDecoration(
                  labelText: 'Private key (PEM/OpenSSH)',
                ),
                maxLines: 4,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: () async {
                      try {
                        final result = await FilePicker.platform.pickFiles(
                          dialogTitle: 'Select private key file',
                          allowMultiple: false,
                        );
                        final path = result?.files.single.path;
                        if (path == null) return;
                        final file = File(path);
                        final content = await file.readAsString();
                        keyController.text = content;
                        if (ScaffoldMessenger.maybeOf(context) != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Loaded key from file')),
                          );
                        }
                      } catch (e) {
                        if (ScaffoldMessenger.maybeOf(context) != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to load key: $e')),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Load key from file'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final data =
                          await Clipboard.getData(Clipboard.kTextPlain);
                      final text = data?.text ?? '';
                      if (text.isNotEmpty) {
                        keyController.text = text;
                        if (ScaffoldMessenger.maybeOf(context) != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Pasted key from clipboard')),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.paste),
                    label: const Text('Paste'),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result != true) return;
    if (existing == null) {
      await service.addIdentity(
        name: nameController.text.trim(),
        type: typeController.text.trim(),
        privateKey: keyController.text.trim(),
      );
    } else {
      await service.updateIdentity(
        existing.copyWith(
          name: nameController.text.trim(),
          type: typeController.text.trim(),
          privateKey: keyController.text.trim(),
        ),
      );
    }
  }

  /// Scans ~/.ssh directory for private keys and allows importing them.
  Future<void> _promptImportFromSsh(BuildContext context) async {
    // Get home directory
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    if (home.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not determine home directory')),
        );
      }
      return;
    }

    final sshDir = Directory('$home/.ssh');
    if (!await sshDir.exists()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Directory not found: ${sshDir.path}')),
        );
      }
      return;
    }

    // Scan for private key files
    final keyFiles = <_SshKeyFile>[];
    try {
      await for (final entity in sshDir.list()) {
        if (entity is File) {
          final name = entity.path.split(Platform.pathSeparator).last;
          // Skip public keys, known_hosts, config, etc.
          if (name.endsWith('.pub') ||
              name == 'known_hosts' ||
              name == 'authorized_keys' ||
              name == 'config') {
            continue;
          }

          // Try to read and check if it looks like a private key
          try {
            final content = await entity.readAsString();
            if (content.contains('PRIVATE KEY')) {
              // Detect key type
              String keyType = 'unknown';
              if (content.contains('RSA PRIVATE KEY') ||
                  content.contains('-----BEGIN RSA')) {
                keyType = 'ssh-rsa';
              } else if (content.contains('EC PRIVATE KEY') ||
                  content.contains('-----BEGIN EC')) {
                keyType = 'ecdsa';
              } else if (content.contains('OPENSSH PRIVATE KEY')) {
                // OpenSSH format - check the key data for type hints
                if (name.contains('ed25519')) {
                  keyType = 'ssh-ed25519';
                } else if (name.contains('ecdsa')) {
                  keyType = 'ecdsa';
                } else if (name.contains('rsa')) {
                  keyType = 'ssh-rsa';
                } else {
                  keyType = 'ssh-ed25519'; // Modern default
                }
              }

              keyFiles.add(_SshKeyFile(
                path: entity.path,
                name: name,
                content: content,
                keyType: keyType,
              ));
            }
          } catch (_) {
            // Skip files that can't be read as text
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error scanning ~/.ssh: $e')),
        );
      }
      return;
    }

    if (keyFiles.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No private keys found in ~/.ssh')),
        );
      }
      return;
    }

    // Show selection dialog
    if (!context.mounted) return;

    final selected = await showDialog<List<_SshKeyFile>>(
      context: context,
      builder: (context) => _ImportSshKeysDialog(
        keyFiles: keyFiles,
        existingNames:
            service.currentData?.identities.map((i) => i.name).toSet() ?? {},
      ),
    );

    if (selected == null || selected.isEmpty) return;

    // Import selected keys
    int imported = 0;
    for (final key in selected) {
      try {
        await service.addIdentity(
          name: key.name,
          type: key.keyType,
          privateKey: key.content,
        );
        imported++;
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to import ${key.name}: $e')),
          );
        }
      }
    }

    if (context.mounted && imported > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported $imported key(s)')),
      );
    }
  }

  void _connectHost(VaultHost host) {
    VaultIdentity? identity;
    for (final id
        in service.currentData?.identities ?? const <VaultIdentity>[]) {
      if (id.id == host.identityId) {
        identity = id;
        break;
      }
    }
    onConnectHost(host, identity);
  }
}

// -----------------------------------------------------------------------------
// SSH Key Import Support
// -----------------------------------------------------------------------------

/// Represents a private key file found in ~/.ssh
class _SshKeyFile {
  const _SshKeyFile({
    required this.path,
    required this.name,
    required this.content,
    required this.keyType,
  });

  final String path;
  final String name;
  final String content;
  final String keyType;
}

/// Dialog for selecting SSH keys to import
class _ImportSshKeysDialog extends StatefulWidget {
  const _ImportSshKeysDialog({
    required this.keyFiles,
    required this.existingNames,
  });

  final List<_SshKeyFile> keyFiles;
  final Set<String> existingNames;

  @override
  State<_ImportSshKeysDialog> createState() => _ImportSshKeysDialogState();
}

class _ImportSshKeysDialogState extends State<_ImportSshKeysDialog> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import SSH Keys'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Found ${widget.keyFiles.length} private key(s) in ~/.ssh',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.keyFiles.length,
                itemBuilder: (context, index) {
                  final key = widget.keyFiles[index];
                  final alreadyExists = widget.existingNames.contains(key.name);
                  return CheckboxListTile(
                    value: _selected.contains(key.path),
                    onChanged: alreadyExists
                        ? null
                        : (value) {
                            setState(() {
                              if (value == true) {
                                _selected.add(key.path);
                              } else {
                                _selected.remove(key.path);
                              }
                            });
                          },
                    title: Text(key.name),
                    subtitle: Text(
                      alreadyExists
                          ? 'Already imported'
                          : '${key.keyType} • ${key.path}',
                      style: TextStyle(
                        color: alreadyExists
                            ? Theme.of(context).colorScheme.outline
                            : null,
                      ),
                    ),
                    secondary: Icon(
                      alreadyExists ? Icons.check_circle : Icons.vpn_key,
                      color: alreadyExists
                          ? Theme.of(context).colorScheme.outline
                          : null,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () {
                  final selectedKeys = widget.keyFiles
                      .where((k) => _selected.contains(k.path))
                      .toList();
                  Navigator.of(context).pop(selectedKeys);
                },
          child: Text('Import ${_selected.length} key(s)'),
        ),
      ],
    );
  }
}
