import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/di/injection.dart';
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
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../dashboard/data/dashboard_repository.dart';
import '../../../profile/presentation/link_agency_sheet.dart';
import '../../../subscription/data/subscription_repository.dart';
import '../widgets/security_sheets.dart';

/// Every account option (wallet, store, plans, settings, log out…).
/// Opened from the ☰ on the Profile screen; [showCard] hides the top card
/// there because Profile already shows it.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, this.showCard = true});

  final bool showCard;

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
      appBar: AppBar(title: Text(showCard ? 'Account' : 'Settings & more')),
      body: RefreshIndicator.adaptive(
        color: AppColors.primary,
        onRefresh: () async => context.read<AuthBloc>().add(const AuthRefreshRequested()),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xxl),
          children: [
            if (showCard) AccountCard(user: user),
            const SizedBox(height: AppSpacing.xl),
            const _SectionLabel('Profile'),
            _Group(children: [
              _Tile(icon: AppIcons.user, title: 'Edit profile', onTap: () => context.push(AppRoutes.editProfile)),
              if (role == UserRole.brand) _Tile(icon: AppIcons.image, title: 'My posts & reels', onTap: () => context.push(AppRoutes.posts)),
              if (role == UserRole.creator) ...[
                _Tile(icon: AppIcons.image, title: 'My posts & reels', onTap: () => context.push(AppRoutes.posts)),
              //  _Tile(icon: AppIcons.videoCamera, title: 'Live sessions', onTap: () => context.push(AppRoutes.sessions)),
                _Tile(icon: AppIcons.gift, title: 'FanBox gifts', onTap: () => context.push(AppRoutes.gifts)),
              ],
            ]),
            const SizedBox(height: AppSpacing.lg),
            const _SectionLabel('Fanitt Store'),
            _Group(children: [
              if (role == UserRole.creator) _Tile(icon: AppIcons.store, title: 'My Fanitt Store', subtitle: 'Sell, stream and earn', onTap: () => context.push(AppRoutes.store)),
              if (role != UserRole.fan) _Tile(icon: AppIcons.storeFilled, title: 'Explore stores', onTap: () => context.push(AppRoutes.stores)),
              _Tile(icon: AppIcons.package, title: 'My orders', subtitle: 'Track your Fanitt Store orders', onTap: () => context.push(AppRoutes.shopOrders)),
              _Tile(icon: AppIcons.storeFilled, title: 'Fanitt Store', subtitle: 'Merch & products from creators', onTap: () => context.push(AppRoutes.shop)),
              _Tile(icon: AppIcons.library, title: 'My library', subtitle: 'Digital products you bought', onTap: () => context.push(AppRoutes.library)),
             // _Tile(icon: AppIcons.videoCamera, title: 'Virtual Meets', subtitle: 'Book and join meetings in the app', onTap: () => context.push(AppRoutes.meets)),
              _Tile(icon: AppIcons.bookmark, title: 'Saved posts', onTap: () => context.push(AppRoutes.savedPosts)),
            ]),
            const SizedBox(height: AppSpacing.lg),
            const _SectionLabel('Discover'),
            _Group(children: [
              if (role != UserRole.creator) _Tile(icon: AppIcons.feed, title: role == UserRole.brand ? 'Feed · post, reels & stories' : 'Feed', onTap: () => context.push(AppRoutes.feed)),
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

const _gradient = LinearGradient(colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]);

/// Last numbers per user, so coming back to Account shows them at once
/// (no jump while they reload).
final Map<String, ({CreatorDashboard? dashboard, UserSubscription? sub})> _accountCache = {};

/// Top of Account: photo, name, verified, role — and a fixed-height row of
/// money / plan numbers (with placeholders while loading, so the card
/// never changes size).
/// Who you are + your money numbers. [extra] is shown under the name
/// (the Profile screen puts followers / following / posts there).
class AccountCard extends StatefulWidget {
  const AccountCard({super.key, required this.user, this.extra});

  final AppUser user;
  final Widget? extra;

  @override
  State<AccountCard> createState() => AccountCardState();
}

class AccountCardState extends State<AccountCard> {
  CreatorDashboard? _dashboard;
  UserSubscription? _sub;
  bool _loaded = false;

  AppUser get user => widget.user;
  bool get _isCreator => user.role == UserRole.creator;
  bool get _hasPlan => user.role == UserRole.creator || user.role == UserRole.brand;

  @override
  void initState() {
    super.initState();
    final cached = _accountCache[user.id];
    if (cached != null) {
      _dashboard = cached.dashboard;
      _sub = cached.sub;
      _loaded = true;
    }
    _load();
  }

  @override
  void didUpdateWidget(covariant AccountCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.user, widget.user)) _load();
  }

  Future<void> _load() async {
    if (!_isCreator && !_hasPlan) {
      if (mounted) setState(() => _loaded = true);
      return;
    }
    try {
      final results = await Future.wait<Object?>([
        _isCreator ? sl<DashboardRepository>().creator(user.id) : Future<Object?>.value(),
        _hasPlan ? sl<SubscriptionRepository>().mine() : Future<Object?>.value(),
      ]);
      if (!mounted) return;
      setState(() {
        _dashboard = results[0] as CreatorDashboard?;
        _sub = results[1] as UserSubscription?;
        _loaded = true;
      });
      _accountCache[user.id] = (dashboard: _dashboard, sub: _sub);
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final status = user.profileStatus;
    final verified = status == VerificationStatus.verified;
    final sub = _sub;
    final limit = sub?.plan.proposalLimit;

    final stats = <Widget>[
      if (_isCreator)
        _Stat(
          label: 'Earnings',
          value: _dashboard == null ? null : Fmt.money(_dashboard!.totalEarnings),
          hint: _dashboard == null ? null : '${Fmt.money(_dashboard!.thisMonthEarnings)} this month',
          highlight: true,
          loading: !_loaded,
          onTap: () => context.push(AppRoutes.wallet),
        ),
      _Stat(
        label: 'Wallet',
        value: Fmt.money(user.walletBalance),
        hint: _isCreator ? 'Withdraw' : 'Open',
        highlight: !_isCreator,
        onTap: () => context.push(AppRoutes.wallet),
      ),
      if (_hasPlan)
        _Stat(
          label: 'Plan',
          value: sub?.plan.name,
          hint: sub == null ? null : (sub.plan.isFree ? 'Upgrade' : 'Manage'),
          hintColor: AppColors.primary,
          loading: !_loaded,
          onTap: () => context.push(AppRoutes.plans),
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border),
        boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x0F101828), blurRadius: 18, offset: Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Who you are
          Row(
            children: [
              SizedBox(
                width: 60,
                height: 60,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: _gradient),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(shape: BoxShape.circle, color: palette.surface),
                        child: UserAvatar(initials: user.initials, imageUrl: user.avatarUrl, size: 52),
                      ),
                    ),
                    if (verified)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          padding: const EdgeInsets.all(1.5),
                          decoration: BoxDecoration(shape: BoxShape.circle, color: palette.surface),
                          child: const Icon(AppIcons.sealCheck, size: 18, color: Color(0xFF3B82F6)),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.2),
                    ),
                    const SizedBox(height: 1),
                    Text(user.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _Tag(label: user.role.label, color: AppColors.primary),
                        if (status != null) ...[
                          const SizedBox(width: 6),
                          verified
                              ? const _Tag(label: 'Verified', color: Color(0xFF3B82F6), icon: AppIcons.sealCheck)
                              : _Tag(label: status.label, color: status == VerificationStatus.rejected ? AppColors.error : AppColors.warning),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit profile',
                onPressed: () => context.push(AppRoutes.editProfile),
                style: IconButton.styleFrom(backgroundColor: palette.surfaceMuted, fixedSize: const Size(38, 38)),
                icon: Icon(AppIcons.pencil, size: 17, color: palette.textPrimary),
              ),
            ],
          ),
          if (widget.extra != null) ...[
            const SizedBox(height: 14),
            widget.extra!,
          ],
          const SizedBox(height: 14),

          // Numbers — fixed height, so nothing jumps while loading.
          Material(
            color: palette.surfaceMuted,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: 70,
              child: Row(
                children: [
                  for (final (i, stat) in stats.indexed) ...[
                    if (i > 0) VerticalDivider(width: 1, thickness: 1, indent: 14, endIndent: 14, color: palette.border),
                    Expanded(child: stat),
                  ],
                ],
              ),
            ),
          ),

          // Proposals used (creators) — space kept while it loads.
          if (_isCreator) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 34,
              child: !_loaded
                  ? const _Placeholder(height: 34)
                  : sub == null
                  ? const SizedBox.shrink()
                  : limit == null
                  ? Row(
                children: [
                  Icon(AppIcons.paperPlane, size: 14, color: palette.textSecondary),
                  const SizedBox(width: 6),
                  Text('Unlimited proposals on your plan', style: context.text.bodySmall?.copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              )
                  : _ProposalMeter(used: sub.proposalsUsed, limit: limit, isFree: sub.plan.isFree),
            ),
          ],
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 11, color: color), const SizedBox(width: 3)],
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// One number in the stats row: label, value, small action.
class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.onTap, this.hint, this.hintColor, this.highlight = false, this.loading = false});

  final String label;
  final String? value;
  final String? hint;
  final Color? hintColor;
  final bool highlight;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final valueStyle = context.text.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: highlight ? Colors.white : palette.textPrimary);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, maxLines: 1, style: context.text.bodySmall?.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            SizedBox(
              height: 21,
              child: loading || value == null
                  ? const Align(alignment: Alignment.centerLeft, child: _Placeholder(width: 64, height: 14))
                  : FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: highlight
                    ? ShaderMask(shaderCallback: (r) => _gradient.createShader(r), child: Text(value!, style: valueStyle))
                    : Text(value!, style: valueStyle),
              ),
            ),
            SizedBox(
              height: 15,
              child: hint == null
                  ? null
                  : Text(
                hint!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: hintColor ?? palette.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grey bar shown while a number loads (same size as the real thing).
class _Placeholder extends StatelessWidget {
  const _Placeholder({this.width, required this.height});

  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: context.palette.border.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(8)),
    );
  }
}

/// "3 of 10 proposals used" with a slim bar — tap to manage the plan.
class _ProposalMeter extends StatelessWidget {
  const _ProposalMeter({required this.used, required this.limit, required this.isFree});

  final int used;
  final int limit;
  final bool isFree;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final share = limit == 0 ? 0.0 : (used / limit).clamp(0.0, 1.0).toDouble();
    return InkWell(
      onTap: () => context.push(AppRoutes.plans),
      borderRadius: BorderRadius.circular(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(AppIcons.paperPlane, size: 14, color: palette.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '$used', style: TextStyle(fontWeight: FontWeight.w800, color: palette.textPrimary)),
                    TextSpan(text: ' of $limit proposals used this cycle'),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall?.copyWith(fontSize: 12),
                ),
              ),
              if (isFree) Text('Get more', style: context.text.bodySmall?.copyWith(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Stack(
              children: [
                Container(height: 5, color: palette.surfaceMuted),
                FractionallySizedBox(widthFactor: share, child: Container(height: 5, decoration: const BoxDecoration(gradient: _gradient))),
              ],
            ),
          ),
        ],
      ),
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