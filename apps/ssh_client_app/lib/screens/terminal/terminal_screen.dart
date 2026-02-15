import 'dart:async';

import 'package:core_ssh/core_ssh.dart';
import 'package:core_vault/core_vault.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui_terminal/ui_terminal.dart';
import 'package:uuid/uuid.dart';

import '../../services/vault_service.dart';

part 'connection_tab.dart';
part 'terminal_dialogs.dart';
part 'terminal_widgets.dart';
part 'tmux_widgets.dart';

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

    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Container(
        color: termTheme.background,
        child: Column(
          children: [
            _buildTabBar(termTheme),
            Expanded(child: _buildTerminalArea(termTheme)),
            if (_isMobilePlatform(context)) _buildExtraKeyRow(termTheme),
            _buildStatusBar(termTheme),
            if (_showLogs) _buildLogsDrawer(termTheme),
          ],
        ),
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (!ctrl) return KeyEventResult.ignored;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    // Ctrl+Tab / Ctrl+Shift+Tab — cycle tabs
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      if (shift) {
        _switchToPreviousTab();
      } else {
        _switchToNextTab();
      }
      return KeyEventResult.handled;
    }

    // Ctrl+1..9 — jump to tab by index
    final digitIndex = _digitKeyIndex(event.logicalKey);
    if (digitIndex != null) {
      _switchToTab(digitIndex);
      return KeyEventResult.handled;
    }

    // Ctrl+T — new connection
    if (event.logicalKey == LogicalKeyboardKey.keyT && !shift) {
      _showHostPicker();
      return KeyEventResult.handled;
    }

    // Ctrl+W — close current tab
    if (event.logicalKey == LogicalKeyboardKey.keyW && !shift) {
      final tab = _activeTab;
      if (tab != null) _confirmCloseTab(tab);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _switchToNextTab() {
    if (_tabController == null || _tabs.length < 2) return;
    _tabController!.animateTo((_tabController!.index + 1) % _tabs.length);
  }

  void _switchToPreviousTab() {
    if (_tabController == null || _tabs.length < 2) return;
    _tabController!.animateTo(
      (_tabController!.index - 1 + _tabs.length) % _tabs.length,
    );
  }

  void _switchToTab(int index) {
    if (_tabController == null || index >= _tabs.length) return;
    _tabController!.animateTo(index);
  }

  /// Returns 0-based tab index for Ctrl+1..9 keys, or null if not a digit key.
  int? _digitKeyIndex(LogicalKeyboardKey key) {
    const digitKeys = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    final idx = digitKeys.indexOf(key);
    return idx >= 0 ? idx : null;
  }

  Widget _buildTabBar(TerminalTheme termTheme) {
    // Create a slightly lighter/darker shade for the tab bar
    final tabBarColor = Color.lerp(termTheme.background, termTheme.foreground, 0.08)!;
    final textColor = termTheme.foreground;
    final iconColor = termTheme.foreground.withValues(alpha:0.8);

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: tabBarColor,
        border: Border(
          bottom: BorderSide(
            color: termTheme.foreground.withValues(alpha:0.1),
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
                      style: TextStyle(color: textColor.withValues(alpha:0.6)),
                    ),
                  )
                : Theme(
                    data: Theme.of(context).copyWith(
                      tabBarTheme: TabBarThemeData(
                        labelColor: textColor,
                        unselectedLabelColor: textColor.withValues(alpha:0.6),
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
              child: Icon(Icons.close, size: 16, color: textColor.withValues(alpha:0.7)),
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
          color: termTheme.foreground.withValues(alpha:0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.3),
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
    final dimColor = termTheme.foreground.withValues(alpha:0.6);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.terminal,
            size: 64,
            color: termTheme.cyan.withValues(alpha:0.7),
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
                  side: BorderSide(color: termTheme.foreground.withValues(alpha:0.3)),
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
    final iconColor = termTheme.foreground.withValues(alpha:0.8);

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: statusBarColor,
        border: Border(
          top: BorderSide(
            color: termTheme.foreground.withValues(alpha:0.1),
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
                style: TextStyle(fontSize: 12, color: textColor.withValues(alpha:0.8)),
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
                      style: TextStyle(fontSize: 12, color: textColor.withValues(alpha:0.8)),
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
            icon: Icon(Icons.code, size: 18, color: iconColor),
            tooltip: 'Snippets',
            onPressed: hasSession ? _showSnippetPicker : null,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: Icon(Icons.grid_view, size: 18, color: iconColor),
            tooltip: 'tmux sessions',
            onPressed: hasSession ? () => _showTmuxQuickSwitch(tab!) : null,
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

  bool _isMobilePlatform(BuildContext context) {
    final platform = Theme.of(context).platform;
    return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  }

  Widget _buildExtraKeyRow(TerminalTheme termTheme) {
    final hasSession = _activeTab?.session != null;
    final barColor = Color.lerp(termTheme.background, Colors.black, 0.1)!;
    final textColor = termTheme.foreground;

    VoidCallback? key(String data) =>
        hasSession ? () => _sendKey(data) : null;

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: barColor,
        border: Border(
          top: BorderSide(
            color: termTheme.foreground.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            // Common control keys
            _KeyButton(label: 'Esc', textColor: textColor, onPressed: key('\x1b')),
            _KeyButton(label: 'Tab', textColor: textColor, onPressed: key('\t')),
            _KeyButton(label: 'Ctrl+C', textColor: textColor, onPressed: key('\x03')),
            _KeyButton(label: 'Ctrl+D', textColor: textColor, onPressed: key('\x04')),
            _KeyButton(label: 'Ctrl+Z', textColor: textColor, onPressed: key('\x1a')),
            _KeyButton(label: 'Ctrl+L', textColor: textColor, onPressed: key('\x0c')),
            _KeyButton(label: 'Ctrl+A', textColor: textColor, onPressed: key('\x01')),
            _KeyButton(label: 'Ctrl+R', textColor: textColor, onPressed: key('\x12')),
            // Arrow keys
            _KeyButton(label: '\u2191', textColor: textColor, onPressed: key('\x1b[A')),
            _KeyButton(label: '\u2193', textColor: textColor, onPressed: key('\x1b[B')),
            _KeyButton(label: '\u2190', textColor: textColor, onPressed: key('\x1b[D')),
            _KeyButton(label: '\u2192', textColor: textColor, onPressed: key('\x1b[C')),
            // Navigation
            _KeyButton(label: 'Home', textColor: textColor, onPressed: key('\x1b[H')),
            _KeyButton(label: 'End', textColor: textColor, onPressed: key('\x1b[F')),
            _KeyButton(label: 'PgUp', textColor: textColor, onPressed: key('\x1b[5~')),
            _KeyButton(label: 'PgDn', textColor: textColor, onPressed: key('\x1b[6~')),
            // Special characters hard to type on mobile
            _KeyButton(label: '|', textColor: textColor, onPressed: key('|')),
            _KeyButton(label: '~', textColor: textColor, onPressed: key('~')),
            _KeyButton(label: '`', textColor: textColor, onPressed: key('`')),
            _KeyButton(label: r'\', textColor: textColor, onPressed: key(r'\')),
            _KeyButton(label: '/', textColor: textColor, onPressed: key('/')),
            _KeyButton(label: '-', textColor: textColor, onPressed: key('-')),
          ],
        ),
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
            top: BorderSide(color: termTheme.foreground.withValues(alpha:0.1)),
          ),
        ),
        child: Center(
          child: Text('No logs', style: TextStyle(color: textColor.withValues(alpha:0.5))),
        ),
      );
    }
    return Container(
      height: 150,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: logsColor,
        border: Border(
          top: BorderSide(color: termTheme.foreground.withValues(alpha:0.1)),
        ),
      ),
      child: tab.logs.isEmpty
          ? Center(
              child: Text('No logs yet', style: TextStyle(color: textColor.withValues(alpha:0.5))),
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

  Future<void> _showSnippetPicker() async {
    final snippets = widget.service.currentData?.snippets ?? [];
    if (snippets.isEmpty) {
      _showMessage('No snippets. Add snippets in the Hosts screen.');
      return;
    }

    final selected = await showDialog<VaultSnippet>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Send snippet'),
          children: snippets.map((snippet) {
            return SimpleDialogOption(
              onPressed: () => Navigator.pop(context, snippet),
              child: ListTile(
                leading: const Icon(Icons.code, size: 20),
                title: Text(snippet.title),
                subtitle: Text(
                  snippet.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            );
          }).toList(),
        );
      },
    );

    if (selected == null) return;
    final tab = _activeTab;
    if (tab?.session == null) return;
    await tab!.session!.writeString(selected.content);
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

  Future<void> _showTmuxQuickSwitch(_ConnectionTab tab) async {
    final sessions = await tab.listTmuxSessions();
    if (!mounted) return;

    final termTheme = _currentTerminalTheme;
    final textColor = termTheme.foreground;
    final currentSession = tab.attachedTmuxSession;

    final RenderBox button = context.findRenderObject() as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    // Position near the tmux icon in the status bar
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset(button.size.width - 200, 0),
            ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    final result = await showMenu<String>(
      context: context,
      position: position,
      items: [
        // Header
        const PopupMenuItem<String>(
          enabled: false,
          child: Text(
            'tmux Sessions',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        const PopupMenuDivider(),
        // Session list
        ...sessions.map((s) {
          final isCurrent = s.name == currentSession;
          return PopupMenuItem<String>(
            value: s.name,
            child: Row(
              children: [
                Icon(
                  isCurrent ? Icons.check_circle : Icons.grid_view,
                  size: 16,
                  color: isCurrent ? Colors.green : textColor.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.name,
                    style: isCurrent
                        ? const TextStyle(fontWeight: FontWeight.bold)
                        : null,
                  ),
                ),
                Text(
                  '${s.windows}w',
                  style: TextStyle(
                    fontSize: 11,
                    color: textColor.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          );
        }),
        if (sessions.isNotEmpty) const PopupMenuDivider(),
        // New session
        const PopupMenuItem<String>(
          value: '_new',
          child: Row(
            children: [
              Icon(Icons.add, size: 16),
              SizedBox(width: 8),
              Text('New session'),
            ],
          ),
        ),
        // Detach
        if (currentSession != null)
          const PopupMenuItem<String>(
            value: '_detach',
            child: Row(
              children: [
                Icon(Icons.logout, size: 16),
                SizedBox(width: 8),
                Text('Detach'),
              ],
            ),
          ),
        const PopupMenuDivider(),
        // Full manager
        const PopupMenuItem<String>(
          value: '_manager',
          child: Row(
            children: [
              Icon(Icons.settings, size: 16),
              SizedBox(width: 8),
              Text('Session Manager...'),
            ],
          ),
        ),
      ],
    );

    if (result == null || !mounted) return;

    switch (result) {
      case '_new':
        await _executeTmuxAction(tab, TmuxAction.newSession, null);
      case '_detach':
        await _executeTmuxAction(tab, TmuxAction.detach, null);
      case '_manager':
        _showTmuxManager(tab);
      default:
        // Switch to selected session
        if (result != currentSession) {
          await _executeTmuxAction(tab, TmuxAction.switchSession, result);
        }
    }

    if (mounted) setState(() {});
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
        tab.attachedTmuxSession = null;
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
      case TmuxAction.switchSession:
        if (sessionName == null) return;
        await tab.switchTmuxSession(sessionName);
        return;
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
