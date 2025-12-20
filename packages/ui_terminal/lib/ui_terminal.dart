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
  bool _wasComposing = false;
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
                // When the IME/overlay field submits (Enter), forward CR to session.
                if (widget.bridge.onOutput != null) {
                  try {
                    widget.bridge.onOutput!('\r');
                  } catch (_) {}
                } else {
                  try {
                    widget.bridge.write('\r');
                  } catch (_) {}
                }
                _inputController.clear();
              },
              // We handle changes and commit composed text here.
              onChanged: (s) {
                final v = _inputController.value;
                if (v.composing.isValid) {
                  _wasComposing = true;
                  return;
                }
                if (_wasComposing) {
                  _wasComposing = false;
                }
                if (s.isNotEmpty) {
                  final text = s;
                  if (widget.bridge.onOutput != null) {
                    try {
                      widget.bridge.onOutput!(text);
                    } catch (_) {}
                  } else {
                    try {
                      widget.bridge.debugWrite(text);
                    } catch (_) {}
                  }
                  _inputController.clear();
                }
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
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      widget.bridge.write('\r');
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      widget.bridge.write('\x7f');
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      widget.bridge.write('\t');
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      widget.bridge.write('\x1b[A');
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      widget.bridge.write('\x1b[B');
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      widget.bridge.write('\x1b[C');
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      widget.bridge.write('\x1b[D');
      return;
    }
    final char = event.character;
    if (char != null && char.isNotEmpty) {
      // Prefer sending to the bridge output (connected session). If no
      // session is attached (bridge.onOutput == null), fall back to
      // writing directly to the terminal for local echo.
      if (widget.bridge.onOutput != null) {
        try {
          widget.bridge.onOutput!(char);
        } catch (_) {
          // ignore errors from user-provided onOutput
        }
      } else {
        widget.bridge.debugWrite(char);
      }
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
