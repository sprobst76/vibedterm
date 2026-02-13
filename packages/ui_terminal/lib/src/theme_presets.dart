import 'package:flutter/material.dart';

import 'terminal_theme.dart';

/// Terminal cursor display styles.
enum TerminalCursorStyle {
  /// Solid block cursor.
  block,

  /// Underline cursor.
  underline,

  /// Vertical bar (I-beam) cursor.
  bar,
}

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
