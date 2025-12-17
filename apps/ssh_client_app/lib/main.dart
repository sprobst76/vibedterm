import 'dart:async';

import 'package:core_ssh/core_ssh.dart';
import 'package:core_vault/core_vault.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:ui_terminal/ui_terminal.dart';

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

  final _pages = const [
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
          body: Row(
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
              Expanded(
                child: IndexedStack(
                  index: _index,
                  children: [
                    VaultScreen(service: _vaultService),
                    HostsScreen(service: _vaultService),
                    TerminalScreen(service: _vaultService),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PageConfig {
  const _PageConfig(this.label, this.icon);

  final String label;
  final IconData icon;
}

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
    if (result == null) return;
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
      path: result,
      password: passwordResult.password,
      payload: payload,
      rememberPasswordForSession: passwordResult.rememberSession,
      rememberPasswordSecurely: passwordResult.rememberSecure,
    );
  }

  Future<_PasswordPromptResult?> _promptForPassword(
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
    if (ok != true) return null;
    return _PasswordPromptResult(
      controller.text,
      rememberSession: rememberSession,
      rememberSecure: rememberSecure,
    );
  }
}

class _PasswordPromptResult {
  _PasswordPromptResult(
    this.password, {
    required this.rememberSession,
    required this.rememberSecure,
  });
  final String password;
  final bool rememberSession;
  final bool rememberSecure;
}

class HostsScreen extends StatelessWidget {
  const HostsScreen({super.key, required this.service});

  final VaultService service;

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
                        onPressed: () => _promptAddIdentity(context, existing: id),
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
                                onPressed: () => _promptAddHost(context, existing: host),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete),
                                onPressed: () => service.deleteHost(host.id),
                              ),
                              IconButton(
                                tooltip: 'Connect',
                                icon: const Icon(Icons.play_arrow),
                                onPressed: () => _connectHost(context, host),
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

  Future<void> _promptAddHost(BuildContext context, {VaultHost? existing}) async {
    final labelController = TextEditingController(text: existing?.label ?? '');
    final hostController = TextEditingController(text: existing?.hostname ?? '');
    final userController = TextEditingController(text: existing?.username ?? 'root');
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

  Future<void> _promptAddIdentity(BuildContext context, {VaultIdentity? existing}) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final typeController =
        TextEditingController(text: existing?.type ?? 'ssh-ed25519');
    final keyController = TextEditingController(text: existing?.privateKey ?? '');

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

  void _connectHost(BuildContext context, VaultHost host) {
    VaultIdentity? identity;
    for (final id in service.currentData?.identities ?? const <VaultIdentity>[]) {
      if (id.id == host.identityId) {
        identity = id;
        break;
      }
    }
    service.setPendingConnectHost(host, identity: identity);
    final shell = context.findAncestorStateOfType<_HomeShellState>();
    shell?._setIndex(2);
  }
}

class TerminalScreen extends StatelessWidget {
  const TerminalScreen({super.key, required this.service});

  final VaultService service;

  @override
  Widget build(BuildContext context) {
    return TerminalPanel(service: service);
  }
}

class TerminalPanel extends StatefulWidget {
  const TerminalPanel({super.key, required this.service});

  final VaultService service;

  @override
  State<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends State<TerminalPanel> {
  final _manager = SshConnectionManager();
  final _hostController = TextEditingController(text: 'localhost');
  final _portController = TextEditingController(text: '22');
  final _userController = TextEditingController(text: 'root');
  final _passwordController = TextEditingController();
  final _privateKeyController = TextEditingController();
  final _passphraseController = TextEditingController();
  final _commandController = TextEditingController(text: 'uname -a');
  final TerminalBridge _terminalBridge = TerminalBridge();
  final _trustedKeysExpanded = ValueNotifier<bool>(false);

  late final VoidCallback _vaultListener;
  StreamSubscription<String>? _logSub;
  StreamSubscription<SshConnectionStatus>? _statusSub;
  List<String> _logs = [];
  String _output = '';
  SshConnectionStatus _status = SshConnectionStatus.disconnected;
  bool _busy = false;
  String? _selectedHostId;
  final Map<String, Set<String>> _trustedHostKeys = {};
  SshShellSession? _shellSession;
  Timer? _pendingHostCheckTimer;

  @override
  void initState() {
    super.initState();
    _vaultListener = () {
      if (widget.service.isUnlocked) {
        _refreshTrustedKeys();
      }
    };
    widget.service.state.addListener(_vaultListener);
    _refreshTrustedKeys();
    _statusSub = _manager.statusStream.listen((status) {
      if (!mounted) return;
      setState(() {
        _status = status;
      });
    });
    _logSub = _manager.logs.listen((msg) {
      if (!mounted) return;
      setState(() {
        final updated = [..._logs, msg];
        _logs = updated.length > 200 ? updated.sublist(updated.length - 200) : updated;
      });
    });
    _maybeApplyPendingHost();
  }

  @override
  void dispose() {
    _pendingHostCheckTimer?.cancel();
    _statusSub?.cancel();
    _logSub?.cancel();
    unawaited(_manager.disconnect());
    _manager.dispose();
    widget.service.state.removeListener(_vaultListener);
    _hostController.dispose();
    _portController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    _privateKeyController.dispose();
    _passphraseController.dispose();
    _commandController.dispose();
    _terminalBridge.dispose();
    _trustedKeysExpanded.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _status == SshConnectionStatus.connected;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildConnectionCard(isConnected),
          const SizedBox(height: 12),
          _buildTrustedKeysSection(),
          const SizedBox(height: 12),
          _buildCommandCard(isConnected),
          const SizedBox(height: 12),
          _buildShellCard(isConnected),
          const SizedBox(height: 12),
          Expanded(child: _buildLogsCard()),
        ],
      ),
    );
  }

  Widget _buildConnectionCard(bool isConnected) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'SSH Connection',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Chip(
                  label: Text(_status.name),
                  backgroundColor: switch (_status) {
                    SshConnectionStatus.connected => Colors.green.shade100,
                    SshConnectionStatus.connecting => Colors.amber.shade100,
                    SshConnectionStatus.error => Colors.red.shade100,
                    SshConnectionStatus.disconnected => Colors.grey.shade200,
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.service.currentData?.hosts.isNotEmpty ?? false) ...[
              DropdownButtonFormField<String?>(
                initialValue: _selectedHostId,
                decoration: const InputDecoration(
                  labelText: 'Use saved host',
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Choose...'),
                  ),
                  ...widget.service.currentData!.hosts.map(
                    (h) => DropdownMenuItem(
                      value: h.id,
                      child: Text('${h.label} (${h.hostname})'),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() => _selectedHostId = value);
                  if (value != null) {
                    _applyHost(value);
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _hostController,
                    decoration: const InputDecoration(labelText: 'Host'),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _portController,
                    decoration: const InputDecoration(labelText: 'Port'),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _userController,
                    decoration: const InputDecoration(labelText: 'Username'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _passwordController,
                    decoration: const InputDecoration(labelText: 'Password (optional)'),
                    obscureText: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _privateKeyController,
              decoration: const InputDecoration(
                labelText: 'Private key (PEM, optional)',
                alignLabelWithHint: true,
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passphraseController,
              decoration: const InputDecoration(
                labelText: 'Key passphrase (optional)',
              ),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _connect,
                  icon: const Icon(Icons.power_settings_new),
                  label: const Text('Connect'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _busy || !isConnected ? null : _disconnect,
                  icon: const Icon(Icons.link_off),
                  label: const Text('Disconnect'),
                ),
                if (_busy) ...[
                  const SizedBox(width: 12),
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrustedKeysSection() {
    final trusted = widget.service.trustedHostKeys();
    final items = trusted.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Trusted host keys',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: _trustedKeysExpanded,
                  builder: (context, expanded, _) {
                    return IconButton(
                      onPressed: () =>
                          _trustedKeysExpanded.value = !expanded,
                      icon: Icon(expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down),
                    );
                  },
                ),
              ],
            ),
            ValueListenableBuilder<bool>(
              valueListenable: _trustedKeysExpanded,
              builder: (context, expanded, _) {
                if (!expanded) {
                  return const SizedBox.shrink();
                }
                if (items.isEmpty) {
                  return const Text('No trusted keys yet.');
                }
                return Column(
                  children: items.map((entry) {
                    final host = entry.key;
                    final fps = entry.value.toList()..sort();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          host,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        ...fps.map(
                          (fp) => Row(
                            children: [
                              Expanded(
                                child: Text(
                                  fp,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Remove',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _removeTrustedKey(host, fp),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommandCard(bool isConnected) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Quick command',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commandController,
                    decoration: const InputDecoration(
                      labelText: 'Command',
                    ),
                    minLines: 1,
                    maxLines: 2,
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _busy || !isConnected ? null : _runCommand,
                  child: const Text('Run'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey.shade50,
              ),
              constraints: const BoxConstraints(minHeight: 80, maxHeight: 200),
              child: SingleChildScrollView(
                child: SelectableText(
                  _output.isEmpty ? 'Command output will appear here.' : _output,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShellCard(bool isConnected) {
    final shellActive = _shellSession != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Interactive shell (experimental)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy || !isConnected || shellActive
                          ? null
                          : _startShell,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Open shell'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: shellActive ? _closeShell : null,
                      icon: const Icon(Icons.stop),
                      label: const Text('Close'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              constraints: const BoxConstraints(minHeight: 260, maxHeight: 420),
              child: VibedTerminalView(bridge: _terminalBridge),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Logs',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _logs.isEmpty
                    ? const Center(child: Text('No logs yet.'))
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.all(8),
                        itemCount: _logs.length,
                        itemBuilder: (context, index) {
                          final entry = _logs[_logs.length - 1 - index];
                          return Text(
                            entry,
                            style: const TextStyle(fontFamily: 'monospace'),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _connect() async {
    final host = _hostController.text.trim();
    final username = _userController.text.trim();
    if (host.isEmpty || username.isEmpty) {
      _showMessage('Host and username are required.');
      return;
    }
    final port = int.tryParse(_portController.text) ?? 22;
    setState(() => _busy = true);
    try {
      await _manager.connect(
        SshTarget(
          host: host,
          port: port,
          username: username,
          password: _passwordController.text.isEmpty
              ? null
              : _passwordController.text,
          privateKey: _privateKeyController.text.trim().isEmpty
              ? null
              : _privateKeyController.text.trim(),
          passphrase: _passphraseController.text.isEmpty
              ? null
              : _passphraseController.text,
          onHostKeyVerify: (type, fingerprint) =>
              _handleHostKeyPrompt(host, type, fingerprint),
        ),
      );
      _showMessage('Connected to $host');
    } catch (e) {
      final message = e is SshException ? e.message : e.toString();
      _showMessage('Connection failed: $message');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    await _closeShell();
    await _manager.disconnect();
    if (mounted) {
      setState(() => _busy = false);
    }
  }

  Future<void> _runCommand() async {
    final command = _commandController.text.trim();
    if (command.isEmpty) {
      _showMessage('Enter a command to run.');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await _manager.runCommand(command);
      if (!mounted) return;
      setState(() {
        _output = [
          if (result.stdout.isNotEmpty) result.stdout.trim(),
          if (result.stderr.isNotEmpty) 'stderr:\n${result.stderr.trim()}',
        ].where((line) => line.isNotEmpty).join('\n\n');
      });
    } catch (e) {
      final message = e is SshException ? e.message : e.toString();
      _showMessage('Command failed: $message');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _applyHost(String hostId) {
    VaultHost? host;
    for (final h in widget.service.currentData?.hosts ?? const <VaultHost>[]) {
      if (h.id == hostId) {
        host = h;
        break;
      }
    }
    final selected = host;
    if (selected == null) return;
    setState(() {
      _hostController.text = selected.hostname;
      _portController.text = selected.port.toString();
      _userController.text = selected.username;
      _selectedHostId = hostId;
    });
    VaultIdentity? identity;
    for (final id in widget.service.currentData?.identities ?? const <VaultIdentity>[]) {
      if (id.id == selected.identityId) {
        identity = id;
        break;
      }
    }
    if (identity != null) {
      _privateKeyController.text = identity.privateKey;
      _passwordController.clear();
    }
  }

  Future<bool> _handleHostKeyPrompt(
    String host,
    String type,
    String fingerprint,
  ) async {
    final trusted = _trustedHostKeys[host];
    if (trusted != null && trusted.contains(fingerprint)) {
      return true;
    }
    final mismatch = trusted != null && trusted.isNotEmpty && !trusted.contains(fingerprint);
    if (!mounted) return false;
    final accept = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Trust host key?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Host: $host'),
              Text('Type: $type'),
              Text('Fingerprint: $fingerprint'),
              if (mismatch) ...[
                const SizedBox(height: 8),
                const Text(
                  'Warning: This host presented a different fingerprint than previously trusted.',
                  style: TextStyle(color: Colors.redAccent),
                ),
                const SizedBox(height: 4),
                Text('Previously trusted:\n${trusted.join('\n')}'),
              ],
              const SizedBox(height: 8),
              const Text(
                'Accept this host key? It will be remembered in the vault.',
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
              child: const Text('Trust'),
            ),
          ],
        );
      },
    );
    if (accept == true) {
      _trustedHostKeys.putIfAbsent(host, () => <String>{}).add(fingerprint);
      await widget.service.trustHostKey(host: host, fingerprint: fingerprint);
      return true;
    }
    return false;
  }

  void _refreshTrustedKeys() {
    final trusted = widget.service.trustedHostKeys();
    setState(() {
      _trustedHostKeys
        ..clear()
        ..addAll(trusted);
    });
  }

  Future<void> _removeTrustedKey(String host, String fingerprint) async {
    await widget.service.untrustHostKey(host: host, fingerprint: fingerprint);
    _refreshTrustedKeys();
  }

  void _maybeApplyPendingHost() {
    // Delay slightly to ensure UI is built.
    _pendingHostCheckTimer = Timer(const Duration(milliseconds: 300), () {
      final pending = widget.service.pendingConnectHost;
      if (pending == null) return;
      widget.service.setPendingConnectHost(pending);
      _applyHost(pending.id);
      _connect();
    });
  }

  Future<void> _startShell() async {
    if (_shellSession != null) return;
    if (_status != SshConnectionStatus.connected) {
      _showMessage('Connect first.');
      return;
    }
    _terminalBridge.terminal.buffer.clear();
    _terminalBridge.terminal.buffer.setCursor(0, 0);
    _terminalBridge.write('Opening shell...\r\n');
    try {
      final session = await _manager.startShell(
        ptyConfig: SshPtyConfig(
          width: _terminalBridge.terminal.viewWidth,
          height: _terminalBridge.terminal.viewHeight,
        ),
      );
      _shellSession = session;
      _terminalBridge.attachStreams(
        stdout: session.stdout,
        stderr: session.stderr,
      );
      _terminalBridge.onOutput = (data) async {
        await session.writeString(data);
      };
      _terminalBridge.terminal.onResize =
          (width, height, pixelWidth, pixelHeight) {
        session.resize(width, height);
      };
      setState(() {});
      unawaited(session.done.whenComplete(() {
        if (mounted) {
          setState(() {
            _shellSession = null;
          });
        }
      }));
    } catch (e) {
      final message = e is SshException ? e.message : e.toString();
      _showMessage('Shell failed: $message');
    }
  }

  Future<void> _closeShell() async {
    _terminalBridge.onOutput = null;
    _terminalBridge.terminal.onResize = null;
    final session = _shellSession;
    _shellSession = null;
    await session?.close();
    _shellSession = null;
    if (mounted) {
      setState(() {});
    }
  }
}
