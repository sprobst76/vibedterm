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
