import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/enums/user_role.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/services/share_service.dart';
import '../../../../core/services/link_opener.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../profile/presentation/link_agency_sheet.dart';
import '../widgets/security_sheets.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    final ok = await confirmAction(
      context,
      title: 'Log out of Fanitt?',
      message: 'You’ll need to log in again to see your campaigns and payments.',
      confirmLabel: 'Log out',
      destructive: true,
    );
    if (ok && context.mounted) context.read<AuthBloc>().add(const AuthLogoutRequested());
  }

  Future<void> _contactSupport(BuildContext context) async {
    try {
      await LinkOpener.email(AppConfig.supportEmail);
    } on ApiException {
      await Clipboard.setData(const ClipboardData(text: AppConfig.supportEmail));
      if (context.mounted) AppSnackbar.info(context, 'Support email copied');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    if (auth is! AuthAuthenticated) return const Scaffold();
    final user = auth.user;
    final role = user.role;

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: RefreshIndicator.adaptive(
        color: AppColors.primary,
        onRefresh: () async => context.read<AuthBloc>().add(const AuthRefreshRequested()),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xxl),
          children: [
            _ProfileHeader(user: user),
            const SizedBox(height: AppSpacing.xl),
            const _SectionLabel('Profile'),
            _Group(children: [
              _Tile(icon: AppIcons.user, title: 'Edit profile', onTap: () => context.push(AppRoutes.editProfile)),
              if (role == UserRole.creator) ...[
                _Tile(icon: AppIcons.image, title: 'My posts', onTap: () => context.push(AppRoutes.posts)),
                //_Tile(icon: AppIcons.videoCamera, title: 'Live sessions', onTap: () => context.push(AppRoutes.sessions)),
                _Tile(icon: AppIcons.gift, title: 'FanBox gifts', onTap: () => context.push(AppRoutes.gifts)),
              ],
            ]),
            const SizedBox(height: AppSpacing.lg),
            const _SectionLabel('Fanitt Store'),
            _Group(children: [
              if (role == UserRole.creator) _Tile(icon: AppIcons.store, title: 'My Fanitt Store', subtitle: 'Sell, stream and earn', onTap: () => context.push(AppRoutes.store)),
              if (role != UserRole.fan) _Tile(icon: AppIcons.storeFilled, title: 'Explore stores', onTap: () => context.push(AppRoutes.stores)),
              _Tile(icon: AppIcons.library, title: 'My library', subtitle: 'Products you bought', onTap: () => context.push(AppRoutes.library)),
              _Tile(icon: AppIcons.videoCamera, title: 'Explore Live Sessions', subtitle: 'Book and join meetings in the app', onTap: () => context.push(AppRoutes.meets)),
              _Tile(icon: AppIcons.bookmark, title: 'Saved posts', onTap: () => context.push(AppRoutes.savedPosts)),
            ]),
            const SizedBox(height: AppSpacing.lg),
            const _SectionLabel('Discover'),
            _Group(children: [
              if (role != UserRole.creator) _Tile(icon: AppIcons.feed, title: 'Creator feed', onTap: () => context.push(AppRoutes.feed)),
              if (role != UserRole.brand)
                _Tile(icon: AppIcons.creators, title: 'Creators', onTap: () => context.push(AppRoutes.creatorsDirectory)),
              if (role == UserRole.creator) _Tile(icon: AppIcons.brand, title: 'Brands', onTap: () => context.push(AppRoutes.brands)),
              _Tile(icon: AppIcons.users, title: 'Communities', onTap: () => context.push(AppRoutes.communities)),
              _Tile(icon: AppIcons.userPlus, title: 'Following', onTap: () => context.push(AppRoutes.following)),
            ]),
            const SizedBox(height: AppSpacing.lg),
            const _SectionLabel('Money'),
            _Group(children: [
              if (role != UserRole.agency && role != UserRole.fan) _Tile(icon: AppIcons.crown, title: 'Plans & billing', onTap: () => context.push(AppRoutes.plans)),
              if (role == UserRole.creator || role == UserRole.brand || role == UserRole.fan)
                _Tile(icon: AppIcons.wallet, title: 'Wallet', subtitle: Fmt.money(user.walletBalance), onTap: () => context.push(AppRoutes.wallet)),
              _Tile(icon: AppIcons.receipt, title: 'All activity', onTap: () => context.push(AppRoutes.transactions)),
              if (role != UserRole.agency) _Tile(icon: AppIcons.gift, title: 'Refer & earn', onTap: () => context.push(AppRoutes.referrals)),
              if (role == UserRole.creator || role == UserRole.brand)
                _Tile(
                  icon: AppIcons.agency,
                  title: 'Join an agency',
                  onTap: () async {
                    final linked = await showLinkAgencySheet(context, asCreator: role == UserRole.creator);
                    if (linked && context.mounted) AppSnackbar.success(context, 'You’ve joined the agency');
                  },
                ),
            ]),
            const SizedBox(height: AppSpacing.lg),
            const _SectionLabel('Help'),
            _Group(children: [
              _Tile(icon: AppIcons.bell, title: 'Notifications', onTap: () => context.push(AppRoutes.notifications)),
              _Tile(icon: AppIcons.mail, title: 'Contact support', subtitle: AppConfig.supportEmail, onTap: () => _contactSupport(context)),
              _Tile(icon: AppIcons.shieldCheck, title: 'Privacy policy', onTap: () => context.push(AppRoutes.privacyPolicy)),
              _Tile(icon: AppIcons.fileText, title: 'Terms of use', onTap: () => context.push(AppRoutes.termsOfUse)),
              Builder(builder: (ctx) => _Tile(icon: AppIcons.share, title: 'Share Fanitt', subtitle: 'Invite friends to the app', onTap: () => ShareService.send(ctx, ShareService.app()))),
            ]),
            const SizedBox(height: AppSpacing.lg),
            const _SectionLabel('Security'),
            _Group(children: [
              if (user.authProvider != 'google')
                _Tile(
                  icon: AppIcons.lock,
                  title: 'Change password',
                  onTap: () async {
                    if (await showChangePasswordSheet(context) && context.mounted) AppSnackbar.success(context, 'Password updated');
                  },
                ),
              _Tile(icon: AppIcons.signOut, title: 'Log out', onTap: () => _logout(context)),
              _Tile(icon: AppIcons.trash, title: 'Delete account', destructive: true, onTap: () => showDeleteAccountSheet(context)),
            ]),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final status = user.profileStatus;
    return Row(
      children: [
        UserAvatar(initials: user.initials, imageUrl: user.avatarUrl, size: 64),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.name, style: context.text.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(user.email, style: context.text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  StatusChip(label: user.role.label, color: AppColors.primary),
                  if (status != null)
                    StatusChip(
                      label: status.label,
                      color: status == VerificationStatus.verified ? AppColors.success : palette.textSecondary,
                      icon: status == VerificationStatus.verified ? AppIcons.sealCheck : null,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: AppSpacing.xxs, bottom: AppSpacing.xs),
    child: Text(text, style: context.text.labelMedium?.copyWith(color: context.palette.textSecondary)),
  );
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg), side: BorderSide(color: palette.border)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0) const Divider(indent: 56),
            child,
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, required this.onTap, this.subtitle, this.destructive = false});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ListTile(
      onTap: onTap,
      minTileHeight: 56,
      shape: const RoundedRectangleBorder(),
      leading: Icon(icon, size: 22, color: destructive ? AppColors.error : palette.textSecondary),
      title: Text(title, style: context.text.titleSmall?.copyWith(color: destructive ? AppColors.error : palette.textPrimary)),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: destructive ? null : Icon(AppIcons.chevronRight, size: 18, color: palette.textTertiary),
    );
  }
}