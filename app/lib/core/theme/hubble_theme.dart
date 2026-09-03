import 'package:flutter/material.dart';

import 'tokens.dart';
import 'typography.dart';

/// Builds a full Material theme from a token set. Called once for the host
/// and again whenever a vendor storefront injects overrides.
ThemeData buildHubbleTheme(HubbleTokens t) {
  final scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: t.accent,
    onPrimary: t.onAccent,
    secondary: t.iron,
    onSecondary: t.onCanvas,
    error: t.alert,
    onError: Colors.white,
    surface: t.surface,
    onSurface: t.onCanvas,
    outline: t.iron,
    surfaceContainerHighest: t.surface,
  );
  final text = HubbleType.textTheme(t.onCanvas, t.iron);
  const shape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(6)));

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.canvas,
    canvasColor: t.canvas,
    cardColor: t.surface,
    dividerColor: t.iron,
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: t.canvas,
      foregroundColor: t.onCanvas,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
      shape: Border(bottom: BorderSide(color: t.iron, width: 1)),
    ),
    cardTheme: CardThemeData(
      color: t.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: t.iron),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.accent,
        foregroundColor: t.onAccent,
        shape: shape,
        textStyle: HubbleType.mono(size: 14, weight: FontWeight.w700),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.accent,
        side: BorderSide(color: t.accent, width: 1.5),
        shape: shape,
        textStyle: HubbleType.mono(size: 14, weight: FontWeight.w700),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: t.accent, textStyle: HubbleType.mono(size: 13)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.surface,
      labelStyle: HubbleType.mono(size: 13, color: t.iron),
      hintStyle: HubbleType.mono(size: 13, color: t.iron),
      border: OutlineInputBorder(
        borderSide: BorderSide(color: t.iron),
        borderRadius: BorderRadius.circular(6),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: t.iron),
        borderRadius: BorderRadius.circular(6),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: t.accent, width: 2),
        borderRadius: BorderRadius.circular(6),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: BorderSide(color: t.alert),
        borderRadius: BorderRadius.circular(6),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: t.surface,
      selectedColor: t.accent,
      labelStyle: HubbleType.mono(size: 12, color: t.onCanvas),
      side: BorderSide(color: t.iron),
      shape: shape,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: t.surface,
      indicatorColor: t.accent.withValues(alpha: 0.18),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(color: states.contains(WidgetState.selected) ? t.accent : t.iron),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => HubbleType.mono(
          size: 11,
          color: states.contains(WidgetState.selected) ? t.accent : t.iron,
          weight: FontWeight.w600,
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.onAccent : t.onCanvas,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.accent : t.iron,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.surface,
      contentTextStyle: HubbleType.mono(size: 13, color: t.onCanvas),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: t.iron),
      ),
    ),
    dividerTheme: DividerThemeData(color: t.iron, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(iconColor: t.accent, textColor: t.onCanvas),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: t.accent),
  );
}
