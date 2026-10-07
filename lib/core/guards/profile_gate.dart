import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/entities/app_user.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../enums/user_role.dart';
import '../router/app_routes.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_palette.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_button.dart';

// "Complete your profile first" gate.
//
// Creators, brands and agencies who haven't completed their profile yet
// (status `unverified`) can look around, but can't use the main actions:
// post campaigns or posts, apply, message, browse creators or the feed,
// run a store, go live, take calls or buy. Fans have no profile to
// complete, so they're never gated. (Once a profile is submitted it goes
// to review, which the app already handles with the verification screen.)

/// True when this user must finish their profile before taking actions.
bool needsProfileCompletion(AppUser? user) {
  if (user == null) return false;
  const roles = {UserRole.creator, UserRole.brand, UserRole.agency};
  return roles.contains(user.role) && user.profileStatus == VerificationStatus.unverified;
}

/// Screens that need a complete profile. Matching is by path prefix.
const _lockedPaths = <String>[
  AppRoutes.campaignEditorPath, // post a campaign
  '/app/manage', // manage campaign (proposals, payments)
  '/app/chat', // open a conversation
  AppRoutes.creatorsDirectory, // creators list + creator profiles
  AppRoutes.feed,
  AppRoutes.following,
  AppRoutes.posts, // create / manage posts
  AppRoutes.sessions, // create sessions
  AppRoutes.communityForm, // create a community
  AppRoutes.communityChat,
  AppRoutes.gifts,
  AppRoutes.store, // my Fanitt Store and everything under it
  AppRoutes.liveRoom,
  '/app/call', // 1-to-1 calls
];

/// True when [location] is one of the screens above.
bool isProfileLockedLocation(String location) {
  final path = Uri.parse(location).path;
  return _lockedPaths.any((p) => path == p || path.startsWith('$p/'));
}

AppUser? _currentUser(BuildContext context) {
  final auth = context.read<AuthBloc>().state;
  return auth is AuthAuthenticated ? auth.user : null;
}

/// For buttons that don't navigate (apply, buy, book…). Shows the popup and
/// returns false when the profile isn't complete; true otherwise.
Future<bool> ensureProfileComplete(BuildContext context) async {
  if (!needsProfileCompletion(_currentUser(context))) return true;
  await context.push(AppRoutes.completeProfile);
  return false;
}

/// The popup, shown as a see-through page on top of the current screen
/// (the router sends locked screens here).
class CompleteProfilePopup extends StatelessWidget {
  const CompleteProfilePopup({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final role = auth is AuthAuthenticated ? auth.user.role : null;
    final palette = context.palette;
    final what = switch (role) {
      UserRole.brand => 'brand profile',
      UserRole.agency => 'agency profile',
      _ => 'creator profile',
    };

    return GestureDetector(
      onTap: () => context.pop(),
      behavior: HitTestBehavior.opaque,
      child: Material(
        color: Colors.transparent,
        child: Center(
          child: GestureDetector(
            onTap: () {}, // taps inside the card don't close it
            child: Container(
              margin: const EdgeInsets.all(AppSpacing.xl),
              padding: const EdgeInsets.all(AppSpacing.xl),
              constraints: const BoxConstraints(maxWidth: 420),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(AppRadius.xl),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 30, offset: const Offset(0, 12))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primary.withValues(alpha: 0.14)),
                    child: const Icon(AppIcons.user, color: AppColors.primary, size: 34),
                  )
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .scaleXY(begin: 1, end: 1.07, duration: 1100.ms, curve: Curves.easeInOut),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Please complete your profile', textAlign: TextAlign.center, style: context.text.titleLarge),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Finish your $what to post, apply, message, see creators and the feed, and use Fanitt Store. You can keep looking around until then.',
                    textAlign: TextAlign.center,
                    style: context.text.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  AppButton(
                    label: 'Complete profile',
                    icon: AppIcons.arrowRightSimple,
                    onPressed: () {
                      final router = GoRouter.of(context);
                      router.pop();
                      router.push(AppRoutes.editProfile);
                    },
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  TextButton(onPressed: () => context.pop(), child: const Text('Not now')),
                ],
              ),
            ).animate().fadeIn(duration: 200.ms).scaleXY(begin: 0.92, curve: Curves.easeOutBack, duration: 320.ms),
          ),
        ),
      ),
    );
  }
}

/// Wraps a bottom-nav tab (Feed, Creators, Messages): shows a friendly lock
/// screen instead of the content until the profile is complete.
class ProfileGatedTab extends StatelessWidget {
  const ProfileGatedTab({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    if (!needsProfileCompletion(auth is AuthAuthenticated ? auth.user : null)) return child;
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(shape: BoxShape.circle, color: palette.surfaceMuted),
                child: Icon(AppIcons.lock, size: 38, color: palette.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Complete your profile to unlock $title', textAlign: TextAlign.center, style: context.text.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              Text('It only takes a few minutes.', textAlign: TextAlign.center, style: context.text.bodyMedium),
              const SizedBox(height: AppSpacing.lg),
              AppButton(label: 'Complete profile', expand: false, onPressed: () => context.push(AppRoutes.editProfile)),
            ].animate(interval: 60.ms).fadeIn(duration: 300.ms).slideY(begin: 0.08),
          ),
        ),
      ),
    );
  }
}