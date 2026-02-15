part of 'terminal_screen.dart';

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
  SftpClient? _sftpClient;
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

  /// Returns a lazily-initialized SFTP client for this connection.
  Future<SftpClient> getSftpClient() async {
    _sftpClient ??= await manager.openSftp();
    return _sftpClient!;
  }

  /// Switches from the current tmux session to a different one.
  Future<void> switchTmuxSession(String targetSession) async {
    final shellSession = session;
    if (shellSession == null) return;

    _addLog('Switching tmux session to: $targetSession');
    await shellSession.writeString('tmux switch-client -t $targetSession\n');
    attachedTmuxSession = targetSession;
    _onStatusChange?.call();
  }

  Future<void> dispose() async {
    _userDisconnected = true; // Prevent auto-reconnect
    unawaited(_statusSub?.cancel());
    unawaited(_logSub?.cancel());
    bridge.onOutput = null;
    bridge.onResize = null;
    _sftpClient?.close();
    _sftpClient = null;
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
