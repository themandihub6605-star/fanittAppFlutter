import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/bloc/load_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_update_banner.dart';
import '../../../core/widgets/async_view.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../campaigns/data/campaign_repository.dart';
import '../../campaigns/presentation/widgets/campaign_widgets.dart';
import '../../store/data/store_access.dart';
import '../../store/presentation/widgets/store_promo_banner.dart';
import '../../subscription/data/subscription_repository.dart';
import '../../wallet/presentation/wallet_screen.dart';
import '../data/dashboard_repository.dart';
import 'home_discover.dart';
import 'home_widgets.dart';
import 'home_banner_slider.dart';

class CreatorHomeData {
  const CreatorHomeData({required this.dashboard, required this.subscription, required this.suggested, required this.suggestionsLocked});

  final CreatorDashboard dashboard;
  final UserSubscription subscription;
  final List<SuggestedCampaign> suggested;
  final bool suggestionsLocked;
}

Future<CreatorHomeData> _load(String myId) async {
  // Is the Fanitt Store live? (locks the store tools on the home)
  unawaited(StoreAccess.refresh(myId));
  final results = await Future.wait<Object>([
    sl<DashboardRepository>().creator(myId),
    sl<SubscriptionRepository>().mine(),
  ]);
  var suggested = const <SuggestedCampaign>[];
  var locked = false;
  try {
    suggested = await sl<CampaignRepository>().suggested();
  } on ApiException catch (error) {
    if (error.errorCode == 'PRO_FEATURE_LOCKED') {
      locked = true;
    } else if (error.statusCode != 404) {
      rethrow;
    }
  }
  return CreatorHomeData(
    dashboard: results[0] as CreatorDashboard,
    subscription: results[1] as UserSubscription,
    suggested: suggested,
    suggestionsLocked: locked,
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
                  const HomeSearchBar(hint: 'Search creators, brands, stores…'),
                  const SizedBox(height: AppSpacing.lg),

                  // Followers / profile views / reviews moved to the Profile tab.
                  // Quick actions
                  const HomeSectionHeader(title: 'Quick actions'),
                  const SizedBox(height: AppSpacing.sm),
                  // Store tools (live, calls, products…) stay inside My store, not here.
                  HomeQuickActions(
                    // Most used first. The 8th tile is "More".
                    actions: [
                      HomeAction(icon: AppIcons.storeFilled, label: 'My store', isNew: true, onTap: () => context.push(AppRoutes.store)),
                      HomeAction(icon: AppIcons.campaigns, label: 'Campaigns', color: AppColors.success, onTap: () => context.go(AppRoutes.creatorCampaigns)),
                      HomeAction(icon: AppIcons.brand, label: 'Brands', color: const Color(0xFF7C4DFF), onTap: () => context.push(AppRoutes.brands)),
                      HomeAction(icon: AppIcons.users, label: 'Communities', color: AppColors.warning, onTap: () => context.push(AppRoutes.communities)),
                      HomeAction(icon: AppIcons.messages, label: 'Messages', color: const Color(0xFF0EA5E9), onTap: () => context.go(AppRoutes.creatorMessages)),
                      HomeAction(icon: AppIcons.package, label: 'Shop', color: const Color(0xFF00A3A3), onTap: () => context.push(AppRoutes.products)),
                      HomeAction(icon: AppIcons.gift, label: 'Refer & earn', color: AppColors.error, onTap: () => context.push(AppRoutes.referrals)),
                    ],
                    more: [
                      HomeAction(icon: AppIcons.wallet, label: 'Wallet', color: const Color(0xFFF59E0B), onTap: () => context.push(AppRoutes.wallet)),
                      HomeAction(icon: AppIcons.image, label: 'My posts', color: const Color(0xFFDB2777), onTap: () => context.push(AppRoutes.posts)),
                      HomeAction(icon: AppIcons.feed, label: 'Feed', color: const Color(0xFF6366F1), onTap: () => context.go(AppRoutes.creatorFeed)),
                      HomeAction(icon: AppIcons.crown, label: 'Plans', color: const Color(0xFFEAB308), onTap: () => context.push(AppRoutes.plans)),
                      HomeAction(icon: AppIcons.receipt, label: 'Activity', color: const Color(0xFF16A34A), onTap: () => context.push(AppRoutes.transactions)),
                      HomeAction(icon: AppIcons.userPlus, label: 'Following', color: const Color(0xFF14B8A6), onTap: () => context.push(AppRoutes.following)),
                      HomeAction(icon: AppIcons.bookmark, label: 'Saved', color: const Color(0xFFE11D48), onTap: () => context.push(AppRoutes.savedPosts)),
                      HomeAction(icon: AppIcons.pencil, label: 'Edit profile', color: AppColors.info, onTap: () => context.push(AppRoutes.editProfile)),
                    ],
                  ),

                  // Store banner — wider than the cards (12px side margins) and taller.
                  const Padding(padding: EdgeInsets.fromLTRB(12, AppSpacing.xl, 12, 0), child: StorePromoBanner()),

                  // Picked for you
                  homeGap,
                  HomeSectionHeader(title: 'Picked for you', subtitle: 'Campaigns that match your profile', onSeeAll: () => context.go(AppRoutes.creatorCampaigns)),
                  const SizedBox(height: AppSpacing.sm),
                  Padding(
                    padding: _gutter,
                    child: data.suggestionsLocked
                        ? AppCard(
                      onTap: () => context.push(AppRoutes.plans),
                      child: Row(
                        children: [
                          const Icon(AppIcons.sparkle, color: AppColors.primary),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(child: Text('Upgrade to Pro to see campaigns matched to your profile.', style: context.text.bodyMedium?.copyWith(color: context.palette.textPrimary))),
                        ],
                      ),
                    )
                        : data.suggested.isEmpty
                        ? Text('Add skills and a category to your profile to get better matches.', style: context.text.bodyMedium)
                        : Column(
                      children: [
                        for (final (i, s) in data.suggested.take(3).indexed)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: CampaignCard(campaign: s.campaign, onTap: () => context.push(AppRoutes.campaignDetail(s.campaign.id)))
                                .animate(delay: (60 * i).ms)
                                .fadeIn(duration: 300.ms)
                                .slideY(begin: 0.06),
                          ),
                      ],
                    ),
                  ),

                  // Discover sections — order, titles and pinned items come from the admin panel.
                  HomeSections(campaignsSeeAll: () => context.go(AppRoutes.creatorCampaigns), showBrands: false),

                  if (d.recentTransactions.isNotEmpty) ...[
                    homeGap,
                    HomeSectionHeader(title: 'Recent earnings', onSeeAll: () => context.push(AppRoutes.wallet)),
                    const SizedBox(height: AppSpacing.sm),
                    Padding(
                      padding: _gutter,
                      child: AppCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            for (final (i, t) in d.recentTransactions.take(4).indexed) ...[
                              if (i > 0) const Divider(indent: 64),
                              TransactionTile(transaction: t),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],

                  // Brands on Fanitt — sliding logos at the very bottom.
                  // (Earnings now live in the Account tab.)
                  const HomeBrandsSlot(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}