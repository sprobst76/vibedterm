import 'dart:io';

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

  final VaultService service;
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
              (id) => Card(
                child: ListTile(
                  leading: const Icon(Icons.vpn_key),
                  title: Text(id.name),
                  subtitle: Text('${id.type} • ${id.id}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () =>
                            _promptAddIdentity(context, existing: id),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () => service.deleteIdentity(id.id),
                      ),
                    ],
                  ),
                ),
              ),
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
    String? selectedIdentityId = existing?.identityId;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(existing == null ? 'Add host' : 'Edit host'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelController,
                decoration: const InputDecoration(labelText: 'Label'),
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
              if (service.currentData?.identities.isNotEmpty ?? false) ...[
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
    final port = int.tryParse(portController.text) ?? 22;
    if (existing == null) {
      await service.addHost(
        label: labelController.text.trim(),
        hostname: hostController.text.trim(),
        port: port,
        username: userController.text.trim(),
        identityId: selectedIdentityId,
      );
    } else {
      await service.updateHost(
        existing.copyWith(
          label: labelController.text.trim(),
          hostname: hostController.text.trim(),
          port: port,
          username: userController.text.trim(),
          identityId: selectedIdentityId,
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
