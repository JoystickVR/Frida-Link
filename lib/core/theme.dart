import 'package:flutter/material.dart';

/// Material 3 (Material You) theme for Frida Link, seeded from a user-chosen
/// accent color. Defaults to the Meta brand blue `#0081FB`.
///
/// All Chrome/surface colors derive from `ColorScheme.fromSeed` roles; the
/// only deliberate constants left are semantic log/status colors ([LogColors]).
ThemeData buildFridaTheme({
  required bool dark,
  int accentSeed = 0xFF0081FB,
  bool material2 = false,
}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: Color(accentSeed),
    brightness: dark ? Brightness.dark : Brightness.light,
  );

  // Honor the picked accent exactly: fromSeed derives a tonal palette that
  // can shift the hue/tone, so pin the primary roles to the exact seed. On
  // surfaces pick the on-color by luminance for readable contrast.
  final accent = Color(accentSeed);
  final accentLuma = accent.computeLuminance();
  final onAccent = accentLuma > 0.45 ? Colors.black : Colors.white;
  final withAccent = ThemeData(
    colorScheme: scheme.copyWith(
      primary: accent,
      onPrimary: onAccent,
      primaryContainer: dark
          ? Color.lerp(accent, Colors.white, 0.18)!
          : Color.lerp(accent, Colors.black, 0.22)!,
      onPrimaryContainer: dark
          ? Color.lerp(accent, Colors.white, 0.72)!
          : Color.lerp(accent, Colors.white, 0.9)!,
    ),
  );

  final base = ThemeData(
    useMaterial3: !material2,
    brightness: dark ? Brightness.dark : Brightness.light,
    colorScheme: withAccent.colorScheme,
    scaffoldBackgroundColor: withAccent.colorScheme.surface,
    visualDensity: VisualDensity.compact,
    dividerColor: withAccent.colorScheme.outlineVariant,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),
    // Cards: M3 "medium" corner (12), tonal elevation via surfaceContainer.
    cardTheme: CardTheme(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    // Text fields: basic text fields use the "small" M3 corner (8).
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    // Navigation rail indicator uses the tonal secondary-container role.
    navigationRailTheme: const NavigationRailThemeData(
      labelType: NavigationRailLabelType.all,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    // Dialogs / bottom sheets get M3 extra-large corners (28).
    dialogTheme: DialogTheme(
      backgroundColor: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      contentTextStyle: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(
        color: scheme.onInverseSurface,
        fontSize: 12.5,
        fontFamily: 'monospace',
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    // Buttons keep the monospace treatment of the terminal aesthetic.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        textStyle: const TextStyle(
            fontFamily: 'monospace', fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        textStyle: const TextStyle(
            fontFamily: 'monospace', fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: const TextStyle(
            fontFamily: 'monospace', fontWeight: FontWeight.w600),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 600),
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(4),
      ),
    ),
  );
}

/// Colors for log output levels — semantic, terminal-style signal colors.
class LogColors {
  static const info = Color(0xFF9AA7AD);
  static const output = Color(0xFFC8D0D3);
  static const payload = Color(0xFF4FB8FF);
  static const warning = Color(0xFFFFC94D);
  static const error = Color(0xFFFF6B6B);
  static const system = Color(0xFF7DD7F7);
}

/// Monospace text helpers for the terminal aesthetic.
class Mono {
  static TextStyle small(TextTheme t, {Color? color}) => TextStyle(
        fontFamily: 'monospace',
        fontSize: 12,
        height: 1.45,
        color: color,
      );

  static TextStyle code(TextTheme t, {Color? color, double size = 12.5}) =>
      TextStyle(
        fontFamily: 'monospace',
        fontSize: size,
        height: 1.4,
        color: color,
      );
}
