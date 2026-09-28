import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/fanitt_logo.dart';
import '../widgets/sunrise_backdrop.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const _points = [
    (AppIcons.shieldCheck, 'Payment is locked in escrow before work starts'),
    (AppIcons.sealCheck, 'Every creator, brand and agency is verified'),
    (AppIcons.handshake, 'Deals, chat and delivery in one place'),
  ];

  @override
  Widget build(BuildContext context) {
    final white70 = Colors.white.withValues(alpha: 0.72);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.navy,
        body: SunriseBackdrop(
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.xl),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // The logo artwork already includes the name — no separate text.
                          const FanittLogo(size: 44).animate().fadeIn(duration: 400.ms),
                          const Spacer(),
                          Text(
                            'Work with brands.\nGet paid on time.',
                            style: context.text.displaySmall?.copyWith(color: Colors.white),
                          )
                              .animate(delay: 120.ms)
                              .fadeIn(duration: 500.ms)
                              .slideY(begin: 0.12, curve: Curves.easeOutCubic),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'Fanitt connects creators, brands and agencies across India, '
                                'with every payment protected by escrow.',
                            style: context.text.bodyLarge?.copyWith(color: white70),
                          ).animate(delay: 220.ms).fadeIn(duration: 500.ms),
                          const SizedBox(height: AppSpacing.xxl),
                          for (final (index, point) in _points.indexed)
                            Padding(
                              padding: const EdgeInsets.only(bottom: AppSpacing.md),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(AppRadius.sm),
                                    ),
                                    child: Icon(point.$1, size: 19, color: AppColors.sunrise),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Text(
                                      point.$2,
                                      style: context.text.titleSmall?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
                                    ),
                                  ),
                                ],
                              ),
                            ).animate(delay: (320 + index * 90).ms).fadeIn(duration: 400.ms).slideX(begin: 0.06),
                          const _RoleChips(),
                          const SizedBox(height: AppSpacing.xl),
                          AppButton(
                            label: 'Create account',
                            onPressed: () => context.push(AppRoutes.register),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          AppButton.secondary(
                            label: 'Log in',
                            onDark: true,
                            onPressed: () => context.push(AppRoutes.login),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Who Fanitt is for — three pills in place of platform numbers.
class _RoleChips extends StatelessWidget {
  const _RoleChips();

  static const _roles = [
    (AppIcons.creator, 'Creators'),
    (AppIcons.brand, 'Brands'),
    (AppIcons.agency, 'Agencies'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          for (final (index, role) in _roles.indexed)
            Container(
              padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(role.$1, size: 16, color: AppColors.sunrise),
                  const SizedBox(width: 6),
                  Text(role.$2, style: context.text.labelMedium?.copyWith(color: Colors.white)),
                ],
              ),
            ).animate(delay: (600 + index * 80).ms).fadeIn(duration: 350.ms).scale(begin: const Offset(0.92, 0.92)),
        ],
      ),
    );
  }
}