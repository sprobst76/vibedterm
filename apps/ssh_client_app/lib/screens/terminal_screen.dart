import 'dart:async';

import 'package:core_ssh/core_ssh.dart';
import 'package:core_vault/core_vault.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui_terminal/ui_terminal.dart';
import 'package:uuid/uuid.dart';

import '../services/vault_service.dart';

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
  State<TerminalPanel> createState() => TerminalPanelState();
}

class TerminalPanelState extends State<TerminalPanel>
    with TickerProviderStateMixin {
  static const _uuid = Uuid();

  final List<_ConnectionTab> _tabs = [];
  TabController? _tabController;
  final Map<String, Set<String>> _trustedHostKeys = {};
  bool _showLogs = false;
  late final VoidCallback _vaultListener;

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
    _maybeApplyPendingHost();
  }

  @override
  void dispose() {
    widget.service.state.removeListener(_vaultListener);
    for (final tab in _tabs) {
      tab.dispose();
    }
    _tabController?.dispose();
    super.dispose();
  }

  /// Public method to connect to a host from outside (e.g., from HostsScreen)
  Future<void> connectToHost(VaultHost host, VaultIdentity? identity) async {
    await _connectToHost(host, identity: identity);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildTabBar(),
        Expanded(child: _buildTerminalArea()),
        _buildStatusBar(),
        if (_showLogs) _buildLogsDrawer(),
      ],
    );
  }

  Widget _buildTabBar() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 48,
      color: colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Expanded(
            child: _tabs.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('No connections'),
                  )
                : TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    dividerColor: Colors.transparent,
                    tabs: _tabs.map((t) => _buildTabLabel(t)).toList(),
                  ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New connection',
            onPressed: _showHostPicker,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'More options',
            onSelected: _handleMenuAction,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'trusted_keys',
                child: ListTile(
                  leading: Icon(Icons.key),
                  title: Text('Trusted keys'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'logs',
                child: ListTile(
                  leading:
                      Icon(_showLogs ? Icons.visibility_off : Icons.visibility),
                  title: Text(_showLogs ? 'Hide logs' : 'Show logs'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildTabLabel(_ConnectionTab tab) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _statusColor(tab.status),
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              tab.label,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _confirmCloseTab(tab),
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.close, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTerminalArea() {
    if (_tabs.isEmpty) {
      return _buildEmptyState();
    }
    return TabBarView(
      controller: _tabController,
      children: _tabs.map((t) => VibedTerminalView(bridge: t.bridge)).toList(),
    );
  }

  Widget _buildEmptyState() {
    final hosts = widget.service.currentData?.hosts ?? [];
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.terminal,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No active connections',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 24),
          if (hosts.isNotEmpty) ...[
            Text(
              'Quick connect:',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: hosts.take(6).map((h) {
                return ActionChip(
                  avatar: const Icon(Icons.dns, size: 18),
                  label: Text(h.label),
                  onPressed: () => _connectToHost(h),
                );
              }).toList(),
            ),
            if (hosts.length > 6) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: _showHostPicker,
                child: Text('Show all ${hosts.length} hosts'),
              ),
            ],
          ] else ...[
            const Text('No hosts configured yet.'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                // Navigate to Hosts tab (index 1)
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Add hosts in the Hosts tab')),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('Add a host'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    final tab = _activeTab;
    final hasSession = tab?.session != null;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          if (tab != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _statusColor(tab.status),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tab.connectionInfo,
                style: Theme.of(context).textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else ...[
            const Expanded(child: SizedBox.shrink()),
          ],
          _KeyButton(
              label: 'Esc',
              onPressed: hasSession ? () => _sendKey('\x1b') : null),
          _KeyButton(
              label: 'Ctrl+C',
              onPressed: hasSession ? () => _sendKey('\x03') : null),
          _KeyButton(
              label: 'Ctrl+D',
              onPressed: hasSession ? () => _sendKey('\x04') : null),
          _KeyButton(
              label: 'Tab',
              onPressed: hasSession ? () => _sendKey('\t') : null),
          IconButton(
            icon: const Icon(Icons.content_paste, size: 18),
            tooltip: 'Paste',
            onPressed: hasSession ? _pasteToShell : null,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: Icon(_showLogs ? Icons.expand_more : Icons.expand_less,
                size: 18),
            tooltip: _showLogs ? 'Hide logs' : 'Show logs',
            onPressed: () => setState(() => _showLogs = !_showLogs),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildLogsDrawer() {
    final tab = _activeTab;
    if (tab == null) {
      return Container(
        height: 120,
        padding: const EdgeInsets.all(12),
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        child: const Center(child: Text('No logs')),
      );
    }
    return Container(
      height: 150,
      padding: const EdgeInsets.all(8),
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: tab.logs.isEmpty
          ? const Center(child: Text('No logs yet'))
          : ListView.builder(
              reverse: true,
              itemCount: tab.logs.length,
              itemBuilder: (context, index) {
                final entry = tab.logs[tab.logs.length - 1 - index];
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  child: SelectableText(
                    entry,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: _logColor(entry),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Color _logColor(String entry) {
    final lower = entry.toLowerCase();
    if (lower.contains('error') ||
        lower.contains('failed') ||
        lower.contains('exception')) {
      return Colors.red;
    }
    if (lower.contains('authenticated') ||
        lower.contains('auth success') ||
        lower.contains('success') ||
        lower.contains('connected')) {
      return Colors.green[700]!;
    }
    if (lower.contains('warning') ||
        lower.contains('warn') ||
        lower.contains('mismatch')) {
      return Colors.amber[800]!;
    }
    return Colors.blue[700]!;
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'logs':
        setState(() => _showLogs = !_showLogs);
        break;
      case 'trusted_keys':
        _showTrustedKeysDialog();
        break;
    }
  }

  Future<void> _showHostPicker() async {
    final data = widget.service.currentData;
    if (data == null || data.hosts.isEmpty) {
      _showMessage('No hosts configured. Add one in the Hosts tab.');
      return;
    }

    final selected = await showModalBottomSheet<VaultHost>(
      context: context,
      builder: (context) => _HostPickerSheet(
        hosts: data.hosts,
        identities: data.identities,
      ),
    );

    if (selected != null) {
      await _connectToHost(selected);
    }
  }

  Future<void> _connectToHost(VaultHost host, {VaultIdentity? identity}) async {
    // Find identity if not provided
    identity ??= widget.service.currentData?.identities
        .where((i) => i.id == host.identityId)
        .firstOrNull;

    // Always prompt for password (can be empty if using key auth)
    final password = await _promptForPassword(host,
        hasKey: identity?.privateKey.isNotEmpty == true);
    if (password == null) return; // User cancelled

    // Create new tab
    final tab = _ConnectionTab(
      id: _uuid.v4(),
      host: host,
      identity: identity,
      password: password,
    );

    tab.init(
      onStatusChange: () {
        if (mounted) setState(() {});
      },
      onLog: (msg) {
        // ignore: avoid_print
        print('[SSH:${tab.label}] $msg');
      },
    );

    setState(() {
      _tabs.add(tab);
      _resetTabController(_tabs.length - 1);
    });

    // Connect
    await tab.connect(
      trustedKeys: _trustedHostKeys,
      onHostKeyPrompt: _handleHostKeyPrompt,
    );

    if (mounted) {
      setState(() {});
      // Delay focus to avoid Windows platform exception
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          tab.focusNode.requestFocus();
        }
      });
    }
  }

  Future<void> _confirmCloseTab(_ConnectionTab tab) async {
    if (tab.status == TabConnectionStatus.connected) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Close connection?'),
          content: Text('Disconnect from ${tab.label}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    await _closeTab(tab);
  }

  Future<void> _closeTab(_ConnectionTab tab) async {
    final index = _tabs.indexOf(tab);
    if (index < 0) return;

    await tab.dispose();

    setState(() {
      _tabs.removeAt(index);
      final nextIndex = _tabs.isEmpty
          ? 0
          : (index >= _tabs.length ? _tabs.length - 1 : index);
      _resetTabController(nextIndex);
    });
  }

  void _resetTabController(int preferredIndex) {
    final newLength = _tabs.length;
    _tabController?.dispose();

    if (newLength == 0) {
      _tabController = null;
      return;
    }

    final newIndex = preferredIndex.clamp(0, newLength - 1);
    _tabController = TabController(
      length: newLength,
      vsync: this,
      initialIndex: newIndex,
    );
  }

  _ConnectionTab? get _activeTab {
    if (_tabs.isEmpty) return null;
    final idx = _tabController?.index ?? 0;
    if (idx < 0 || idx >= _tabs.length) return null;
    return _tabs[idx];
  }

  Future<void> _sendKey(String data) async {
    final tab = _activeTab;
    if (tab?.session == null) return;
    await tab!.session!.writeString(data);
  }

  Future<void> _pasteToShell() async {
    final tab = _activeTab;
    if (tab?.session == null) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    await tab!.session!.writeString(text);
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<String?> _promptForPassword(VaultHost host,
      {bool hasKey = false}) async {
    final controller = TextEditingController();

    final result = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('SSH Authentication'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${host.username}@${host.hostname}:${host.port}'),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: true,
                autofocus: false,
                decoration: InputDecoration(
                  labelText: 'Password',
                  hintText: hasKey ? 'Leave empty for key auth' : null,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => Navigator.pop(context, controller.text),
              ),
              if (hasKey) ...[
                const SizedBox(height: 8),
                Text(
                  'A private key is configured. Leave empty to use key authentication.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Connect'),
            ),
          ],
        );
      },
    );

    // Return empty string (not null) to indicate "use key auth"
    return result;
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

    final mismatch =
        trusted != null && trusted.isNotEmpty && !trusted.contains(fingerprint);

    if (!mounted) return false;

    final accept = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Trust host key?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Host: $host'),
            Text('Type: $type'),
            const SizedBox(height: 8),
            SelectableText(
              fingerprint,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            if (mismatch) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Warning: Different fingerprint than previously trusted!',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Trust'),
          ),
        ],
      ),
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

  void _showTrustedKeysDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Trusted Host Keys'),
        content: SizedBox(
          width: 400,
          child: _buildTrustedKeysList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildTrustedKeysList() {
    final trusted = widget.service.trustedHostKeys();
    if (trusted.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No trusted keys yet.'),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: trusted.entries.map((entry) {
          final host = entry.key;
          final fingerprints = entry.value.toList()..sort();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      host,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await widget.service.untrustHost(host);
                      _refreshTrustedKeys();
                      if (mounted) Navigator.pop(context);
                      _showTrustedKeysDialog();
                    },
                    child: const Text('Remove all'),
                  ),
                ],
              ),
              ...fingerprints.map((fp) => Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            fp,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 16),
                          onPressed: () async {
                            await widget.service.untrustHostKey(
                              host: host,
                              fingerprint: fp,
                            );
                            _refreshTrustedKeys();
                            if (mounted) Navigator.pop(context);
                            _showTrustedKeysDialog();
                          },
                        ),
                      ],
                    ),
                  )),
              const Divider(),
            ],
          );
        }).toList(),
      ),
    );
  }

  void _maybeApplyPendingHost() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pending = widget.service.pendingConnectHost;
      final pendingIdentity = widget.service.pendingConnectIdentity;
      if (pending != null) {
        widget.service.clearPendingConnect();
        _connectToHost(pending, identity: pendingIdentity);
      }
    });
  }

  Color _statusColor(TabConnectionStatus status) => switch (status) {
        TabConnectionStatus.connected => Colors.green,
        TabConnectionStatus.connecting => Colors.amber,
        TabConnectionStatus.error => Colors.red,
        TabConnectionStatus.disconnected => Colors.grey,
      };
}

// -----------------------------------------------------------------------------
// Host Picker Sheet
// -----------------------------------------------------------------------------

class _HostPickerSheet extends StatelessWidget {
  const _HostPickerSheet({
    required this.hosts,
    required this.identities,
  });

  final List<VaultHost> hosts;
  final List<VaultIdentity> identities;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Connect to host',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const Divider(height: 1),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.5,
          ),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: hosts.length,
            itemBuilder: (context, index) {
              final host = hosts[index];
              final identity =
                  identities.where((i) => i.id == host.identityId).firstOrNull;
              return ListTile(
                leading: const Icon(Icons.dns),
                title: Text(host.label),
                subtitle:
                    Text('${host.username}@${host.hostname}:${host.port}'),
                trailing: identity != null
                    ? Chip(
                        label: Text(
                          identity.name,
                          style: const TextStyle(fontSize: 10),
                        ),
                        visualDensity: VisualDensity.compact,
                      )
                    : null,
                onTap: () => Navigator.pop(context, host),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Key Button Widget
// -----------------------------------------------------------------------------

class _KeyButton extends StatelessWidget {
  const _KeyButton({required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 32),
          visualDensity: VisualDensity.compact,
        ),
        child: Text(label, style: const TextStyle(fontSize: 11)),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Connection Tab with its own SshConnectionManager
// -----------------------------------------------------------------------------

enum TabConnectionStatus { disconnected, connecting, connected, error }

class _ConnectionTab {
  _ConnectionTab({
    required this.id,
    required this.host,
    this.identity,
    this.password,
  })  : manager = SshConnectionManager(),
        bridge = TerminalBridge(),
        focusNode = FocusNode();

  final String id;
  final VaultHost host;
  final VaultIdentity? identity;
  final String? password;
  final SshConnectionManager manager;
  final TerminalBridge bridge;
  final FocusNode focusNode;

  SshShellSession? session;
  TabConnectionStatus status = TabConnectionStatus.disconnected;
  final List<String> logs = [];

  StreamSubscription<SshConnectionStatus>? _statusSub;
  StreamSubscription<String>? _logSub;
  VoidCallback? _onStatusChange;

  String get label => host.label;
  String get connectionInfo => '${host.username}@${host.hostname}:${host.port}';

  void init({
    required VoidCallback onStatusChange,
    required void Function(String) onLog,
  }) {
    _onStatusChange = onStatusChange;

    _statusSub = manager.statusStream.listen((s) {
      status = _mapStatus(s);
      onStatusChange();
    });

    _logSub = manager.logs.listen((msg) {
      _addLog(msg);
      onLog(msg);
    });
  }

  Future<void> connect({
    required Map<String, Set<String>> trustedKeys,
    required Future<bool> Function(String host, String type, String fp)
        onHostKeyPrompt,
  }) async {
    status = TabConnectionStatus.connecting;
    _onStatusChange?.call();
    bridge.write('Connecting to ${host.hostname}:${host.port}...\r\n');

    // Debug logging - also print to console
    final key = identity?.privateKey ?? '';
    final keyPreview = key.isNotEmpty
        ? '${key.substring(0, key.length.clamp(0, 50))}...'
        : '(no key)';
    // ignore: avoid_print
    print('[SSH-DEBUG] User: ${host.username}');
    // ignore: avoid_print
    print('[SSH-DEBUG] Host: ${host.hostname}:${host.port}');
    // ignore: avoid_print
    print('[SSH-DEBUG] Key: $keyPreview');
    // ignore: avoid_print
    print('[SSH-DEBUG] Password provided: ${password?.isNotEmpty == true}');
    _addLog('Connecting: ${host.username}@${host.hostname}:${host.port}');

    try {
      await manager.connect(
        SshTarget(
          host: host.hostname,
          port: host.port,
          username: host.username,
          password: password?.isNotEmpty == true ? password : null,
          privateKey: identity?.privateKey,
          passphrase: identity?.passphrase,
          onHostKeyVerify: (type, fp) => _handleHostKey(
            type,
            fp,
            trustedKeys,
            onHostKeyPrompt,
          ),
        ),
      );

      _addLog('Connected, opening shell...');
      bridge.write('Connected. Opening shell...\r\n');

      // Auto-start shell
      await _startShell();
    } catch (e) {
      status = TabConnectionStatus.error;
      _onStatusChange?.call();
      final msg = e is SshException ? e.message : e.toString();
      bridge.write('\r\nConnection failed: $msg\r\n');
      _addLog('Connection failed: $msg');
    }
  }

  Future<bool> _handleHostKey(
    String type,
    String fingerprint,
    Map<String, Set<String>> trustedKeys,
    Future<bool> Function(String, String, String) onPrompt,
  ) async {
    final trusted = trustedKeys[host.hostname];
    if (trusted != null && trusted.contains(fingerprint)) {
      _addLog('Host key known, auto-accepting');
      return true;
    }
    return onPrompt(host.hostname, type, fingerprint);
  }

  Future<void> _startShell() async {
    if (status != TabConnectionStatus.connected) return;
    if (session != null) return;

    bridge.terminal.buffer.clear();
    bridge.terminal.buffer.setCursor(0, 0);

    final newSession = await manager.startShell(
      ptyConfig: SshPtyConfig(
        width: bridge.terminal.viewWidth,
        height: bridge.terminal.viewHeight,
      ),
    );

    session = newSession;
    bridge.attachStreams(stdout: newSession.stdout, stderr: newSession.stderr);
    bridge.onOutput = (data) => newSession.writeString(data);
    bridge.terminal.onResize = (w, h, pw, ph) => newSession.resize(w, h);

    _addLog('Shell opened');

    unawaited(newSession.done.whenComplete(() {
      session = null;
      _addLog('Shell closed');
      _onStatusChange?.call();
    }));
  }

  Future<void> dispose() async {
    unawaited(_statusSub?.cancel());
    unawaited(_logSub?.cancel());
    bridge.onOutput = null;
    bridge.terminal.onResize = null;
    unawaited(session?.close());
    unawaited(manager.disconnect());
    manager.dispose();
    bridge.dispose();
    focusNode.dispose();
  }

  void _addLog(String msg) {
    logs.add(msg);
    if (logs.length > 200) logs.removeAt(0);
  }

  static TabConnectionStatus _mapStatus(SshConnectionStatus s) => switch (s) {
        SshConnectionStatus.disconnected => TabConnectionStatus.disconnected,
        SshConnectionStatus.connecting => TabConnectionStatus.connecting,
        SshConnectionStatus.connected => TabConnectionStatus.connected,
        SshConnectionStatus.error => TabConnectionStatus.error,
      };
}
