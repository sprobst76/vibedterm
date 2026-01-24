/// Terminal UI components for VibedTerm SSH client.
///
/// This library provides terminal widgets and theme management, wrapping the
/// xterm package with additional features like:
/// - Predefined color theme presets (Solarized, Monokai, Dracula, Nord, etc.)
/// - Theme-to-ThemeData conversion for consistent app styling
/// - SSH stream bridging to terminal display
/// - Cross-platform keyboard input handling
///
/// ## Usage
///
/// ```dart
/// // Create a terminal bridge
/// final bridge = TerminalBridge();
///
/// // Attach SSH streams
/// bridge.attachStreams(stdout: sshSession.stdout, stderr: sshSession.stderr);
///
/// // Forward user input to SSH
/// bridge.onOutput = (data) => sshSession.write(utf8.encode(data));
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

import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

// Re-export xterm types needed by consumers
export 'package:xterm/xterm.dart' show TerminalTheme, TerminalStyle;

// =============================================================================
// Terminal Configuration
// =============================================================================

/// Terminal cursor display styles.
enum TerminalCursorStyle {
  /// Solid block cursor.
  block,

  /// Underline cursor.
  underline,

  /// Vertical bar (I-beam) cursor.
  bar,
}

// =============================================================================
// Theme Presets
// =============================================================================

/// Predefined terminal color themes.
///
/// Provides 12 popular color schemes including both dark and light themes.
/// Use [getTheme] to get a theme by name, or access individual themes directly.
class TerminalThemePresets {
  TerminalThemePresets._();

  /// List of all available theme names.
  static const List<String> themeNames = [
    'default',
    'solarized-dark',
    'solarized-light',
    'monokai',
    'dracula',
    'nord',
    'gruvbox-dark',
    'gruvbox-light',
    'one-dark',
    'one-light',
    'github-light',
    'tomorrow-light',
  ];

  /// Get theme by name.
  static TerminalTheme getTheme(String name) {
    switch (name) {
      case 'solarized-dark':
        return solarizedDark;
      case 'solarized-light':
        return solarizedLight;
      case 'monokai':
        return monokai;
      case 'dracula':
        return dracula;
      case 'nord':
        return nord;
      case 'gruvbox-dark':
        return gruvboxDark;
      case 'gruvbox-light':
        return gruvboxLight;
      case 'one-dark':
        return oneDark;
      case 'one-light':
        return oneLight;
      case 'github-light':
        return githubLight;
      case 'tomorrow-light':
        return tomorrowLight;
      case 'default':
      default:
        return defaultTheme;
    }
  }

  /// Default dark theme (VS Code style).
  static const defaultTheme = TerminalTheme(
    cursor: Color(0xFFAEAFAD),
    selection: Color(0x80AEAFAD),
    foreground: Color(0xFFCCCCCC),
    background: Color(0xFF1E1E1E),
    black: Color(0xFF000000),
    red: Color(0xFFCD3131),
    green: Color(0xFF0DBC79),
    yellow: Color(0xFFE5E510),
    blue: Color(0xFF2472C8),
    magenta: Color(0xFFBC3FBC),
    cyan: Color(0xFF11A8CD),
    white: Color(0xFFE5E5E5),
    brightBlack: Color(0xFF666666),
    brightRed: Color(0xFFF14C4C),
    brightGreen: Color(0xFF23D18B),
    brightYellow: Color(0xFFF5F543),
    brightBlue: Color(0xFF3B8EEA),
    brightMagenta: Color(0xFFD670D6),
    brightCyan: Color(0xFF29B8DB),
    brightWhite: Color(0xFFFFFFFF),
    searchHitBackground: Color(0xFFFFFF2B),
    searchHitBackgroundCurrent: Color(0xFF31FF26),
    searchHitForeground: Color(0xFF000000),
  );

  /// Solarized Dark theme.
  static const solarizedDark = TerminalTheme(
    cursor: Color(0xFF839496),
    selection: Color(0x80839496),
    foreground: Color(0xFF839496),
    background: Color(0xFF002B36),
    black: Color(0xFF073642),
    red: Color(0xFFDC322F),
    green: Color(0xFF859900),
    yellow: Color(0xFFB58900),
    blue: Color(0xFF268BD2),
    magenta: Color(0xFFD33682),
    cyan: Color(0xFF2AA198),
    white: Color(0xFFEEE8D5),
    brightBlack: Color(0xFF002B36),
    brightRed: Color(0xFFCB4B16),
    brightGreen: Color(0xFF586E75),
    brightYellow: Color(0xFF657B83),
    brightBlue: Color(0xFF839496),
    brightMagenta: Color(0xFF6C71C4),
    brightCyan: Color(0xFF93A1A1),
    brightWhite: Color(0xFFFDF6E3),
    searchHitBackground: Color(0xFFFFFF2B),
    searchHitBackgroundCurrent: Color(0xFF31FF26),
    searchHitForeground: Color(0xFF000000),
  );

  /// Solarized Light theme.
  static const solarizedLight = TerminalTheme(
    cursor: Color(0xFF657B83),
    selection: Color(0x80657B83),
    foreground: Color(0xFF657B83),
    background: Color(0xFFFDF6E3),
    black: Color(0xFF073642),
    red: Color(0xFFDC322F),
    green: Color(0xFF859900),
    yellow: Color(0xFFB58900),
    blue: Color(0xFF268BD2),
    magenta: Color(0xFFD33682),
    cyan: Color(0xFF2AA198),
    white: Color(0xFFEEE8D5),
    brightBlack: Color(0xFF002B36),
    brightRed: Color(0xFFCB4B16),
    brightGreen: Color(0xFF586E75),
    brightYellow: Color(0xFF657B83),
    brightBlue: Color(0xFF839496),
    brightMagenta: Color(0xFF6C71C4),
    brightCyan: Color(0xFF93A1A1),
    brightWhite: Color(0xFFFDF6E3),
    searchHitBackground: Color(0xFFFFFF2B),
    searchHitBackgroundCurrent: Color(0xFF31FF26),
    searchHitForeground: Color(0xFF000000),
  );

  /// Monokai theme.
  static const monokai = TerminalTheme(
    cursor: Color(0xFFF8F8F0),
    selection: Color(0x8049483E),
    foreground: Color(0xFFF8F8F2),
    background: Color(0xFF272822),
    black: Color(0xFF272822),
    red: Color(0xFFF92672),
    green: Color(0xFFA6E22E),
    yellow: Color(0xFFF4BF75),
    blue: Color(0xFF66D9EF),
    magenta: Color(0xFFAE81FF),
    cyan: Color(0xFFA1EFE4),
    white: Color(0xFFF8F8F2),
    brightBlack: Color(0xFF75715E),
    brightRed: Color(0xFFF92672),
    brightGreen: Color(0xFFA6E22E),
    brightYellow: Color(0xFFF4BF75),
    brightBlue: Color(0xFF66D9EF),
    brightMagenta: Color(0xFFAE81FF),
    brightCyan: Color(0xFFA1EFE4),
    brightWhite: Color(0xFFF9F8F5),
    searchHitBackground: Color(0xFFFFFF2B),
    searchHitBackgroundCurrent: Color(0xFF31FF26),
    searchHitForeground: Color(0xFF000000),
  );

  /// Dracula theme.
  static const dracula = TerminalTheme(
    cursor: Color(0xFFF8F8F2),
    selection: Color(0x8044475A),
    foreground: Color(0xFFF8F8F2),
    background: Color(0xFF282A36),
    black: Color(0xFF21222C),
    red: Color(0xFFFF5555),
    green: Color(0xFF50FA7B),
    yellow: Color(0xFFF1FA8C),
    blue: Color(0xFFBD93F9),
    magenta: Color(0xFFFF79C6),
    cyan: Color(0xFF8BE9FD),
    white: Color(0xFFF8F8F2),
    brightBlack: Color(0xFF6272A4),
    brightRed: Color(0xFFFF6E6E),
    brightGreen: Color(0xFF69FF94),
    brightYellow: Color(0xFFFFFFA5),
    brightBlue: Color(0xFFD6ACFF),
    brightMagenta: Color(0xFFFF92DF),
    brightCyan: Color(0xFFA4FFFF),
    brightWhite: Color(0xFFFFFFFF),
    searchHitBackground: Color(0xFFFFFF2B),
    searchHitBackgroundCurrent: Color(0xFF31FF26),
    searchHitForeground: Color(0xFF000000),
  );

  /// Nord theme.
  static const nord = TerminalTheme(
    cursor: Color(0xFFD8DEE9),
    selection: Color(0x804C566A),
    foreground: Color(0xFFD8DEE9),
    background: Color(0xFF2E3440),
    black: Color(0xFF3B4252),
    red: Color(0xFFBF616A),
    green: Color(0xFFA3BE8C),
    yellow: Color(0xFFEBCB8B),
    blue: Color(0xFF81A1C1),
    magenta: Color(0xFFB48EAD),
    cyan: Color(0xFF88C0D0),
    white: Color(0xFFE5E9F0),
    brightBlack: Color(0xFF4C566A),
    brightRed: Color(0xFFBF616A),
    brightGreen: Color(0xFFA3BE8C),
    brightYellow: Color(0xFFEBCB8B),
    brightBlue: Color(0xFF81A1C1),
    brightMagenta: Color(0xFFB48EAD),
    brightCyan: Color(0xFF8FBCBB),
    brightWhite: Color(0xFFECEFF4),
    searchHitBackground: Color(0xFFFFFF2B),
    searchHitBackgroundCurrent: Color(0xFF31FF26),
    searchHitForeground: Color(0xFF000000),
  );

  /// Gruvbox Dark theme.
  static const gruvboxDark = TerminalTheme(
    cursor: Color(0xFFEBDBB2),
    selection: Color(0x80504945),
    foreground: Color(0xFFEBDBB2),
    background: Color(0xFF282828),
    black: Color(0xFF282828),
    red: Color(0xFFCC241D),
    green: Color(0xFF98971A),
    yellow: Color(0xFFD79921),
    blue: Color(0xFF458588),
    magenta: Color(0xFFB16286),
    cyan: Color(0xFF689D6A),
    white: Color(0xFFA89984),
    brightBlack: Color(0xFF928374),
    brightRed: Color(0xFFFB4934),
    brightGreen: Color(0xFFB8BB26),
    brightYellow: Color(0xFFFABD2F),
    brightBlue: Color(0xFF83A598),
    brightMagenta: Color(0xFFD3869B),
    brightCyan: Color(0xFF8EC07C),
    brightWhite: Color(0xFFEBDBB2),
    searchHitBackground: Color(0xFFFFFF2B),
    searchHitBackgroundCurrent: Color(0xFF31FF26),
    searchHitForeground: Color(0xFF000000),
  );

  /// One Dark theme (Atom style).
  static const oneDark = TerminalTheme(
    cursor: Color(0xFFABB2BF),
    selection: Color(0x803E4451),
    foreground: Color(0xFFABB2BF),
    background: Color(0xFF282C34),
    black: Color(0xFF282C34),
    red: Color(0xFFE06C75),
    green: Color(0xFF98C379),
    yellow: Color(0xFFE5C07B),
    blue: Color(0xFF61AFEF),
    magenta: Color(0xFFC678DD),
    cyan: Color(0xFF56B6C2),
    white: Color(0xFFABB2BF),
    brightBlack: Color(0xFF5C6370),
    brightRed: Color(0xFFE06C75),
    brightGreen: Color(0xFF98C379),
    brightYellow: Color(0xFFE5C07B),
    brightBlue: Color(0xFF61AFEF),
    brightMagenta: Color(0xFFC678DD),
    brightCyan: Color(0xFF56B6C2),
    brightWhite: Color(0xFFFFFFFF),
    searchHitBackground: Color(0xFFFFFF2B),
    searchHitBackgroundCurrent: Color(0xFF31FF26),
    searchHitForeground: Color(0xFF000000),
  );

  /// One Light theme (Atom style).
  static const oneLight = TerminalTheme(
    cursor: Color(0xFF383A42),
    selection: Color(0x40526FFF),
    foreground: Color(0xFF383A42),
    background: Color(0xFFFAFAFA),
    black: Color(0xFF383A42),
    red: Color(0xFFE45649),
    green: Color(0xFF50A14F),
    yellow: Color(0xFFC18401),
    blue: Color(0xFF4078F2),
    magenta: Color(0xFFA626A4),
    cyan: Color(0xFF0184BC),
    white: Color(0xFFA0A1A7),
    brightBlack: Color(0xFF696C77),
    brightRed: Color(0xFFE45649),
    brightGreen: Color(0xFF50A14F),
    brightYellow: Color(0xFFC18401),
    brightBlue: Color(0xFF4078F2),
    brightMagenta: Color(0xFFA626A4),
    brightCyan: Color(0xFF0184BC),
    brightWhite: Color(0xFFFFFFFF),
    searchHitBackground: Color(0xFFFFFF00),
    searchHitBackgroundCurrent: Color(0xFF00FF00),
    searchHitForeground: Color(0xFF000000),
  );

  /// Gruvbox Light theme.
  static const gruvboxLight = TerminalTheme(
    cursor: Color(0xFF282828),
    selection: Color(0x40458588),
    foreground: Color(0xFF3C3836),
    background: Color(0xFFFBF1C7),
    black: Color(0xFFFBF1C7),
    red: Color(0xFFCC241D),
    green: Color(0xFF98971A),
    yellow: Color(0xFFD79921),
    blue: Color(0xFF458588),
    magenta: Color(0xFFB16286),
    cyan: Color(0xFF689D6A),
    white: Color(0xFF7C6F64),
    brightBlack: Color(0xFF928374),
    brightRed: Color(0xFF9D0006),
    brightGreen: Color(0xFF79740E),
    brightYellow: Color(0xFFB57614),
    brightBlue: Color(0xFF076678),
    brightMagenta: Color(0xFF8F3F71),
    brightCyan: Color(0xFF427B58),
    brightWhite: Color(0xFF3C3836),
    searchHitBackground: Color(0xFFFFFF00),
    searchHitBackgroundCurrent: Color(0xFF00FF00),
    searchHitForeground: Color(0xFF000000),
  );

  /// GitHub Light theme.
  static const githubLight = TerminalTheme(
    cursor: Color(0xFF044289),
    selection: Color(0x40044289),
    foreground: Color(0xFF24292E),
    background: Color(0xFFFFFFFF),
    black: Color(0xFF24292E),
    red: Color(0xFFD73A49),
    green: Color(0xFF28A745),
    yellow: Color(0xFFDBAB09),
    blue: Color(0xFF0366D6),
    magenta: Color(0xFF6F42C1),
    cyan: Color(0xFF1B7C83),
    white: Color(0xFF6A737D),
    brightBlack: Color(0xFF959DA5),
    brightRed: Color(0xFFCB2431),
    brightGreen: Color(0xFF22863A),
    brightYellow: Color(0xFFB08800),
    brightBlue: Color(0xFF005CC5),
    brightMagenta: Color(0xFF5A32A3),
    brightCyan: Color(0xFF3192AA),
    brightWhite: Color(0xFFD1D5DA),
    searchHitBackground: Color(0xFFFFFF00),
    searchHitBackgroundCurrent: Color(0xFF00FF00),
    searchHitForeground: Color(0xFF000000),
  );

  /// Tomorrow Light theme.
  static const tomorrowLight = TerminalTheme(
    cursor: Color(0xFF4D4D4C),
    selection: Color(0x40D6D6D6),
    foreground: Color(0xFF4D4D4C),
    background: Color(0xFFFFFFFF),
    black: Color(0xFF000000),
    red: Color(0xFFC82829),
    green: Color(0xFF718C00),
    yellow: Color(0xFFEAB700),
    blue: Color(0xFF4271AE),
    magenta: Color(0xFF8959A8),
    cyan: Color(0xFF3E999F),
    white: Color(0xFFFFFFFF),
    brightBlack: Color(0xFF8E908C),
    brightRed: Color(0xFFC82829),
    brightGreen: Color(0xFF718C00),
    brightYellow: Color(0xFFEAB700),
    brightBlue: Color(0xFF4271AE),
    brightMagenta: Color(0xFF8959A8),
    brightCyan: Color(0xFF3E999F),
    brightWhite: Color(0xFFFFFFFF),
    searchHitBackground: Color(0xFFFFFF00),
    searchHitBackgroundCurrent: Color(0xFF00FF00),
    searchHitForeground: Color(0xFF000000),
  );
}

// =============================================================================
// Theme Conversion
// =============================================================================

/// Converts terminal themes to Flutter [ThemeData].
///
/// This enables the entire app to be styled consistently with the terminal,
/// deriving colors for buttons, dialogs, inputs, etc. from the terminal palette.
class TerminalThemeConverter {
  TerminalThemeConverter._();

  /// Determines if a theme is light or dark based on background luminance.
  static bool isLightTheme(TerminalTheme theme) {
    return theme.background.computeLuminance() > 0.5;
  }

  /// Creates a Flutter ThemeData from a TerminalTheme.
  static ThemeData toFlutterTheme(TerminalTheme termTheme) {
    final isLight = isLightTheme(termTheme);
    final brightness = isLight ? Brightness.light : Brightness.dark;

    // Create color scheme based on terminal theme
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: termTheme.cyan,
      onPrimary: isLight ? Colors.white : termTheme.background,
      primaryContainer: Color.lerp(termTheme.cyan, termTheme.background, 0.7)!,
      onPrimaryContainer: termTheme.foreground,
      secondary: termTheme.magenta,
      onSecondary: isLight ? Colors.white : termTheme.background,
      secondaryContainer: Color.lerp(termTheme.magenta, termTheme.background, 0.7)!,
      onSecondaryContainer: termTheme.foreground,
      tertiary: termTheme.yellow,
      onTertiary: termTheme.background,
      tertiaryContainer: Color.lerp(termTheme.yellow, termTheme.background, 0.7)!,
      onTertiaryContainer: termTheme.foreground,
      error: termTheme.red,
      onError: Colors.white,
      errorContainer: Color.lerp(termTheme.red, termTheme.background, 0.7)!,
      onErrorContainer: termTheme.foreground,
      surface: termTheme.background,
      onSurface: termTheme.foreground,
      surfaceContainerHighest: Color.lerp(termTheme.background, termTheme.foreground, 0.08)!,
      surfaceContainerHigh: Color.lerp(termTheme.background, termTheme.foreground, 0.06)!,
      surfaceContainer: Color.lerp(termTheme.background, termTheme.foreground, 0.04)!,
      surfaceContainerLow: Color.lerp(termTheme.background, termTheme.foreground, 0.02)!,
      surfaceContainerLowest: termTheme.background,
      onSurfaceVariant: termTheme.foreground.withOpacity(0.7),
      outline: termTheme.foreground.withOpacity(0.3),
      outlineVariant: termTheme.foreground.withOpacity(0.15),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: termTheme.foreground,
      onInverseSurface: termTheme.background,
      inversePrimary: Color.lerp(termTheme.cyan, termTheme.background, 0.5)!,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: termTheme.background,
      appBarTheme: AppBarTheme(
        backgroundColor: Color.lerp(termTheme.background, termTheme.foreground, 0.05),
        foregroundColor: termTheme.foreground,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Color.lerp(termTheme.background, termTheme.foreground, 0.03),
        selectedIconTheme: IconThemeData(color: termTheme.cyan),
        unselectedIconTheme: IconThemeData(color: termTheme.foreground.withOpacity(0.6)),
        selectedLabelTextStyle: TextStyle(color: termTheme.cyan, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle: TextStyle(color: termTheme.foreground.withOpacity(0.6)),
        indicatorColor: termTheme.cyan.withOpacity(0.2),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Color.lerp(termTheme.background, termTheme.foreground, 0.05),
        indicatorColor: termTheme.cyan.withOpacity(0.2),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: termTheme.cyan);
          }
          return IconThemeData(color: termTheme.foreground.withOpacity(0.6));
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(color: termTheme.cyan, fontWeight: FontWeight.w600, fontSize: 12);
          }
          return TextStyle(color: termTheme.foreground.withOpacity(0.6), fontSize: 12);
        }),
      ),
      cardTheme: CardThemeData(
        color: Color.lerp(termTheme.background, termTheme.foreground, 0.05),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: termTheme.foreground.withOpacity(0.1)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Color.lerp(termTheme.background, termTheme.foreground, 0.05),
        titleTextStyle: TextStyle(color: termTheme.foreground, fontSize: 20, fontWeight: FontWeight.w600),
        contentTextStyle: TextStyle(color: termTheme.foreground.withOpacity(0.8)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: termTheme.foreground.withOpacity(0.1)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Color.lerp(termTheme.background, termTheme.foreground, 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: termTheme.foreground.withOpacity(0.2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: termTheme.foreground.withOpacity(0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: termTheme.cyan, width: 2),
        ),
        labelStyle: TextStyle(color: termTheme.foreground.withOpacity(0.7)),
        hintStyle: TextStyle(color: termTheme.foreground.withOpacity(0.4)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: termTheme.cyan,
          foregroundColor: isLight ? Colors.white : termTheme.background,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: termTheme.cyan,
          foregroundColor: isLight ? Colors.white : termTheme.background,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: termTheme.cyan,
        ),
      ),
      iconTheme: IconThemeData(color: termTheme.foreground.withOpacity(0.8)),
      dividerTheme: DividerThemeData(color: termTheme.foreground.withOpacity(0.1)),
      listTileTheme: ListTileThemeData(
        iconColor: termTheme.foreground.withOpacity(0.7),
        textColor: termTheme.foreground,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: Color.lerp(termTheme.foreground, termTheme.background, 0.2),
        contentTextStyle: TextStyle(color: termTheme.background),
        actionTextColor: termTheme.cyan,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Color.lerp(termTheme.background, termTheme.foreground, 0.08),
        labelStyle: TextStyle(color: termTheme.foreground),
        side: BorderSide(color: termTheme.foreground.withOpacity(0.2)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Color.lerp(termTheme.background, termTheme.foreground, 0.05),
        textStyle: TextStyle(color: termTheme.foreground),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: termTheme.foreground.withOpacity(0.1)),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: Color.lerp(termTheme.background, termTheme.foreground, 0.03),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      textTheme: TextTheme(
        displayLarge: TextStyle(color: termTheme.foreground),
        displayMedium: TextStyle(color: termTheme.foreground),
        displaySmall: TextStyle(color: termTheme.foreground),
        headlineLarge: TextStyle(color: termTheme.foreground),
        headlineMedium: TextStyle(color: termTheme.foreground),
        headlineSmall: TextStyle(color: termTheme.foreground),
        titleLarge: TextStyle(color: termTheme.foreground),
        titleMedium: TextStyle(color: termTheme.foreground),
        titleSmall: TextStyle(color: termTheme.foreground),
        bodyLarge: TextStyle(color: termTheme.foreground),
        bodyMedium: TextStyle(color: termTheme.foreground),
        bodySmall: TextStyle(color: termTheme.foreground.withOpacity(0.7)),
        labelLarge: TextStyle(color: termTheme.foreground),
        labelMedium: TextStyle(color: termTheme.foreground),
        labelSmall: TextStyle(color: termTheme.foreground.withOpacity(0.7)),
      ),
    );
  }
}

// =============================================================================
// Terminal Bridge
// =============================================================================

/// Bridges SSH streams to an xterm [Terminal] instance.
///
/// The bridge handles:
/// - Attaching SSH stdout/stderr to terminal display
/// - Forwarding user input from terminal to SSH stdin
/// - Terminal resizing
///
/// ## Example
///
/// ```dart
/// final bridge = TerminalBridge();
///
/// // Connect SSH streams
/// bridge.attachStreams(
///   stdout: sshSession.stdout,
///   stderr: sshSession.stderr,
/// );
///
/// // Forward user input to SSH
/// bridge.onOutput = (data) async {
///   await sshSession.write(utf8.encode(data));
/// };
///
/// // Resize terminal when window changes
/// bridge.resize(80, 24);
/// ```
class TerminalBridge {
  /// Creates a terminal bridge with an optional existing terminal.
  TerminalBridge({Terminal? initialTerminal})
      : terminal = initialTerminal ??
            Terminal(
              maxLines: 2000,
            ),
        controller = TerminalController() {
    terminal.onOutput = (data) {
      onOutput?.call(data);
    };
  }

  /// The underlying xterm Terminal instance.
  final Terminal terminal;

  /// Controller for terminal view (handles selection, scrolling).
  final TerminalController controller;

  final List<StreamSubscription<List<int>>> _subscriptions = [];

  /// Callback invoked when the user types into the terminal.
  ///
  /// Forward this data to the SSH session's stdin.
  void Function(String data)? onOutput;

  /// Attaches SSH stdout/stderr streams to the terminal display.
  ///
  /// Data from these streams is decoded as UTF-8 and written to the terminal.
  void attachStreams({
    required Stream<List<int>> stdout,
    required Stream<List<int>> stderr,
  }) {
    _cancelSubscriptions();
    _subscriptions.add(
      stdout.listen((data) => terminal.write(utf8.decode(data, allowMalformed: true))),
    );
    _subscriptions.add(
      stderr.listen((data) => terminal.write(utf8.decode(data, allowMalformed: true))),
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

  /// Get selected text from terminal using the controller.
  String? getSelectedText() {
    final selection = controller.selection;
    if (selection == null) return null;
    return terminal.buffer.getText(selection);
  }

  /// Clear the current selection.
  void clearSelection() {
    controller.clearSelection();
  }

  void _cancelSubscriptions() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }
}

// =============================================================================
// Terminal Widget
// =============================================================================

/// Terminal display widget built on xterm.
///
/// Provides a fully functional terminal view with:
/// - Configurable color themes
/// - Adjustable font size and family
/// - Multiple cursor styles
/// - Cross-platform keyboard input handling
/// - Selection and copy support
///
/// ## Example
///
/// ```dart
/// VibedTerminalView(
///   bridge: bridge,
///   themeName: 'dracula',
///   fontSize: 14.0,
///   fontFamily: 'Fira Code',
///   cursorStyle: TerminalCursorStyle.bar,
/// )
/// ```
class VibedTerminalView extends StatefulWidget {
  /// Creates a terminal view widget.
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

  /// Optional focus node for keyboard input.
  final FocusNode? focusNode;

  /// Whether to automatically focus on build (may cause issues on some platforms).
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
  State<VibedTerminalView> createState() => _VibedTerminalViewState();
}

class _VibedTerminalViewState extends State<VibedTerminalView> {
  FocusNode? _internalFocusNode;
  bool _activated = false;
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  OverlayEntry? _inputOverlay;
  final ScrollController _scrollController = ScrollController();

  FocusNode? get _effectiveFocusNode => widget.focusNode ?? _internalFocusNode;

  /// Get the TerminalTheme from the preset name.
  TerminalTheme get _terminalTheme =>
      TerminalThemePresets.getTheme(widget.themeName);

  /// Build the TerminalStyle with font settings.
  TerminalStyle get _terminalStyle => TerminalStyle(
        fontSize: widget.fontSize,
        fontFamily: widget.fontFamily ?? 'monospace',
      );

  /// Convert our cursor style enum to xterm's TerminalCursorType.
  TerminalCursorType get _cursorType {
    switch (widget.cursorStyle) {
      case TerminalCursorStyle.underline:
        return TerminalCursorType.underline;
      case TerminalCursorStyle.bar:
        return TerminalCursorType.verticalBar;
      case TerminalCursorStyle.block:
        return TerminalCursorType.block;
    }
  }

  @override
  void dispose() {
    // Only dispose focus node if we created it here.
    if (_internalFocusNode != null) {
      _internalFocusNode!.dispose();
    }
    _inputController.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
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
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              if (HardwareKeyboard.instance.isShiftPressed) {
                if (_scrollController.hasClients) {
                  final offset = _scrollController.offset + event.scrollDelta.dy;
                  final maxScroll = _scrollController.position.maxScrollExtent;
                  _scrollController.jumpTo(offset.clamp(0.0, maxScroll));
                }
              }
            }
          },
          child: TerminalView(
            widget.bridge.terminal,
            controller: widget.bridge.controller,
            scrollController: _scrollController,
            theme: _terminalTheme,
            textStyle: _terminalStyle,
            cursorType: _cursorType,
            backgroundOpacity: widget.opacity,
            autofocus: false,
            padding: const EdgeInsets.all(8),
          ),
        ),
      );
    }

    // Use RawKeyboardListener for keyboard input.
    // Wrap in Listener to intercept Shift+Scroll for local buffer scrolling.
    // Normal scroll goes to terminal (tmux/vim), Shift+scroll scrolls locally.
    return RawKeyboardListener(
      focusNode: _effectiveFocusNode!,
      onKey: _handleRawKey,
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            // Check if Shift is held - if so, scroll local buffer
            if (HardwareKeyboard.instance.isShiftPressed) {
              if (_scrollController.hasClients) {
                final offset = _scrollController.offset + event.scrollDelta.dy;
                final maxScroll = _scrollController.position.maxScrollExtent;
                _scrollController.jumpTo(offset.clamp(0.0, maxScroll));
              }
            }
            // If Shift not pressed, let event pass through to TerminalView (tmux)
          }
        },
        child: TerminalView(
          widget.bridge.terminal,
          controller: widget.bridge.controller,
          scrollController: _scrollController,
          theme: _terminalTheme,
          textStyle: _terminalStyle,
          cursorType: _cursorType,
          backgroundOpacity: widget.opacity,
          autofocus: false,
          padding: const EdgeInsets.all(8),
        ),
      ),
    );
  }
}
