import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_terminal/ui_terminal.dart';

void main() {
  group('VibedTerminalTheme', () {
    test('toXtermJsTheme produces valid hex colors', () {
      const theme = VibedTerminalTheme(
        cursor: Color(0xFFFFFFFF),
        selection: Color(0x40FFFFFF),
        foreground: Color(0xFFCCCCCC),
        background: Color(0xFF000000),
        black: Color(0xFF000000),
        red: Color(0xFFFF0000),
        green: Color(0xFF00FF00),
        yellow: Color(0xFFFFFF00),
        blue: Color(0xFF0000FF),
        magenta: Color(0xFFFF00FF),
        cyan: Color(0xFF00FFFF),
        white: Color(0xFFFFFFFF),
        brightBlack: Color(0xFF808080),
        brightRed: Color(0xFFFF0000),
        brightGreen: Color(0xFF00FF00),
        brightYellow: Color(0xFFFFFF00),
        brightBlue: Color(0xFF0000FF),
        brightMagenta: Color(0xFFFF00FF),
        brightCyan: Color(0xFF00FFFF),
        brightWhite: Color(0xFFFFFFFF),
      );

      final jsTheme = theme.toXtermJsTheme();

      expect(jsTheme['red'], '#ff0000');
      expect(jsTheme['green'], '#00ff00');
      expect(jsTheme['blue'], '#0000ff');
      expect(jsTheme['background'], '#000000');
      expect(jsTheme['foreground'], '#cccccc');
      expect(jsTheme['cursor'], '#ffffff');
    });

    test('toXtermJsTheme contains all required keys', () {
      final theme = TerminalThemePresets.getTheme('default');
      final jsTheme = theme.toXtermJsTheme();

      final requiredKeys = [
        'cursor', 'cursorAccent', 'selectionBackground', 'selectionForeground',
        'foreground', 'background', 'black', 'red', 'green', 'yellow',
        'blue', 'magenta', 'cyan', 'white', 'brightBlack', 'brightRed',
        'brightGreen', 'brightYellow', 'brightBlue', 'brightMagenta',
        'brightCyan', 'brightWhite',
      ];
      for (final key in requiredKeys) {
        expect(jsTheme.containsKey(key), isTrue, reason: 'Missing key: $key');
      }
    });

    test('hex format is #rrggbb (6 chars, no alpha)', () {
      final theme = TerminalThemePresets.getTheme('dracula');
      final jsTheme = theme.toXtermJsTheme();

      for (final entry in jsTheme.entries) {
        expect(entry.value, startsWith('#'),
            reason: '${entry.key} should start with #');
        expect(entry.value.length, 7,
            reason: '${entry.key} should be #rrggbb format');
      }
    });
  });

  group('TerminalThemePresets', () {
    test('default theme is available', () {
      final theme = TerminalThemePresets.getTheme('default');
      expect(theme, isNotNull);
    });

    test('unknown theme falls back to default', () {
      final theme = TerminalThemePresets.getTheme('nonexistent');
      final defaultTheme = TerminalThemePresets.getTheme('default');
      // They should be the same theme
      final jsA = theme.toXtermJsTheme();
      final jsB = defaultTheme.toXtermJsTheme();
      expect(jsA, jsB);
    });

    test('all 12 named themes load without error', () {
      for (final name in TerminalThemePresets.themeNames) {
        final theme = TerminalThemePresets.getTheme(name);
        expect(theme, isNotNull, reason: 'Theme "$name" should load');
        // Verify it can serialize
        final js = theme.toXtermJsTheme();
        expect(js.isNotEmpty, isTrue, reason: 'Theme "$name" should serialize');
      }
    });
  });
}
