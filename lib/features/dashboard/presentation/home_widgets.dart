import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/injection.dart';
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
import '../../notifications/data/notification_repository.dart';
import 'home_discover.dart';

/// Greeting header shared by all home screens, with notifications.
class HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const HomeAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(72);

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
      toolbarHeight: 72,
      titleSpacing: AppSpacing.gutter,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${_greeting()},', style: context.text.bodySmall?.copyWith(fontSize: 12)),
          const SizedBox(height: 2),
          Text(
            '${user?.firstName ?? ''} 👋',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.headlineSmall?.copyWith(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3),
          ),
        ],
      ),
      actions: [
        const _NotificationBell(),
        const SizedBox(width: AppSpacing.xxs),
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.gutter),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => context.push(AppRoutes.editProfile),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFFF4511E), Color(0xFFEC2A78)])),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(shape: BoxShape.circle, color: context.palette.background),
                child: UserAvatar(initials: user?.initials ?? '?', imageUrl: user?.avatarUrl, size: 38),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Bell with the unread count. Refreshes when the home is pulled to refresh
/// and whenever the user comes back from the notifications screen.
class _NotificationBell extends StatefulWidget {
  const _NotificationBell();

  @override
  State<_NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<_NotificationBell> {
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _load();
    homeRefreshTick.addListener(_load);
  }

  @override
  void dispose() {
    homeRefreshTick.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final feed = await sl<NotificationRepository>().feed();
      if (mounted) setState(() => _unread = feed.unreadCount);
    } catch (_) {
      // Keep the last known count.
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Material(
            color: palette.surface,
            shape: CircleBorder(side: BorderSide(color: palette.border)),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () async {
                await context.push(AppRoutes.notifications);
                _load();
              },
              child: const SizedBox(width: 44, height: 44, child: Icon(AppIcons.bell, size: 22)),
            ),
          ),
          if (_unread > 0)
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(9), border: Border.all(color: palette.background, width: 2)),
                alignment: Alignment.center,
                child: Text(_unread > 99 ? '99+' : '$_unread', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, height: 1)),
              ).animate(key: ValueKey(_unread)).scale(begin: const Offset(0.4, 0.4), duration: 300.ms, curve: Curves.easeOutBack),
            ),
        ],
      ),
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