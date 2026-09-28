import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// One family, Plus Jakarta Sans, with a deliberate scale.
abstract final class AppTypography {
  static TextStyle _style(
    double size,
    FontWeight weight,
    Color color, {
    double height = 1.35,
    double letterSpacing = 0,
  }) {
    return GoogleFonts.plusJakartaSans(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static TextTheme textTheme({required Color primary, required Color secondary}) {
    return TextTheme(
      displaySmall: _style(34, FontWeight.w800, primary, height: 1.12, letterSpacing: -1.0),
      headlineLarge: _style(30, FontWeight.w800, primary, height: 1.15, letterSpacing: -0.8),
      headlineMedium: _style(26, FontWeight.w800, primary, height: 1.2, letterSpacing: -0.6),
      headlineSmall: _style(22, FontWeight.w700, primary, height: 1.25, letterSpacing: -0.4),
      titleLarge: _style(18, FontWeight.w700, primary, height: 1.3, letterSpacing: -0.2),
      titleMedium: _style(16, FontWeight.w600, primary, height: 1.35),
      titleSmall: _style(14, FontWeight.w600, primary, height: 1.4),
      bodyLarge: _style(16, FontWeight.w400, primary, height: 1.5),
      bodyMedium: _style(14, FontWeight.w400, secondary, height: 1.5),
      bodySmall: _style(12.5, FontWeight.w400, secondary, height: 1.45),
      labelLarge: _style(15, FontWeight.w600, primary, height: 1.2),
      labelMedium: _style(13, FontWeight.w600, primary, height: 1.2),
      labelSmall: _style(11.5, FontWeight.w600, secondary, height: 1.2, letterSpacing: 0.1),
    );
  }
}
