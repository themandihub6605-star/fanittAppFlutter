import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/di/injection.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../store/presentation/widgets/store_checkout.dart';
import '../data/community_repository.dart';

// Paid communities: pick a plan (monthly / yearly / one-time), then pay
// with the same checkout as the Fanitt Store (UPI, card or wallet).

const _brand = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]);

/// "₹199/month" for the cheapest plan, or '' for free communities.
String communityPriceLabel(Community c) {
  final p = c.cheapestPlan;
  if (!c.isPaid || p == null) return '';
  return '${Fmt.money(p.price)}${p.key.suffix}';
}

/// Shows the plans and pays. Returns true when the member is in.
Future<bool> joinPaidCommunity(BuildContext context, Community c) async {
  if (c.plans.isEmpty) return false;
  final plan = await showAppSheet<CommunityPlan>(context, builder: (_) => _PlansSheet(community: c));
  if (plan == null || !context.mounted) return false;
  final order = await payForStoreItem(
    context,
    amount: plan.price,
    title: '${c.name} · ${plan.key.label}',
    start: (payWith) => sl<CommunityRepository>().checkout(c.id, plan.key, payWith: payWith),
  );
  return order != null;
}

class _PlansSheet extends StatefulWidget {
  const _PlansSheet({required this.community});

  final Community community;

  @override
  State<_PlansSheet> createState() => _PlansSheetState();
}

class _PlansSheetState extends State<_PlansSheet> {
  late CommunityPlan _selected = _defaultPlan();

  Community get c => widget.community;

  /// Yearly first (best value), else the first plan.
  CommunityPlan _defaultPlan() => c.plans.firstWhere((p) => p.key == CommunityPlanKey.yearly, orElse: () => c.plans.first);

  /// "Save 17%" on yearly vs paying monthly for 12 months.
  int? _yearlySaving() {
    final monthly = c.plans.where((p) => p.key == CommunityPlanKey.monthly).firstOrNull;
    final yearly = c.plans.where((p) => p.key == CommunityPlanKey.yearly).firstOrNull;
    if (monthly == null || yearly == null || monthly.price <= 0) return null;
    final full = monthly.price * 12;
    final saving = ((full - yearly.price) / full * 100).round();
    return saving > 0 ? saving : null;
  }

  @override
  Widget build(BuildContext context) {
    final renewing = c.isExpired || (c.membership?.isPaid ?? false);
    final saving = _yearlySaving();
    return SheetBody(
      title: renewing ? 'Renew your membership' : 'Join ${c.name}',
      subtitle: 'Pick a plan — posts, chat and lives unlock right after payment.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, plan) in c.plans.indexed) ...[
            _PlanTile(
              plan: plan,
              selected: plan == _selected,
              badge: plan.key == CommunityPlanKey.yearly && saving != null
                  ? 'Save $saving%'
                  : plan.key == CommunityPlanKey.lifetime
                  ? 'Pay once'
                  : null,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _selected = plan);
              },
            ).animate(delay: (60 * i).ms).fadeIn(duration: 250.ms).slideY(begin: 0.15, curve: Curves.easeOutCubic),
            const SizedBox(height: AppSpacing.sm),
          ],
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Icon(AppIcons.shieldCheck, size: 14, color: context.palette.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _selected.key == CommunityPlanKey.lifetime
                      ? 'One payment, access for as long as the community runs.'
                      : 'No auto-debit. We’ll remind you before it ends — renew in one tap.',
                  style: context.text.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Continue · ${Fmt.money(_selected.price)}',
            icon: AppIcons.lock,
            onPressed: () => Navigator.of(context).pop(_selected),
          ),
        ],
      ),
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({required this.plan, required this.selected, required this.onTap, this.badge});

  final CommunityPlan plan;
  final bool selected;
  final String? badge;
  final VoidCallback onTap;

  String get _hint => switch (plan.key) {
    CommunityPlanKey.monthly => 'Billed every month — renew when it ends',
    CommunityPlanKey.yearly => '12 months of access',
    CommunityPlanKey.lifetime => 'Lifetime access, one payment',
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        gradient: selected ? _brand : null,
        color: selected ? null : palette.border,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Material(
        color: selected ? palette.primarySoft : palette.surface,
        borderRadius: BorderRadius.circular(16.5),
        child: InkWell(
          borderRadius: BorderRadius.circular(16.5),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: selected ? _brand : null,
                    border: selected ? null : Border.all(color: palette.border, width: 2),
                  ),
                  child: selected ? const Icon(AppIcons.check, size: 13, color: Colors.white) : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(plan.key.label, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                          if (badge != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(gradient: _brand, borderRadius: BorderRadius.circular(999)),
                              child: Text(badge!, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(_hint, style: context.text.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: Fmt.money(plan.price), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w900, color: selected ? AppColors.primary : null)),
                      if (plan.key != CommunityPlanKey.lifetime) TextSpan(text: plan.key.suffix, style: context.text.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Owner / member status strip for a paid community (detail screen).
class PaidCommunityStrip extends StatelessWidget {
  const PaidCommunityStrip({super.key, required this.community, required this.onRenew});

  final Community community;
  final VoidCallback onRenew;

  @override
  Widget build(BuildContext context) {
    final c = community;
    final palette = context.palette;
    final m = c.membership;

    late final IconData icon;
    late final String title;
    late final String sub;
    var showRenew = false;

    if (c.isOwner) {
      icon = AppIcons.crown;
      title = 'Paid community · ${c.plans.map((p) => '${Fmt.money(p.price)}${p.key.suffix}').join(' · ')}';
      sub = '${Fmt.money(c.paidRevenue)} earned from ${c.paidPayments} payment${c.paidPayments == 1 ? '' : 's'} — goes to your wallet';
    } else if (c.isExpired) {
      icon = AppIcons.hourglass;
      title = 'Your membership ended';
      sub = 'Renew to get back into posts, chat and lives.';
      showRenew = true;
    } else if (m != null && m.isActive && m.isPaid) {
      icon = AppIcons.crown;
      if (m.plan == CommunityPlanKey.lifetime || m.paidUntil == null) {
        title = 'Lifetime member';
        sub = 'You paid once — enjoy!';
      } else {
        final daysLeft = m.paidUntil!.difference(DateTime.now()).inDays;
        title = '${m.plan?.label ?? 'Paid'} member';
        sub = 'Active till ${Fmt.date(m.paidUntil!)}${daysLeft <= 3 ? ' · ends soon' : ''}';
        showRenew = daysLeft <= 7;
      }
    } else if (m != null && m.isActive) {
      icon = AppIcons.gift;
      title = 'You have free access';
      sub = 'You joined before this community went paid.';
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: palette.primarySoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: _brand),
            child: Icon(icon, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
              ],
            ),
          ),
          if (showRenew) ...[
            const SizedBox(width: 8),
            SizedBox(
              height: 34,
              child: FilledButton(
                onPressed: onRenew,
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(horizontal: 14)),
                child: const Text('Renew'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}