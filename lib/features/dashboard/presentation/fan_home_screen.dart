// File: lib/features/dashboard/presentation/fan_home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_tour.dart';
import '../../../core/di/injection.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/services/feature_flags.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../core/widgets/app_update_banner.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../store/data/store_models.dart';
import '../../store/data/store_repository.dart';
import '../../store/presentation/call/request_call_sheet.dart';
import '../../store/presentation/call/talk_experts_screen.dart';
import '../../store/presentation/live/live_discover_screen.dart';
import '../../store/presentation/live/live_now_stories.dart';
import 'home_banner_slider.dart';
import 'home_discover.dart';

/// Fan home — everything a fan comes for: creators to follow and message,
/// lives to join, products to buy, posts to watch and communities to join.
/// (No campaigns — those are for creators and brands.)
class FanHomeScreen extends StatelessWidget {
  const FanHomeScreen({super.key});

  static const _gutter = EdgeInsets.symmetric(horizontal: AppSpacing.gutter);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppRefresh(
        onRefresh: () async {
          context.read<AuthBloc>().add(const AuthRefreshRequested());
          homeRefreshTick.value++;
        },
        // The hero draws under the status bar itself.
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            cacheExtent: 4000,
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            children: [
              HomeHeroSlider(topInset: MediaQuery.paddingOf(context).top),
              const Padding(padding: _gutter, child: AppUpdateBanner()),
              KeyedSubtree(key: TourTargets.search, child: const HomeSearchBar(hint: 'Search creators, lives, products…')),
              const SizedBox(height: AppSpacing.lg),

              // What a fan does on Fanitt. The admin's Fanitt Store switch only
              // turns the PHYSICAL shop on/off (merch + My orders); lives, sessions,
              // calls, communities, digital products and stores always show.
              ValueListenableBuilder<bool>(
                valueListenable: FeatureFlags.store,
                builder: (context, storeOn, _) {
                  final shop = HomeAction(icon: AppIcons.storeFilled, label: 'Fanitt Store', isNew: true, onTap: () => context.push(AppRoutes.shop));
                  final live = HomeAction(icon: AppIcons.broadcast, label: 'Live', color: AppColors.error, onTap: () => context.push(LiveDiscoverScreen.route));
                  final sessions = HomeAction(icon: AppIcons.videoCamera, label: 'Live sessions', color: const Color(0xFF7C3AED), onTap: () => context.push(AppRoutes.meets));
                  final communities = HomeAction(icon: AppIcons.users, label: 'Communities', color: AppColors.warning, onTap: () => context.push(AppRoutes.communities));
                  final products = HomeAction(icon: AppIcons.download, label: 'Digital products', color: AppColors.success, onTap: () => context.push(AppRoutes.products));
                  final stores = HomeAction(icon: AppIcons.store, label: 'Stores', color: const Color(0xFF00A3A3), onTap: () => context.push(AppRoutes.stores));
                  final creators = HomeAction(icon: AppIcons.creators, label: 'Creators', onTap: () => context.go(AppRoutes.fanLibrary));
                  final feed = HomeAction(icon: AppIcons.feed, label: 'Feed', color: const Color(0xFF6366F1), onTap: () => context.go(AppRoutes.fanFeed));
                  final messages = HomeAction(icon: AppIcons.messages, label: 'Messages', color: const Color(0xFF0EA5E9), onTap: () => context.go(AppRoutes.fanMessages));
                  final library = HomeAction(icon: AppIcons.library, label: 'My library', color: const Color(0xFFDB2777), onTap: () => context.push(AppRoutes.library));
                  final orders = HomeAction(icon: AppIcons.package, label: 'My orders', color: const Color(0xFF7C4DFF), onTap: () => context.push(AppRoutes.shopOrders));
                  final following = HomeAction(icon: AppIcons.userPlus, label: 'Following', color: const Color(0xFF14B8A6), onTap: () => context.push(AppRoutes.following));
                  final saved = HomeAction(icon: AppIcons.bookmark, label: 'Saved', color: const Color(0xFFE11D48), onTap: () => context.push(AppRoutes.savedPosts));
                  final refer = HomeAction(icon: AppIcons.gift, label: 'Refer & earn', color: AppColors.error, onTap: () => context.push(AppRoutes.referrals));

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const HomeSectionHeader(title: 'Quick actions'),
                      const SizedBox(height: AppSpacing.sm),
                      // The first tile is the big one; 5 more show, the rest are under "More".
                      // Keyed so the first-time walkthrough can point at Quick actions.
                      KeyedSubtree(
                        key: TourTargets.quickActions,
                        child: storeOn
                            ? HomeQuickActions(
                          actions: [shop, live, sessions, communities, products, stores],
                          more: [library, orders, creators, feed, messages, following, saved, refer],
                        )
                            : HomeQuickActions(
                          // No shop and no physical orders while the shop is off.
                          actions: [HomeAction(icon: AppIcons.broadcast, label: 'Live', isNew: true, onTap: () => context.push(LiveDiscoverScreen.route)), sessions, communities, products, stores, creators],
                          more: [library, feed, messages, following, saved, refer],
                        ),
                      ),

                      ...[
                        // Lives first — join your creators while they're on. Takes no
                        // space when nobody is live, and adds its own top gap when shown.
                        LiveNowStories(refresh: homeRefreshTick),

                        // Talk 1:1 with experts — audio / video calls at their own per-minute
                        // rate (or free). The rail adds its own top gap, like every section.
                        const CallCreatorsRail(),

                        // Creator stores (the admin list hides this rail, so it is placed here).
                        const StoresRail(),
                      ],

                      // Creators, sessions, communities, products… in the order set
                      // in the admin panel. No campaigns for fans; lives are shown above.
                      // The physical shop section hides itself while the shop is off.
                      // showBrands: false → no "Brands on Fanitt" strip for fans.
                      HomeSections(
                        showCampaigns: false,
                        showBrands: false,
                        hide: const {'live'},
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Talk 1:1 with experts" — creators taking audio / video calls. Online
/// first; each card shows the per-minute rate (or Free) and a Call button.
/// Used on the fan, creator and brand homes (the server leaves out the
/// viewer's own store). See all → every expert, with categories.
class CallCreatorsRail extends StatelessWidget {
  const CallCreatorsRail({super.key});

  @override
  Widget build(BuildContext context) {
    return HomeRail<({StoreInfo store, CallInfo calls, ExpertCreator creator})>(
      title: 'Talk 1:1 with experts',
      subtitle: 'Audio & video calls · pay per minute or free',
      height: 192,
      itemWidth: 250,
      leading: const Icon(AppIcons.phone, size: 16, color: AppColors.primary),
      onSeeAll: () => context.push(TalkExpertsScreen.route),
      load: () => sl<StoreRepository>().callCreators(),
      itemBuilder: (context, item) => _CallCreatorCard(store: item.store, info: item.calls, creator: item.creator),
    );
  }
}

class _CallCreatorCard extends StatelessWidget {
  const _CallCreatorCard({required this.store, required this.info, required this.creator});

  /// Needed to place the call (rates and checkout live on the store).
  final StoreInfo store;
  final CallInfo info;

  /// Who the fan actually talks to.
  final ExpertCreator creator;

  String _rate(int paise) => paise <= 0 ? 'Free' : '${Fmt.money(paise)}/min';

  void _openProfile(BuildContext context) {
    HapticFeedback.selectionClick();
    context.push(creator.slug.isNotEmpty ? AppRoutes.creatorProfile(creator.slug) : AppRoutes.storePage(store.slug));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final canCall = info.online && !info.busy;
    final (statusText, statusColor) = info.busy
        ? ('In a call', AppColors.warning)
        : info.online
        ? ('Online now', const Color(0xFF22C55E))
        : ('Offline', palette.textTertiary);
    final name = creator.name.trim().isEmpty ? store.name : creator.name.trim();
    final headline = creator.headline;
    final bio = creator.bio.trim().replaceAll(RegExp(r'\s+'), ' ');
    // Title on the first line under the name; the bio below if it adds something.
    final about = headline != bio && bio.isNotEmpty ? bio : (headline.isEmpty ? store.tagline.trim() : '');

    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openProfile(context),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: canCall ? const Color(0xFF22C55E).withValues(alpha: 0.45) : palette.border.withValues(alpha: 0.8)),
            boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x0D101828), blurRadius: 14, offset: Offset(0, 6))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: canCall ? const Color(0xFF22C55E) : palette.border, width: 2)),
                        child: UserAvatar(initials: creator.initials, imageUrl: creator.avatarUrl.isEmpty ? null : creator.avatarUrl, size: 42),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle, border: Border.all(color: palette.surface, width: 2.5)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.2))),
                            if (creator.verified) ...[
                              const SizedBox(width: 4),
                              const Icon(AppIcons.sealCheck, size: 14, color: AppColors.info),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          headline.isNotEmpty ? headline : statusText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: headline.isNotEmpty ? palette.textSecondary : statusColor),
                        ),
                      ],
                    ),
                  ),
                  if (creator.rating > 0) ...[
                    const SizedBox(width: 6),
                    const Icon(AppIcons.starFilled, size: 13, color: Color(0xFFF5A524)),
                    const SizedBox(width: 2),
                    Text(creator.rating.toStringAsFixed(1), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: palette.textPrimary)),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                about.isNotEmpty ? about : statusText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, height: 1.35, color: about.isNotEmpty ? palette.textSecondary : statusColor),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(AppIcons.phone, size: 13, color: palette.textSecondary),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      [
                        if (info.audioEnabled) 'Audio ${_rate(info.audioRate)}',
                        if (info.videoEnabled) 'Video ${_rate(info.videoRate)}',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: palette.textPrimary),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 36,
                child: canCall
                    ? DecoratedBox(
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(99)),
                  child: TextButton.icon(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      showRequestCallSheet(context, store: store, info: info);
                    },
                    icon: const Icon(AppIcons.phone, size: 16, color: Colors.white),
                    label: Text('Call ${name.split(' ').first}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
                )
                    : OutlinedButton(
                  onPressed: () => _openProfile(context),
                  style: OutlinedButton.styleFrom(shape: const StadiumBorder(), side: BorderSide(color: palette.border)),
                  child: Text(info.busy ? 'In a call · view profile' : 'Offline · view profile', style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w700, fontSize: 12.5)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}