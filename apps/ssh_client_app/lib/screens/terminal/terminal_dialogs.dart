part of 'terminal_screen.dart';

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
// Port Forwarding Dialog
// -----------------------------------------------------------------------------

class _PortForwardingDialog extends StatefulWidget {
  const _PortForwardingDialog({
    required this.tab,
    required this.onForwardChanged,
  });

  final _ConnectionTab tab;
  final VoidCallback onForwardChanged;

  @override
  State<_PortForwardingDialog> createState() => _PortForwardingDialogState();
}

class _PortForwardingDialogState extends State<_PortForwardingDialog> {
  String _type = 'local';
  final _localHostController = TextEditingController(text: 'localhost');
  final _localPortController = TextEditingController();
  final _remoteHostController = TextEditingController(text: 'localhost');
  final _remotePortController = TextEditingController();
  bool _isStarting = false;
  String? _error;

  @override
  void dispose() {
    _localHostController.dispose();
    _localPortController.dispose();
    _remoteHostController.dispose();
    _remotePortController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final forwards = widget.tab.manager.activeForwards;

    return AlertDialog(
      title: const Text('Port Forwarding'),
      content: SizedBox(
        width: 450,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Active forwards
              if (forwards.isNotEmpty) ...[
                Text('Active Forwards',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                ...forwards.where((f) => f.active).map(_buildForwardTile),
                const Divider(height: 24),
              ],

              // Add new forward
              Text('New Forward',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 12),

              // Type selector
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'local',
                    label: Text('Local'),
                    icon: Icon(Icons.arrow_forward, size: 16),
                  ),
                  ButtonSegment(
                    value: 'remote',
                    label: Text('Remote'),
                    icon: Icon(Icons.arrow_back, size: 16),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (sel) =>
                    setState(() => _type = sel.first),
              ),
              const SizedBox(height: 8),

              // Description text
              Text(
                _type == 'local'
                    ? 'Listen locally, forward traffic to remote host'
                    : 'Listen on remote server, forward traffic to local host',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),

              // Local host/port row
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _localHostController,
                      decoration: const InputDecoration(
                        labelText: 'Local host',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _localPortController,
                      decoration: const InputDecoration(
                        labelText: 'Local port',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Remote host/port row
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _remoteHostController,
                      decoration: const InputDecoration(
                        labelText: 'Remote host',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _remotePortController,
                      decoration: const InputDecoration(
                        labelText: 'Remote port',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),

              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],

              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _isStarting ? null : _startForward,
                  icon: _isStarting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: const Text('Start'),
                ),
              ),
            ],
          ),
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

  Widget _buildForwardTile(ActivePortForward forward) {
    final rule = forward.rule;
    final icon = rule.type == 'local' ? Icons.arrow_forward : Icons.arrow_back;
    final label = rule.type == 'local'
        ? '${rule.localHost}:${rule.localPort} \u2192 ${rule.remoteHost}:${rule.remotePort}'
        : '${rule.remoteHost}:${rule.remotePort} \u2192 ${rule.localHost}:${rule.localPort}';

    return ListTile(
      leading: Icon(icon, size: 20),
      title: Text(label, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
      subtitle: Text(rule.type == 'local' ? 'Local forward' : 'Remote forward'),
      trailing: IconButton(
        icon: const Icon(Icons.stop_circle_outlined, color: Colors.red),
        tooltip: 'Stop',
        onPressed: () async {
          await widget.tab.manager.stopForward(forward);
          widget.onForwardChanged();
          if (mounted) setState(() {});
        },
      ),
      dense: true,
      contentPadding: EdgeInsets.zero,
    );
  }

  Future<void> _startForward() async {
    final localPort = int.tryParse(_localPortController.text.trim());
    final remotePort = int.tryParse(_remotePortController.text.trim());
    final localHost = _localHostController.text.trim();
    final remoteHost = _remoteHostController.text.trim();

    if (localPort == null || localPort < 1 || localPort > 65535) {
      setState(() => _error = 'Invalid local port');
      return;
    }
    if (remotePort == null || remotePort < 1 || remotePort > 65535) {
      setState(() => _error = 'Invalid remote port');
      return;
    }
    if (localHost.isEmpty) {
      setState(() => _error = 'Local host is required');
      return;
    }
    if (remoteHost.isEmpty) {
      setState(() => _error = 'Remote host is required');
      return;
    }

    setState(() {
      _isStarting = true;
      _error = null;
    });

    try {
      final rule = PortForwardRule(
        type: _type,
        localHost: localHost,
        localPort: localPort,
        remoteHost: remoteHost,
        remotePort: remotePort,
      );

      if (_type == 'local') {
        await widget.tab.manager.startLocalForward(rule);
      } else {
        await widget.tab.manager.startRemoteForward(rule);
      }

      widget.onForwardChanged();
      if (mounted) {
        setState(() {
          _isStarting = false;
          _localPortController.clear();
          _remotePortController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isStarting = false;
          _error = e.toString();
        });
      }
    }
  }
}
