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
class VibedTerminalView extends StatelessWidget {
  const VibedTerminalView({
    super.key,
    required this.bridge,
  });

  final TerminalBridge bridge;

  @override
  Widget build(BuildContext context) {
    return TerminalView(
      bridge.terminal,
      backgroundOpacity: 0.95,
      autofocus: true,
      padding: const EdgeInsets.all(8),
    );
  }
}
