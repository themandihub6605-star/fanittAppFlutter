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
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_update_banner.dart';
import '../../../core/widgets/async_view.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../campaigns/data/campaign_repository.dart';
import '../../campaigns/presentation/widgets/campaign_widgets.dart';
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
          final sub = data.subscription;
          final limit = sub.plan.proposalLimit;
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
                padding: const EdgeInsets.only(bottom: AppSpacing.huge),
                children: [
                  // Full-bleed slider + header (greeting header when no banners).
                  HomeHeroSlider(topInset: MediaQuery.paddingOf(context).top),
                  const Padding(padding: _gutter, child: AppUpdateBanner()),
                  if (auth is AuthAuthenticated) Padding(padding: _gutter, child: ProfileCompletionBanner(user: auth.user)),
                  const HomeSearchBar(hint: 'Search creators, brands, stores…'),
                  const SizedBox(height: AppSpacing.lg),

                  HomeStatsRow(
                    stats: [
                      (label: 'Followers', value: Fmt.compact(d.followerCount), icon: AppIcons.users, color: AppColors.primary),
                      (label: 'Profile views', value: Fmt.compact(d.profileViews), icon: AppIcons.eye, color: AppColors.info),
                      (
                      label: d.reviewCount == 0 ? 'No reviews yet' : '${d.reviewCount} reviews',
                      value: d.reviewCount == 0 ? '—' : d.averageRating.toStringAsFixed(1),
                      icon: AppIcons.star,
                      color: AppColors.warning,
                      ),
                    ],
                  ),
                  // Quick actions
                  homeGap,
                  const HomeSectionHeader(title: 'Quick actions'),
                  const SizedBox(height: AppSpacing.sm),
                  HomeQuickActions(
                    actions: [
                      HomeAction(icon: AppIcons.storeFilled, label: 'My store', isNew: true, onTap: () => context.push(AppRoutes.store)),
                      HomeAction(icon: AppIcons.chartLine, label: 'Analytics', color: AppColors.info, onTap: () => context.push(AppRoutes.storeAnalytics)),
                      HomeAction(icon: AppIcons.brand, label: 'Brands', color: const Color(0xFF7C4DFF), onTap: () => context.push(AppRoutes.brands)),
                      HomeAction(icon: AppIcons.campaigns, label: 'Campaigns', color: AppColors.success, onTap: () => context.go(AppRoutes.creatorCampaigns)),
                      HomeAction(icon: AppIcons.gift, label: 'FanBox', color: const Color(0xFFEC2A78), onTap: () => context.push(AppRoutes.storeFanbox)),
                      HomeAction(icon: AppIcons.users, label: 'Communities', color: AppColors.warning, onTap: () => context.push(AppRoutes.communities)),
                      HomeAction(icon: AppIcons.package, label: 'Shop', color: const Color(0xFF00A3A3), onTap: () => context.push(AppRoutes.products)),
                      HomeAction(icon: AppIcons.gift, label: 'Refer & earn', color: AppColors.error, onTap: () => context.push(AppRoutes.referrals)),
                    ],
                  ),

                  const Padding(padding: EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xl, AppSpacing.gutter, 0), child: StorePromoBanner()),

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
                  HomeSections(campaignsSeeAll: () => context.go(AppRoutes.creatorCampaigns)),

                  if (d.upcomingSessions.isNotEmpty) ...[
                    homeGap,
                    HomeSectionHeader(title: 'Your upcoming sessions', onSeeAll: () => context.push(AppRoutes.sessions)),
                    const SizedBox(height: AppSpacing.sm),
                    for (final s in d.upcomingSessions.take(3))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, AppSpacing.xs),
                        child: AppCard(
                          onTap: () => context.push(AppRoutes.sessions),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.md)),
                                child: const Icon(AppIcons.videoCamera, color: AppColors.primary, size: 20),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(s.title, style: context.text.titleSmall),
                                    Text('${Fmt.weekdayDateTime(s.scheduledAt)} · ${s.bookedCount} booked', style: context.text.bodySmall),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
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

                  // Earnings card — at the bottom of the home.
                  homeGap,
                  HomeHero(
                    label: 'Total earnings',
                    value: Fmt.money(d.totalEarnings),
                    caption: 'This month ${Fmt.money(d.thisMonthEarnings)}',
                    trailing: _PlanChip(name: sub.plan.name, isFree: sub.plan.isFree),
                    // One clear call to action.
                    primaryAction: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _HeroButton(icon: AppIcons.wallet, label: 'View wallet & withdraw', filled: true, onTap: () => context.push(AppRoutes.wallet)),
                        // Plan usage sits inside the same card.
                        if (limit != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          _ProposalMeter(used: sub.proposalsUsed, limit: limit, isFree: sub.plan.isFree),
                        ],
                      ],
                    ),
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

class _PlanChip extends StatelessWidget {
  const _PlanChip({required this.name, required this.isFree});

  final String name;
  final bool isFree;

  @override
  Widget build(BuildContext context) {
    return InkWell(
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
            Text(isFree ? '$name · Upgrade' : name, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

/// "3 of 10 proposals used" + bar, styled for the dark earnings card.
class _ProposalMeter extends StatelessWidget {
  const _ProposalMeter({required this.used, required this.limit, required this.isFree});

  final int used;
  final int limit;
  final bool isFree;

  @override
  Widget build(BuildContext context) {
    final share = limit == 0 ? 0.0 : (used / limit).clamp(0.0, 1.0).toDouble();
    return Material(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(AppRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(AppRoutes.plans),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(AppIcons.paperPlane, size: 15, color: Colors.white70),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '$used', style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                          TextSpan(text: ' of $limit proposals used'),
                        ],
                      ),
                      style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(isFree ? 'Upgrade' : 'Manage', style: const TextStyle(color: AppColors.sunrise, fontSize: 12.5, fontWeight: FontWeight.w800)),
                  const Icon(AppIcons.chevronRight, size: 14, color: AppColors.sunrise),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: share),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => Stack(
                    children: [
                      Container(height: 6, color: Colors.white.withValues(alpha: 0.14)),
                      FractionallySizedBox(
                        widthFactor: v,
                        child: Container(height: 6, decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]))),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroButton extends StatelessWidget {
  const _HeroButton({required this.icon, required this.label, required this.onTap, this.filled = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.md),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: filled ? const LinearGradient(colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]) : null,
          color: filled ? null : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}