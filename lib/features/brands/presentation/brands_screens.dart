// File: lib/features/brands/presentation/brands_screens.dart

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/bloc/action_cubit.dart';
import '../../../core/bloc/load_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/services/share_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/action_scope.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/report_sheet.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../campaigns/presentation/widgets/campaign_widgets.dart';
import '../data/brands_repository.dart';

/// Brands — simple and lively: just each brand's logo and name. A few rows
/// glide on their own (alternate directions; touch to pause, tap to open),
/// then every brand in a grid that pops in. No search, no extra details.
class BrandsScreen extends StatefulWidget {
  const BrandsScreen({super.key});

  @override
  State<BrandsScreen> createState() => _BrandsScreenState();
}

class _BrandsScreenState extends State<BrandsScreen> {
  late Future<List<BrandListItem>> _future = _loadAll();

  /// Every brand (page by page, up to 500).
  static Future<List<BrandListItem>> _loadAll() async {
    final repo = sl<BrandsRepository>();
    final all = <BrandListItem>[];
    var page = 1;
    while (page <= 10) {
      final p = await repo.list(page: page, limit: 50);
      all.addAll(p.items);
      if (!p.hasMore) break;
      page++;
    }
    return all;
  }

  Future<void> _refresh() async {
    final next = _loadAll();
    setState(() => _future = next);
    await next.catchError((_) => const <BrandListItem>[]);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Brands', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3)),
      ),
      body: FutureBuilder<List<BrandListItem>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const _BrandsSkeleton();
          if (snap.hasError) return ErrorView(message: 'Could not load brands.', onRetry: _refresh);
          final brands = snap.data ?? const <BrandListItem>[];
          if (brands.isEmpty) {
            return const MessageView(icon: AppIcons.brand, title: 'No brands yet', message: 'Brands joining Fanitt show up here.');
          }
          // Gliding rows only when there are enough brands to fill them.
          final rows = brands.length >= 12 ? 3 : (brands.length >= 6 ? 2 : 0);
          final rowItems = [for (var r = 0; r < rows; r++) [for (var i = r; i < brands.length; i += rows) brands[i]]];

          return RefreshIndicator.adaptive(
            color: AppColors.primary,
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 4, AppSpacing.gutter, 14),
                    child: Text(
                      '${brands.length} ${brands.length == 1 ? 'brand' : 'brands'} working with creators',
                      style: TextStyle(fontSize: 13, color: palette.textSecondary),
                    ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.3),
                  ),
                ),
                if (rows > 0)
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        for (var r = 0; r < rows; r++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _GlideRow(items: rowItems[r], reverse: r.isOdd, speed: 26 + r * 6)
                                .animate(delay: (120 * r).ms)
                                .fadeIn(duration: 450.ms)
                                .slideX(begin: r.isOdd ? -0.15 : 0.15, curve: Curves.easeOutCubic),
                          ),
                      ],
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(AppSpacing.gutter, rows > 0 ? 12 : 0, AppSpacing.gutter, 12),
                    child: Text('All brands', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: palette.textPrimary))
                        .animate()
                        .fadeIn(delay: 200.ms, duration: 350.ms),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, AppSpacing.xxl),
                  sliver: SliverGrid.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 18, crossAxisSpacing: 12, mainAxisExtent: 118),
                    itemCount: brands.length,
                    itemBuilder: (context, i) => _BrandBubble(item: brands[i], size: 74)
                        .animate(delay: (35 * (i % 12)).ms)
                        .fadeIn(duration: 320.ms)
                        .scaleXY(begin: 0.8, curve: Curves.easeOutBack, duration: 420.ms),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Logo in a white circle with a soft ring, the name under it. Tap → brand page.
class _BrandBubble extends StatefulWidget {
  const _BrandBubble({required this.item, required this.size, this.width});

  final BrandListItem item;
  final double size;
  final double? width;

  @override
  State<_BrandBubble> createState() => _BrandBubbleState();
}

class _BrandBubbleState extends State<_BrandBubble> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final b = widget.item.profile;
    final name = b.companyName.trim().isEmpty ? 'Brand' : b.companyName.trim();
    final verified = b.verificationStatus == VerificationStatus.verified;
    final size = widget.size;
    return SizedBox(
      width: widget.width,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: b.slug.isEmpty
            ? null
            : () {
          HapticFeedback.selectionClick();
          context.push(AppRoutes.brandProfile(b.slug));
        },
        child: AnimatedScale(
          scale: _down ? 0.92 : 1,
          duration: const Duration(milliseconds: 120),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: size,
                    height: size,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: palette.surface,
                      border: Border.all(color: palette.border.withValues(alpha: 0.9)),
                      boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x14101828), blurRadius: 14, offset: Offset(0, 6))],
                    ),
                    child: ClipOval(
                      child: (widget.item.logoUrl ?? '').isEmpty
                          ? ColoredBox(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        child: Center(child: Text(name[0].toUpperCase(), style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900, fontSize: size * 0.38))),
                      )
                          : AppNetworkImage(url: widget.item.logoUrl, width: size, height: size, placeholderIcon: AppIcons.brand),
                    ),
                  ),
                  if (verified)
                    Positioned(
                      right: 0,
                      bottom: 2,
                      child: Container(
                        padding: const EdgeInsets.all(1.5),
                        decoration: BoxDecoration(shape: BoxShape.circle, color: palette.surface),
                        child: const Icon(AppIcons.sealCheck, size: 16, color: AppColors.info),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: -0.1, color: palette.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One endless row of brands that glides by itself. Touch pauses it (and
/// you can drag); it carries on when you let go.
class _GlideRow extends StatefulWidget {
  const _GlideRow({required this.items, this.reverse = false, this.speed = 28});

  final List<BrandListItem> items;
  final bool reverse;

  /// Pixels per second.
  final double speed;

  @override
  State<_GlideRow> createState() => _GlideRowState();
}

class _GlideRowState extends State<_GlideRow> with SingleTickerProviderStateMixin {
  static const double _itemWidth = 92;
  final _controller = ScrollController();
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  bool _held = false;

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (_held || !_controller.hasClients || dt <= 0 || dt > 0.2) return;
    _controller.jumpTo(_controller.offset + widget.speed * dt);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    return SizedBox(
      height: 116,
      child: Listener(
        onPointerDown: (_) => _held = true,
        onPointerUp: (_) => _held = false,
        onPointerCancel: (_) => _held = false,
        child: ShaderMask(
          // Fade out at both edges.
          blendMode: BlendMode.dstIn,
          shaderCallback: (r) => const LinearGradient(
            colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
            stops: [0, 0.06, 0.94, 1],
          ).createShader(r),
          child: ListView.builder(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            reverse: widget.reverse,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _BrandBubble(item: items[i % items.length], size: 66, width: _itemWidth - 8),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandsSkeleton extends StatelessWidget {
  const _BrandsSkeleton();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget circle(double s) => Container(width: s, height: s, decoration: BoxDecoration(color: palette.surfaceMuted, shape: BoxShape.circle));
    Widget bar(double w) => Container(width: w, height: 10, decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(6)));
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 16, AppSpacing.gutter, 0),
      child: Column(
        children: [
          for (var r = 0; r < 4; r++)
            Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [for (var i = 0; i < 3; i++) Column(children: [circle(70), const SizedBox(height: 8), bar(60)])],
              ),
            ),
        ],
      ),
    ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1200.ms, color: palette.surface.withValues(alpha: 0.6));
  }
}

class BrandProfileScreen extends StatelessWidget {
  const BrandProfileScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    final myId = auth is AuthAuthenticated ? auth.user.id : '';
    return ActionScope(
      child: BlocProvider(
        create: (_) => LoadCubit<BrandPublicProfile>(() => sl<BrandsRepository>().bySlug(slug, myUserId: myId)),
        child: const _BrandProfileView(),
      ),
    );
  }
}

class _BrandProfileView extends StatelessWidget {
  const _BrandProfileView();

  Future<void> _follow(BuildContext context, BrandPublicProfile data) async {
    final cubit = context.read<LoadCubit<BrandPublicProfile>>();
    final following = await context.read<ActionCubit>().run('follow', () => sl<BrandsRepository>().toggleFollow(data.brand.id));
    if (following == null) return;
    HapticFeedback.lightImpact();
    cubit.replace(data.copyWith(isFollowing: following, followerCount: data.followerCount + (following ? 1 : -1)));
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<BrandPublicProfile>>();
    final actions = context.watch<ActionCubit>().state;
    final auth = context.watch<AuthBloc>().state;
    final myId = auth is AuthAuthenticated ? auth.user.id : '';
    final loaded = cubit.state.data;
    // Rebuild when someone is blocked / unblocked.
    return ValueListenableBuilder<Set<String>>(
      valueListenable: BlockedUsers.instance,
      builder: (context, _, _) => _scaffold(context, cubit, actions, myId, loaded),
    );
  }

  Widget _scaffold(BuildContext context, LoadCubit<BrandPublicProfile> cubit, ActionState actions, String myId, BrandPublicProfile? loaded) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Brand'),
        actions: [
          if (loaded != null)
            ShareIconButton(
              size: 44,
              message: () => ShareService.brand(
                slug: loaded.brand.slug,
                name: loaded.brand.companyName,
                industry: loaded.brand.industry,
                mine: loaded.brand.userId == myId,
              ),
            ),
          if (loaded != null && myId.isNotEmpty && loaded.brand.userId.isNotEmpty && loaded.brand.userId != myId)
            IconButton(
              tooltip: 'More',
              icon: const Icon(AppIcons.dotsThree),
              onPressed: () => showContentActions(context, type: ReportType.user, id: loaded.brand.userId, name: loaded.brand.companyName, userId: loaded.brand.userId),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: AsyncView<BrandPublicProfile>(
        state: cubit.state,
        onRetry: cubit.load,
        builder: (data) {
          final b = data.brand;
          final palette = context.palette;
          if (b.userId.isNotEmpty && b.userId != myId && BlockedUsers.instance.isHidden(b.userId)) {
            return BlockedProfileNotice(userId: b.userId, name: b.companyName);
          }
          return AppRefresh(
            onRefresh: cubit.refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xxl),
              children: [
                Row(
                  children: [
                    AppNetworkImage(url: b.logoUrl, width: 76, height: 76, radius: 38, placeholderIcon: AppIcons.brand),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(child: Text(b.companyName, style: context.text.headlineSmall)),
                              if (b.verificationStatus.name == 'verified') ...[
                                const SizedBox(width: AppSpacing.xxs),
                                const Icon(AppIcons.sealCheck, size: 20, color: AppColors.info),
                              ],
                            ],
                          ),
                          if (b.tagline.isNotEmpty) Text(b.tagline, style: context.text.bodyMedium),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(child: StatCard(label: 'Campaigns', value: '${data.campaignsPosted}', icon: AppIcons.campaigns)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: StatCard(label: 'Followers', value: Fmt.compact(data.followerCount), icon: AppIcons.users)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: StatCard(label: 'Rating', value: b.averageRating == 0 ? '—' : b.averageRating.toStringAsFixed(1), icon: AppIcons.star, accent: AppColors.warning)),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                data.isFollowing
                    ? AppButton.secondary(label: 'Following', icon: AppIcons.check, isLoading: actions.isBusy, onPressed: actions.isBusy ? null : () => _follow(context, data))
                    : AppButton(label: 'Follow', icon: AppIcons.userPlus, isLoading: actions.isBusy, onPressed: actions.isBusy ? null : () => _follow(context, data)),
                const SizedBox(height: AppSpacing.xl),
                const SectionHeader(title: 'About'),
                AppCard(
                  child: Column(
                    children: [
                      if (b.industry.isNotEmpty) KeyValueRow(label: 'Industry', value: b.industry),
                      if (b.location.isNotEmpty) KeyValueRow(label: 'Headquarters', value: b.location),
                      if (b.foundedYear != null) KeyValueRow(label: 'Founded', value: '${b.foundedYear}'),
                      if (b.companySize.isNotEmpty) KeyValueRow(label: 'Team size', value: b.companySize),
                    ],
                  ),
                ),
                if (b.about.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(b.about, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary)),
                ],
                if (b.website.isNotEmpty || b.socials.values.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  for (final link in [if (b.website.isNotEmpty) b.website, ...b.socials.values.values]) LinkText(url: link),
                ],
                const SizedBox(height: AppSpacing.xl),
                const SectionHeader(title: 'Open campaigns'),
                if (data.campaigns.isEmpty)
                  Text('No open campaigns right now.', style: context.text.bodyMedium)
                else
                  for (final c in data.campaigns) ...[
                    CampaignCard(campaign: c, onTap: () => context.push(AppRoutes.campaignDetail(c.id))),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                const SizedBox(height: AppSpacing.lg),
                const SectionHeader(title: 'Reviews'),
                if (data.reviews.isEmpty)
                  Text('No reviews yet.', style: context.text.bodyMedium)
                else
                  for (final r in data.reviews) ...[
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(r.from?.name ?? 'Fanitt user', style: context.text.titleSmall)),
                              for (var i = 0; i < 5; i++) Icon(i < r.rating ? AppIcons.starFilled : AppIcons.star, size: 14, color: AppColors.warning),
                            ],
                          ),
                          if (r.comment.isNotEmpty) ...[const SizedBox(height: AppSpacing.xs), Text(r.comment, style: context.text.bodyMedium)],
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}