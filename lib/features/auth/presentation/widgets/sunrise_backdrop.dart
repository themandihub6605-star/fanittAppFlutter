import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Navy canvas with the brand's sunrise glow rising from the bottom edge.
/// Used on the splash and welcome screens only.
class SunriseBackdrop extends StatelessWidget {
  const SunriseBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: AppColors.navy),
        Positioned(
          left: -120,
          right: -120,
          bottom: -260,
          height: 520,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.55),
                  AppColors.primary.withValues(alpha: 0.18),
                  AppColors.navy.withValues(alpha: 0),
                ],
                stops: const [0, 0.45, 1],
              ),
            ),
          ),
        ),
        Positioned(
          left: 40,
          right: 40,
          bottom: -140,
          height: 260,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.sunrise.withValues(alpha: 0.35),
                  AppColors.sunrise.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
