import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/bloc/load_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../dashboard/presentation/home_discover.dart';
import '../../store/presentation/widgets/store_promo_banner.dart';
import '../../../core/widgets/app_update_banner.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/form_controls.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../dashboard/presentation/home_widgets.dart';
import '../data/agency_repository.dart';

Future<void> shareReferralCode(String code) {
  return Share.share(
    'Join me on Fanitt — creators and brands collaborate with escrow-protected payments. '
        'Use my agency code $code when you sign up: https://fanitt.com',
  );
}

class AgencyHomeScreen extends StatelessWidget {
  const AgencyHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LoadCubit<AgencyDashboard>(sl<AgencyRepository>().dashboard),
      child: const _AgencyHomeView(),
    );
  }
}

class _AgencyHomeView extends StatelessWidget {
  const _AgencyHomeView();

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<AgencyDashboard>>();
    final auth = context.watch<AuthBloc>().state;

    return Scaffold(
      appBar: const HomeAppBar(),
      body: AsyncView<AgencyDashboard>(
        state: cubit.state,
        onRetry: cubit.load,
        builder: (d) => AppRefresh(
          onRefresh: () async {
            homeRefreshTick.value++;
            await cubit.refresh();
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            // Build the whole home once so sections don't reload or re-animate while scrolling.
            cacheExtent: 4000,
            padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.huge),
            children: [
              const HomeSearchBar(hint: 'Search creators, brands, communities…'),
              const SizedBox(height: AppSpacing.lg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AppUpdateBanner(),
                    const StorePromoBanner(),
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
                          Text('Your agency code', style: context.text.bodyMedium?.copyWith(color: Colors.white70)),
                          const SizedBox(height: AppSpacing.xs),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  d.referralCode.isEmpty ? '—' : d.referralCode,
                                  style: context.text.headlineMedium?.copyWith(color: Colors.white, letterSpacing: 2),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Copy',
                                icon: const Icon(AppIcons.copy, color: Colors.white),
                                onPressed: d.referralCode.isEmpty
                                    ? null
                                    : () {
                                  Clipboard.setData(ClipboardData(text: d.referralCode));
                                  AppSnackbar.success(context, 'Code copied');
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          AppButton(
                            label: 'Invite creators & brands',
                            icon: AppIcons.shareNetwork,
                            onPressed: d.referralCode.isEmpty || d.verificationStatus.name != 'verified' ? null : () => shareReferralCode(d.referralCode),
                          ),
                          if (d.verificationStatus.name != 'verified') ...[
                            const SizedBox(height: AppSpacing.xs),
                            Text('Your code works once your agency is verified.', style: context.text.bodySmall?.copyWith(color: AppColors.sunrise)),
                          ],
                        ],
                      ),
                    ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.05),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(child: StatCard(label: 'Creators', value: '${d.creatorCount}', icon: AppIcons.creator)),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: StatCard(label: 'Brands', value: '${d.brandCount}', icon: AppIcons.brand)),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(child: StatCard(label: 'Total commission', value: Fmt.money(d.totalCommission), icon: AppIcons.wallet, accent: AppColors.success)),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: StatCard(label: 'This month', value: Fmt.money(d.thisMonthCommission), icon: AppIcons.calendar, accent: AppColors.primary)),
                      ],
                    ),
                  ],
                ),
              ),
              // Discover sections — order, titles and pinned items come from the admin panel.
              const HomeSections(),
            ],
          ),
        ),
      ),
    );
  }
}

class AgencyNetworkScreen extends StatelessWidget {
  const AgencyNetworkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LoadCubit<List<Referral>>(sl<AgencyRepository>().referrals),
      child: const _NetworkView(),
    );
  }
}

class _NetworkView extends StatefulWidget {
  const _NetworkView();

  @override
  State<_NetworkView> createState() => _NetworkViewState();
}

class _NetworkViewState extends State<_NetworkView> {
  bool? _creators;

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<List<Referral>>>();
    return Scaffold(
      appBar: AppBar(title: const Text('Network')),
      body: AsyncView<List<Referral>>(
        state: cubit.state,
        onRetry: cubit.load,
        builder: (all) {
          final items = _creators == null ? all : all.where((r) => r.isCreator == _creators).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.xs),
                child: ChoicePills<bool?>(
                  scrollable: true,
                  options: const [null, true, false],
                  selected: {_creators},
                  labelOf: (v) => switch (v) {
                    null => 'All ${all.length}',
                    true => 'Creators ${all.where((r) => r.isCreator).length}',
                    false => 'Brands ${all.where((r) => !r.isCreator).length}',
                  },
                  onChanged: (v) => setState(() => _creators = v),
                ),
              ),
              Expanded(
                child: AppRefresh(
                  onRefresh: cubit.refresh,
                  child: items.isEmpty
                      ? const ScrollableMessage(
                    child: MessageView(
                      icon: AppIcons.network,
                      title: 'No one in your network yet',
                      message: 'Share your agency code. Creators and brands who join with it show up here.',
                    ),
                  )
                      : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xxl),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) {
                      final r = items[i];
                      final initials = r.name.isEmpty ? '?' : r.name.substring(0, 1).toUpperCase();
                      return AppCard(
                        child: Row(
                          children: [
                            UserAvatar(initials: initials, imageUrl: r.avatarUrl, size: 44),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(r.name, style: context.text.titleSmall),
                                  Text('Joined ${Fmt.date(r.joinedAt)}', style: context.text.bodySmall),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                StatusChip(label: r.isCreator ? 'Creator' : 'Brand', color: r.isCreator ? AppColors.primary : AppColors.info),
                                if (r.totalEarnings != null) ...[
                                  const SizedBox(height: 4),
                                  Text('Earned ${Fmt.money(r.totalEarnings!)}', style: context.text.bodySmall?.copyWith(color: context.palette.textSecondary)),
                                ],
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}