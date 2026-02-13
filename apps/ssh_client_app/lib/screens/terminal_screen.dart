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

  final VaultServiceInterface service;

  @override
  Widget build(BuildContext context) {
    return TerminalPanel(service: service);
  }
}

class TerminalPanel extends StatefulWidget {
  const TerminalPanel({super.key, required this.service});

  final VaultServiceInterface service;

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

  /// Get the current terminal theme for styling surrounding UI.
  TerminalTheme get _currentTerminalTheme {
    final themeName = widget.service.currentData?.settings.terminalTheme ?? 'default';
    return TerminalThemePresets.getTheme(themeName);
  }

  @override
  Widget build(BuildContext context) {
    final termTheme = _currentTerminalTheme;

    return Container(
      color: termTheme.background,
      child: Column(
        children: [
          _buildTabBar(termTheme),
          Expanded(child: _buildTerminalArea(termTheme)),
          _buildStatusBar(termTheme),
          if (_showLogs) _buildLogsDrawer(termTheme),
        ],
      ),
    );
  }

  Widget _buildTabBar(TerminalTheme termTheme) {
    // Create a slightly lighter/darker shade for the tab bar
    final tabBarColor = Color.lerp(termTheme.background, termTheme.foreground, 0.08)!;
    final textColor = termTheme.foreground;
    final iconColor = termTheme.foreground.withOpacity(0.8);

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: tabBarColor,
        border: Border(
          bottom: BorderSide(
            color: termTheme.foreground.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _tabs.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'No connections',
                      style: TextStyle(color: textColor.withOpacity(0.6)),
                    ),
                  )
                : Theme(
                    data: Theme.of(context).copyWith(
                      tabBarTheme: TabBarThemeData(
                        labelColor: textColor,
                        unselectedLabelColor: textColor.withOpacity(0.6),
                        indicatorColor: termTheme.cyan,
                        dividerColor: Colors.transparent,
                      ),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      dividerColor: Colors.transparent,
                      tabs: _tabs.map((t) => _buildTabLabel(t, textColor)).toList(),
                    ),
                  ),
          ),
          IconButton(
            icon: Icon(Icons.add, color: iconColor),
            tooltip: 'New connection',
            onPressed: _showHostPicker,
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: iconColor),
            tooltip: 'More options',
            onSelected: _handleMenuAction,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'terminal_settings',
                child: ListTile(
                  leading: Icon(Icons.palette),
                  title: Text('Terminal settings'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
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

  Widget _buildTabLabel(_ConnectionTab tab, Color textColor) {
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
              style: TextStyle(color: textColor),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _confirmCloseTab(tab),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.close, size: 16, color: textColor.withOpacity(0.7)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTerminalArea(TerminalTheme termTheme) {
    if (_tabs.isEmpty) {
      return _buildEmptyState(termTheme);
    }
    final settings = widget.service.currentData?.settings;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: termTheme.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: termTheme.foreground.withOpacity(0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: TabBarView(
          controller: _tabController,
          children: _tabs
              .map(
                (t) => VibedTerminalView(
                  bridge: t.bridge,
                  focusNode: t.focusNode,
                  themeName: settings?.terminalTheme ?? 'default',
                  fontSize: settings?.terminalFontSize ?? 14.0,
                  fontFamily: settings?.terminalFontFamily,
                  opacity: settings?.terminalOpacity ?? 1.0,
                  cursorStyle: _parseCursorStyle(settings?.terminalCursorStyle),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  TerminalCursorStyle _parseCursorStyle(String? style) {
    switch (style) {
      case 'underline':
        return TerminalCursorStyle.underline;
      case 'bar':
        return TerminalCursorStyle.bar;
      case 'block':
      default:
        return TerminalCursorStyle.block;
    }
  }

  Widget _buildEmptyState(TerminalTheme termTheme) {
    final hosts = widget.service.currentData?.hosts ?? [];
    final textColor = termTheme.foreground;
    final dimColor = termTheme.foreground.withOpacity(0.6);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.terminal,
            size: 64,
            color: termTheme.cyan.withOpacity(0.7),
          ),
          const SizedBox(height: 16),
          Text(
            'No active connections',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
          ),
          const SizedBox(height: 24),
          if (hosts.isNotEmpty) ...[
            Text(
              'Quick connect:',
              style: TextStyle(fontSize: 12, color: dimColor),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: hosts.take(6).map((h) {
                return ActionChip(
                  avatar: Icon(Icons.dns, size: 18, color: termTheme.green),
                  label: Text(h.label, style: TextStyle(color: textColor)),
                  backgroundColor: termTheme.background,
                  side: BorderSide(color: termTheme.foreground.withOpacity(0.3)),
                  onPressed: () => _connectToHost(h),
                );
              }).toList(),
            ),
            if (hosts.length > 6) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: _showHostPicker,
                child: Text(
                  'Show all ${hosts.length} hosts',
                  style: TextStyle(color: termTheme.cyan),
                ),
              ),
            ],
          ] else ...[
            Text(
              'No hosts configured yet.',
              style: TextStyle(color: dimColor),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Add hosts in the Hosts tab')),
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: termTheme.cyan,
                foregroundColor: termTheme.background,
              ),
              icon: const Icon(Icons.add),
              label: const Text('Add a host'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusBar(TerminalTheme termTheme) {
    final tab = _activeTab;
    final hasSession = tab?.session != null;
    final statusBarColor = Color.lerp(termTheme.background, Colors.black, 0.15)!;
    final textColor = termTheme.foreground;
    final iconColor = termTheme.foreground.withOpacity(0.8);

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: statusBarColor,
        border: Border(
          top: BorderSide(
            color: termTheme.foreground.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
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
                style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.8)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (tab.canReconnect)
              TextButton.icon(
                onPressed: () async {
                  await tab.reconnect();
                  if (mounted) setState(() {});
                },
                icon: Icon(Icons.refresh, size: 16, color: iconColor),
                label: Text(
                  'Reconnect',
                  style: TextStyle(fontSize: 12, color: textColor),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                ),
              ),
            if (tab.isReconnecting)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: iconColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Reconnecting...',
                      style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.8)),
                    ),
                  ],
                ),
              ),
          ] else ...[
            const Expanded(child: SizedBox.shrink()),
          ],
          _KeyButton(
              label: 'Esc',
              textColor: textColor,
              onPressed: hasSession ? () => _sendKey('\x1b') : null),
          _KeyButton(
              label: 'Ctrl+C',
              textColor: textColor,
              onPressed: hasSession ? () => _sendKey('\x03') : null),
          _KeyButton(
              label: 'Ctrl+D',
              textColor: textColor,
              onPressed: hasSession ? () => _sendKey('\x04') : null),
          _KeyButton(
              label: 'Tab',
              textColor: textColor,
              onPressed: hasSession ? () => _sendKey('\t') : null),
          IconButton(
            icon: Icon(Icons.content_paste, size: 18, color: iconColor),
            tooltip: 'Paste',
            onPressed: hasSession ? _pasteToShell : null,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: Icon(Icons.grid_view, size: 18, color: iconColor),
            tooltip: 'tmux sessions',
            onPressed: hasSession ? () => _showTmuxManager(tab!) : null,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: Icon(
              _showLogs ? Icons.expand_more : Icons.expand_less,
              size: 18,
              color: iconColor,
            ),
            tooltip: _showLogs ? 'Hide logs' : 'Show logs',
            onPressed: () => setState(() => _showLogs = !_showLogs),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildLogsDrawer(TerminalTheme termTheme) {
    final tab = _activeTab;
    final logsColor = Color.lerp(termTheme.background, Colors.black, 0.25)!;
    final textColor = termTheme.foreground;

    if (tab == null) {
      return Container(
        height: 120,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: logsColor,
          border: Border(
            top: BorderSide(color: termTheme.foreground.withOpacity(0.1)),
          ),
        ),
        child: Center(
          child: Text('No logs', style: TextStyle(color: textColor.withOpacity(0.5))),
        ),
      );
    }
    return Container(
      height: 150,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: logsColor,
        border: Border(
          top: BorderSide(color: termTheme.foreground.withOpacity(0.1)),
        ),
      ),
      child: tab.logs.isEmpty
          ? Center(
              child: Text('No logs yet', style: TextStyle(color: textColor.withOpacity(0.5))),
            )
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
                      color: _logColor(entry, termTheme),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Color _logColor(String entry, TerminalTheme termTheme) {
    final lower = entry.toLowerCase();
    if (lower.contains('error') ||
        lower.contains('failed') ||
        lower.contains('exception')) {
      return termTheme.red;
    }
    if (lower.contains('authenticated') ||
        lower.contains('auth success') ||
        lower.contains('success') ||
        lower.contains('connected')) {
      return termTheme.green;
    }
    if (lower.contains('warning') ||
        lower.contains('warn') ||
        lower.contains('mismatch')) {
      return termTheme.yellow;
    }
    return termTheme.cyan;
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'logs':
        setState(() => _showLogs = !_showLogs);
        break;
      case 'trusted_keys':
        _showTrustedKeysDialog();
        break;
      case 'terminal_settings':
        _showTerminalSettingsDialog();
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

    // Connect with settings from vault
    final settings = widget.service.currentData?.settings;
    final keepaliveSecs = settings?.sshKeepaliveInterval ?? 30;
    final autoReconnect = settings?.sshAutoReconnect ?? false;
    await tab.connect(
      trustedKeys: _trustedHostKeys,
      onHostKeyPrompt: _handleHostKeyPrompt,
      keepAliveInterval:
          keepaliveSecs > 0 ? Duration(seconds: keepaliveSecs) : null,
      autoReconnect: autoReconnect,
    );

    if (mounted) {
      setState(() {});

      // Handle tmux auto-attach if enabled
      if (host.tmuxEnabled && tab.status == TabConnectionStatus.connected) {
        await _handleTmuxAutoAttach(tab, host);
      }

      // Delay focus to avoid Windows platform exception (200ms for slower machines)
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          // ignore: avoid_print
          print('[TAB-DEBUG] requesting tab focus for tab ${tab.id}');
          tab.focusNode.requestFocus();
        }
      });
    }
  }

  Future<void> _handleTmuxAutoAttach(_ConnectionTab tab, VaultHost host) async {
    // If a specific session name is configured, just attach to it
    if (host.tmuxSessionName != null && host.tmuxSessionName!.isNotEmpty) {
      await tab.attachTmuxSession(host.tmuxSessionName);
      if (mounted) setState(() {});
      return;
    }

    // List existing sessions
    final sessions = await tab.listTmuxSessions();

    if (sessions.isEmpty) {
      // No sessions, create a new one
      await tab.attachTmuxSession(null);
      if (mounted) setState(() {});
      return;
    }

    if (sessions.length == 1) {
      // Only one session, attach to it
      await tab.attachTmuxSession(sessions.first.name);
      if (mounted) setState(() {});
      return;
    }

    // Multiple sessions - show picker
    if (!mounted) return;
    final selected = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _TmuxSessionPickerDialog(sessions: sessions),
    );

    if (selected != null) {
      await tab.attachTmuxSession(selected);
    } else {
      // User cancelled or chose to skip tmux
      tab.attachedTmuxSession = null;
    }

    if (mounted) setState(() {});
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
                autofocus: true,
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

    // Do not dispose the controller here: disposing it after the dialog
    // can race with the TextField still being used by the framework
    // (causes "A TextEditingController was used after being disposed").
    // Let the controller be reclaimed by GC once out of scope.
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

  void _showTerminalSettingsDialog() {
    final currentSettings = widget.service.currentData?.settings;
    showDialog(
      context: context,
      builder: (context) => _TerminalSettingsDialog(
        initialSettings: currentSettings ?? const VaultSettings(),
        onSave: (settings) async {
          await widget.service.updateSettings(settings);
          if (mounted) {
            setState(() {});
          }
        },
      ),
    );
  }

  void _showTmuxManager(_ConnectionTab tab) {
    showDialog(
      context: context,
      builder: (context) => _TmuxSessionManagerDialog(
        tab: tab,
        onSessionAction: (action, sessionName) async {
          await _executeTmuxAction(tab, action, sessionName);
          if (mounted) {
            Navigator.pop(context);
          }
        },
      ),
    );
  }

  Future<void> _executeTmuxAction(
    _ConnectionTab tab,
    TmuxAction action,
    String? sessionName,
  ) async {
    final session = tab.session;
    if (session == null) return;

    String cmd;
    switch (action) {
      case TmuxAction.attach:
        cmd = sessionName != null
            ? 'tmux attach -t $sessionName'
            : 'tmux attach';
        break;
      case TmuxAction.detach:
        // Send Ctrl+B, d to detach from current tmux session
        await session.writeString('\x02d');
        tab.logs.add('Sent tmux detach (Ctrl+B, d)');
        return;
      case TmuxAction.newSession:
        cmd = sessionName != null && sessionName.isNotEmpty
            ? 'tmux new -s $sessionName'
            : 'tmux new';
        break;
      case TmuxAction.killSession:
        if (sessionName == null) return;
        cmd = 'tmux kill-session -t $sessionName';
        break;
    }

    tab.logs.add('Executing: $cmd');
    await session.writeString('$cmd\n');
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
  const _KeyButton({required this.label, this.onPressed, this.textColor});

  final String label;
  final VoidCallback? onPressed;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final color = textColor ?? Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 32),
          visualDensity: VisualDensity.compact,
          foregroundColor: color,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: onPressed != null ? color : color.withOpacity(0.4),
          ),
        ),
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

  /// The currently attached tmux session name (if any).
  String? attachedTmuxSession;

  StreamSubscription<SshConnectionStatus>? _statusSub;
  StreamSubscription<String>? _logSub;
  VoidCallback? _onStatusChange;

  // Auto-reconnect state
  bool _autoReconnectEnabled = false;
  bool _isReconnecting = false;
  bool _userDisconnected = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;

  // Stored connection params for reconnect
  Map<String, Set<String>>? _trustedKeys;
  Future<bool> Function(String, String, String)? _onHostKeyPrompt;
  Duration? _keepAliveInterval;

  String get label => attachedTmuxSession != null
      ? '${host.label} [$attachedTmuxSession]'
      : host.label;
  String get connectionInfo => '${host.username}@${host.hostname}:${host.port}';
  bool get isReconnecting => _isReconnecting;

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
    Duration? keepAliveInterval,
    bool autoReconnect = false,
  }) async {
    // Store params for potential reconnect
    _trustedKeys = trustedKeys;
    _onHostKeyPrompt = onHostKeyPrompt;
    _keepAliveInterval = keepAliveInterval;
    _autoReconnectEnabled = autoReconnect;
    _userDisconnected = false;

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
    // ignore: avoid_print
    print('[SSH-DEBUG] Keepalive: ${keepAliveInterval?.inSeconds ?? 0}s');
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
          keepAliveInterval: keepAliveInterval,
          onHostKeyVerify: (type, fp) => _handleHostKey(
            type,
            fp,
            trustedKeys,
            onHostKeyPrompt,
          ),
        ),
      );

      // Mark connected so shell startup does not skip input wiring.
      status = TabConnectionStatus.connected;
      _onStatusChange?.call();

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
    if (session != null) return;

    await bridge.ready;
    bridge.resetTerminal();

    final newSession = await manager.startShell(
      ptyConfig: SshPtyConfig(
        width: bridge.viewWidth,
        height: bridge.viewHeight,
      ),
    );

    session = newSession;
    bridge.attachStreams(stdout: newSession.stdout, stderr: newSession.stderr);
    bridge.onOutput = (data) => newSession.writeString(data);
    bridge.onResize = (cols, rows) => newSession.resize(cols, rows);

    _addLog('Shell opened');
    _reconnectAttempts = 0; // Reset on successful connection

    unawaited(newSession.done.whenComplete(() {
      session = null;
      _addLog('Shell closed');
      _onStatusChange?.call();

      // Attempt auto-reconnect if enabled and not user-initiated
      if (_autoReconnectEnabled && !_userDisconnected && !_isReconnecting) {
        _attemptReconnect();
      }
    }));
  }

  /// Attempts to reconnect with exponential backoff.
  Future<void> _attemptReconnect() async {
    if (_isReconnecting) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      bridge.write('\r\n[Auto-reconnect] Max attempts reached. Use manual reconnect.\r\n');
      _addLog('Auto-reconnect: max attempts reached');
      return;
    }

    _isReconnecting = true;
    _reconnectAttempts++;

    // Exponential backoff: 1s, 2s, 4s, 8s, 16s
    final delay = Duration(seconds: 1 << (_reconnectAttempts - 1));
    bridge.write('\r\n[Auto-reconnect] Attempt $_reconnectAttempts/$_maxReconnectAttempts in ${delay.inSeconds}s...\r\n');
    _addLog('Auto-reconnect: attempt $_reconnectAttempts in ${delay.inSeconds}s');

    await Future.delayed(delay);

    // Check if user cancelled or tab was closed
    if (_userDisconnected || _trustedKeys == null || _onHostKeyPrompt == null) {
      _isReconnecting = false;
      return;
    }

    try {
      bridge.write('[Auto-reconnect] Connecting...\r\n');
      await manager.connect(
        SshTarget(
          host: host.hostname,
          port: host.port,
          username: host.username,
          password: password?.isNotEmpty == true ? password : null,
          privateKey: identity?.privateKey,
          passphrase: identity?.passphrase,
          keepAliveInterval: _keepAliveInterval,
          onHostKeyVerify: (type, fp) => _handleHostKey(
            type,
            fp,
            _trustedKeys!,
            _onHostKeyPrompt!,
          ),
        ),
      );

      status = TabConnectionStatus.connected;
      _onStatusChange?.call();

      bridge.write('[Auto-reconnect] Connected! Opening shell...\r\n');
      _addLog('Auto-reconnect: success');

      await _startShell();

      // Re-attach tmux if was attached before
      if (attachedTmuxSession != null) {
        await attachTmuxSession(attachedTmuxSession);
      }

      _isReconnecting = false;
    } catch (e) {
      _isReconnecting = false;
      final msg = e is SshException ? e.message : e.toString();
      bridge.write('[Auto-reconnect] Failed: $msg\r\n');
      _addLog('Auto-reconnect failed: $msg');

      // Try again if we haven't exceeded max attempts
      if (_reconnectAttempts < _maxReconnectAttempts && !_userDisconnected) {
        unawaited(_attemptReconnect());
      }
    }
  }

  /// Cancels auto-reconnect and marks as user-disconnected.
  void cancelReconnect() {
    _userDisconnected = true;
    _isReconnecting = false;
    bridge.write('[Auto-reconnect] Cancelled by user.\r\n');
    _addLog('Auto-reconnect: cancelled');
  }

  /// Whether the tab can be manually reconnected.
  bool get canReconnect =>
      !_isReconnecting &&
      (status == TabConnectionStatus.disconnected ||
          status == TabConnectionStatus.error) &&
      _trustedKeys != null &&
      _onHostKeyPrompt != null;

  /// Manually reconnect the tab.
  Future<void> reconnect() async {
    if (!canReconnect) return;

    _userDisconnected = false;
    _reconnectAttempts = 0;
    bridge.write('\r\n[Reconnect] Connecting...\r\n');
    _addLog('Manual reconnect initiated');

    status = TabConnectionStatus.connecting;
    _onStatusChange?.call();

    try {
      await manager.connect(
        SshTarget(
          host: host.hostname,
          port: host.port,
          username: host.username,
          password: password?.isNotEmpty == true ? password : null,
          privateKey: identity?.privateKey,
          passphrase: identity?.passphrase,
          keepAliveInterval: _keepAliveInterval,
          onHostKeyVerify: (type, fp) => _handleHostKey(
            type,
            fp,
            _trustedKeys!,
            _onHostKeyPrompt!,
          ),
        ),
      );

      status = TabConnectionStatus.connected;
      _onStatusChange?.call();

      bridge.write('[Reconnect] Connected! Opening shell...\r\n');
      _addLog('Reconnect: success');

      await _startShell();

      // Re-attach tmux if was attached before
      if (attachedTmuxSession != null && host.tmuxEnabled) {
        await attachTmuxSession(attachedTmuxSession);
      }
    } catch (e) {
      status = TabConnectionStatus.error;
      _onStatusChange?.call();
      final msg = e is SshException ? e.message : e.toString();
      bridge.write('[Reconnect] Failed: $msg\r\n');
      _addLog('Reconnect failed: $msg');
    }
  }

  /// Lists tmux sessions on the remote host.
  Future<List<TmuxSession>> listTmuxSessions() async {
    try {
      final result = await manager.runCommand('tmux list-sessions 2>/dev/null');
      if (result.exitCode != 0 || result.stdout.isEmpty) {
        return [];
      }
      return TmuxSession.parseListSessions(result.stdout);
    } catch (e) {
      _addLog('Failed to list tmux sessions: $e');
      return [];
    }
  }

  /// Sends the tmux attach command for the specified session.
  Future<void> attachTmuxSession(String? sessionName) async {
    final shellSession = session;
    if (shellSession == null) return;

    // Small delay to let the shell initialize
    await Future.delayed(const Duration(milliseconds: 300));

    String tmuxCmd;
    if (sessionName != null && sessionName.isNotEmpty) {
      // Attach to named session or create it
      tmuxCmd = 'tmux attach -t $sessionName 2>/dev/null || tmux new -s $sessionName';
      attachedTmuxSession = sessionName;
    } else {
      // Attach to any existing session or create default
      tmuxCmd = 'tmux attach 2>/dev/null || tmux new';
      attachedTmuxSession = 'default';
    }

    _addLog('Auto-attaching tmux: $tmuxCmd');
    await shellSession.writeString('$tmuxCmd\n');
    _onStatusChange?.call();
  }

  Future<void> dispose() async {
    _userDisconnected = true; // Prevent auto-reconnect
    unawaited(_statusSub?.cancel());
    unawaited(_logSub?.cancel());
    bridge.onOutput = null;
    bridge.onResize = null;
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

// -----------------------------------------------------------------------------
// Terminal Settings Dialog
// -----------------------------------------------------------------------------

class _TerminalSettingsDialog extends StatefulWidget {
  const _TerminalSettingsDialog({
    required this.initialSettings,
    required this.onSave,
  });

  final VaultSettings initialSettings;
  final Future<void> Function(VaultSettings) onSave;

  @override
  State<_TerminalSettingsDialog> createState() => _TerminalSettingsDialogState();
}

class _TerminalSettingsDialogState extends State<_TerminalSettingsDialog> {
  late String _themeName;
  late double _fontSize;
  late String? _fontFamily;
  late double _opacity;
  late String _cursorStyle;

  @override
  void initState() {
    super.initState();
    _themeName = widget.initialSettings.terminalTheme;
    _fontSize = widget.initialSettings.terminalFontSize;
    _fontFamily = widget.initialSettings.terminalFontFamily;
    _opacity = widget.initialSettings.terminalOpacity;
    _cursorStyle = widget.initialSettings.terminalCursorStyle;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Terminal Settings'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Theme selector
              Text('Theme', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _themeName,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: TerminalThemePresets.themeNames
                    .map((name) => DropdownMenuItem(
                          value: name,
                          child: Text(_formatThemeName(name)),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _themeName = value);
                  }
                },
              ),
              const SizedBox(height: 16),

              // Font size slider
              Text('Font Size: ${_fontSize.toInt()}',
                  style: Theme.of(context).textTheme.titleSmall),
              Slider(
                value: _fontSize,
                min: 8,
                max: 24,
                divisions: 16,
                label: _fontSize.toInt().toString(),
                onChanged: (value) => setState(() => _fontSize = value),
              ),
              const SizedBox(height: 16),

              // Font family (optional text field)
              Text('Font Family',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: _fontFamily ?? '',
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'monospace (default)',
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onChanged: (value) {
                  _fontFamily = value.isEmpty ? null : value;
                },
              ),
              const SizedBox(height: 16),

              // Opacity slider
              Text('Background Opacity: ${(_opacity * 100).toInt()}%',
                  style: Theme.of(context).textTheme.titleSmall),
              Slider(
                value: _opacity,
                min: 0.5,
                max: 1.0,
                divisions: 10,
                label: '${(_opacity * 100).toInt()}%',
                onChanged: (value) => setState(() => _opacity = value),
              ),
              const SizedBox(height: 16),

              // Cursor style selector
              Text('Cursor Style',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'block', label: Text('Block')),
                  ButtonSegment(value: 'underline', label: Text('Underline')),
                  ButtonSegment(value: 'bar', label: Text('Bar')),
                ],
                selected: {_cursorStyle},
                onSelectionChanged: (selection) {
                  setState(() => _cursorStyle = selection.first);
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saveSettings,
          child: const Text('Save'),
        ),
      ],
    );
  }

  String _formatThemeName(String name) {
    return name
        .split('-')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  Future<void> _saveSettings() async {
    final newSettings = widget.initialSettings.copyWith(
      terminalTheme: _themeName,
      terminalFontSize: _fontSize,
      terminalFontFamily: _fontFamily,
      terminalOpacity: _opacity,
      terminalCursorStyle: _cursorStyle,
    );
    await widget.onSave(newSettings);
    if (mounted) {
      Navigator.pop(context);
    }
  }
}

// -----------------------------------------------------------------------------
// tmux Session Manager
// -----------------------------------------------------------------------------

enum TmuxAction { attach, detach, newSession, killSession }

/// Represents a parsed tmux session from `tmux list-sessions` output.
class TmuxSession {
  const TmuxSession({
    required this.name,
    required this.windows,
    required this.created,
    this.attached = false,
  });

  final String name;
  final int windows;
  final String created;
  final bool attached;

  /// Parse tmux list-sessions output.
  /// Format: "session_name: N windows (created Day Mon DD HH:MM:SS YYYY) (attached)"
  static List<TmuxSession> parseListSessions(String output) {
    final sessions = <TmuxSession>[];
    final lines = output.split('\n').where((l) => l.trim().isNotEmpty);

    for (final line in lines) {
      // Skip error messages
      if (line.startsWith('error:') ||
          line.startsWith('no server') ||
          line.contains('no sessions')) {
        continue;
      }

      // Parse: "name: N windows (created ...)"
      final colonIdx = line.indexOf(':');
      if (colonIdx < 0) continue;

      final name = line.substring(0, colonIdx).trim();
      final rest = line.substring(colonIdx + 1).trim();

      // Extract window count
      final windowsMatch = RegExp(r'(\d+) windows?').firstMatch(rest);
      final windows = windowsMatch != null
          ? int.tryParse(windowsMatch.group(1) ?? '1') ?? 1
          : 1;

      // Check if attached
      final attached = rest.contains('(attached)');

      // Extract created time (simplified)
      final createdMatch = RegExp(r'\(created ([^)]+)\)').firstMatch(rest);
      final created = createdMatch?.group(1) ?? '';

      sessions.add(TmuxSession(
        name: name,
        windows: windows,
        created: created,
        attached: attached,
      ));
    }

    return sessions;
  }
}

class _TmuxSessionManagerDialog extends StatefulWidget {
  const _TmuxSessionManagerDialog({
    required this.tab,
    required this.onSessionAction,
  });

  final _ConnectionTab tab;
  final Future<void> Function(TmuxAction action, String? sessionName)
      onSessionAction;

  @override
  State<_TmuxSessionManagerDialog> createState() =>
      _TmuxSessionManagerDialogState();
}

class _TmuxSessionManagerDialogState extends State<_TmuxSessionManagerDialog> {
  List<TmuxSession>? _sessions;
  bool _loading = true;
  String? _error;
  final _newSessionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Run tmux list-sessions and capture output
      // We'll send the command and parse the terminal buffer after a delay
      final session = widget.tab.session;
      if (session == null) {
        setState(() {
          _loading = false;
          _error = 'No active session';
        });
        return;
      }

      // Clear some buffer space and send command
      await session.writeString('tmux list-sessions 2>&1\n');

      // Wait for output
      await Future.delayed(const Duration(milliseconds: 500));

      // For now, we'll just show an empty list with action buttons
      // Real implementation would capture the output from a separate channel
      // or use exec instead of shell for this command
      setState(() {
        _loading = false;
        _sessions = []; // Placeholder - real parsing would happen here
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.grid_view),
          const SizedBox(width: 12),
          const Expanded(child: Text('tmux Sessions')),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadSessions,
            tooltip: 'Refresh',
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        height: 350,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Quick actions
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () =>
                      widget.onSessionAction(TmuxAction.newSession, null),
                  icon: const Icon(Icons.add),
                  label: const Text('New session'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      widget.onSessionAction(TmuxAction.attach, null),
                  icon: const Icon(Icons.login),
                  label: const Text('Attach (default)'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      widget.onSessionAction(TmuxAction.detach, null),
                  icon: const Icon(Icons.logout),
                  label: const Text('Detach'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // New session with name
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newSessionController,
                    decoration: const InputDecoration(
                      hintText: 'Session name (optional)',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    final name = _newSessionController.text.trim();
                    widget.onSessionAction(
                      TmuxAction.newSession,
                      name.isEmpty ? null : name,
                    );
                  },
                  child: const Text('Create'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            // Session list header
            Text(
              'Active Sessions',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),

            // Session list
            Expanded(
              child: _buildSessionList(),
            ),

            // Tip
            const SizedBox(height: 8),
            Text(
              'Tip: Press Ctrl+B, d to detach from tmux',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildSessionList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade400, size: 32),
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loadSessions,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final sessions = _sessions;
    if (sessions == null || sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.grid_view, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            const Text(
              'Use "tmux list-sessions" to see sessions.\n'
              'Session list auto-detection coming soon.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        final session = sessions[index];
        return ListTile(
          leading: Icon(
            session.attached ? Icons.visibility : Icons.grid_view,
            color: session.attached ? Colors.green : null,
          ),
          title: Text(session.name),
          subtitle: Text(
            '${session.windows} window${session.windows > 1 ? 's' : ''}'
            '${session.attached ? ' (attached)' : ''}',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!session.attached)
                IconButton(
                  icon: const Icon(Icons.login),
                  tooltip: 'Attach',
                  onPressed: () => widget.onSessionAction(
                    TmuxAction.attach,
                    session.name,
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Kill session',
                onPressed: () => _confirmKillSession(session.name),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmKillSession(String sessionName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kill session?'),
        content: Text('Are you sure you want to kill tmux session "$sessionName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Kill'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.onSessionAction(TmuxAction.killSession, sessionName);
    }
  }
}

// -----------------------------------------------------------------------------
// tmux Session Picker Dialog (shown when multiple sessions exist)
// -----------------------------------------------------------------------------

class _TmuxSessionPickerDialog extends StatelessWidget {
  const _TmuxSessionPickerDialog({required this.sessions});

  final List<TmuxSession> sessions;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.grid_view),
          SizedBox(width: 12),
          Text('Select tmux Session'),
        ],
      ),
      content: SizedBox(
        width: 350,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Multiple tmux sessions found. Choose one to attach:',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: sessions.length,
                itemBuilder: (context, index) {
                  final session = sessions[index];
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        session.attached ? Icons.visibility : Icons.grid_view,
                        color: session.attached ? Colors.green : null,
                      ),
                      title: Text(
                        session.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${session.windows} window${session.windows > 1 ? 's' : ''}'
                        '${session.attached ? ' • attached' : ''}',
                      ),
                      onTap: () => Navigator.pop(context, session.name),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Create new session'),
              contentPadding: EdgeInsets.zero,
              onTap: () => Navigator.pop(context, ''),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Skip tmux'),
        ),
      ],
    );
  }
}
