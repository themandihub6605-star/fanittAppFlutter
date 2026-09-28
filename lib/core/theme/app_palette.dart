import 'package:flutter/material.dart';

/// Neutral colors that change between light and dark themes.
/// Read with `context.palette`.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.primarySoft,
  });

  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  /// Tinted brand background for selected states and icon wells.
  final Color primarySoft;

  static const AppPalette light = AppPalette(
    background: Color(0xFFF7F7F9),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF0F1F4),
    border: Color(0xFFE6E7EC),
    borderStrong: Color(0xFFD3D5DD),
    textPrimary: Color(0xFF111827),
    textSecondary: Color(0xFF5A6272),
    textTertiary: Color(0xFF979DAB),
    primarySoft: Color(0xFFFFF0EA),
  );

  static const AppPalette dark = AppPalette(
    background: Color(0xFF0A1325),
    surface: Color(0xFF111C31),
    surfaceMuted: Color(0xFF17243D),
    border: Color(0xFF212F4A),
    borderStrong: Color(0xFF2E3E5E),
    textPrimary: Color(0xFFF2F4F8),
    textSecondary: Color(0xFFA2ACBF),
    textTertiary: Color(0xFF6C7890),
    primarySoft: Color(0xFF2A1D22),
  );

  @override
  AppPalette copyWith({
    Color? background,
    Color? surface,
    Color? surfaceMuted,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? primarySoft,
  }) {
    return AppPalette(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      primarySoft: primarySoft ?? this.primarySoft,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      primarySoft: Color.lerp(primarySoft, other.primarySoft, t)!,
    );
  }
}

extension ThemeContextX on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
  TextTheme get text => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
