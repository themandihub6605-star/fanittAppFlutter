// File: lib/features/dashboard/presentation/brand_home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_tour.dart';
import '../../../core/bloc/load_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/services/feature_flags.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_update_banner.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/async_view.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../campaigns/data/campaign_models.dart';
import '../../campaigns/presentation/brand/brand_campaigns_screen.dart';
import '../../campaigns/presentation/widgets/campaign_widgets.dart';
import '../../store/presentation/live/live_discover_screen.dart';
import '../../subscription/data/subscription_repository.dart';
import '../data/dashboard_repository.dart';
import 'fan_home_screen.dart' show CallCreatorsRail;
import 'home_discover.dart';
import 'home_widgets.dart';
import 'home_banner_slider.dart';

class BrandHomeData {
  const BrandHomeData({required this.dashboard, required this.subscription});

  final BrandDashboard dashboard;
  final UserSubscription subscription;
}

class BrandHomeScreen extends StatelessWidget {
  const BrandHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LoadCubit<BrandHomeData>(() async {
        final results = await Future.wait<Object>([sl<DashboardRepository>().brand(), sl<SubscriptionRepository>().mine()]);
        return BrandHomeData(dashboard: results[0] as BrandDashboard, subscription: results[1] as UserSubscription);
      }),
      child: const _BrandHomeView(),
    );
  }
}

class _BrandHomeView extends StatelessWidget {
  const _BrandHomeView();

  static const _gutter = EdgeInsets.symmetric(horizontal: AppSpacing.gutter);

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<BrandHomeData>>();
    final auth = context.watch<AuthBloc>().state;

    return Scaffold(
      body: AsyncView<BrandHomeData>(
        state: cubit.state,
        onRetry: cubit.load,
        builder: (data) {
          final d = data.dashboard;
          final active = d.campaigns.where((c) => c.status.isActive).toList();
          final needsReview = active.where((c) => c.status == CampaignStatus.submitted || c.status == CampaignStatus.disputed).length;
          final limit = data.subscription.plan.campaignPostLimit;

          Future<void> postCampaign() async {
            final created = await context.push<bool>(AppRoutes.campaignEditor());
            if ((created ?? false) && context.mounted) cubit.refresh();
          }

          return AppRefresh(
            onRefresh: () async {
              context.read<AuthBloc>().add(const AuthRefreshRequested());
              homeRefreshTick.value++;
              await cubit.refresh();
            },
            // The hero handles the status bar itself; without this every
            // grid/list inside the home adds the status-bar height as extra
            // top space (e.g. under "Quick actions").
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                // Build the whole home once so sections don't reload or re-animate while scrolling.
                cacheExtent: 4000,
                // The hero draws under the status bar itself.
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                children: [
                  // Full-bleed slider + header (greeting header when no banners).
                  HomeHeroSlider(topInset: MediaQuery.paddingOf(context).top),
                  const Padding(padding: _gutter, child: AppUpdateBanner()),
                  if (auth is AuthAuthenticated) Padding(padding: _gutter, child: ProfileCompletionBanner(user: auth.user)),
                  KeyedSubtree(key: TourTargets.search, child: const HomeSearchBar(hint: 'Search creators, brands, communities…')),
                  const SizedBox(height: AppSpacing.lg),

                  // Escrow hero
                  HomeHero(
                    label: 'Protected in escrow',
                    value: Fmt.money(d.inEscrow),
                    caption: 'Total spent ${Fmt.money(d.totalSpent)}${limit != null ? ' · ${data.subscription.campaignsPosted}/$limit campaigns used' : ''}',
                    trailing: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      onTap: () => context.push(AppRoutes.plans),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.pill)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(AppIcons.crown, size: 14, color: AppColors.sunrise),
                            const SizedBox(width: 4),
                            Text(
                              data.subscription.plan.isFree ? '${data.subscription.plan.name} · Upgrade' : data.subscription.plan.name,
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                    primaryAction: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      clipBehavior: Clip.antiAlias,
                      child: Ink(
                        decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFF4511E), Color(0xFFEC2A78)])),
                        child: InkWell(
                          onTap: postCampaign,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 13),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(AppIcons.plus, color: Colors.white, size: 18),
                                SizedBox(width: 6),
                                Text('Post a campaign', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  HomeStatsRow(
                    stats: [
                      (label: 'Active campaigns', value: '${active.length}', icon: AppIcons.campaigns, color: AppColors.primary),
                      (label: 'To review', value: '$needsReview', icon: AppIcons.eye, color: needsReview > 0 ? AppColors.error : AppColors.info),
                      (label: 'Profile views', value: Fmt.compact(d.profileViews), icon: AppIcons.users, color: AppColors.success),
                    ],
                  ),

                  // Quick actions
                  homeGap,
                  const HomeSectionHeader(title: 'Quick actions'),
                  const SizedBox(height: AppSpacing.md),
                  // The admin's Fanitt Store switch only turns the PHYSICAL shop on/off
                  // (merch, orders). Everything else always shows.
                  // ON  → My campaigns, Find creators, Live, Live sessions, Communities, Fanitt Store.
                  // OFF → same, with Digital products in place of the Fanitt Store shop.
                  // Keyed so the first-time walkthrough can point at Quick actions.
                  KeyedSubtree(
                    key: TourTargets.quickActions,
                    child: ValueListenableBuilder<bool>(
                      valueListenable: FeatureFlags.store,
                      builder: (context, storeOn, _) {
                        // Feed is a tab now; Find creators opens as its own page.
                        final findCreators = HomeAction(icon: AppIcons.creators, label: 'Find creators', color: AppColors.info, onTap: () => context.push(AppRoutes.creatorsDirectory));
                        // First (big) tile: New campaign already sits higher up on Home, so this is My campaigns.
                        final myCampaigns = HomeAction(icon: AppIcons.campaigns, label: 'My campaigns', onTap: () => context.push(AppRoutes.brandCampaigns));
                        final messages = HomeAction(icon: AppIcons.messages, label: 'Messages', color: const Color(0xFF7C4DFF), onTap: () => context.go(AppRoutes.brandMessages));
                        final live = HomeAction(icon: AppIcons.broadcast, label: 'Live', color: AppColors.error, onTap: () => context.push(LiveDiscoverScreen.route));
                        final sessions = HomeAction(icon: AppIcons.videoCamera, label: 'Live sessions', color: const Color(0xFF7C3AED), onTap: () => context.push(AppRoutes.meets));
                        final communities = HomeAction(icon: AppIcons.users, label: 'Communities', color: AppColors.warning, onTap: () => context.push(AppRoutes.communities));
                        final fanittStore = HomeAction(icon: AppIcons.store, label: 'Fanitt Store', color: const Color(0xFF00A3A3), onTap: () => context.push(AppRoutes.shop));
                        final products = HomeAction(icon: AppIcons.package, label: 'Digital products', color: const Color(0xFF0D9488), onTap: () => context.push(AppRoutes.products));
                        final rest = [
                          HomeAction(icon: AppIcons.wallet, label: 'Wallet', color: const Color(0xFFF59E0B), onTap: () => context.push(AppRoutes.wallet)),
                          HomeAction(icon: AppIcons.crown, label: 'Plans', color: const Color(0xFFEAB308), onTap: () => context.push(AppRoutes.plans)),
                          HomeAction(icon: AppIcons.receipt, label: 'Activity', color: const Color(0xFF16A34A), onTap: () => context.push(AppRoutes.transactions)),
                          HomeAction(icon: AppIcons.userPlus, label: 'Following', color: const Color(0xFF14B8A6), onTap: () => context.push(AppRoutes.following)),
                          HomeAction(icon: AppIcons.pencil, label: 'Edit profile', color: AppColors.info, onTap: () => context.push(AppRoutes.editProfile)),
                        ];
                        // The first tile is the big one; 5 more show, the rest are under "More".
                        return storeOn
                            ? HomeQuickActions(
                          actions: [myCampaigns, findCreators, live, sessions, communities, fanittStore],
                          more: [products, messages, ...rest],
                        )
                            : HomeQuickActions(
                          actions: [myCampaigns, findCreators, live, sessions, communities, products],
                          more: [messages, ...rest],
                        );
                      },
                    ),
                  ),

                  // Active campaigns
                  homeGap,
                  HomeSectionHeader(title: 'Active campaigns', subtitle: needsReview > 0 ? '$needsReview need your review' : null, onSeeAll: () => context.push(AppRoutes.brandCampaigns)),
                  const SizedBox(height: AppSpacing.sm),
                  Padding(
                    padding: _gutter,
                    child: active.isEmpty
                        ? AppCard(
                      onTap: postCampaign,
                      child: Row(
                        children: [
                          const Icon(AppIcons.campaigns, color: AppColors.primary),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(child: Text('No live campaigns yet — post one and creators start applying.', style: context.text.bodyMedium?.copyWith(color: context.palette.textPrimary))),
                        ],
                      ),
                    )
                        : Column(
                      children: [
                        for (final (i, c) in active.take(4).indexed)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: CampaignCard(
                              campaign: c,
                              showStatus: true,
                              onTap: () async {
                                if (await openBrandCampaign(context, c) && context.mounted) cubit.refresh();
                              },
                            ).animate(delay: (60 * i).ms).fadeIn(duration: 300.ms).slideY(begin: 0.06),
                          ),
                      ],
                    ),
                  ),

                  // Talk 1:1 with experts — audio / video calls with creators.
                  const CallCreatorsRail(),

                  // Discover sections — order, titles and pinned items come from the admin panel.
                  // No "Open campaigns" here — those are other brands' campaigns.
                  // Live, live sessions, communities, digital products, the Fanitt Store
                  // shop and "Brands on Fanitt" are not repeated here (Quick actions).
                  const HomeSections(
                    showCampaigns: false,
                    showBrands: false,
                    hide: {'live', 'livenow', 'meets', 'communities', 'shop', 'products'},
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}