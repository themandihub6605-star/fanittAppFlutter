import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/bloc/load_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../dashboard/presentation/home_discover.dart';
import '../../../core/widgets/app_update_banner.dart';
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
    final repo = sl<AgencyRepository>();
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => LoadCubit<AgencyDashboard>(repo.dashboard)),
        BlocProvider(create: (_) => LoadCubit<List<Referral>>(repo.referrals)),
      ],
      child: const _AgencyHomeView(),
    );
  }
}

/// Agency dashboard: your code + invite, earnings, your network and quick
/// links. (No shopping, campaigns or lives — that's for creators, brands
/// and fans.)
class _AgencyHomeView extends StatelessWidget {
  const _AgencyHomeView();

  static const _gutter = EdgeInsets.symmetric(horizontal: AppSpacing.gutter);

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<AgencyDashboard>>();
    final network = context.watch<LoadCubit<List<Referral>>>();
    final auth = context.watch<AuthBloc>().state;
    final palette = context.palette;

    return Scaffold(
      appBar: const HomeAppBar(),
      body: AsyncView<AgencyDashboard>(
        state: cubit.state,
        onRetry: cubit.load,
        builder: (d) {
          final verified = d.verificationStatus == VerificationStatus.verified;
          final recent = [...(network.state.data ?? const <Referral>[])]..sort((a, b) => b.joinedAt.compareTo(a.joinedAt));
          return AppRefresh(
            onRefresh: () async {
              context.read<AuthBloc>().add(const AuthRefreshRequested());
              homeRefreshTick.value++;
              await Future.wait([cubit.refresh(), network.refresh()]);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              cacheExtent: 4000,
              padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.huge),
              children: [
                const Padding(padding: _gutter, child: AppUpdateBanner()),
                if (auth is AuthAuthenticated) Padding(padding: _gutter, child: ProfileCompletionBanner(user: auth.user)),

                // Code + invite
                Padding(
                  padding: _gutter,
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]),
                      boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text('Your agency code', style: context.text.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85)))),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(AppRadius.pill)),
                              child: Text(verified ? 'Verified' : 'Not verified yet', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                d.referralCode.isEmpty ? '—' : d.referralCode,
                                style: context.text.headlineMedium?.copyWith(color: Colors.white, letterSpacing: 2, fontWeight: FontWeight.w900),
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
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                            onPressed: d.referralCode.isEmpty || !verified ? null : () => shareReferralCode(d.referralCode),
                            icon: const Icon(AppIcons.shareNetwork, size: 18),
                            label: const Text('Invite creators & brands', style: TextStyle(fontWeight: FontWeight.w800)),
                          ),
                        ),
                        if (!verified) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text('Your code works once your agency is verified.', style: context.text.bodySmall?.copyWith(color: Colors.white)),
                        ],
                      ],
                    ),
                  ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.05),
                ),
                const SizedBox(height: AppSpacing.md),

                // Numbers
                Padding(
                  padding: _gutter,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: StatCard(label: 'Total commission', value: Fmt.money(d.totalCommission), icon: AppIcons.wallet, accent: AppColors.success)),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(child: StatCard(label: 'This month', value: Fmt.money(d.thisMonthCommission), icon: AppIcons.calendar, accent: AppColors.primary)),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Expanded(child: StatCard(label: 'Creators', value: '${d.creatorCount}', icon: AppIcons.creator)),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(child: StatCard(label: 'Brands', value: '${d.brandCount}', icon: AppIcons.brand)),
                        ],
                      ),
                    ],
                  ),
                ),

                // Quick actions
                homeGap,
                const HomeSectionHeader(title: 'Quick actions'),
                const SizedBox(height: AppSpacing.sm),
                HomeQuickActions(
                  actions: [
                    HomeAction(
                      icon: AppIcons.shareNetwork,
                      label: 'Invite',
                      onTap: () {
                        if (d.referralCode.isEmpty || !verified) {
                          AppSnackbar.info(context, 'Your code works once your agency is verified.');
                        } else {
                          shareReferralCode(d.referralCode);
                        }
                      },
                    ),
                    HomeAction(icon: AppIcons.network, label: 'My network', color: AppColors.info, onTap: () => context.go(AppRoutes.agencyNetwork)),
                    HomeAction(icon: AppIcons.wallet, label: 'Earnings', color: AppColors.success, onTap: () => context.go(AppRoutes.agencyEarnings)),
                    HomeAction(icon: AppIcons.receipt, label: 'Activity', color: const Color(0xFF7C4DFF), onTap: () => context.push(AppRoutes.transactions)),
                    HomeAction(icon: AppIcons.creators, label: 'Creators', color: const Color(0xFFEC2A78), onTap: () => context.push(AppRoutes.creatorsDirectory)),
                    HomeAction(icon: AppIcons.brand, label: 'Brands', color: const Color(0xFF00A3A3), onTap: () => context.push(AppRoutes.brands)),
                    HomeAction(icon: AppIcons.bell, label: 'Alerts', color: AppColors.warning, onTap: () => context.push(AppRoutes.notifications)),
                    HomeAction(icon: AppIcons.user, label: 'Profile', color: const Color(0xFF6366F1), onTap: () => context.go(AppRoutes.agencyAccount)),
                  ],
                ),

                // Newest people in the network
                homeGap,
                HomeSectionHeader(
                  title: 'Recently joined',
                  subtitle: 'People who signed up with your code',
                  onSeeAll: recent.isEmpty ? null : () => context.go(AppRoutes.agencyNetwork),
                ),
                const SizedBox(height: AppSpacing.sm),
                Padding(
                  padding: _gutter,
                  child: network.state.data == null
                      ? const Padding(padding: EdgeInsets.all(AppSpacing.lg), child: Center(child: CircularProgressIndicator()))
                      : recent.isEmpty
                      ? AppCard(
                    child: Row(
                      children: [
                        Icon(AppIcons.network, color: palette.textSecondary),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: Text('No one yet — share your code and they show up here.', style: context.text.bodyMedium?.copyWith(color: palette.textPrimary))),
                      ],
                    ),
                  )
                      : Column(
                    children: [
                      for (final r in recent.take(5))
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: _ReferralTile(referral: r),
                        ),
                    ],
                  ),
                ),

                // Creators & brands to recruit — no campaigns, lives, products or shop here.
                const HomeSections(showCampaigns: false, hide: {'live', 'meets', 'products', 'communities', 'shop'}),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One person in the agency's network.
class _ReferralTile extends StatelessWidget {
  const _ReferralTile({required this.referral});

  final Referral referral;

  @override
  Widget build(BuildContext context) {
    final r = referral;
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
                    itemBuilder: (context, i) => _ReferralTile(referral: items[i]),
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