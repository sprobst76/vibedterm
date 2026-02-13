import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart' as xterm;

import 'terminal_bridge.dart';
import 'theme_presets.dart';

/// Terminal view using native Dart xterm package (Linux fallback).
class NativeTerminalView extends StatefulWidget {
  const NativeTerminalView({
    super.key,
    required this.bridge,
    this.focusNode,
    this.autofocus = false,
    this.themeName = 'default',
    this.fontSize = 14.0,
    this.fontFamily,
    this.opacity = 1.0,
    this.cursorStyle = TerminalCursorStyle.block,
  });

  final TerminalBridge bridge;
  final FocusNode? focusNode;
  final bool autofocus;
  final String themeName;
  final double fontSize;
  final String? fontFamily;
  final double opacity;
  final TerminalCursorStyle cursorStyle;

  @override
  State<NativeTerminalView> createState() => _NativeTerminalViewState();
}

class _NativeTerminalViewState extends State<NativeTerminalView> {
  FocusNode? _internalFocusNode;
  bool _activated = false;
  final ScrollController _scrollController = ScrollController();

  FocusNode? get _effectiveFocusNode =>
      widget.focusNode ?? _internalFocusNode;

  xterm.TerminalTheme get _terminalTheme {
    final t = TerminalThemePresets.getTheme(widget.themeName);
    return xterm.TerminalTheme(
      cursor: t.cursor,
      selection: t.selection,
      foreground: t.foreground,
      background: t.background,
      black: t.black,
      red: t.red,
      green: t.green,
      yellow: t.yellow,
      blue: t.blue,
      magenta: t.magenta,
      cyan: t.cyan,
      white: t.white,
      brightBlack: t.brightBlack,
      brightRed: t.brightRed,
      brightGreen: t.brightGreen,
      brightYellow: t.brightYellow,
      brightBlue: t.brightBlue,
      brightMagenta: t.brightMagenta,
      brightCyan: t.brightCyan,
      brightWhite: t.brightWhite,
      searchHitBackground: t.searchHitBackground,
      searchHitBackgroundCurrent: t.searchHitBackgroundCurrent,
      searchHitForeground: t.searchHitForeground,
    );
  }

  xterm.TerminalStyle get _terminalStyle => xterm.TerminalStyle(
        fontSize: widget.fontSize,
        fontFamily: widget.fontFamily ?? 'monospace',
      );

  xterm.TerminalCursorType get _cursorType {
    switch (widget.cursorStyle) {
      case TerminalCursorStyle.underline:
        return xterm.TerminalCursorType.underline;
      case TerminalCursorStyle.bar:
        return xterm.TerminalCursorType.verticalBar;
      case TerminalCursorStyle.block:
        return xterm.TerminalCursorType.block;
    }
  }

  @override
  void dispose() {
    _internalFocusNode?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _activateFocus() {
    if (_activated) return;
    if (widget.focusNode != null) {
      widget.focusNode!.requestFocus();
      _activated = true;
      return;
    }
    _internalFocusNode = FocusNode();
    _activated = true;
    setState(() {});
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
    final terminal = widget.bridge.nativeTerminal;
    final controller = widget.bridge.nativeController;
    if (terminal == null || controller == null) {
      return const Center(child: Text('Terminal not available'));
    }

    Widget terminalView = xterm.TerminalView(
      terminal,
      controller: controller,
      scrollController: _scrollController,
      theme: _terminalTheme,
      textStyle: _terminalStyle,
      cursorType: _cursorType,
      backgroundOpacity: widget.opacity,
      autofocus: false,
      padding: const EdgeInsets.all(8),
    );

    // Shift+Scroll for local buffer scrolling
    terminalView = Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          if (HardwareKeyboard.instance.isShiftPressed) {
            if (_scrollController.hasClients) {
              final offset =
                  _scrollController.offset + event.scrollDelta.dy;
              final maxScroll =
                  _scrollController.position.maxScrollExtent;
              _scrollController.jumpTo(offset.clamp(0.0, maxScroll));
            }
          }
        }
      },
      child: terminalView,
    );

    if (_effectiveFocusNode == null) {
      return GestureDetector(
        onTap: _activateFocus,
        child: terminalView,
      );
    }

    return Focus(
      focusNode: _effectiveFocusNode!,
      child: terminalView,
    );
  }
}
