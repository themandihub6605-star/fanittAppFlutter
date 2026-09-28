import 'package:flutter/material.dart';

/// Fanitt brand colors. Theme-dependent neutrals live in [AppPalette].
abstract final class AppColors {
  // Brand
  static const Color primary = Color(0xFFF4511E);
  static const Color primaryPressed = Color(0xFFD9420F);
  static const Color sunrise = Color(0xFFFFD65C);
  static const Color navy = Color(0xFF0A1325);
  static const Color navyRaised = Color(0xFF14203A);

  // Status
  static const Color success = Color(0xFF12A150);
  static const Color warning = Color(0xFFE59A0B);
  static const Color error = Color(0xFFDC2F2F);
  static const Color info = Color(0xFF2F6FEB);

  /// The sunrise gradient. Reserved for the logo mark and brand moments.
  static const LinearGradient sunriseGradient = LinearGradient(
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
    colors: [primary, sunrise],
  );
}
