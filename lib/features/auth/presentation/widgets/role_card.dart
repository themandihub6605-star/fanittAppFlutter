import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/enums/user_role.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';

extension RolePresentation on UserRole {
  IconData get icon => switch (this) {
        UserRole.brand => AppIcons.brand,
        UserRole.agency => AppIcons.agency,
        _ => AppIcons.creator,
      };

  String get pitch => switch (this) {
        UserRole.creator => 'Find paid campaigns, send proposals and get paid safely through escrow.',
        UserRole.brand => 'Post campaigns, hire creators and pay only for work you approve.',
        UserRole.agency => 'Bring creators and brands to Fanitt with your code and earn commission.',
        _ => '',
      };

  String get nameFieldLabel => switch (this) {
        UserRole.brand => 'Brand name',
        UserRole.agency => 'Agency name',
        _ => 'Full name',
      };

  String get nameFieldHint => switch (this) {
        UserRole.brand => 'e.g. Chai Point',
        UserRole.agency => 'e.g. Northstar Talent',
        _ => 'Your full name',
      };
}

class RoleCard extends StatelessWidget {
  const RoleCard({super.key, required this.role, required this.selected, required this.onTap});

  final UserRole role;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Semantics(
      selected: selected,
      button: true,
      child: AnimatedContainer(
        duration: AppDurations.normal,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected ? palette.primarySoft : palette.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: selected ? AppColors.primary : palette.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: AppDurations.normal,
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: selected ? AppColors.primary : palette.surfaceMuted,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(role.icon, size: 22, color: selected ? Colors.white : palette.textSecondary),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(role.label, style: context.text.titleMedium),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(role.pitch, style: context.text.bodySmall?.copyWith(fontSize: 13)),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _RadioDot(selected: selected),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppDurations.normal,
      width: 22,
      height: 22,
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? AppColors.primary : context.palette.borderStrong,
          width: selected ? 6.5 : 1.5,
        ),
      ),
    );
  }
}
