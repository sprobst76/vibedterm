import 'package:flutter/material.dart';

/// Terminal color theme definition.
///
/// Replaces the xterm package's TerminalTheme with an independent type
/// that can serialize to xterm.js JSON format for WebView communication.
@immutable
class VibedTerminalTheme {
  const VibedTerminalTheme({
    required this.cursor,
    required this.selection,
    required this.foreground,
    required this.background,
    required this.black,
    required this.red,
    required this.green,
    required this.yellow,
    required this.blue,
    required this.magenta,
    required this.cyan,
    required this.white,
    required this.brightBlack,
    required this.brightRed,
    required this.brightGreen,
    required this.brightYellow,
    required this.brightBlue,
    required this.brightMagenta,
    required this.brightCyan,
    required this.brightWhite,
    this.searchHitBackground = const Color(0xFFFFFF2B),
    this.searchHitBackgroundCurrent = const Color(0xFF31FF26),
    this.searchHitForeground = const Color(0xFF000000),
  });

  final Color cursor;
  final Color selection;
  final Color foreground;
  final Color background;
  final Color black;
  final Color red;
  final Color green;
  final Color yellow;
  final Color blue;
  final Color magenta;
  final Color cyan;
  final Color white;
  final Color brightBlack;
  final Color brightRed;
  final Color brightGreen;
  final Color brightYellow;
  final Color brightBlue;
  final Color brightMagenta;
  final Color brightCyan;
  final Color brightWhite;
  final Color searchHitBackground;
  final Color searchHitBackgroundCurrent;
  final Color searchHitForeground;

  /// Serialize to xterm.js theme JSON for WebView communication.
  Map<String, String> toXtermJsTheme() {
    String hex(Color c) {
      final argb = c.toARGB32();
      return '#${argb.toRadixString(16).padLeft(8, '0').substring(2)}';
    }

    return {
      'cursor': hex(cursor),
      'cursorAccent': hex(background),
      'selectionBackground': hex(selection),
      'selectionForeground': hex(foreground),
      'foreground': hex(foreground),
      'background': hex(background),
      'black': hex(black),
      'red': hex(red),
      'green': hex(green),
      'yellow': hex(yellow),
      'blue': hex(blue),
      'magenta': hex(magenta),
      'cyan': hex(cyan),
      'white': hex(white),
      'brightBlack': hex(brightBlack),
      'brightRed': hex(brightRed),
      'brightGreen': hex(brightGreen),
      'brightYellow': hex(brightYellow),
      'brightBlue': hex(brightBlue),
      'brightMagenta': hex(brightMagenta),
      'brightCyan': hex(brightCyan),
      'brightWhite': hex(brightWhite),
    };
  }
}

/// Backward-compatible typedef so existing code using `TerminalTheme` continues to work.
typedef TerminalTheme = VibedTerminalTheme;
