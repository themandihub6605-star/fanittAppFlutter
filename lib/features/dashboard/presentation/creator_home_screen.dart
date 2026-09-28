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
import '../../../core/widgets/async_view.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../campaigns/data/campaign_repository.dart';
import '../../campaigns/presentation/widgets/campaign_widgets.dart';
import '../../subscription/data/subscription_repository.dart';
import '../../wallet/presentation/wallet_screen.dart';
import '../data/dashboard_repository.dart';
import 'home_widgets.dart';

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

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<CreatorHomeData>>();
    final auth = context.watch<AuthBloc>().state;
    return Scaffold(
      appBar: const HomeAppBar(),
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
              await cubit.refresh();
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xxl),
              children: [
                if (auth is AuthAuthenticated) ProfileCompletionBanner(user: auth.user),
                _EarningsCard(total: d.totalEarnings, thisMonth: d.thisMonthEarnings)
                    .animate()
                    .fadeIn(duration: 350.ms)
                    .slideY(begin: 0.05),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(child: StatCard(label: 'Followers', value: Fmt.compact(d.followerCount), icon: AppIcons.users)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: StatCard(label: 'Profile views', value: Fmt.compact(d.profileViews), icon: AppIcons.eye)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: StatCard(
                        label: 'Rating',
                        value: d.reviewCount == 0 ? '—' : d.averageRating.toStringAsFixed(1),
                        icon: AppIcons.star,
                        accent: AppColors.warning,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                AppCard(
                  onTap: () => context.push(AppRoutes.plans),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(AppIcons.crown, size: 20, color: AppColors.primary),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(child: Text('${sub.plan.name} plan', style: context.text.titleSmall)),
                          Text(sub.plan.isFree ? 'Upgrade' : 'Manage', style: context.text.labelMedium?.copyWith(color: AppColors.primary)),
                        ],
                      ),
                      if (limit != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          child: LinearProgressIndicator(
                            value: limit == 0 ? 0.0 : (sub.proposalsUsed / limit).clamp(0.0, 1.0).toDouble(),
                            minHeight: 6,
                            backgroundColor: context.palette.surfaceMuted,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text('${sub.proposalsUsed} of $limit proposals used this cycle', style: context.text.bodySmall),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    QuickAction(icon: AppIcons.image, label: 'Posts', onTap: () => context.push(AppRoutes.posts)),
                    const SizedBox(width: AppSpacing.sm),
                    QuickAction(icon: AppIcons.videoCamera, label: 'Sessions', onTap: () => context.push(AppRoutes.sessions)),
                    const SizedBox(width: AppSpacing.sm),
                    QuickAction(icon: AppIcons.gift, label: 'FanBox', onTap: () => context.push(AppRoutes.gifts)),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    QuickAction(icon: AppIcons.creators, label: 'Creators', onTap: () => context.push(AppRoutes.creatorsDirectory)),
                    const SizedBox(width: AppSpacing.sm),
                    QuickAction(icon: AppIcons.brand, label: 'Brands', onTap: () => context.push(AppRoutes.brands)),
                    const SizedBox(width: AppSpacing.sm),
                    QuickAction(icon: AppIcons.users, label: 'Communities', onTap: () => context.push(AppRoutes.communities)),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                SectionHeader(title: 'Picked for you', actionLabel: 'All campaigns', onAction: () => context.go(AppRoutes.creatorCampaigns)),
                if (data.suggestionsLocked)
                  AppCard(
                    onTap: () => context.push(AppRoutes.plans),
                    child: Row(
                      children: [
                        const Icon(AppIcons.sparkle, color: AppColors.primary),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: Text('Upgrade to Pro to see campaigns matched to your profile.', style: context.text.bodyMedium?.copyWith(color: context.palette.textPrimary))),
                      ],
                    ),
                  )
                else if (data.suggested.isEmpty)
                  Text('Complete your profile with skills and a category to get better matches.', style: context.text.bodyMedium)
                else
                  for (final s in data.suggested.take(5)) ...[
                    CampaignCard(campaign: s.campaign, onTap: () => context.push(AppRoutes.campaignDetail(s.campaign.id))),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                if (d.upcomingSessions.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  SectionHeader(title: 'Upcoming sessions', actionLabel: 'Manage', onAction: () => context.push(AppRoutes.sessions)),
                  for (final s in d.upcomingSessions.take(3))
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: AppCard(
                        child: Row(
                          children: [
                            const Icon(AppIcons.videoCamera, color: AppColors.primary),
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
                  const SizedBox(height: AppSpacing.lg),
                  SectionHeader(title: 'Recent earnings', actionLabel: 'Wallet', onAction: () => context.push(AppRoutes.wallet)),
                  AppCard(
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
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EarningsCard extends StatelessWidget {
  const _EarningsCard({required this.total, required this.thisMonth});

  final int total;
  final int thisMonth;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.navy, AppColors.navyRaised]),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total earnings', style: context.text.bodyMedium?.copyWith(color: Colors.white70)),
                const SizedBox(height: AppSpacing.xxs),
                Text(Fmt.money(total), style: context.text.headlineMedium?.copyWith(color: Colors.white)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('This month', style: context.text.bodySmall?.copyWith(color: Colors.white70)),
              const SizedBox(height: AppSpacing.xxs),
              Text(Fmt.money(thisMonth), style: context.text.titleMedium?.copyWith(color: AppColors.sunrise)),
            ],
          ),
        ],
      ),
    );
  }
}