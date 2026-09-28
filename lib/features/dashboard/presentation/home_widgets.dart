import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/enums/user_role.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/domain/entities/app_user.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';

/// Greeting header shared by all home screens, with notifications.
class HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const HomeAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(64);

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final user = auth is AuthAuthenticated ? auth.user : null;
    return AppBar(
      toolbarHeight: 64,
      title: Row(
        children: [
          UserAvatar(initials: user?.initials ?? '?', imageUrl: user?.avatarUrl, size: 40),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_greeting(), style: context.text.bodySmall),
                Text(user?.firstName ?? '', style: context.text.titleMedium, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(tooltip: 'Notifications', icon: const Icon(AppIcons.bell), onPressed: () => context.push(AppRoutes.notifications)),
        const SizedBox(width: AppSpacing.xs),
      ],
    );
  }
}

/// Nudges an unverified user to complete and submit their profile.
class ProfileCompletionBanner extends StatelessWidget {
  const ProfileCompletionBanner({super.key, required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    if (user.profileStatus != VerificationStatus.unverified) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: AppCard(
        color: context.palette.primarySoft,
        borderColor: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(AppIcons.sealCheck, color: AppColors.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text('Get verified', style: context.text.titleMedium)),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Complete your ${user.role.label.toLowerCase()} profile and submit it for review to unlock everything on Fanitt.',
              style: context.text.bodyMedium?.copyWith(color: context.palette.textPrimary),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(label: 'Complete profile', height: 46, onPressed: () => context.push(AppRoutes.editProfile)),
          ],
        ),
      ),
    );
  }
}

class QuickAction extends StatelessWidget {
  const QuickAction({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Expanded(
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.xs),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: palette.primarySoft, borderRadius: BorderRadius.circular(AppRadius.sm)),
              child: Icon(icon, size: 20, color: AppColors.primary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(label, style: context.text.labelMedium, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
