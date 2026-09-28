import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/bloc/action_cubit.dart';
import '../../../core/bloc/load_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/services/payment_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/action_scope.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/form_controls.dart';
import '../../../core/widgets/status_chip.dart';
import '../../auth/domain/entities/app_user.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../data/subscription_repository.dart';

class PlansData {
  const PlansData({required this.plans, required this.current});

  final List<SubscriptionPlan> plans;
  final UserSubscription current;
}

class PlansScreen extends StatelessWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    final role = auth is AuthAuthenticated ? auth.user.role : UserRole.creator;
    final repo = sl<SubscriptionRepository>();
    return ActionScope(
      child: BlocProvider(
        create: (_) => LoadCubit<PlansData>(() async {
          final results = await Future.wait<Object>([repo.plans(role == UserRole.brand ? 'brand' : 'creator'), repo.mine()]);
          return PlansData(plans: results[0] as List<SubscriptionPlan>, current: results[1] as UserSubscription);
        }),
        child: const _PlansView(),
      ),
    );
  }
}

class _PlansView extends StatefulWidget {
  const _PlansView();

  @override
  State<_PlansView> createState() => _PlansViewState();
}

class _PlansViewState extends State<_PlansView> {
  bool _yearly = true;

  Future<void> _subscribe(SubscriptionPlan plan, AppUser? user) async {
    final result = await context.read<ActionCubit>().run(
          'plan-${plan.id}',
          () => sl<SubscriptionRepository>().subscribe(
            plan,
            prefill: CheckoutPrefill(name: user?.name, email: user?.email, contact: user?.phone),
          ),
          success: 'You’re now on ${plan.name}',
        );
    if (result != null && mounted) {
      context.read<LoadCubit<PlansData>>().refresh();
      context.read<AuthBloc>().add(const AuthRefreshRequested());
    }
  }

  Future<void> _cancel() async {
    final ok = await confirmAction(
      context,
      title: 'Cancel your plan?',
      message: 'You keep your benefits until the end of this billing period. After that you move to the free plan.',
      confirmLabel: 'Cancel plan',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final result = await context.read<ActionCubit>().run('cancel', sl<SubscriptionRepository>().cancel, success: 'Your plan will end at the end of this period');
    if (result != null && mounted) context.read<LoadCubit<PlansData>>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<PlansData>>();
    final actions = context.watch<ActionCubit>().state;
    final auth = context.watch<AuthBloc>().state;
    final user = auth is AuthAuthenticated ? auth.user : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Plans')),
      body: AsyncView<PlansData>(
        state: cubit.state,
        onRetry: cubit.load,
        builder: (data) {
          final hasCycles = data.plans.any((p) => p.isYearly) && data.plans.any((p) => !p.isYearly && !p.isFree);
          final visible = data.plans.where((p) => p.isFree || !hasCycles || p.isYearly == _yearly).toList();
          final current = data.current;

          return AppRefresh(
            onRefresh: cubit.refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xxl),
              children: [
                AppCard(
                  color: context.palette.primarySoft,
                  borderColor: Colors.transparent,
                  child: Row(
                    children: [
                      const Icon(AppIcons.crown, color: AppColors.primary),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Current plan: ${current.plan.name}', style: context.text.titleSmall),
                            if (current.periodEnd != null && !current.plan.isFree)
                              Text(
                                current.cancelAtPeriodEnd ? 'Ends ${Fmt.date(current.periodEnd!)}' : 'Renews ${Fmt.date(current.periodEnd!)}',
                                style: context.text.bodySmall,
                              ),
                          ],
                        ),
                      ),
                      if (!current.plan.isFree && !current.cancelAtPeriodEnd)
                        TextButton(
                          style: TextButton.styleFrom(foregroundColor: AppColors.error),
                          onPressed: actions.isBusy ? null : _cancel,
                          child: const Text('Cancel'),
                        ),
                    ],
                  ),
                ),
                if (hasCycles) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Center(
                    child: ChoicePills<bool>(
                      options: const [false, true],
                      selected: {_yearly},
                      labelOf: (y) => y ? 'Yearly' : 'Monthly',
                      onChanged: (y) => setState(() => _yearly = y),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                for (final plan in visible) ...[
                  _PlanCard(
                    plan: plan,
                    isCurrent: plan.id == current.plan.id,
                    isBusy: actions.isBusyWith('plan-${plan.id}'),
                    onSubscribe: actions.isBusy || plan.isFree ? null : () => _subscribe(plan, user),
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

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.isCurrent, required this.isBusy, required this.onSubscribe});

  final SubscriptionPlan plan;
  final bool isCurrent;
  final bool isBusy;
  final VoidCallback? onSubscribe;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      borderColor: isCurrent ? AppColors.primary : null,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(plan.name, style: context.text.titleLarge)),
              if (isCurrent) const StatusChip(label: 'Current', color: AppColors.primary),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: plan.isFree ? 'Free' : Fmt.money(plan.price), style: context.text.headlineMedium),
                if (!plan.isFree) TextSpan(text: plan.isYearly ? ' / year' : ' / month', style: context.text.bodyMedium),
              ],
            ),
          ),
          if (plan.description.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(plan.description, style: context.text.bodyMedium),
          ],
          const SizedBox(height: AppSpacing.md),
          for (final perk in [
            if (plan.platformFeePercent >= 0) '${plan.platformFeePercent.toStringAsFixed(plan.platformFeePercent % 1 == 0 ? 0 : 1)}% platform fee',
            if (plan.proposalLimit != null) '${plan.proposalLimit} proposals per cycle',
            if (plan.campaignPostLimit != null) '${plan.campaignPostLimit} campaigns per cycle',
            ...plan.perks,
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(padding: EdgeInsets.only(top: 2), child: Icon(AppIcons.check, size: 16, color: AppColors.success)),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(child: Text(perk, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary))),
                ],
              ),
            ),
          if (!plan.isFree && !isCurrent) ...[
            const SizedBox(height: AppSpacing.md),
            AppButton(label: 'Upgrade to ${plan.name}', isLoading: isBusy, onPressed: onSubscribe),
          ],
        ],
      ),
    );
  }
}
