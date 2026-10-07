import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/async_view.dart';
import '../../auth/domain/entities/app_user.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../community/data/community_repository.dart';
import '../../store/data/store_repository.dart';
import '../data/subscription_repository.dart';

const _gradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]);
const _cardRadius = 20.0;

class PlansData {
  const PlansData({required this.plans, required this.current, this.access = const PlanAccess()});

  final List<SubscriptionPlan> plans;
  final UserSubscription current;
  final PlanAccess access;
}

/// Features the admin has put behind a paid plan (Fanitt Store / community
/// switches in the admin panel). Only these are shown as "Premium unlocks".
class PlanAccess {
  const PlanAccess({this.storeNeedsPlan = false, this.communityNeedsPlan = false});

  final bool storeNeedsPlan;
  final bool communityNeedsPlan;

  bool get any => storeNeedsPlan || communityNeedsPlan;

  /// Best effort — if a check fails the row is simply not shown.
  static Future<PlanAccess> load({required bool isCreator}) async {
    final results = await Future.wait<bool>([
      if (isCreator) sl<StoreRepository>().myStore().then((m) => m.subscriptionRequired).catchError((_) => false) else Future.value(false),
      sl<CommunityRepository>().config().then((c) => c.requireSubscription).catchError((_) => false),
    ]);
    return PlanAccess(storeNeedsPlan: results[0], communityNeedsPlan: results[1]);
  }
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
          final results = await Future.wait<Object>([
            repo.plans(role == UserRole.brand ? 'brand' : 'creator'),
            repo.mine(),
            PlanAccess.load(isCreator: role == UserRole.creator),
          ]);
          return PlansData(
            plans: results[0] as List<SubscriptionPlan>,
            current: results[1] as UserSubscription,
            access: results[2] as PlanAccess,
          );
        }),
        child: _PlansView(isBrand: role == UserRole.brand),
      ),
    );
  }
}

class _PlansView extends StatefulWidget {
  const _PlansView({required this.isBrand});

  final bool isBrand;

  @override
  State<_PlansView> createState() => _PlansViewState();
}

class _PlansViewState extends State<_PlansView> {
  bool _yearly = true;

  Future<void> _subscribe(SubscriptionPlan plan, AppUser? user) async {
    HapticFeedback.mediumImpact();
    final result = await context.read<ActionCubit>().run(
      'plan-${plan.id}',
          () => sl<SubscriptionRepository>().subscribe(
        plan,
        prefill: CheckoutPrefill(name: user?.name, email: user?.email, contact: user?.phone),
      ),
    );
    if (result == null || !mounted) return;
    context.read<LoadCubit<PlansData>>().refresh();
    context.read<AuthBloc>().add(const AuthRefreshRequested());
    HapticFeedback.heavyImpact();
    await showAppSheet<void>(context, builder: (_) => _WelcomeSheet(plan: plan));
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

  /// Best saving of yearly over 12 × monthly, across plan groups (0–100).
  int _yearlySaving(List<SubscriptionPlan> plans) {
    var best = 0.0;
    for (final y in plans.where((p) => p.isYearly && !p.isFree)) {
      final monthly = plans.where((p) => !p.isYearly && !p.isFree && p.groupSlug == y.groupSlug && p.groupSlug.isNotEmpty);
      for (final m in monthly) {
        if (m.price > 0) best = math.max(best, 1 - y.price / (m.price * 12));
      }
    }
    return (best * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<PlansData>>();
    final actions = context.watch<ActionCubit>().state;
    final auth = context.watch<AuthBloc>().state;
    final user = auth is AuthAuthenticated ? auth.user : null;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Light status bar icons over the dark header.
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: AsyncView<PlansData>(
          state: cubit.state,
          onRetry: cubit.load,
          builder: (data) {
            final hasCycles = data.plans.any((p) => p.isYearly) && data.plans.any((p) => !p.isYearly && !p.isFree);
            final visible = data.plans.where((p) => p.isFree || !hasCycles || p.isYearly == _yearly).toList()
              ..sort((a, b) => a.price.compareTo(b.price));
            final current = data.current;
            final paid = visible.where((p) => !p.isFree).toList();
            // "Most popular" = the first paid tier (the usual upgrade); the top tier if there's only one.
            final popularId = paid.isEmpty ? null : paid.first.id;
            final saving = _yearlySaving(data.plans);

            return RefreshIndicator.adaptive(
              color: AppColors.primary,
              onRefresh: cubit.refresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: _Hero(current: current, isBrand: widget.isBrand, access: data.access, onCancel: actions.isBusy ? null : _cancel),
                  ),
                  if (hasCycles)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.lg, AppSpacing.gutter, 0),
                        child: _CycleToggle(yearly: _yearly, saving: saving, onChanged: (y) {
                          HapticFeedback.selectionClick();
                          setState(() => _yearly = y);
                        }),
                      ),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.lg, AppSpacing.gutter, 0),
                    sliver: SliverList.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                      itemBuilder: (context, i) {
                        final plan = visible[i];
                        return _PlanCard(
                          plan: plan,
                          isCurrent: plan.id == current.plan.id,
                          isPopular: plan.id == popularId && plan.id != current.plan.id,
                          isBusy: actions.isBusyWith('plan-${plan.id}'),
                          isBrand: widget.isBrand,
                          access: data.access,
                          onSubscribe: actions.isBusy || plan.isFree ? null : () => _subscribe(plan, user),
                        ).animate(delay: (90 * i).ms).fadeIn(duration: 380.ms).slideY(begin: 0.08, curve: Curves.easeOutCubic);
                      },
                    ),
                  ),
                  if (visible.length > 1)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xl, AppSpacing.gutter, 0),
                        child: _CompareTable(plans: visible, currentId: current.plan.id, isBrand: widget.isBrand, access: data.access),
                      ),
                    ),
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xl, AppSpacing.gutter, AppSpacing.huge),
                      child: _TrustRow(),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero with the current plan
// ---------------------------------------------------------------------------

class _Hero extends StatelessWidget {
  const _Hero({required this.current, required this.isBrand, required this.access, required this.onCancel});

  final UserSubscription current;
  final bool isBrand;
  final PlanAccess access;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final plan = current.plan;
    final premium = !plan.isFree;

    // What a paid plan gives — admin-locked features first.
    final unlocks = <({IconData icon, String label})>[
      if (access.storeNeedsPlan) (icon: AppIcons.storeFilled, label: 'Open your store'),
      if (access.communityNeedsPlan) (icon: AppIcons.users, label: 'Create communities'),
      (icon: AppIcons.rupee, label: 'Lower fees'),
      (icon: isBrand ? AppIcons.campaigns : AppIcons.send, label: isBrand ? 'More campaigns' : 'More proposals'),
    ].take(3).toList();

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF17121F), Color(0xFF251225)]),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(right: -70, top: -60, child: _Glow(color: const Color(0xFFF4511E), size: 230)),
          Positioned(left: -80, bottom: -90, child: _Glow(color: const Color(0xFFEC2A78), size: 210, delayMs: 800)),
          Padding(
            padding: EdgeInsets.fromLTRB(AppSpacing.gutter, top + 8, AppSpacing.gutter, AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top bar: back · title
                SizedBox(
                  height: 44,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Material(
                          color: Colors.white.withValues(alpha: 0.10),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => Navigator.of(context).maybePop(),
                            child: const SizedBox(width: 40, height: 40, child: Icon(AppIcons.back, color: Colors.white, size: 20)),
                          ),
                        ),
                      ),
                      Text('Plans & billing', style: context.text.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Headline
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            premium ? 'You’re on Premium' : (isBrand ? 'Hire better creators, faster' : 'Go Premium, grow faster'),
                            style: context.text.headlineSmall?.copyWith(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.4, height: 1.2),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            premium
                                ? 'All your plan benefits are active.'
                                : access.any
                                ? 'A paid plan unlocks the tools below.'
                                : (isBrand ? 'Post more campaigns and pay lower fees.' : 'Send more proposals, keep more of what you earn.'),
                            style: context.text.bodyMedium?.copyWith(color: Colors.white70, height: 1.35),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(gradient: _gradient, borderRadius: BorderRadius.circular(16), boxShadow: [
                        BoxShadow(color: const Color(0xFFF4511E).withValues(alpha: 0.45), blurRadius: 22, offset: const Offset(0, 8)),
                      ]),
                      child: const Icon(AppIcons.crown, color: Colors.white, size: 24),
                    ).animate(onPlay: (c) => c.repeat(reverse: true)).moveY(begin: 0, end: -4, duration: 1600.ms, curve: Curves.easeInOut),
                  ],
                ).animate().fadeIn(duration: 380.ms),
                const SizedBox(height: AppSpacing.lg),

                // What Premium unlocks
                Row(
                  children: [
                    for (final (i, u) in unlocks.indexed) ...[
                      if (i > 0) const SizedBox(width: AppSpacing.xs),
                      Expanded(child: _UnlockTile(icon: u.icon, label: u.label, unlocked: premium)),
                    ],
                  ],
                ).animate().fadeIn(delay: 120.ms, duration: 380.ms).slideY(begin: 0.08),
                const SizedBox(height: AppSpacing.md),

                _CurrentPlanCard(current: current, isBrand: isBrand, onCancel: onCancel)
                    .animate()
                    .fadeIn(delay: 220.ms, duration: 420.ms)
                    .slideY(begin: 0.08, curve: Curves.easeOutCubic),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small glass tile: what a paid plan unlocks (ticked when you have it).
class _UnlockTile extends StatelessWidget {
  const _UnlockTile({required this.icon, required this.label, required this.unlocked});

  final IconData icon;
  final String label;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: const BoxDecoration(gradient: _gradient, shape: BoxShape.circle),
                child: Icon(icon, size: 15, color: Colors.white),
              ),
              const Spacer(),
              Icon(unlocked ? AppIcons.checkCircle : AppIcons.lock, size: 15, color: unlocked ? const Color(0xFF6EE7A0) : Colors.white38),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 2,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, height: 1.2),
          ),
        ],
      ),
    );
  }
}

/// "Your plan" glass card: name, renew / end date, usage and cancel.
class _CurrentPlanCard extends StatelessWidget {
  const _CurrentPlanCard({required this.current, required this.isBrand, required this.onCancel});

  final UserSubscription current;
  final bool isBrand;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final plan = current.plan;
    final limit = isBrand ? plan.campaignPostLimit : plan.proposalLimit;
    final used = isBrand ? current.campaignsPosted : current.proposalsUsed;
    final usageLabel = isBrand ? 'campaigns posted' : 'proposals sent';
    final ratio = limit == null || limit == 0 ? 0.0 : (used / limit).clamp(0.0, 1.0).toDouble();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('YOUR PLAN', style: context.text.labelSmall?.copyWith(color: Colors.white54, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(plan.name, style: context.text.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              if (!plan.isFree && current.periodEnd != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: (current.cancelAtPeriodEnd ? AppColors.warning : AppColors.success).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    current.cancelAtPeriodEnd ? 'Ends ${Fmt.shortDate(current.periodEnd!)}' : 'Renews ${Fmt.shortDate(current.periodEnd!)}',
                    style: TextStyle(color: current.cancelAtPeriodEnd ? AppColors.sunrise : const Color(0xFF6EE7A0), fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                )
              else if (plan.isFree)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: const Text('Free', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (limit != null) ...[
            Row(
              children: [
                Expanded(child: Text('$used of $limit $usageLabel this cycle', style: context.text.bodySmall?.copyWith(color: Colors.white70))),
                Text('${(ratio * 100).round()}%', style: context.text.labelMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: ratio),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => Stack(
                  children: [
                    Container(height: 8, color: Colors.white.withValues(alpha: 0.12)),
                    FractionallySizedBox(widthFactor: v, child: Container(height: 8, decoration: const BoxDecoration(gradient: _gradient))),
                  ],
                ),
              ),
            ),
          ] else
            Text(isBrand ? 'Unlimited campaigns' : 'Unlimited proposals', style: context.text.bodySmall?.copyWith(color: Colors.white70)),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                Text('Platform fee ${_feeLabel(plan.platformFeePercent)}', style: context.text.bodySmall?.copyWith(color: Colors.white60)),
                const Spacer(),
                if (!plan.isFree && !current.cancelAtPeriodEnd && onCancel != null)
                  GestureDetector(
                    onTap: onCancel,
                    child: Text('Cancel plan', style: context.text.bodySmall?.copyWith(color: Colors.white60, decoration: TextDecoration.underline, decorationColor: Colors.white38)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size, this.delayMs = 0});

  final Color color;
  final double size;
  final int delayMs;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [color.withValues(alpha: 0.45), Colors.transparent])),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true), delay: delayMs.ms)
        .scaleXY(begin: 0.85, end: 1.15, duration: 3200.ms, curve: Curves.easeInOut)
        .move(begin: Offset.zero, end: const Offset(-12, 10), duration: 3200.ms, curve: Curves.easeInOut);
  }
}

// ---------------------------------------------------------------------------
// Monthly / Yearly toggle with a sliding pill
// ---------------------------------------------------------------------------

class _CycleToggle extends StatelessWidget {
  const _CycleToggle({required this.yearly, required this.saving, required this.onChanged});

  final bool yearly;
  final int saving;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Container(
        width: 300,
        height: 52,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(16)),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              alignment: yearly ? Alignment.centerRight : Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                child: Container(
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 3))],
                  ),
                ),
              ),
            ),
            Row(
              children: [
                for (final y in const [false, true])
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(y),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              y ? 'Yearly' : 'Monthly',
                              style: context.text.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: yearly == y ? palette.textPrimary : palette.textSecondary,
                              ),
                            ),
                            if (y && saving > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(gradient: _gradient, borderRadius: BorderRadius.circular(6)),
                                child: Text('-$saving%', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                              ).animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(begin: 1, end: 1.08, duration: 900.ms),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Plan card
// ---------------------------------------------------------------------------

String _feeLabel(double fee) => '${fee.toStringAsFixed(fee % 1 == 0 ? 0 : 1)}%';

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.isCurrent,
    required this.isPopular,
    required this.isBusy,
    required this.isBrand,
    required this.access,
    required this.onSubscribe,
  });

  final SubscriptionPlan plan;
  final bool isCurrent;
  final bool isPopular;
  final bool isBusy;
  final bool isBrand;
  final PlanAccess access;
  final VoidCallback? onSubscribe;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final limit = isBrand ? plan.campaignPostLimit : plan.proposalLimit;
    final perMonth = plan.isYearly && !plan.isFree ? (plan.price / 12).round() : null;

    final card = Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(_cardRadius - (isPopular ? 2 : 0)),
        border: isPopular ? null : Border.all(color: isCurrent ? AppColors.primary : palette.border, width: isCurrent ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(plan.name, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
              if (isCurrent)
                _Badge(label: 'Current plan', color: AppColors.primary, filled: false)
              else if (isPopular)
                const _Badge(label: '★ Most popular', color: AppColors.primary, filled: true),
            ],
          ),
          if (plan.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(plan.description, style: context.text.bodyMedium),
          ],
          const SizedBox(height: AppSpacing.md),
          // Price (animates when switching monthly / yearly)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(anim), child: child),
            ),
            child: Column(
              key: ValueKey(plan.id),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    ShaderMask(
                      shaderCallback: (r) => (isPopular ? _gradient : LinearGradient(colors: [palette.textPrimary, palette.textPrimary])).createShader(r),
                      child: Text(
                        plan.isFree ? 'Free' : Fmt.money(plan.price),
                        style: context.text.displaySmall?.copyWith(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -1),
                      ),
                    ),
                    if (!plan.isFree)
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 6),
                        child: Text(plan.isYearly ? '/year' : '/month', style: context.text.bodyMedium),
                      ),
                  ],
                ),
                if (perMonth != null)
                  Text('Just ${Fmt.money(perMonth)}/month, billed yearly', style: context.text.bodySmall?.copyWith(color: AppColors.success, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Key numbers
          Row(
            children: [
              Expanded(child: _Metric(icon: AppIcons.rupee, value: _feeLabel(plan.platformFeePercent), label: 'platform fee')),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _Metric(
                  icon: isBrand ? AppIcons.campaigns : AppIcons.send,
                  value: limit == null ? 'Unlimited' : '$limit',
                  label: isBrand ? 'campaigns / cycle' : 'proposals / cycle',
                ),
              ),
            ],
          ),
          if (access.any) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                if (access.storeNeedsPlan) Expanded(child: _AccessChip(icon: AppIcons.storeFilled, label: 'Your store', open: !plan.isFree)),
                if (access.storeNeedsPlan && access.communityNeedsPlan) const SizedBox(width: AppSpacing.sm),
                if (access.communityNeedsPlan) Expanded(child: _AccessChip(icon: AppIcons.users, label: 'Communities', open: !plan.isFree)),
              ],
            ),
          ],
          if (plan.perks.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            for (final (i, perk) in plan.perks.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 1),
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(shape: BoxShape.circle, gradient: isPopular ? _gradient : null, color: isPopular ? null : AppColors.success.withValues(alpha: 0.15)),
                      child: Icon(AppIcons.check, size: 12, color: isPopular ? Colors.white : AppColors.success),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(perk, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary, height: 1.35))),
                  ],
                ),
              ).animate(delay: (200 + 60 * i).ms).fadeIn(duration: 260.ms).slideX(begin: 0.04),
          ],
          const SizedBox(height: AppSpacing.sm),
          if (isCurrent)
            Container(
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
              child: Text('You’re on this plan', style: context.text.titleSmall?.copyWith(color: AppColors.primary)),
            )
          else if (!plan.isFree)
            _UpgradeButton(label: 'Get ${plan.name}', busy: isBusy, highlighted: isPopular, onTap: onSubscribe),
        ],
      ),
    );

    if (!isPopular) return card;
    // Gradient border + soft glow for the recommended plan.
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        gradient: _gradient,
        borderRadius: BorderRadius.circular(_cardRadius),
        boxShadow: [BoxShadow(color: const Color(0xFFF4511E).withValues(alpha: 0.25), blurRadius: 28, offset: const Offset(0, 12))],
      ),
      child: card,
    );
  }
}

/// "Your store ✓" on paid plans, "Your store 🔒" on the free one.
class _AccessChip extends StatelessWidget {
  const _AccessChip({required this.icon, required this.label, required this.open});

  final IconData icon;
  final String label;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = open ? AppColors.success : palette.textTertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: open ? AppColors.success.withValues(alpha: 0.10) : palette.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: open ? AppColors.success.withValues(alpha: 0.25) : palette.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: open ? AppColors.success : palette.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              open ? label : '$label locked',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: open ? palette.textPrimary : palette.textSecondary),
            ),
          ),
          Icon(open ? AppIcons.checkCircle : AppIcons.lock, size: 15, color: color),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color, required this.filled});

  final String label;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: filled ? _gradient : null,
        color: filled ? null : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(label, style: TextStyle(color: filled ? Colors.white : color, fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UpgradeButton extends StatefulWidget {
  const _UpgradeButton({required this.label, required this.busy, required this.highlighted, required this.onTap});

  final String label;
  final bool busy;
  final bool highlighted;
  final VoidCallback? onTap;

  @override
  State<_UpgradeButton> createState() => _UpgradeButtonState();
}

class _UpgradeButtonState extends State<_UpgradeButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null && !widget.busy;
    final button = AnimatedScale(
      scale: _down ? 0.97 : 1,
      duration: const Duration(milliseconds: 110),
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: widget.highlighted ? _gradient : null,
          color: widget.highlighted ? null : context.palette.textPrimary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: widget.busy
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
            : Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.label, style: TextStyle(color: widget.highlighted ? Colors.white : context.palette.background, fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(width: 6),
            Icon(AppIcons.arrowRightSimple, size: 18, color: widget.highlighted ? Colors.white : context.palette.background),
          ],
        ),
      ),
    );
    final shimmering = widget.highlighted && enabled
        ? button.animate(onPlay: (c) => c.repeat()).shimmer(delay: 1800.ms, duration: 1200.ms, color: Colors.white.withValues(alpha: 0.35))
        : button;
    return Opacity(
      opacity: enabled || widget.busy ? 1 : 0.5,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: enabled ? widget.onTap : null,
        child: shimmering,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compare plans
// ---------------------------------------------------------------------------

class _CompareTable extends StatelessWidget {
  const _CompareTable({required this.plans, required this.currentId, required this.isBrand, required this.access});

  final List<SubscriptionPlan> plans;
  final String currentId;
  final bool isBrand;
  final PlanAccess access;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final allPerks = <String>[for (final p in plans) ...p.perks].toSet().toList();
    Widget lockOrTick(SubscriptionPlan p) =>
        p.isFree ? Icon(AppIcons.lock, size: 16, color: palette.textTertiary) : const Icon(AppIcons.checkCircle, size: 18, color: AppColors.success);
    final rows = <({String label, List<Widget> cells})>[
      if (access.storeNeedsPlan) (label: 'Open your Fanitt Store', cells: [for (final p in plans) lockOrTick(p)]),
      if (access.communityNeedsPlan) (label: 'Create a community', cells: [for (final p in plans) lockOrTick(p)]),
      (label: 'Platform fee', cells: [for (final p in plans) _cellText(context, _feeLabel(p.platformFeePercent))]),
      (
      label: isBrand ? 'Campaigns / cycle' : 'Proposals / cycle',
      cells: [
        for (final p in plans)
          _cellText(context, () {
            final l = isBrand ? p.campaignPostLimit : p.proposalLimit;
            return l == null ? '∞' : '$l';
          }()),
      ],
      ),
      for (final perk in allPerks)
        (
        label: perk,
        cells: [
          for (final p in plans)
            p.perks.contains(perk)
                ? const Icon(AppIcons.checkCircle, size: 18, color: AppColors.success)
                : Icon(AppIcons.minus, size: 16, color: palette.textTertiary),
        ],
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Compare plans', style: context.text.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: AppSpacing.sm),
        Container(
          decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: palette.border)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // Header
              Container(
                color: palette.surfaceMuted,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    const Expanded(flex: 3, child: SizedBox()),
                    for (final p in plans)
                      Expanded(
                        flex: 2,
                        child: Text(
                          p.name,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w800, color: p.id == currentId ? AppColors.primary : palette.textPrimary),
                        ),
                      ),
                  ],
                ),
              ),
              for (final (i, r) in rows.indexed) ...[
                if (i > 0) Divider(height: 1, color: palette.border),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  child: Row(
                    children: [
                      Expanded(flex: 3, child: Text(r.label, style: context.text.bodySmall?.copyWith(color: palette.textPrimary, fontSize: 12))),
                      for (final c in r.cells) Expanded(flex: 2, child: Center(child: c)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05),
      ],
    );
  }

  Widget _cellText(BuildContext context, String text) => Text(text, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700));
}

// ---------------------------------------------------------------------------
// Trust row
// ---------------------------------------------------------------------------

class _TrustRow extends StatelessWidget {
  const _TrustRow();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget item(IconData icon, String title, String text) => Expanded(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 20, color: AppColors.primary),
          ),
          const SizedBox(height: 6),
          Text(title, textAlign: TextAlign.center, style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: palette.textPrimary)),
          const SizedBox(height: 2),
          Text(text, textAlign: TextAlign.center, style: context.text.bodySmall?.copyWith(fontSize: 11)),
        ],
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        item(AppIcons.shieldCheck, 'Secure payment', 'Paid safely through Razorpay'),
        item(AppIcons.close, 'Cancel anytime', 'No questions asked'),
        item(AppIcons.calendar, 'Keep benefits', 'Until your period ends'),
      ],
    ).animate().fadeIn(duration: 400.ms);
  }
}

// ---------------------------------------------------------------------------
// After upgrading
// ---------------------------------------------------------------------------

class _WelcomeSheet extends StatelessWidget {
  const _WelcomeSheet({required this.plan});

  final SubscriptionPlan plan;

  @override
  Widget build(BuildContext context) {
    final random = math.Random(7);
    return SheetBody(
      title: 'Welcome to ${plan.name}!',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 140,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Little burst of sparkles
                for (var i = 0; i < 12; i++)
                  Builder(builder: (context) {
                    final angle = (i / 12) * 2 * math.pi;
                    final distance = 50 + random.nextInt(20).toDouble();
                    return Icon(AppIcons.sparkle, size: 14 + random.nextInt(8).toDouble(), color: i.isEven ? const Color(0xFFF4511E) : const Color(0xFFEC2A78))
                        .animate()
                        .move(begin: Offset.zero, end: Offset(math.cos(angle) * distance, math.sin(angle) * distance), duration: 700.ms, curve: Curves.easeOutCubic)
                        .fadeOut(delay: 500.ms, duration: 500.ms);
                  }),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(gradient: _gradient, shape: BoxShape.circle, boxShadow: [
                    BoxShadow(color: const Color(0xFFF4511E).withValues(alpha: 0.4), blurRadius: 30),
                  ]),
                  child: const Icon(AppIcons.crown, color: Colors.white, size: 40),
                ).animate().scale(begin: const Offset(0.2, 0.2), duration: 600.ms, curve: Curves.elasticOut),
              ],
            ),
          ),
          Text('Your new benefits are active right now.', textAlign: TextAlign.center, style: context.text.bodyMedium),
          const SizedBox(height: AppSpacing.lg),
          AppButton(label: 'Let’s go', onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }
}