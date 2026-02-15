import 'package:flutter/material.dart';

import 'terminal_theme.dart';

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

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: termTheme.cyan,
      onPrimary: isLight ? Colors.white : termTheme.background,
      primaryContainer:
          Color.lerp(termTheme.cyan, termTheme.background, 0.7)!,
      onPrimaryContainer: termTheme.foreground,
      secondary: termTheme.magenta,
      onSecondary: isLight ? Colors.white : termTheme.background,
      secondaryContainer:
          Color.lerp(termTheme.magenta, termTheme.background, 0.7)!,
      onSecondaryContainer: termTheme.foreground,
      tertiary: termTheme.yellow,
      onTertiary: termTheme.background,
      tertiaryContainer:
          Color.lerp(termTheme.yellow, termTheme.background, 0.7)!,
      onTertiaryContainer: termTheme.foreground,
      error: termTheme.red,
      onError: Colors.white,
      errorContainer:
          Color.lerp(termTheme.red, termTheme.background, 0.7)!,
      onErrorContainer: termTheme.foreground,
      surface: termTheme.background,
      onSurface: termTheme.foreground,
      surfaceContainerHighest:
          Color.lerp(termTheme.background, termTheme.foreground, 0.08)!,
      surfaceContainerHigh:
          Color.lerp(termTheme.background, termTheme.foreground, 0.06)!,
      surfaceContainer:
          Color.lerp(termTheme.background, termTheme.foreground, 0.04)!,
      surfaceContainerLow:
          Color.lerp(termTheme.background, termTheme.foreground, 0.02)!,
      surfaceContainerLowest: termTheme.background,
      onSurfaceVariant: termTheme.foreground.withValues(alpha:0.7),
      outline: termTheme.foreground.withValues(alpha:0.3),
      outlineVariant: termTheme.foreground.withValues(alpha:0.15),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: termTheme.foreground,
      onInverseSurface: termTheme.background,
      inversePrimary:
          Color.lerp(termTheme.cyan, termTheme.background, 0.5)!,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: termTheme.background,
      appBarTheme: AppBarTheme(
        backgroundColor:
            Color.lerp(termTheme.background, termTheme.foreground, 0.05),
        foregroundColor: termTheme.foreground,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor:
            Color.lerp(termTheme.background, termTheme.foreground, 0.03),
        selectedIconTheme: IconThemeData(color: termTheme.cyan),
        unselectedIconTheme:
            IconThemeData(color: termTheme.foreground.withValues(alpha:0.6)),
        selectedLabelTextStyle:
            TextStyle(color: termTheme.cyan, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle:
            TextStyle(color: termTheme.foreground.withValues(alpha:0.6)),
        indicatorColor: termTheme.cyan.withValues(alpha:0.2),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor:
            Color.lerp(termTheme.background, termTheme.foreground, 0.05),
        indicatorColor: termTheme.cyan.withValues(alpha:0.2),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: termTheme.cyan);
          }
          return IconThemeData(
              color: termTheme.foreground.withValues(alpha:0.6));
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
                color: termTheme.cyan,
                fontWeight: FontWeight.w600,
                fontSize: 12);
          }
          return TextStyle(
              color: termTheme.foreground.withValues(alpha:0.6), fontSize: 12);
        }),
      ),
      cardTheme: CardThemeData(
        color: Color.lerp(
            termTheme.background, termTheme.foreground, 0.05),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: termTheme.foreground.withValues(alpha:0.1)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor:
            Color.lerp(termTheme.background, termTheme.foreground, 0.05),
        titleTextStyle: TextStyle(
            color: termTheme.foreground,
            fontSize: 20,
            fontWeight: FontWeight.w600),
        contentTextStyle:
            TextStyle(color: termTheme.foreground.withValues(alpha:0.8)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: termTheme.foreground.withValues(alpha:0.1)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor:
            Color.lerp(termTheme.background, termTheme.foreground, 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              BorderSide(color: termTheme.foreground.withValues(alpha:0.2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              BorderSide(color: termTheme.foreground.withValues(alpha:0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: termTheme.cyan, width: 2),
        ),
        labelStyle:
            TextStyle(color: termTheme.foreground.withValues(alpha:0.7)),
        hintStyle:
            TextStyle(color: termTheme.foreground.withValues(alpha:0.4)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: termTheme.cyan,
          foregroundColor:
              isLight ? Colors.white : termTheme.background,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: termTheme.cyan,
          foregroundColor:
              isLight ? Colors.white : termTheme.background,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: termTheme.cyan,
        ),
      ),
      iconTheme:
          IconThemeData(color: termTheme.foreground.withValues(alpha:0.8)),
      dividerTheme:
          DividerThemeData(color: termTheme.foreground.withValues(alpha:0.1)),
      listTileTheme: ListTileThemeData(
        iconColor: termTheme.foreground.withValues(alpha:0.7),
        textColor: termTheme.foreground,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: Color.lerp(
            termTheme.foreground, termTheme.background, 0.2),
        contentTextStyle: TextStyle(color: termTheme.background),
        actionTextColor: termTheme.cyan,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Color.lerp(
            termTheme.background, termTheme.foreground, 0.08),
        labelStyle: TextStyle(color: termTheme.foreground),
        side: BorderSide(color: termTheme.foreground.withValues(alpha:0.2)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Color.lerp(
            termTheme.background, termTheme.foreground, 0.05),
        textStyle: TextStyle(color: termTheme.foreground),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: termTheme.foreground.withValues(alpha:0.1)),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor:
            Color.lerp(termTheme.background, termTheme.foreground, 0.03),
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
        bodySmall:
            TextStyle(color: termTheme.foreground.withValues(alpha:0.7)),
        labelLarge: TextStyle(color: termTheme.foreground),
        labelMedium: TextStyle(color: termTheme.foreground),
        labelSmall:
            TextStyle(color: termTheme.foreground.withValues(alpha:0.7)),
      ),
    );
  }
}
