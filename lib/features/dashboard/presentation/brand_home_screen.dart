import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/bloc/load_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/async_view.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../campaigns/data/campaign_models.dart';
import '../../campaigns/presentation/brand/brand_campaigns_screen.dart';
import '../../campaigns/presentation/widgets/campaign_widgets.dart';
import '../../subscription/data/subscription_repository.dart';
import '../data/dashboard_repository.dart';
import 'home_widgets.dart';

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

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<BrandHomeData>>();
    final auth = context.watch<AuthBloc>().state;

    return Scaffold(
      appBar: const HomeAppBar(),
      body: AsyncView<BrandHomeData>(
        state: cubit.state,
        onRetry: cubit.load,
        builder: (data) {
          final d = data.dashboard;
          final active = d.campaigns.where((c) => c.status.isActive).toList();
          final needsReview = active.where((c) => c.status == CampaignStatus.submitted || c.status == CampaignStatus.disputed).length;
          final limit = data.subscription.plan.campaignPostLimit;

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
                Container(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.navy, AppColors.navyRaised]),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Protected in escrow', style: context.text.bodyMedium?.copyWith(color: Colors.white70)),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(Fmt.money(d.inEscrow), style: context.text.headlineMedium?.copyWith(color: Colors.white)),
                      const SizedBox(height: AppSpacing.xs),
                      Text('Total spent ${Fmt.money(d.totalSpent)}', style: context.text.bodySmall?.copyWith(color: AppColors.sunrise)),
                      const SizedBox(height: AppSpacing.lg),
                      AppButton(
                        label: 'Post a campaign',
                        icon: AppIcons.plus,
                        onPressed: () async {
                          final created = await context.push<bool>(AppRoutes.campaignEditor());
                          if ((created ?? false) && context.mounted) cubit.refresh();
                        },
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.05),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(child: StatCard(label: 'Active', value: '${active.length}', icon: AppIcons.campaigns)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: StatCard(label: 'To review', value: '$needsReview', icon: AppIcons.eye, accent: needsReview > 0 ? AppColors.primary : null)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: StatCard(label: 'Profile views', value: Fmt.compact(d.profileViews), icon: AppIcons.users)),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                AppCard(
                  onTap: () => context.push(AppRoutes.plans),
                  child: Row(
                    children: [
                      const Icon(AppIcons.crown, size: 20, color: AppColors.primary),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${data.subscription.plan.name} plan', style: context.text.titleSmall),
                            if (limit != null)
                              Text('${data.subscription.campaignsPosted} of $limit campaigns used', style: context.text.bodySmall),
                          ],
                        ),
                      ),
                      Text(data.subscription.plan.isFree ? 'Upgrade' : 'Manage', style: context.text.labelMedium?.copyWith(color: AppColors.primary)),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    QuickAction(icon: AppIcons.image, label: 'Creator feed', onTap: () => context.push(AppRoutes.feed)),
                    const SizedBox(width: AppSpacing.sm),
                    QuickAction(icon: AppIcons.users, label: 'Communities', onTap: () => context.push(AppRoutes.communities)),
                    const SizedBox(width: AppSpacing.sm),
                    QuickAction(icon: AppIcons.gift, label: 'Refer', onTap: () => context.push(AppRoutes.referrals)),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                SectionHeader(title: 'Active campaigns', actionLabel: 'See all', onAction: () => context.go(AppRoutes.brandCampaigns)),
                if (active.isEmpty)
                  Text('Your live campaigns appear here.', style: context.text.bodyMedium?.copyWith(color: context.palette.textSecondary))
                else
                  for (final c in active.take(5)) ...[
                    CampaignCard(
                      campaign: c,
                      showStatus: true,
                      onTap: () async {
                        if (await openBrandCampaign(context, c) && context.mounted) cubit.refresh();
                      },
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
