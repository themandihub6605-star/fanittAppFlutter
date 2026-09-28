import 'package:flutter/widgets.dart';

/// 4-point spacing scale. Every margin and padding in the app comes from here.
abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 40;
  static const double huge = 56;

  /// Horizontal gutter for every screen.
  static const double gutter = 20;

  static const EdgeInsets screen = EdgeInsets.symmetric(horizontal: gutter);
}

abstract final class AppRadius {
  static const double xs = 8;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;
  static const double pill = 999;
}

abstract final class AppDurations {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);
}
