library ui_terminal;

import 'package:flutter/material.dart';

/// Placeholder terminal widget. Will wrap xterm and provide extra key row on
/// Android in later stages.
class VibedTerminal extends StatelessWidget {
  const VibedTerminal({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: const Text(
        'Terminal placeholder',
        style: TextStyle(color: Colors.greenAccent),
      ),
    );
  }
}
