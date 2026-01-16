library ui_terminal;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  /// Debug wrapper to observe writes from key handling.
  void debugWrite(String data) => terminal.write(data);

  void resize(int cols, int rows) {
    terminal.resize(cols, rows);
  }

  void dispose() {
    _cancelSubscriptions();
    terminal.onOutput = null;
  }

  /// Try to read selected text from the underlying xterm Terminal instance.
  /// Returns null when no selection or not accessible.
  String? getSelectedText() {
    try {
      final t = terminal as dynamic;
      // common direct properties
      try {
        final v = t.selectedText;
        if (v is String && v.isNotEmpty) return v;
      } catch (_) {}
      try {
        final v = t.selection;
        if (v is String && v.isNotEmpty) return v;
        if (v != null) {
          final s = v.toString();
          if (s.isNotEmpty) return s;
        }
      } catch (_) {}

      // buffer-based accessors
      try {
        final buf = t.buffer as dynamic;
        try {
          final v = buf.selectedText;
          if (v is String && v.isNotEmpty) return v;
        } catch (_) {}
        try {
          final v = buf.getSelectedText();
          if (v is String && v.isNotEmpty) return v;
        } catch (_) {}
        try {
          final v = buf.getSelection();
          if (v != null) {
            final s = v.toString();
            if (s.isNotEmpty) return s;
          }
        } catch (_) {}
      } catch (_) {}

      // last resort: try calling common-named methods on terminal
      try {
        final v = t.getSelectedText();
        if (v is String && v.isNotEmpty) return v;
      } catch (_) {}
    } catch (_) {}
    return null;
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
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  OverlayEntry? _inputOverlay;

  FocusNode? get _effectiveFocusNode => widget.focusNode ?? _internalFocusNode;

  @override
  void dispose() {
    // Only dispose focus node if we created it here.
    if (_internalFocusNode != null) {
      _internalFocusNode!.dispose();
    }
    _inputController.dispose();
    _inputFocusNode.dispose();
    _inputOverlay?.remove();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Overlay insertion is deferred until activation to avoid TextInput
    // client races with TerminalView. The overlay will be created when the
    // widget is explicitly activated (tap/focus) by calling _activateFocus().
  }

  void _activateFocus() {
    if (_activated) return;
    if (widget.focusNode != null) {
      // external focus node provided, just request focus on it
      // Request focus for our hidden input field as well so IME attaches.
      // ignore: avoid_print
      print(
          '[IME-DEBUG] activateFocus: requesting external focus and input focus');
      widget.focusNode!.requestFocus();
      _activated = true;
      // Insert overlay now and request input focus after insertion.
      if (_inputOverlay == null) {
        _createAndInsertOverlay();
      }
      try {
        _inputFocusNode.requestFocus();
      } catch (_) {}
      return;
    }
    // create internal focus node and rebuild to attach it to TerminalView
    _internalFocusNode = FocusNode();
    _activated = true;
    setState(() {});
    // request focus and insert overlay in a post frame callback to avoid
    // modifying the widget tree during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          // ignore: avoid_print
          print('[IME-DEBUG] postFrame: requesting internal and input focus');
          _internalFocusNode!.requestFocus();
          if (_inputOverlay == null) {
            _createAndInsertOverlay();
          }
          _inputFocusNode.requestFocus();
        } catch (_) {}
      }
    });
  }

  void _createAndInsertOverlay() {
    _inputOverlay = OverlayEntry(
      builder: (context) {
        return Positioned(
          left: 0,
          top: 0,
          width: 1,
          height: 1,
          child: Material(
            type: MaterialType.transparency,
            child: TextField(
              controller: _inputController,
              focusNode: _inputFocusNode,
              autofocus: false,
              showCursor: false,
              enableInteractiveSelection: false,
              decoration: const InputDecoration.collapsed(hintText: ''),
              onSubmitted: (s) {
                // On platforms where the overlay works, Enter might come here.
                // But we also handle it in _handleRawKey, so just clear.
                _inputController.clear();
              },
              // Character input is handled by _handleRawKey to avoid double-sending.
              // The overlay TextField exists mainly for IME support on mobile platforms.
              // On Windows, _handleRawKey handles everything.
              onChanged: (s) {
                // Clear the controller to prevent accumulation, but don't send
                // characters here - _handleRawKey already handles them.
                _inputController.clear();
              },
            ),
          ),
        );
      },
    );
    try {
      final overlay = Overlay.of(context, debugRequiredFor: widget);
      overlay.insert(_inputOverlay!);
    } catch (_) {}
  }

  void _handleRawKey(RawKeyEvent event) {
    if (event is! RawKeyDownEvent) return;

    // Helper to send data to SSH session or fall back to local echo
    void sendToSession(String data) {
      if (widget.bridge.onOutput != null) {
        try {
          widget.bridge.onOutput!(data);
        } catch (_) {}
      } else {
        widget.bridge.debugWrite(data);
      }
    }

    // Only handle special keys here - regular characters are handled by the
    // overlay TextField to properly support IME and composed characters (umlauts etc.)
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      sendToSession('\r');
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      sendToSession('\x7f');
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      sendToSession('\t');
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      sendToSession('\x1b');
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      sendToSession('\x1b[A');
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      sendToSession('\x1b[B');
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      sendToSession('\x1b[C');
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      sendToSession('\x1b[D');
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.home) {
      sendToSession('\x1b[H');
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.end) {
      sendToSession('\x1b[F');
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.pageUp) {
      sendToSession('\x1b[5~');
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.pageDown) {
      sendToSession('\x1b[6~');
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete) {
      sendToSession('\x1b[3~');
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.insert) {
      sendToSession('\x1b[2~');
      return;
    }

    // Send regular characters - the overlay TextField approach doesn't work
    // reliably on Windows, so we handle all character input here.
    final char = event.character;
    if (char != null && char.isNotEmpty) {
      sendToSession(char);
    }
  }

  @override
  Widget build(BuildContext context) {
    // If no focus node is attached yet, wrap in GestureDetector to enable onTap activation.
    if (_effectiveFocusNode == null) {
      return GestureDetector(
        onTap: _activateFocus,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerUp: (event) async {
            // attempt to copy selection to clipboard
            try {
              final sel = widget.bridge.getSelectedText();
              if (sel != null && sel.isNotEmpty) {
                await Clipboard.setData(ClipboardData(text: sel));
              }
            } catch (_) {}
          },
          child: TerminalView(
            widget.bridge.terminal,
            backgroundOpacity: 0.95,
            autofocus: false,
            padding: const EdgeInsets.all(8),
          ),
        ),
      );
    }

    // Keep a surrounding Focus to intercept key presses for fallback handling.
    // IME/composed input is captured by a persistent OverlayEntry TextField.
    return Focus(
      focusNode: _effectiveFocusNode,
      onKey: (node, event) {
        if (event is RawKeyDownEvent) {
          _handleRawKey(event);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        children: [
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerUp: (event) async {
              try {
                final sel = widget.bridge.getSelectedText();
                if (sel != null && sel.isNotEmpty) {
                  await Clipboard.setData(ClipboardData(text: sel));
                }
              } catch (_) {}
            },
            child: TerminalView(
              widget.bridge.terminal,
              backgroundOpacity: 0.95,
              autofocus: false,
              padding: const EdgeInsets.all(8),
            ),
          ),
        ],
      ),
    );
  }
}
