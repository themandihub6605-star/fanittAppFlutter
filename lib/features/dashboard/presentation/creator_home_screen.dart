// File: lib/features/dashboard/presentation/creator_home_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
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
import '../../../core/widgets/app_update_banner.dart';
import '../../../core/widgets/async_view.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../store/data/store_access.dart';
import '../../store/presentation/live/live_discover_screen.dart';
import '../../store/presentation/widgets/store_promo_banner.dart';
import '../../subscription/data/subscription_repository.dart';
import '../../wallet/presentation/wallet_screen.dart';
import '../data/dashboard_repository.dart';
import 'fan_home_screen.dart' show CallCreatorsRail;
import 'home_discover.dart';
import 'home_widgets.dart';
import 'home_banner_slider.dart';

class CreatorHomeData {
  const CreatorHomeData({required this.dashboard, required this.subscription});

  final CreatorDashboard dashboard;
  final UserSubscription subscription;
}

Future<CreatorHomeData> _load(String myId) async {
  // Is the Fanitt Store live? (locks the store tools on the home)
  unawaited(StoreAccess.refresh(myId));
  final results = await Future.wait<Object>([
    sl<DashboardRepository>().creator(myId),
    sl<SubscriptionRepository>().mine(),
  ]);
  return CreatorHomeData(
    dashboard: results[0] as CreatorDashboard,
    subscription: results[1] as UserSubscription,
  );
}

class CreatorHomeScreen extends StatelessWidget {
  const CreatorHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    final myId = auth is AuthAuthenticated ? auth.user.id : '';
    return BlocProvider(
      create: (_) => LoadCubit<CreatorHomeData>(() => _load(myId)),
      child: const _CreatorHomeView(),
    );
  }
}

class _CreatorHomeView extends StatelessWidget {
  const _CreatorHomeView();

  static const _gutter = EdgeInsets.symmetric(horizontal: AppSpacing.gutter);

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<CreatorHomeData>>();
    final auth = context.watch<AuthBloc>().state;
    return Scaffold(
      body: AsyncView<CreatorHomeData>(
        state: cubit.state,
        onRetry: cubit.load,
        builder: (data) {
          final d = data.dashboard;
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
                  KeyedSubtree(key: TourTargets.search, child: const HomeSearchBar(hint: 'Search creators, brands, stores…')),
                  const SizedBox(height: AppSpacing.lg),

                  // Followers / profile views / reviews moved to the Profile tab.
                  // Quick actions
                  const HomeSectionHeader(title: 'Quick actions'),
                  const SizedBox(height: AppSpacing.sm),
                  // The admin's Fanitt Store switch only turns the PHYSICAL shop on/off
                  // (merch, orders). Everything else always shows.
                  // ON  → My store, Live, Live sessions, Communities, Fanitt Store, Plans (Brands is under More).
                  // OFF → same, with Digital products in place of the Fanitt Store shop.
                  // Keyed so the first-time walkthrough can point at Quick actions.
                  KeyedSubtree(
                    key: TourTargets.quickActions,
                    child: ValueListenableBuilder<bool>(
                      valueListenable: FeatureFlags.store,
                      builder: (context, storeOn, _) {
                        final myStore = HomeAction(icon: AppIcons.storeFilled, label: 'My store', isNew: true, onTap: () => context.push(AppRoutes.store));
                        // Home shows other creators' things; your own live / sessions /
                        // community are managed in My store.
                        final live = HomeAction(icon: AppIcons.broadcast, label: 'Live', color: AppColors.error, onTap: () => context.push(LiveDiscoverScreen.route));
                        final sessions = HomeAction(icon: AppIcons.videoCamera, label: 'Live sessions', color: const Color(0xFF7C3AED), onTap: () => context.push(AppRoutes.meets));
                        final communities = HomeAction(icon: AppIcons.users, label: 'Communities', color: AppColors.warning, onTap: () => context.push(AppRoutes.communities));
                        final fanittStore = HomeAction(icon: AppIcons.store, label: 'Fanitt Store', color: const Color(0xFF00A3A3), onTap: () => context.push(AppRoutes.shop));
                        final plans = HomeAction(icon: AppIcons.crown, label: 'Plans', color: const Color(0xFFEAB308), onTap: () => context.push(AppRoutes.plans));
                        final brands = HomeAction(icon: AppIcons.brand, label: 'Brands', color: const Color(0xFF7C4DFF), onTap: () => context.push(AppRoutes.brands));
                        final campaigns = HomeAction(icon: AppIcons.campaigns, label: 'Campaigns', color: AppColors.success, onTap: () => context.go(AppRoutes.creatorCampaigns));
                        final messages = HomeAction(icon: AppIcons.messages, label: 'Messages', color: const Color(0xFF0EA5E9), onTap: () => context.go(AppRoutes.creatorMessages));
                        final products = HomeAction(icon: AppIcons.package, label: 'Digital products', color: const Color(0xFF0D9488), onTap: () => context.push(AppRoutes.products));
                        final refer = HomeAction(icon: AppIcons.gift, label: 'Refer & earn', color: AppColors.error, onTap: () => context.push(AppRoutes.referrals));
                        final rest = [
                          HomeAction(icon: AppIcons.storeFilled, label: 'Explore stores', color: const Color(0xFF00A3A3), onTap: () => context.push(AppRoutes.stores)),
                          HomeAction(icon: AppIcons.wallet, label: 'Wallet', color: const Color(0xFFF59E0B), onTap: () => context.push(AppRoutes.wallet)),
                          HomeAction(icon: AppIcons.image, label: 'My posts', color: const Color(0xFFDB2777), onTap: () => context.push(AppRoutes.posts)),
                          HomeAction(icon: AppIcons.feed, label: 'Feed', color: const Color(0xFF6366F1), onTap: () => context.go(AppRoutes.creatorFeed)),
                          HomeAction(icon: AppIcons.receipt, label: 'Activity', color: const Color(0xFF16A34A), onTap: () => context.push(AppRoutes.transactions)),
                          HomeAction(icon: AppIcons.userPlus, label: 'Following', color: const Color(0xFF14B8A6), onTap: () => context.push(AppRoutes.following)),
                          HomeAction(icon: AppIcons.bookmark, label: 'Saved', color: const Color(0xFFE11D48), onTap: () => context.push(AppRoutes.savedPosts)),
                          HomeAction(icon: AppIcons.pencil, label: 'Edit profile', color: AppColors.info, onTap: () => context.push(AppRoutes.editProfile)),
                        ];
                        // The first tile is the big one; 5 more show, the rest are under "More".
                        return storeOn
                            ? HomeQuickActions(
                          actions: [myStore, live, sessions, communities, fanittStore, plans],
                          more: [products, brands, campaigns, messages, refer, ...rest],
                        )
                            : HomeQuickActions(
                          actions: [myStore, live, sessions, communities, products, plans],
                          more: [brands, campaigns, messages, refer, ...rest],
                        );
                      },
                    ),
                  ),

                  // Store banner — wider than the cards (12px side margins) and taller.
                  const Padding(padding: EdgeInsets.fromLTRB(12, AppSpacing.xl, 12, 0), child: StorePromoBanner()),

                  // Picked for you — campaigns matched to the profile (loads itself).
                  homeGap,
                  PickedForYouSection(onSeeAll: () => context.go(AppRoutes.creatorCampaigns)),

                  // Open campaigns — right after Picked for you, above Talk 1:1.
                  CampaignsRail(onSeeAll: () => context.go(AppRoutes.creatorCampaigns)),

                  // Talk 1:1 with experts (the server leaves out your own store).
                  const CallCreatorsRail(),

                  // Discover sections — order, titles and pinned items come from the admin panel.
                  // Live, live sessions, communities, digital products and the Fanitt Store
                  // shop are reached from Quick actions instead, and Open campaigns is
                  // placed above, so they are not repeated here.
                  HomeSections(
                    campaignsSeeAll: () => context.go(AppRoutes.creatorCampaigns),
                    showBrands: false,
                    hide: const {'live', 'livenow', 'meets', 'communities', 'shop', 'products', 'campaigns'},
                  ),

                  if (d.recentTransactions.isNotEmpty) ...[
                    homeGap,
                    HomeSectionHeader(title: 'Recent earnings', onSeeAll: () => context.push(AppRoutes.wallet)),
                    const SizedBox(height: AppSpacing.sm),
                    Padding(
                      padding: _gutter,
                      // Same card frame as every home section.
                      child: Container(
                        decoration: BoxDecoration(
                          color: context.palette.surface,
                          borderRadius: BorderRadius.circular(kHomeCardRadius),
                          border: Border.all(color: context.palette.border.withValues(alpha: context.isDark ? 0.55 : 0.7)),
                          boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x0D101828), blurRadius: 12, offset: Offset(0, 4))],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            for (final (i, t) in d.recentTransactions.take(4).indexed) ...[
                              if (i > 0) Divider(height: 1, indent: 64, color: context.palette.border),
                              TransactionTile(transaction: t),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],

                ],
              ),
            ),
          );
        },
      ),
    );
  }
}