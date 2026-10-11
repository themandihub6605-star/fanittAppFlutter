import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/injection.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/guards/profile_gate.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/services/share_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../brands/data/brands_repository.dart';
import '../../campaigns/data/campaign_models.dart';
import '../../campaigns/data/campaign_repository.dart';
import '../../community/data/community_repository.dart';
import '../../community/presentation/community_paid_join.dart' show communityPriceLabel;
import '../../creators/data/creators_repository.dart';
import '../../profile/data/profile_models.dart';
import '../../store/data/store_repository.dart';
import '../../store/presentation/live/live_poster_card.dart';
import '../../store/presentation/commerce/shop_home_section.dart';
import '../../store/presentation/meet/meet_detail_screen.dart';
import '../../store/presentation/widgets/store_widgets.dart';

// Home screen discovery kit: section headers, quick actions and horizontal
// rails (creators, brands, campaigns, live, meets, communities, stores).
// Every rail loads its own real data, shows a shimmer while loading and
// hides itself when there's nothing to show — no placeholder content.

/// Admin-pinned items first (in the admin's order), then the usual list,
/// without duplicates.
Future<List<T>> pinnedFirst<T>({
  required List<String> pinned,
  required Future<List<T>> Function(List<String> ids) loadPinned,
  required Future<List<T>> Function() loadRest,
  required String Function(T item) idOf,
  int max = 12,
  bool onlyPinned = false,
}) async {
  var first = <T>[];
  if (pinned.isNotEmpty) {
    try {
      final order = {for (var i = 0; i < pinned.length; i++) pinned[i]: i};
      first = [...await loadPinned(pinned)]..sort((a, b) => (order[idOf(a)] ?? 999).compareTo(order[idOf(b)] ?? 999));
    } catch (_) {
      first = <T>[];
    }
  }
  // Admin chose "only my picks": nothing automatic after them.
  if (onlyPinned && pinned.isNotEmpty) return first.take(max).toList();
  final seen = first.map(idOf).toSet();
  final rest = await loadRest();
  return [...first, ...rest.where((x) => !seen.contains(idOf(x)))].take(max).toList();
}

/// Bump this on pull-to-refresh: every rail reloads.
final ValueNotifier<int> homeRefreshTick = ValueNotifier<int>(0);

const _brandGradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]);

// Home design tokens (8pt grid): 20px side margins, 24px between sections,
// 16px card corners, 12px button corners, 1px borders instead of heavy shadows.
const double kHomeCardRadius = 16;
const double kHomeButtonRadius = 12;

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

class HomeSectionHeader extends StatelessWidget {
  const HomeSectionHeader({super.key, required this.title, this.subtitle, this.onSeeAll, this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.gutter)});

  final String title;
  final String? subtitle;
  final VoidCallback? onSeeAll;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: context.text.bodySmall?.copyWith(fontSize: 12)),
                ],
              ],
            ),
          ),
          if (onSeeAll != null)
            InkWell(
              borderRadius: BorderRadius.circular(kHomeButtonRadius),
              onTap: onSeeAll,
              child: Padding(
                // 44px tall tap target.
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('See all', style: context.text.labelLarge?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 2),
                    const Icon(AppIcons.chevronRight, size: 14, color: AppColors.primary),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick actions (4 per row)
// ---------------------------------------------------------------------------

class HomeAction {
  const HomeAction({required this.icon, required this.label, required this.onTap, this.color = AppColors.primary, this.isNew = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool isNew;
}

class HomeQuickActions extends StatelessWidget {
  const HomeQuickActions({super.key, required this.actions});

  final List<HomeAction> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: actions.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: 88),
        itemBuilder: (context, i) => _ActionTile(action: actions[i], highlighted: i == 0)
            .animate(delay: (35 * i).ms)
            .fadeIn(duration: 280.ms)
            .scaleXY(begin: 0.85, curve: Curves.easeOutBack, duration: 380.ms),
      ),
    );
  }
}

class _ActionTile extends StatefulWidget {
  const _ActionTile({required this.action, this.highlighted = false});

  final HomeAction action;

  /// The first action gets the brand gradient so the main thing stands out.
  final bool highlighted;

  @override
  State<_ActionTile> createState() => _ActionTileState();
}

class _ActionTileState extends State<_ActionTile> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.action;
    final hi = widget.highlighted;
    final palette = context.palette;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        HapticFeedback.selectionClick();
        a.onTap();
      },
      child: AnimatedScale(
        scale: _down ? 0.93 : 1,
        duration: const Duration(milliseconds: 110),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: hi ? _brandGradient : null,
                color: hi ? null : (_down ? palette.surfaceMuted : palette.surface),
                borderRadius: BorderRadius.circular(kHomeCardRadius),
                border: hi ? null : Border.all(color: palette.border),
                boxShadow: hi ? [BoxShadow(color: const Color(0xFFF4511E).withValues(alpha: 0.28), blurRadius: 14, offset: const Offset(0, 6))] : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hi ? Colors.white.withValues(alpha: 0.22) : a.color.withValues(alpha: 0.12),
                    ),
                    child: Icon(a.icon, size: 20, color: hi ? Colors.white : a.color),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      a.label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: hi ? Colors.white : palette.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
            if (a.isNew)
              Positioned(
                right: -4,
                top: -6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    // White badge on the orange card, orange badge on the others.
                    gradient: hi ? null : _brandGradient,
                    color: hi ? Colors.white : null,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4, offset: const Offset(0, 1))],
                  ),
                  child: Text('NEW', style: TextStyle(color: hi ? AppColors.primary : Colors.white, fontSize: 8, fontWeight: FontWeight.w900)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Generic rail
// ---------------------------------------------------------------------------

/// Horizontal list that loads its own data. Hidden when empty or on error.
class HomeRail<T> extends StatefulWidget {
  const HomeRail({
    super.key,
    required this.title,
    required this.load,
    required this.itemBuilder,
    required this.height,
    required this.itemWidth,
    this.subtitle,
    this.onSeeAll,
    this.leading,
  });

  final String title;
  final String? subtitle;
  final Future<List<T>> Function() load;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final double height;
  final double itemWidth;
  final VoidCallback? onSeeAll;

  /// Optional widget before the title (e.g. a pulsing "live" dot).
  final Widget? leading;

  @override
  State<HomeRail<T>> createState() => _HomeRailState<T>();
}

class _HomeRailState<T> extends State<HomeRail<T>> with AutomaticKeepAliveClientMixin {
  // Keep loaded rails alive while scrolling — no reload, no flicker.
  @override
  bool get wantKeepAlive => true;

  late Future<List<T>> _future = _safeLoad();

  Future<List<T>> _safeLoad() async {
    try {
      return await widget.load();
    } catch (error, stack) {
      // The rail hides itself on failure — log why, so a missing section is easy to trace.
      debugPrint('[home] "${widget.title}" failed to load: $error');
      debugPrintStack(stackTrace: stack, maxFrames: 6);
      return <T>[];
    }
  }

  void _reload() {
    if (!mounted) return;
    // setState must not return the Future, so assign inside a block.
    setState(() {
      _future = _safeLoad();
    });
  }

  @override
  void initState() {
    super.initState();
    homeRefreshTick.addListener(_reload);
  }

  @override
  void dispose() {
    homeRefreshTick.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<T>>(
      future: _future,
      builder: (context, snap) {
        final loading = snap.connectionState != ConnectionState.done;
        final items = snap.data ?? <T>[];
        if (!loading && items.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.leading == null)
                HomeSectionHeader(title: widget.title, subtitle: widget.subtitle, onSeeAll: widget.onSeeAll)
              else
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.gutter),
                  child: Row(
                    children: [
                      widget.leading!,
                      const SizedBox(width: 8),
                      Expanded(child: HomeSectionHeader(title: widget.title, subtitle: widget.subtitle, onSeeAll: widget.onSeeAll, padding: const EdgeInsets.only(right: AppSpacing.gutter))),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: widget.height,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                  itemCount: loading ? 4 : items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
                  itemBuilder: (context, i) => SizedBox(
                    width: widget.itemWidth,
                    child: loading
                        ? const _Skeleton()
                        : widget.itemBuilder(context, items[i])
                        .animate(delay: (50 * i.clamp(0, 6)).ms)
                        .fadeIn(duration: 300.ms)
                        .slideX(begin: 0.12, curve: Curves.easeOutCubic),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(kHomeCardRadius)),
    ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1200.ms, color: palette.surface.withValues(alpha: 0.6));
  }
}

// ---------------------------------------------------------------------------
// Card shell used by every rail item
// ---------------------------------------------------------------------------

class _RailCard extends StatelessWidget {
  const _RailCard({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(kHomeCardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Ink(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(kHomeCardRadius), border: Border.all(color: palette.border)),
          child: child,
        ),
      ),
    );
  }
}

Widget _netImage(String? url, {IconData icon = AppIcons.image, BoxFit fit = BoxFit.cover}) {
  final placeholder = DecoratedBox(
    decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0x33F4511E), Color(0x22EC2A78)])),
    child: Center(child: Icon(icon, color: Colors.white54, size: 22)),
  );
  if (url == null || url.isEmpty) return placeholder;
  return CachedNetworkImage(imageUrl: url, fit: fit, placeholder: (_, _) => placeholder, errorWidget: (_, _, _) => placeholder);
}

Widget _avatar(String? url, String name, double size, {bool ring = false, Color? borderColor}) {
  final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
  final inner = ClipOval(
    child: SizedBox(
      width: size,
      height: size,
      child: url == null || url.isEmpty
          ? DecoratedBox(
        decoration: const BoxDecoration(gradient: _brandGradient),
        child: Center(child: Text(initial, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.4))),
      )
          : CachedNetworkImage(imageUrl: url, fit: BoxFit.cover),
    ),
  );
  if (!ring) {
    return borderColor == null ? inner : Container(padding: const EdgeInsets.all(3), decoration: BoxDecoration(shape: BoxShape.circle, color: borderColor), child: inner);
  }
  return Container(
    padding: const EdgeInsets.all(2.5),
    decoration: const BoxDecoration(shape: BoxShape.circle, gradient: _brandGradient),
    child: Container(padding: const EdgeInsets.all(2), decoration: BoxDecoration(shape: BoxShape.circle, color: borderColor ?? Colors.white), child: inner),
  );
}

// ---------------------------------------------------------------------------
// Ready-made rails
// ---------------------------------------------------------------------------

bool _profileIncomplete(BuildContext context) {
  final auth = context.read<AuthBloc>().state;
  return needsProfileCompletion(auth is AuthAuthenticated ? auth.user : null);
}

/// "Top creators" — 3–4 visible, swipe for more, See all → directory.
class CreatorsRail extends StatelessWidget {
  const CreatorsRail({super.key, this.title = 'Top creators', this.subtitle = 'Discover creators to work with', this.pinned = const [], this.onlyPinned = false});

  final List<String> pinned;
  final bool onlyPinned;

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    // Profiles that aren't complete can't browse creators (see profile_gate.dart).
    if (_profileIncomplete(context)) return const SizedBox.shrink();
    final auth = context.read<AuthBloc>().state;
    final myId = auth is AuthAuthenticated ? auth.user.id : '';
    return HomeRail<CreatorProfile>(
      title: title,
      subtitle: subtitle,
      height: 222,
      itemWidth: 152,
      onSeeAll: () => context.push(AppRoutes.creatorsDirectory),
      load: () => pinnedFirst<CreatorProfile>(
        pinned: pinned,
        onlyPinned: onlyPinned,
        loadPinned: (ids) async => (await sl<CreatorsRepository>().list(ids: ids)).items,
        loadRest: () async => (await sl<CreatorsRepository>().list()).items,
        idOf: (c) => c.id,
      ).then((list) => list.where((c) => c.userId != myId).toList()),
      itemBuilder: (context, c) => _CreatorCard(creator: c),
    );
  }
}

/// Creator = a light profile card: soft colour band, round photo with the
/// brand ring, name, niche, followers and a Follow button.
class _CreatorCard extends StatefulWidget {
  const _CreatorCard({required this.creator});

  final CreatorProfile creator;

  @override
  State<_CreatorCard> createState() => _CreatorCardState();
}

class _CreatorCardState extends State<_CreatorCard> {
  late CreatorProfile c = widget.creator;
  bool _busy = false;

  /// Optimistic follow / unfollow; rolls back if the request fails.
  Future<void> _toggleFollow() async {
    if (_busy) return;
    HapticFeedback.lightImpact();
    final before = c;
    setState(() {
      _busy = true;
      c = c.copyWith(isFollowing: !c.isFollowing, followerCount: c.followerCount + (c.isFollowing ? -1 : 1));
    });
    try {
      final res = await sl<CreatorsRepository>().toggleFollow(before.id);
      if (mounted) setState(() => c = c.copyWith(isFollowing: res.following, followerCount: res.followerCount));
    } catch (_) {
      if (mounted) setState(() => c = before);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final verified = c.verificationStatus == VerificationStatus.verified;
    return _RailCard(
      onTap: () => context.push(AppRoutes.creatorProfile(c.slug)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Soft brand band behind the photo.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 46,
            child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [AppColors.primary.withValues(alpha: 0.14), const Color(0xFFEC2A78).withValues(alpha: 0.10)]))),
          ),
          if (c.isProPlan)
            Positioned(
              right: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(gradient: _brandGradient, borderRadius: BorderRadius.circular(6)),
                child: const Text('PRO', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _avatar(c.avatarUrl, c.name, 64, ring: true, borderColor: palette.surface),
                    if (c.isAvailableForWork)
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(width: 13, height: 13, decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle, border: Border.all(color: palette.surface, width: 2))),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                    if (verified) ...[
                      const SizedBox(width: 3),
                      const Icon(AppIcons.sealCheck, size: 14, color: AppColors.info),
                    ],
                  ],
                ),
                Text(
                  c.category?.label ?? (c.title.isEmpty ? 'Creator' : c.title),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall?.copyWith(fontSize: 11.5),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(AppIcons.users, size: 12, color: palette.textSecondary),
                    const SizedBox(width: 3),
                    Text(Fmt.compact(c.followerCount), style: context.text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: palette.textSecondary)),
                    if (c.reviewCount > 0) ...[
                      const SizedBox(width: 8),
                      const Icon(AppIcons.starFilled, size: 12, color: AppColors.sunrise),
                      const SizedBox(width: 2),
                      Text(c.averageRating.toStringAsFixed(1), style: context.text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: palette.textSecondary)),
                    ],
                  ],
                ),
                const Spacer(),
                _LightButton(
                  label: c.isFollowing ? 'Following' : 'Follow',
                  icon: c.isFollowing ? AppIcons.check : AppIcons.plus,
                  filled: !c.isFollowing,
                  height: 32,
                  onTap: _toggleFollow,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Button for light cards: brand gradient when filled, soft outline otherwise.
class _LightButton extends StatelessWidget {
  const _LightButton({required this.label, required this.icon, required this.onTap, this.filled = true, this.busy = false, this.height = 36});

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  final bool busy;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fg = filled ? Colors.white : palette.textPrimary;
    return GestureDetector(
      // Own tap target so the card doesn't open.
      behavior: HitTestBehavior.opaque,
      onTap: busy
          ? null
          : () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: filled ? _brandGradient : null,
          color: filled ? null : palette.surfaceMuted,
          borderRadius: BorderRadius.circular(kHomeButtonRadius),
        ),
        child: Center(
          child: busy
              ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
              : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 5),
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 12.5))),
            ],
          ),
        ),
      ),
    );
  }
}

class BrandsRail extends StatelessWidget {
  const BrandsRail({super.key, this.title = 'Brands on Fanitt', this.subtitle = 'Companies hiring creators', this.pinned = const [], this.onlyPinned = false});

  final List<String> pinned;
  final bool onlyPinned;

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return HomeRail<BrandListItem>(
      title: title,
      subtitle: subtitle,
      height: 228,
      itemWidth: 288,
      onSeeAll: () => context.push(AppRoutes.brands),
      load: () => pinnedFirst<BrandListItem>(
        pinned: pinned,
        onlyPinned: onlyPinned,
        loadPinned: (ids) async => (await sl<BrandsRepository>().list(ids: ids)).items,
        loadRest: () async => (await sl<BrandsRepository>().list()).items,
        idOf: (b) => b.profile.id,
      ),
      itemBuilder: (context, b) => _BrandCard(brand: b),
    );
  }
}

/// Brand = a clean company profile card: round logo (always fills the
/// circle), name with verified tick, industry, one line about them,
/// three key numbers and a clear "View brand" action.
class _BrandCard extends StatelessWidget {
  const _BrandCard({required this.brand});

  final BrandListItem brand;

  // A calm accent per brand (stable — from the name) for the soft top wash.
  static const _tints = [
    Color(0xFFF4511E),
    Color(0xFF6D5DFC),
    Color(0xFF10B981),
    Color(0xFFEC2A78),
    Color(0xFF0EA5E9),
  ];

  @override
  Widget build(BuildContext context) {
    final b = brand;
    final p = b.profile;
    final palette = context.palette;
    final dark = context.isDark;
    final open = () => context.push(AppRoutes.brandProfile(p.slug));
    final name = p.companyName.trim().isEmpty ? 'Brand' : p.companyName.trim();
    final tint = _tints[name.codeUnitAt(0) % _tints.length];
    final verified = p.verificationStatus == VerificationStatus.verified;
    final about = p.tagline.isNotEmpty ? p.tagline : (p.about.isNotEmpty ? p.about : 'Working with creators on Fanitt');

    return _ImmersivePress(
      onTap: open,
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.border),
          boxShadow: dark ? null : const [BoxShadow(color: Color(0x0F101828), blurRadius: 18, offset: Offset(0, 6))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Soft accent wash at the top — just colour, nothing to "read".
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 90,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [tint.withValues(alpha: dark ? 0.18 : 0.10), tint.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo · name · share
                  Row(
                    children: [
                      _BrandLogo(url: b.logoUrl, name: name, accent: tint),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
                                ),
                                if (verified) ...[
                                  const SizedBox(width: 4),
                                  const Icon(AppIcons.sealCheck, size: 16, color: AppColors.info),
                                ],
                                if (b.isPro) ...[
                                  const SizedBox(width: 5),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                    decoration: BoxDecoration(gradient: _brandGradient, borderRadius: BorderRadius.circular(5)),
                                    child: const Text('PRO', style: TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w900, letterSpacing: 0.4)),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                              decoration: BoxDecoration(color: tint.withValues(alpha: dark ? 0.2 : 0.1), borderRadius: BorderRadius.circular(999)),
                              child: Text(
                                p.industry.isEmpty ? 'Brand' : p.industry,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: tint, fontSize: 11, fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),
                      ),
                      ShareIconButton(size: 32, message: () => ShareService.brand(slug: p.slug, name: p.companyName, industry: p.industry)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(about, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(fontSize: 12.5, height: 1.35, color: palette.textSecondary)),
                  const Spacer(),
                  // Key numbers
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        _BrandStat(value: Fmt.compact(b.followerCount), label: 'Followers'),
                        _StatDivider(color: palette.border),
                        _BrandStat(value: Fmt.compact(p.totalCampaigns), label: 'Campaigns'),
                        _StatDivider(color: palette.border),
                        _BrandStat(
                          value: p.averageRating > 0 ? p.averageRating.toStringAsFixed(1) : 'New',
                          label: 'Rating',
                          icon: p.averageRating > 0 ? AppIcons.starFilled : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: p.location.isEmpty
                            ? const SizedBox.shrink()
                            : Row(
                          children: [
                            Icon(AppIcons.mapPin, size: 13, color: palette.textTertiary),
                            const SizedBox(width: 3),
                            Flexible(child: Text(p.location, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(fontSize: 12))),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _GradientPill(label: 'View brand', icon: AppIcons.arrowRightSimple, onTap: open),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Round logo that always fills its circle (cover), with a soft ring.
class _BrandLogo extends StatelessWidget {
  const _BrandLogo({required this.url, required this.name, required this.accent});

  final String? url;
  final String name;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    const size = 54.0;
    final fallback = DecoratedBox(
      decoration: const BoxDecoration(gradient: _brandGradient),
      child: Center(child: Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800))),
    );
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [accent.withValues(alpha: 0.9), accent.withValues(alpha: 0.35)]),
      ),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(shape: BoxShape.circle, color: context.palette.surface),
        child: ClipOval(
          child: SizedBox.expand(
            child: url == null || url!.isEmpty
                ? fallback
                : CachedNetworkImage(
              imageUrl: url!,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              placeholder: (_, _) => ColoredBox(color: context.palette.surfaceMuted),
              errorWidget: (_, _, _) => fallback,
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandStat extends StatelessWidget {
  const _BrandStat({required this.value, required this.label, this.icon});

  final String value;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 12, color: AppColors.warning), const SizedBox(width: 3)],
              Text(value, style: context.text.titleSmall?.copyWith(fontSize: 14, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 1),
          Text(label, style: context.text.bodySmall?.copyWith(fontSize: 10.5)),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(width: 1, height: 24, color: color);
}

/// Press-to-shrink wrapper.
class _ImmersivePress extends StatefulWidget {
  const _ImmersivePress({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_ImmersivePress> createState() => _ImmersivePressState();
}

class _ImmersivePressState extends State<_ImmersivePress> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(scale: _down ? 0.97 : 1, duration: const Duration(milliseconds: 140), child: widget.child),
    );
  }
}

class CampaignsRail extends StatelessWidget {
  const CampaignsRail({super.key, this.title = 'Open campaigns', this.subtitle = 'Paid & barter collaborations', this.onSeeAll, this.pinned = const [], this.onlyPinned = false});

  final List<String> pinned;
  final bool onlyPinned;

  final String title;
  final String subtitle;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    final isCreator = auth is AuthAuthenticated && auth.user.role == UserRole.creator;
    return HomeRail<Campaign>(
      title: title,
      subtitle: subtitle,
      height: 196,
      itemWidth: 272,
      onSeeAll: onSeeAll,
      load: () => pinnedFirst<Campaign>(
        pinned: pinned,
        onlyPinned: onlyPinned,
        loadPinned: (ids) async => (await sl<CampaignRepository>().list(ids: ids)).items,
        loadRest: () async => (await sl<CampaignRepository>().list()).items,
        idOf: (c) => c.id,
        max: 10,
      ),
      itemBuilder: (context, c) => _CampaignTicket(campaign: c, isCreator: isCreator),
    );
  }
}

/// Campaign = a "brief ticket": brand on top, the offer in chips, a
/// perforated tear line and an Apply button — no big photo, so it never
/// looks like a meet or a store.
class _CampaignTicket extends StatelessWidget {
  const _CampaignTicket({required this.campaign, required this.isCreator});

  final Campaign campaign;
  final bool isCreator;

  @override
  Widget build(BuildContext context) {
    final c = campaign;
    final palette = context.palette;
    final open = () => context.push(AppRoutes.campaignDetail(c.id));
    final spotsLeft = c.maxInfluencers > 0 ? (c.maxInfluencers - c.applicantCount).clamp(0, c.maxInfluencers) : null;

    return GestureDetector(
      onTap: open,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(kHomeCardRadius),
              border: Border.all(color: palette.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Brand + title
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                  child: Row(
                    children: [
                      ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: 34, height: 34, child: _netImage(c.brand?.logoUrl, icon: AppIcons.brand))),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.brand?.name ?? 'Brand', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                            Text(c.category?.label ?? 'Campaign', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(fontSize: 11)),
                          ],
                        ),
                      ),
                      if (c.isFeatured)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(AppIcons.sparkle, size: 11, color: AppColors.warning),
                              const SizedBox(width: 3),
                              Text('Featured', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.warning)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontSize: 15, fontWeight: FontWeight.w700, height: 1.25)),
                ),
                const Spacer(),
                // Offer — pay always whole, location shrinks with "…" if long.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      _Chip(
                        icon: c.isPaid ? AppIcons.rupee : AppIcons.gift,
                        label: c.isPaid ? '${Fmt.money(c.costPerInfluencer)} / creator' : 'Barter',
                        color: c.isPaid ? AppColors.success : AppColors.warning,
                      ),
                      const SizedBox(width: 6),
                      Flexible(child: _Chip(icon: AppIcons.mapPin, label: c.locationLabel, color: palette.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Perforated tear line
                SizedBox(height: 1, child: CustomPaint(size: const Size(double.infinity, 1), painter: _DashPainter(color: palette.border))),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
                  child: Row(
                    children: [
                      Icon(AppIcons.users, size: 14, color: palette.textTertiary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          [
                            '${c.applicantCount} applied',
                            if (spotsLeft != null) '$spotsLeft left',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall?.copyWith(fontSize: 12),
                        ),
                      ),
                      ShareIconButton(
                        size: 32,
                        message: () => ShareService.campaign(
                          id: c.id,
                          title: c.title,
                          brand: c.brand?.name ?? 'A brand',
                          isPaid: c.isPaid,
                          pay: c.costPerInfluencer,
                          location: c.locationLabel,
                        ),
                      ),
                      const SizedBox(width: 4),
                      _GradientPill(label: isCreator ? 'Apply' : 'View', icon: AppIcons.arrowRightSimple, onTap: open),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Ticket notches on the tear line
          for (final left in const [true, false])
            Positioned(
              left: left ? -7 : null,
              right: left ? null : -7,
              bottom: 42,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(color: palette.background, shape: BoxShape.circle, border: Border.all(color: palette.border)),
              ),
            ),
        ],
      ),
    );
  }
}

class LiveNowRail extends StatelessWidget {
  const LiveNowRail({super.key, this.title = 'Live streams', this.subtitle = 'Live now & coming up · see who can join'});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    // Public lives + the private ones this person is allowed into
    // (their communities, invites, hand-picked). Each card says who it's for.
    return HomeRail<LiveStream>(
      title: title,
      subtitle: subtitle,
      height: 212,
      itemWidth: 292,
      leading: Container(width: 10, height: 10, decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle))
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .fade(begin: 1, end: 0.3, duration: 700.ms),
      load: () => sl<StoreRepository>().discoverLives(limit: 12),
      itemBuilder: (context, live) => LivePosterCard(live: live),
    );
  }
}

class MeetsRail extends StatelessWidget {
  const MeetsRail({super.key, this.title = 'Virtual Meets', this.subtitle = 'Webinars & 1:1 sessions — join in the app', this.pinned = const [], this.onlyPinned = false});

  final String title;
  final String subtitle;
  final List<String> pinned;
  final bool onlyPinned;

  @override
  Widget build(BuildContext context) {
    return HomeRail<StoreMeet>(
      title: title,
      subtitle: subtitle,
      height: 266,
      itemWidth: 256,
      onSeeAll: () => context.push(AppRoutes.meets),
      load: () => pinnedFirst<StoreMeet>(
        pinned: pinned,
        onlyPinned: onlyPinned,
        loadPinned: (ids) async => (await sl<StoreRepository>().meets(ids: ids)).items,
        loadRest: () async => (await sl<StoreRepository>().meets()).items,
        idOf: (m) => m.id,
        max: 10,
      ),
      itemBuilder: (context, m) => _MeetPoster(meet: m),
    );
  }
}

/// Meet = photo on top (date tile + LIVE badge on it), then title, host,
/// time and a Book / Join / Start button on a light card.
class _MeetPoster extends StatelessWidget {
  const _MeetPoster({required this.meet});

  final StoreMeet meet;

  static const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

  @override
  Widget build(BuildContext context) {
    final m = meet;
    final when = m.scheduledAt?.toLocal();
    final open = () => context.push(AppRoutes.meetDetail(m.id));

    // Button by state: host → Start, booked + live → Join now, booked → Booked, else Book.
    final String cta;
    final VoidCallback onCta;
    if (m.isHost) {
      cta = m.isLive ? 'Rejoin' : 'Start meeting';
      onCta = () => openMeetRoom(context, m.id);
    } else if (m.booked && m.isLive) {
      cta = 'Join now';
      onCta = () => openMeetRoom(context, m.id);
    } else if (m.booked) {
      cta = 'Booked ✓';
      onCta = open;
    } else {
      cta = m.isFree ? 'Book free' : 'Book · ${Fmt.money(m.price)}';
      onCta = open;
    }

    final palette = context.palette;
    return _RailCard(
      onTap: open,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Photo
          SizedBox(
            height: 126,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _coverOrGradient(m.coverUrl, icon: AppIcons.videoCamera, colors: const [Color(0xFF7C4DFF), Color(0xFFB388FF)]),
                // Light top shade so the badges read on any photo.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.center, colors: [Color(0x40000000), Color(0x00000000)]),
                  ),
                ),
                Positioned(
                  left: 10,
                  top: 10,
                  child: Container(
                    width: 42,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      children: [
                        Text(when == null ? 'SOON' : _months[when.month - 1], style: const TextStyle(color: AppColors.error, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                        Text(when == null ? '—' : '${when.day}', style: const TextStyle(color: Color(0xFF111111), fontSize: 17, fontWeight: FontWeight.w800, height: 1.1)),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: 10,
                  top: 10,
                  child: m.isLive
                      ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(6)),
                    child: const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
                  ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 1, end: 0.55, duration: 800.ms)
                      : const _GlassChip(label: 'Online', icon: AppIcons.videoCamera, solid: Color(0x73000000)),
                ),
                if (m.spotsLeft != null && !m.isHost)
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(color: m.spotsLeft! <= 3 ? AppColors.error : Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        m.spotsLeft! <= 0 ? 'Full' : (m.spotsLeft! <= 3 ? 'Only ${m.spotsLeft} left' : '${m.spotsLeft} spots left'),
                        style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.25)),
                  const SizedBox(height: 8),
                  // Host · time · length
                  Row(
                    children: [
                      _avatar(m.hostAvatarUrl, m.hostName, 20),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${m.isHost ? 'You' : m.hostName}${when == null ? '' : ' · ${TimeOfDay.fromDateTime(when).format(context)}'} · ${m.durationMinutes} min',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall?.copyWith(fontSize: 11.5, color: palette.textSecondary),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Full-width button — long labels always fit.
                  _LightButton(
                    label: cta,
                    icon: m.isHost || m.isLive ? AppIcons.videoCamera : (m.booked ? AppIcons.check : AppIcons.calendar),
                    filled: !(m.booked && !m.isLive && !m.isHost),
                    height: 34,
                    onTap: onCta,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CommunitiesRail extends StatelessWidget {
  const CommunitiesRail({super.key});

  @override
  Widget build(BuildContext context) {
    return HomeRail<Community>(
      title: 'Trending communities',
      subtitle: 'Join the conversation',
      height: 168,
      itemWidth: 200,
      onSeeAll: () => context.push(AppRoutes.communities),
      load: () async => (await sl<CommunityRepository>().list()).items.take(10).toList(),
      itemBuilder: (context, c) => _RailCard(
        onTap: () => context.push(AppRoutes.communityDetail(c.slug)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 92,
              child: Stack(
                clipBehavior: Clip.none,
                fit: StackFit.expand,
                children: [
                  Positioned(top: 0, left: 0, right: 0, height: 64, child: _netImage(c.coverImageUrl, icon: AppIcons.users)),
                  Positioned(
                    left: 10,
                    top: 38,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(color: context.palette.surface, borderRadius: BorderRadius.circular(14)),
                      child: ClipRRect(borderRadius: BorderRadius.circular(11), child: SizedBox(width: 46, height: 46, child: _netImage(c.iconUrl, icon: AppIcons.users))),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
              child: Row(
                children: [
                  Flexible(child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall)),
                  if (c.isVerified) ...[
                    const SizedBox(width: 3),
                    const Icon(AppIcons.sealCheck, size: 14, color: AppColors.info),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('${Fmt.compact(c.memberCount)} members · ${Fmt.compact(c.discussionCount)} posts', style: context.text.bodySmall),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Digital products" — the newest things creators are selling.
class ProductsRail extends StatelessWidget {
  const ProductsRail({super.key, this.title = 'Digital products', this.subtitle = 'Courses, ebooks, templates — instant download', this.pinned = const [], this.onlyPinned = false});

  final List<String> pinned;
  final bool onlyPinned;

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return HomeRail<DigitalProduct>(
      title: title,
      subtitle: subtitle,
      height: 280,
      itemWidth: 184,
      onSeeAll: () => context.push(AppRoutes.products),
      load: () => pinnedFirst<DigitalProduct>(
        pinned: pinned,
        onlyPinned: onlyPinned,
        loadPinned: (ids) async => (await sl<StoreRepository>().products(ids: ids)).items,
        loadRest: () async => (await sl<StoreRepository>().products(sort: 'popular')).items,
        idOf: (p) => p.id,
        max: 10,
      ),
      itemBuilder: (context, p) => _ProductCard(product: p),
    );
  }
}

/// Product = a full-bleed poster: cover fills the card, price and category
/// on top, title, store and sales on a dark fade at the bottom.
class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product});

  final DigitalProduct product;

  @override
  Widget build(BuildContext context) {
    final p = product;
    return _ImmersiveCard(
      onTap: () => context.push(AppRoutes.storeProduct(p.id)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _coverOrGradient(p.coverUrl, icon: AppIcons.package, colors: const [Color(0xFF1F2A44), Color(0xFF3B1E5E), Color(0xFF6A1B4D)]),
          _bottomShade,
          // Top: category + owned
          Positioned(
            left: 10,
            right: 10,
            top: 10,
            child: Row(
              children: [
                if (p.category.isNotEmpty) Flexible(child: _GlassChip(label: Fmt.titleCase(p.category))) else const Spacer(),
                if (p.owned) ...[
                  const SizedBox(width: 6),
                  const _GlassChip(label: 'OWNED', icon: AppIcons.check, solid: AppColors.success),
                ],
              ],
            ),
          ),
          // Bottom: price, title, store, stats
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: p.isFree ? null : _brandGradient,
                    color: p.isFree ? AppColors.success : null,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(p.isFree ? 'FREE' : Fmt.money(p.price), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)),
                ),
                const SizedBox(height: 8),
                Text(
                  p.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800, height: 1.22, letterSpacing: -0.2),
                ),
                const SizedBox(height: 8),
                // Store — its own tap target: opens the store, not the product.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: p.storeSlug.isEmpty
                      ? null
                      : () {
                    HapticFeedback.selectionClick();
                    context.push(AppRoutes.storePage(p.storeSlug));
                  },
                  child: Row(
                    children: [
                      StoreLogo(name: p.storeName, url: p.storeLogoUrl, size: 20),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(p.storeName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w700)),
                      ),
                      if (p.storeSlug.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                          ),
                          child: const Text('Visit store ›', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(height: 1, color: Colors.white.withValues(alpha: 0.14)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    p.salesCount > 0
                        ? _OnImageStat(icon: AppIcons.download, value: Fmt.compact(p.salesCount), label: 'bought')
                        : const _GlassChip(label: 'NEW', icon: AppIcons.sparkle),
                    const Spacer(),
                    if (p.fileCount > 0) _OnImageStat(icon: AppIcons.file, value: '${p.fileCount}', label: p.fileCount == 1 ? 'file' : 'files'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class StoresRail extends StatelessWidget {
  const StoresRail({super.key, this.title = 'Creator stores', this.subtitle = 'Courses, ebooks, templates & more', this.pinned = const [], this.onlyPinned = false});

  final String title;
  final String subtitle;
  final List<String> pinned;
  final bool onlyPinned;

  @override
  Widget build(BuildContext context) {
    return HomeRail<StoreInfo>(
      title: title,
      subtitle: subtitle,
      height: 196,
      itemWidth: 300,
      onSeeAll: () => context.push(AppRoutes.stores),
      load: () => pinnedFirst<StoreInfo>(
        pinned: pinned,
        onlyPinned: onlyPinned,
        loadPinned: (ids) async => (await sl<StoreRepository>().stores(ids: ids)).items,
        loadRest: () async => (await sl<StoreRepository>().stores()).items,
        idOf: (s) => s.id,
        max: 10,
      ),
      itemBuilder: (context, s) => _Storefront(store: s),
    );
  }
}

/// Store = a full-bleed shop front: banner fills the card, logo, name,
/// tagline, sales and a Visit button on top of it.
class _Storefront extends StatelessWidget {
  const _Storefront({required this.store});

  final StoreInfo store;

  @override
  Widget build(BuildContext context) {
    final s = store;
    final open = () => context.push(AppRoutes.storePage(s.slug));
    return _ImmersiveCard(
      onTap: open,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _coverOrGradient(s.bannerUrl, icon: AppIcons.storeFilled, colors: const [Color(0xFFFF8A5B), Color(0xFFF4511E), Color(0xFFEC2A78)]),
          _bottomShade,
          Positioned(
            left: 12,
            top: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(AppIcons.storeFilled, size: 12, color: AppColors.primary),
                  SizedBox(width: 4),
                  Text('SHOP', style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                ],
              ),
            ),
          ),
          Positioned(
            right: 10,
            top: 10,
            child: ShareIconButton(onDark: true, size: 32, message: () => ShareService.store(slug: s.slug, name: s.name, tagline: s.tagline)),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 14,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StoreLogo(name: s.name, url: s.logoUrl, size: 54, borderColor: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: -0.3),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.tagline.isEmpty ? 'Courses, guides & templates' : s.tagline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),
                      s.stats.orders > 0
                          ? _OnImageStat(icon: AppIcons.package, value: Fmt.compact(s.stats.orders), label: 'sold')
                          : const _GlassChip(label: 'NEW STORE', icon: AppIcons.sparkle),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: Ink(
                    decoration: const BoxDecoration(shape: BoxShape.circle, gradient: _brandGradient),
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        open();
                      },
                      child: const SizedBox(width: 44, height: 44, child: Icon(AppIcons.arrowUpRight, color: Colors.white, size: 20)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Quiet bordered action ("View brand", "Joined").
class _OutlinePill extends StatelessWidget {
  const _OutlinePill({required this.label, required this.onTap, this.icon});

  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(kHomeButtonRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(kHomeButtonRadius), border: Border.all(color: AppColors.primary.withValues(alpha: 0.45))),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 13, color: AppColors.primary), const SizedBox(width: 4)],
              Text(label, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 12.5)),
              if (icon == null) ...[const SizedBox(width: 3), const Icon(AppIcons.arrowRightSimple, size: 13, color: AppColors.primary)],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero header (greeting card with the user's key number)
// ---------------------------------------------------------------------------

class HomeHero extends StatelessWidget {
  const HomeHero({super.key, required this.label, required this.value, this.caption, this.primaryAction, this.trailing});

  final String label;
  final String value;
  final String? caption;
  final Widget? primaryAction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF14141F), Color(0xFF26131C)]),
          boxShadow: [BoxShadow(color: const Color(0xFFF4511E).withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 10))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              right: -40,
              top: -40,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [const Color(0xFFF4511E).withValues(alpha: 0.45), Colors.transparent])),
              ).animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(begin: 0.9, end: 1.1, duration: 3.seconds, curve: Curves.easeInOut),
            ),
            Positioned(
              left: -30,
              bottom: -50,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [const Color(0xFFEC2A78).withValues(alpha: 0.35), Colors.transparent])),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(label, style: context.text.bodyMedium?.copyWith(color: Colors.white70))),
                      if (trailing != null) trailing!,
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(value, style: context.text.headlineMedium?.copyWith(fontSize: 28, color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
                  if (caption != null) ...[
                    const SizedBox(height: 4),
                    Text(caption!, style: context.text.bodySmall?.copyWith(color: AppColors.sunrise)),
                  ],
                  if (primaryAction != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    primaryAction!,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.06, curve: Curves.easeOutCubic);
  }
}

/// Small numbers row under the hero.
class HomeStatsRow extends StatelessWidget {
  const HomeStatsRow({super.key, required this.stats});

  final List<({String label, String value, IconData icon, Color color})> stats;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: Row(
        children: [
          for (final (i, s) in stats.indexed) ...[
            if (i > 0) const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.sm + 2),
                decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(kHomeCardRadius), border: Border.all(color: palette.border)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(s.icon, size: 18, color: s.color),
                    const SizedBox(height: 6),
                    FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(s.value, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                    Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(delay: 120.ms, duration: 350.ms);
  }
}

/// Section spacing helper.
const homeGap = SizedBox(height: AppSpacing.xl);

// ---------------------------------------------------------------------------
// Search bar (opens the search screen)
// ---------------------------------------------------------------------------

class HomeSearchBar extends StatelessWidget {
  const HomeSearchBar({super.key, this.hint = 'Search creators, brands, communities…'});

  final String hint;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: palette.surface,
              borderRadius: BorderRadius.circular(kHomeButtonRadius),
              child: InkWell(
                borderRadius: BorderRadius.circular(kHomeButtonRadius),
                onTap: () => context.push(AppRoutes.search),
                child: Ink(
                  height: 48,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(kHomeButtonRadius), border: Border.all(color: palette.border)),
                  child: Row(
                    children: [
                      const SizedBox(width: AppSpacing.md),
                      Icon(AppIcons.search, size: 20, color: palette.textTertiary),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(fontSize: 14, color: palette.textTertiary)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Material(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(kHomeButtonRadius),
            child: InkWell(
              borderRadius: BorderRadius.circular(kHomeButtonRadius),
              onTap: () => context.push('${AppRoutes.search}?filters=1'),
              child: const SizedBox(width: 48, height: 48, child: Icon(AppIcons.sliders, color: Colors.white, size: 20)),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }
}

// ---------------------------------------------------------------------------
// Vertical list section (thumbnail, title, subtitle)
// ---------------------------------------------------------------------------

/// Shows up to [max] rows; hidden when empty. Skeleton rows while loading.
class HomeListSection<T> extends StatefulWidget {
  const HomeListSection({
    super.key,
    required this.title,
    required this.load,
    required this.thumbnail,
    required this.titleOf,
    required this.subtitleOf,
    required this.onTap,
    this.subtitle,
    this.onSeeAll,
    this.trailingOf,
    this.max = 4,
  });

  final String title;
  final String? subtitle;
  final Future<List<T>> Function() load;
  final Widget Function(T item) thumbnail;
  final String Function(T item) titleOf;
  final String Function(T item) subtitleOf;
  final Widget? Function(T item)? trailingOf;
  final void Function(T item) onTap;
  final VoidCallback? onSeeAll;
  final int max;

  @override
  State<HomeListSection<T>> createState() => _HomeListSectionState<T>();
}

class _HomeListSectionState<T> extends State<HomeListSection<T>> with AutomaticKeepAliveClientMixin {
  late Future<List<T>> _future = _safeLoad();

  @override
  bool get wantKeepAlive => true;

  Future<List<T>> _safeLoad() async {
    try {
      return (await widget.load()).take(widget.max).toList();
    } catch (error) {
      debugPrint('[home] list section failed to load: $error');
      return <T>[];
    }
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = _safeLoad();
    });
  }

  @override
  void initState() {
    super.initState();
    homeRefreshTick.addListener(_reload);
  }

  @override
  void dispose() {
    homeRefreshTick.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final palette = context.palette;
    return FutureBuilder<List<T>>(
      future: _future,
      builder: (context, snap) {
        final loading = snap.connectionState != ConnectionState.done;
        final items = snap.data ?? <T>[];
        if (!loading && items.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HomeSectionHeader(title: widget.title, subtitle: widget.subtitle, onSeeAll: widget.onSeeAll),
              const SizedBox(height: AppSpacing.xs),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                child: Container(
                  decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(kHomeCardRadius), border: Border.all(color: palette.border)),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < (loading ? 3 : items.length); i++) ...[
                        if (i > 0) Divider(height: 1, indent: 76, color: palette.border),
                        if (loading)
                          const _SkeletonRow()
                        else
                          InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              widget.onTap(items[i]);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                              child: Row(
                                children: [
                                  ClipRRect(borderRadius: BorderRadius.circular(kHomeButtonRadius), child: SizedBox(width: 48, height: 48, child: widget.thumbnail(items[i]))),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(widget.titleOf(items[i]), maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 2),
                                        Text(widget.subtitleOf(items[i]), maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  widget.trailingOf?.call(items[i]) ?? Icon(AppIcons.chevronRight, size: 18, color: palette.textTertiary),
                                ],
                              ),
                            ),
                          ).animate(delay: (50 * i).ms).fadeIn(duration: 250.ms),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget bar(double w, double h) => Container(width: w, height: h, decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(6)));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(kHomeButtonRadius))),
          const SizedBox(width: AppSpacing.sm),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [bar(140, 12), const SizedBox(height: 8), bar(90, 10)]),
        ],
      ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1200.ms, color: palette.surface.withValues(alpha: 0.6)),
    );
  }
}

/// Communities as cover cards: big cover, the community icon on it, name,
/// members/posts and a one-tap Join button.
class CommunitiesList extends StatelessWidget {
  const CommunitiesList({super.key, this.title = 'Trending communities', this.subtitle = 'Join the conversation', this.pinned = const [], this.onlyPinned = false});

  final String title;
  final String subtitle;
  final List<String> pinned;
  final bool onlyPinned;

  @override
  Widget build(BuildContext context) {
    return HomeRail<Community>(
      title: title,
      subtitle: subtitle,
      height: 268,
      itemWidth: 248,
      onSeeAll: () => context.push(AppRoutes.communities),
      load: () => pinnedFirst<Community>(
        pinned: pinned,
        onlyPinned: onlyPinned,
        loadPinned: (ids) async => (await sl<CommunityRepository>().list(ids: ids)).items,
        loadRest: () async => (await sl<CommunityRepository>().list()).items,
        idOf: (c) => c.id,
      ),
      itemBuilder: (context, c) => _CommunityCard(community: c),
    );
  }
}

class _CommunityCard extends StatefulWidget {
  const _CommunityCard({required this.community});

  final Community community;

  @override
  State<_CommunityCard> createState() => _CommunityCardState();
}

class _CommunityCardState extends State<_CommunityCard> {
  late MembershipStatus? _status = widget.community.membership?.status;
  bool _busy = false;

  Community get c => widget.community;

  Future<void> _join() async {
    // Paid community without a plan: plans and payment are on its page.
    if (c.needsPlan || _busy || _status == MembershipStatus.active || _status == MembershipStatus.banned) {
      context.push(AppRoutes.communityDetail(c.slug));
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    try {
      final status = await sl<CommunityRepository>().toggleJoin(c.id);
      if (mounted) setState(() => _status = status);
    } catch (_) {
      if (mounted) context.push(AppRoutes.communityDetail(c.slug));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final joined = _status == MembershipStatus.active;
    final pending = _status == MembershipStatus.pending;
    final about = c.description.isNotEmpty ? c.description : (c.category?.label.isNotEmpty == true ? c.category!.label : 'A Fanitt community');

    final palette = context.palette;
    final category = c.category?.label ?? '';
    return _RailCard(
      onTap: () => context.push(AppRoutes.communityDetail(c.slug)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover, with the icon sitting half on it and Join beside the icon.
          SizedBox(
            height: 156,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 124,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _coverOrGradient(c.coverImageUrl, icon: AppIcons.users, colors: const [Color(0xFF6D5DFC), Color(0xFFB13CC4), Color(0xFFEC2A78)]),
                      const DecoratedBox(
                        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.center, colors: [Color(0x40000000), Color(0x00000000)])),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  top: 10,
                  child: Row(
                    children: [
                      if (category.isNotEmpty) Flexible(child: _GlassChip(label: category, solid: const Color(0x73000000))) else const Spacer(),
                      if (c.isPaid || c.isPrivate) ...[
                        const SizedBox(width: 6),
                        _GlassChip(label: c.isPaid ? 'Paid' : 'Private', icon: c.isPaid ? AppIcons.crown : AppIcons.lock, solid: c.isPaid ? const Color(0xFFEC2A78) : const Color(0x73000000)),
                      ],
                    ],
                  ),
                ),
                Positioned(
                  left: 12,
                  top: 98,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [BoxShadow(color: Color(0x1A101828), blurRadius: 8, offset: Offset(0, 2))],
                    ),
                    child: ClipRRect(borderRadius: BorderRadius.circular(13), child: SizedBox(width: 50, height: 50, child: _netImage(c.iconUrl, icon: AppIcons.users))),
                  ),
                ),
                Positioned(
                  right: 12,
                  top: 130,
                  child: SizedBox(
                    width: 108,
                    child: _LightButton(
                      label: c.needsPlan ? (c.isExpired ? 'Renew' : 'Join') : (joined ? 'Joined' : pending ? 'Requested' : (c.isPrivate ? 'Request' : 'Join')),
                      icon: c.needsPlan ? AppIcons.crown : joined ? AppIcons.check : pending ? AppIcons.hourglass : AppIcons.plus,
                      filled: c.needsPlan || !(joined || pending),
                      busy: _busy,
                      height: 30,
                      onTap: _join,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800, fontSize: 15))),
                      if (c.isVerified) ...[
                        const SizedBox(width: 3),
                        const Icon(AppIcons.sealCheck, size: 15, color: AppColors.info),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(about, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(fontSize: 12, height: 1.35)),
                  const Spacer(),
                  Row(
                    children: [
                      Icon(AppIcons.users, size: 13, color: palette.textSecondary),
                      const SizedBox(width: 4),
                      Text('${Fmt.compact(c.memberCount)} members', style: context.text.labelSmall?.copyWith(color: palette.textSecondary, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 10),
                      Icon(AppIcons.messages, size: 13, color: palette.textSecondary),
                      const SizedBox(width: 4),
                      Flexible(child: Text('${Fmt.compact(c.discussionCount)} posts', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: palette.textSecondary, fontWeight: FontWeight.w700))),
                      if (c.needsPlan) ...[
                        const Spacer(),
                        Text(communityPriceLabel(c), style: context.text.labelSmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Immersive cards: the picture fills the whole card and every detail sits
// on it — no empty space anywhere.
// ---------------------------------------------------------------------------

/// Full-bleed card shell: rounded, soft shadow, press-to-shrink.
class _ImmersiveCard extends StatefulWidget {
  const _ImmersiveCard({required this.onTap, required this.child, this.radius = 22});

  final VoidCallback onTap;
  final Widget child;
  final double radius;

  @override
  State<_ImmersiveCard> createState() => _ImmersiveCardState();
}

class _ImmersiveCardState extends State<_ImmersiveCard> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF15151C),
            borderRadius: BorderRadius.circular(widget.radius),
            boxShadow: dark ? null : const [BoxShadow(color: Color(0x1F101828), blurRadius: 22, offset: Offset(0, 10))],
          ),
          clipBehavior: Clip.antiAlias,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Picture or, when there is none, a rich gradient with a big faded icon.
Widget _coverOrGradient(String? url, {required IconData icon, required List<Color> colors}) {
  if (url != null && url.isNotEmpty) return _netImage(url, icon: icon);
  return DecoratedBox(
    decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors)),
    child: Stack(
      children: [
        Positioned(right: -18, top: -10, child: Icon(icon, size: 120, color: Colors.white.withValues(alpha: 0.10))),
        Positioned(left: -30, bottom: 40, child: Container(width: 110, height: 110, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.06)))),
      ],
    ),
  );
}

/// Dark fade from the middle of the card to the bottom so white text reads.
const _bottomShade = DecoratedBox(
  decoration: BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0x4D000000), Color(0x00000000), Color(0x8C000000), Color(0xE0000000), Color(0xFA000000)],
      stops: [0, 0.22, 0.48, 0.74, 1],
    ),
  ),
);

/// Frosted chip on top of pictures.
class _GlassChip extends StatelessWidget {
  const _GlassChip({required this.label, this.icon, this.color = Colors.white, this.solid});

  final String label;
  final IconData? icon;
  final Color color;

  /// Solid background instead of the glass one (e.g. FREE in green).
  final Color? solid;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: solid ?? Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: solid == null ? Border.all(color: Colors.white.withValues(alpha: 0.22)) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 11, color: color), const SizedBox(width: 4)],
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
          ),
        ],
      ),
    );
  }
}

/// Small white stat: bold number + label.
class _OnImageStat extends StatelessWidget {
  const _OnImageStat({required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.white70),
        const SizedBox(width: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
        const SizedBox(width: 3),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Small pieces used by the cards above
// ---------------------------------------------------------------------------

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _GradientPill extends StatelessWidget {
  const _GradientPill({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(kHomeButtonRadius),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: const BoxDecoration(gradient: _brandGradient),
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(width: 4),
                Icon(icon, color: Colors.white, size: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dashed tear line for the campaign ticket.
class _DashPainter extends CustomPainter {
  const _DashPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 5.0;
    const gap = 4.0;
    var x = 12.0;
    while (x < size.width - 12) {
      canvas.drawLine(Offset(x, 0), Offset(x + dash, 0), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// Admin-managed sections (order, titles, pinned items)
// ---------------------------------------------------------------------------

class _SectionConfig {
  const _SectionConfig({required this.key, required this.title, required this.subtitle, required this.pinned, this.onlyPinned = false});

  factory _SectionConfig.fromJson(Map<String, dynamic> json) => _SectionConfig(
    key: J.str(json, 'key'),
    title: J.str(json, 'title'),
    subtitle: J.str(json, 'subtitle'),
    pinned: [for (final id in (json['pinned'] is List ? json['pinned'] as List : const [])) id.toString()],
    onlyPinned: J.boolean(json, 'onlyPinned'),
  );

  final String key;
  final String title;
  final String subtitle;
  final List<String> pinned;
  final bool onlyPinned;
}

/// All discover sections, in the order (and with the titles and pinned
/// items) set in the admin panel → App home screen. Falls back to the
/// built-in order if the layout can't load.
/// The admin's "brands" section (title / pinned), shared with [HomeBrandsSlot].
/// null = brands are hidden in the admin panel.
final ValueNotifier<_SectionConfig?> _brandsSection = ValueNotifier<_SectionConfig?>(null);

/// Put this where the "Brands on Fanitt" logo strip should sit when the
/// screen uses `HomeSections(showBrands: false)` — e.g. just above a
/// card at the very bottom of the home.
class HomeBrandsSlot extends StatelessWidget {
  const HomeBrandsSlot({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_SectionConfig?>(
      valueListenable: _brandsSection,
      builder: (context, c, _) => c == null
          ? const SizedBox.shrink()
          : BrandLogoStrip(
        key: ValueKey('brands-${c.title}-${c.onlyPinned}-${c.pinned.join(',')}'),
        title: c.title.isEmpty ? 'Brands on Fanitt' : c.title,
        pinned: c.pinned,
        onlyPinned: c.onlyPinned,
      ),
    );
  }
}

class HomeSections extends StatefulWidget {
  const HomeSections({super.key, this.campaignsSeeAll, this.showBrands = true});

  final VoidCallback? campaignsSeeAll;

  /// false = the screen places [HomeBrandsSlot] itself (lower down).
  final bool showBrands;

  @override
  State<HomeSections> createState() => _HomeSectionsState();
}

class _HomeSectionsState extends State<HomeSections> {
  static const _fallback = ['creators', 'campaigns', 'live', 'meets', 'brands', 'communities', 'products', 'stores'];
  List<_SectionConfig>? _sections;

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
      final sections = (await sl<ApiClient>().get(
        '/home/layout',
        parser: (d) => J.list(J.asMap(d), 'sections', _SectionConfig.fromJson),
      ))
          .data;
      if (mounted) setState(() => _sections = sections);
    } catch (_) {
      if (mounted && _sections == null) {
        setState(() => _sections = [for (final k in _fallback) _SectionConfig(key: k, title: '', subtitle: '', pinned: const [])]);
      }
    }
    _brandsSection.value = _sections?.where((c) => c.key == 'brands').firstOrNull;
  }

  Widget _build(_SectionConfig c) {
    String t(String fallback) => c.title.isEmpty ? fallback : c.title;
    String sub(String fallback) => c.subtitle.isEmpty ? fallback : c.subtitle;
    return switch (c.key) {
      'live' => LiveNowRail(title: t('Live streams'), subtitle: sub('Live now & coming up · see who can join')),
      'creators' => CreatorsRail(title: t('Top creators'), subtitle: sub('Discover creators to work with'), pinned: c.pinned, onlyPinned: c.onlyPinned),
      'campaigns' => CampaignsRail(title: t('Open campaigns'), subtitle: sub('Paid & barter collaborations'), pinned: c.pinned, onlyPinned: c.onlyPinned, onSeeAll: widget.campaignsSeeAll),
      'meets' => MeetsRail(title: t('Virtual Meets'), subtitle: sub('Webinars & 1:1 sessions — join in the app'), pinned: c.pinned, onlyPinned: c.onlyPinned),
    // Brands now show as a moving logo strip at the bottom (see build).
      'brands' => const SizedBox.shrink(),
      'communities' => CommunitiesList(title: t('Trending communities'), subtitle: sub('Join the conversation'), pinned: c.pinned, onlyPinned: c.onlyPinned),
      'products' => ProductsRail(title: t('Digital products'), subtitle: sub('Courses, ebooks, templates — instant download'), pinned: c.pinned, onlyPinned: c.onlyPinned),
    // Creator stores are reached from their products ("Visit store").
      'stores' => const SizedBox.shrink(),
      _ => const SizedBox.shrink(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final sections = _sections;
    if (sections == null) return const SizedBox.shrink();
    final brands = sections.where((c) => c.key == 'brands').firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Keyed by the layout so a changed order or pin list rebuilds the rails.
        for (final c in sections) ...[
          // Fanitt Store (physical products) sits just before Digital products.
          if (c.key == 'products') ShopHomeSection(refresh: homeRefreshTick),
          if (c.key != 'brands' && c.key != 'stores')
            KeyedSubtree(key: ValueKey('${c.key}-${c.title}-${c.onlyPinned}-${c.pinned.join(',')}'), child: _build(c)),
        ],
        if (!sections.any((c) => c.key == 'products')) ShopHomeSection(refresh: homeRefreshTick),
        // Brands: a slow, endless logo strip at the very bottom.
        if (brands != null && widget.showBrands)
          BrandLogoStrip(
            key: ValueKey('brands-${brands.title}-${brands.onlyPinned}-${brands.pinned.join(',')}'),
            title: brands.title.isEmpty ? 'Brands on Fanitt' : brands.title,
            pinned: brands.pinned,
            onlyPinned: brands.onlyPinned,
          ),
      ],
    );
  }
}

/// Brands on Fanitt — round logos with the name under each, sliding
/// slowly and endlessly. Touch to pause / drag, tap a logo to open the brand.
class BrandLogoStrip extends StatefulWidget {
  const BrandLogoStrip({super.key, this.title = 'Brands on Fanitt', this.pinned = const [], this.onlyPinned = false});

  final String title;
  final List<String> pinned;
  final bool onlyPinned;

  @override
  State<BrandLogoStrip> createState() => _BrandLogoStripState();
}

class _BrandLogoStripState extends State<BrandLogoStrip> with SingleTickerProviderStateMixin {
  static const _speed = 30.0; // pixels per second
  static const _itemWidth = 104.0;

  final _scroll = ScrollController();
  late final Ticker _ticker = createTicker(_tick);
  List<BrandListItem> _brands = const [];
  bool _held = false;
  Duration _last = Duration.zero;

  /// Fewer logos than this don't fill the screen — show them still.
  bool get _moving => _brands.length >= 4;

  @override
  void initState() {
    super.initState();
    _load();
    homeRefreshTick.addListener(_load);
  }

  @override
  void dispose() {
    homeRefreshTick.removeListener(_load);
    _ticker.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Only the brands marked in the admin panel (Home screen sections →
  /// Brands → pinned), in that order, at most this many.
  static const _maxBrands = 10;

  Future<void> _load() async {
    if (widget.pinned.isEmpty) {
      if (mounted) setState(() => _brands = const []);
      return;
    }
    try {
      final ids = widget.pinned.take(_maxBrands).toList();
      final order = {for (var i = 0; i < ids.length; i++) ids[i]: i};
      final brands = [...(await sl<BrandsRepository>().list(ids: ids)).items]
        ..sort((a, b) => (order[a.profile.id] ?? 999).compareTo(order[b.profile.id] ?? 999));
      if (!mounted) return;
      setState(() => _brands = brands);
      if (_moving && !_ticker.isActive) {
        _last = Duration.zero;
        _ticker.start();
      }
    } catch (_) {
      // No strip when brands can't load.
    }
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (_held || !_scroll.hasClients || !_moving) return;
    _scroll.jumpTo(_scroll.offset + _speed * dt);
  }

  void _open(BrandListItem b) {
    if (b.profile.slug.isEmpty) return;
    HapticFeedback.selectionClick();
    context.push(AppRoutes.brandProfile(b.profile.slug));
  }

  Widget _logo(BrandListItem b) {
    final palette = context.palette;
    final name = b.profile.companyName.trim().isEmpty ? 'Brand' : b.profile.companyName.trim();
    final verified = b.profile.verificationStatus == VerificationStatus.verified;
    final fallback = DecoratedBox(
      decoration: const BoxDecoration(gradient: _brandGradient),
      child: Center(child: Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800))),
    );
    return GestureDetector(
      onTap: () => _open(b),
      child: SizedBox(
        width: _itemWidth,
        child: Column(
          children: [
            // Logo tile — white rounded square, like a partner wall.
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: context.isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFECEDF2)),
                    boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x14101828), blurRadius: 16, offset: Offset(0, 6))],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox.expand(
                      child: (b.logoUrl ?? '').isEmpty
                          ? fallback
                          : CachedNetworkImage(
                        imageUrl: b.logoUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => const ColoredBox(color: Color(0xFFF3F4F7)),
                        errorWidget: (_, _, _) => fallback,
                      ),
                    ),
                  ),
                ),
                if (verified)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(1.5),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: palette.background),
                      child: const Icon(AppIcons.sealCheck, size: 16, color: Color(0xFF3B82F6)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: context.text.labelSmall?.copyWith(fontSize: 12.5, fontWeight: FontWeight.w700, color: palette.textSecondary, letterSpacing: 0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_brands.isEmpty) return const SizedBox.shrink();
    final palette = context.palette;
    final strip = SizedBox(
      height: 122,
      child: _moving
          ? Listener(
        onPointerDown: (_) => _held = true,
        onPointerUp: (_) => _held = false,
        onPointerCancel: (_) => _held = false,
        child: ListView.builder(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(top: 6),
          // Endless: the same brands repeat forever.
          itemBuilder: (context, i) => _logo(_brands[i % _brands.length]),
        ),
      )
          : Center(
        child: ListView(
          shrinkWrap: true,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(top: 6),
          children: [for (final b in _brands) _logo(b)],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Container(
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: context.isDark
                ? [Colors.white.withValues(alpha: 0.03), Colors.white.withValues(alpha: 0.0)]
                : [const Color(0xFFFFF4EF), palette.background],
          ),
        ),
        child: Column(
          children: [
            // "— BRANDS ON FANITT —"
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
              child: Row(
                children: [
                  Expanded(child: Container(height: 1, decoration: BoxDecoration(gradient: LinearGradient(colors: [palette.border.withValues(alpha: 0), palette.border])))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      widget.title.toUpperCase(),
                      style: context.text.labelSmall?.copyWith(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.6, color: palette.textSecondary),
                    ),
                  ),
                  Expanded(child: Container(height: 1, decoration: BoxDecoration(gradient: LinearGradient(colors: [palette.border, palette.border.withValues(alpha: 0)])))),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text('Trusted by brands working with creators', style: context.text.bodySmall?.copyWith(fontSize: 12)),
            const SizedBox(height: 14),
            // Logos fade out at both edges.
            ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (r) => const LinearGradient(
                colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
                stops: [0, 0.08, 0.92, 1],
              ).createShader(r),
              child: strip,
            ),
          ],
        ),
      ),
    );
  }
}