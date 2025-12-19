library ui_terminal;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// Controller to bridge SSH streams into an xterm instance.
class TerminalBridge {
  TerminalBridge({Terminal? initialTerminal})
      : terminal = initialTerminal ??
            Terminal(
              maxLines: 2000,
            ) {
    terminal.onOutput = (data) {
      onOutput?.call(data);
    };
  }

  final Terminal terminal;
  final List<StreamSubscription<List<int>>> _subscriptions = [];

  /// Called when the user types into the terminal; forward to SSH stdin.
  void Function(String data)? onOutput;

  /// Attach stdout/stderr streams from SSH and write into terminal.
  void attachStreams({
    required Stream<List<int>> stdout,
    required Stream<List<int>> stderr,
  }) {
    _cancelSubscriptions();
    _subscriptions.add(
      stdout.listen((data) => terminal.write(String.fromCharCodes(data))),
    );
    _subscriptions.add(
      stderr.listen((data) => terminal.write(String.fromCharCodes(data))),
    );
  }

  void write(String data) => terminal.write(data);

  void resize(int cols, int rows) {
    terminal.resize(cols, rows);
  }

  void dispose() {
    _cancelSubscriptions();
    terminal.onOutput = null;
  }

  void _cancelSubscriptions() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }
}

/// Terminal widget built on xterm.
class VibedTerminalView extends StatefulWidget {
  const VibedTerminalView({
    super.key,
    required this.bridge,
    this.focusNode,
    this.autofocus = false,
  });

  final TerminalBridge bridge;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<VibedTerminalView> createState() => _VibedTerminalViewState();
}

class _VibedTerminalViewState extends State<VibedTerminalView> {
  FocusNode? _internalFocusNode;
  bool _activated = false;

  FocusNode? get _effectiveFocusNode => widget.focusNode ?? _internalFocusNode;

  @override
  void dispose() {
    // Only dispose focus node if we created it here.
    if (_internalFocusNode != null) {
      _internalFocusNode!.dispose();
    }
    super.dispose();
  }

  void _activateFocus() {
    if (_activated) return;
    if (widget.focusNode != null) {
      // external focus node provided, just request focus on it
      widget.focusNode!.requestFocus();
      _activated = true;
      return;
    }
    // create internal focus node and rebuild to attach it to TerminalView
    _internalFocusNode = FocusNode();
    _activated = true;
    setState(() {});
    // request focus in a post frame callback
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          _internalFocusNode!.requestFocus();
        } catch (_) {}
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // If no focus node is attached yet, wrap in GestureDetector to enable onTap activation.
    if (_effectiveFocusNode == null) {
      return GestureDetector(
        onTap: _activateFocus,
        child: TerminalView(
          widget.bridge.terminal,
          backgroundOpacity: 0.95,
          autofocus: false,
          padding: const EdgeInsets.all(8),
        ),
      );
    }

    return TerminalView(
      widget.bridge.terminal,
      backgroundOpacity: 0.95,
      autofocus: widget.autofocus,
      focusNode: _effectiveFocusNode,
      padding: const EdgeInsets.all(8),
    );
  }
}
