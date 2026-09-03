import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// System typography matrix.
///
/// Display headers: heavy condensed industrial geometric. Barlow Condensed
/// Bold is bundled (google_fonts no longer ships Roboto Condensed as its own
/// family); the platform fallback stack lands on SF Pro Display / Roboto.
/// Functional body: monospace for specs and numbers (JetBrains Mono).
class HubbleType {
  const HubbleType._();

  static TextStyle display({double size = 28, Color? color, FontWeight weight = FontWeight.w700}) =>
      GoogleFonts.barlowCondensed(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: 0.5,
        height: 1.05,
        color: color,
      );

  static TextStyle mono({double size = 14, Color? color, FontWeight weight = FontWeight.w500}) =>
      GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: weight, height: 1.35, color: color);

  static TextStyle body({double size = 15, Color? color}) =>
      GoogleFonts.barlowCondensed(fontSize: size, fontWeight: FontWeight.w400, height: 1.35, color: color);

  static TextTheme textTheme(Color onCanvas, Color iron) => TextTheme(
    displayLarge: display(size: 40, color: onCanvas),
    displayMedium: display(size: 32, color: onCanvas),
    displaySmall: display(size: 26, color: onCanvas),
    headlineMedium: display(size: 22, color: onCanvas),
    headlineSmall: display(size: 18, color: onCanvas),
    titleLarge: display(size: 20, color: onCanvas),
    titleMedium: display(size: 16, color: onCanvas),
    titleSmall: mono(size: 13, color: onCanvas, weight: FontWeight.w600),
    bodyLarge: body(size: 16, color: onCanvas),
    bodyMedium: body(size: 15, color: onCanvas),
    bodySmall: mono(size: 12, color: iron),
    labelLarge: mono(size: 14, color: onCanvas, weight: FontWeight.w700),
    labelMedium: mono(size: 12, color: onCanvas, weight: FontWeight.w600),
    labelSmall: mono(size: 11, color: iron),
  );
}
