/// Terminal UI components for VibedTerm SSH client.
///
/// This library provides terminal widgets and theme management:
/// - Predefined color theme presets (Solarized, Monokai, Dracula, Nord, etc.)
/// - Theme-to-ThemeData conversion for consistent app styling
/// - SSH stream bridging to terminal display
/// - WebView-based xterm.js rendering (Windows, Android, iOS, macOS)
/// - Native xterm Dart fallback (Linux)
///
/// ## Usage
///
/// ```dart
/// // Create a terminal bridge
/// final bridge = TerminalBridge();
///
/// // Wait for terminal backend to be ready
/// await bridge.ready;
///
/// // Attach SSH streams
/// bridge.attachStreams(stdout: sshSession.stdout, stderr: sshSession.stderr);
///
/// // Forward user input to SSH
/// bridge.onOutput = (data) => sshSession.writeString(data);
///
/// // Display in widget tree
/// VibedTerminalView(
///   bridge: bridge,
///   themeName: 'dracula',
///   fontSize: 14.0,
/// )
/// ```
///
/// ## Theme Integration
///
/// Terminal themes can be used to style the entire app:
///
/// ```dart
/// final termTheme = TerminalThemePresets.getTheme('monokai');
/// final appTheme = TerminalThemeConverter.toFlutterTheme(termTheme);
///
/// MaterialApp(
///   theme: appTheme,
///   // ...
/// )
/// ```
library ui_terminal;

import 'dart:io';

import 'package:flutter/material.dart';

import 'src/terminal_bridge.dart';
import 'src/theme_presets.dart';
import 'src/native_terminal_view.dart';
import 'src/webview_terminal_view.dart';

export 'src/terminal_theme.dart';
export 'src/theme_presets.dart';
export 'src/theme_converter.dart';
export 'src/terminal_bridge.dart';
export 'src/js_channel_protocol.dart';

// =============================================================================
// Platform-Adaptive Terminal View
// =============================================================================

/// Terminal display widget that automatically selects the correct backend:
/// - WebView + xterm.js on Windows, Android, iOS, macOS
/// - Native Dart xterm on Linux
class VibedTerminalView extends StatelessWidget {
  const VibedTerminalView({
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

  /// The terminal bridge connecting SSH streams to the display.
  final TerminalBridge bridge;

  /// Optional focus node for keyboard input (used on Linux native only).
  final FocusNode? focusNode;

  /// Whether to automatically focus on build.
  final bool autofocus;

  /// Terminal color theme name (from [TerminalThemePresets]).
  final String themeName;

  /// Font size in points for terminal text.
  final double fontSize;

  /// Font family for terminal text (null uses system monospace).
  final String? fontFamily;

  /// Background opacity (0.0 = transparent, 1.0 = opaque).
  final double opacity;

  /// Cursor display style.
  final TerminalCursorStyle cursorStyle;

  @override
  Widget build(BuildContext context) {
    if (Platform.isLinux) {
      return NativeTerminalView(
        bridge: bridge,
        focusNode: focusNode,
        autofocus: autofocus,
        themeName: themeName,
        fontSize: fontSize,
        fontFamily: fontFamily,
        opacity: opacity,
        cursorStyle: cursorStyle,
      );
    }

    return WebViewTerminalView(
      bridge: bridge,
      themeName: themeName,
      fontSize: fontSize,
      fontFamily: fontFamily,
      opacity: opacity,
      cursorStyle: cursorStyle,
    );
  }
}
