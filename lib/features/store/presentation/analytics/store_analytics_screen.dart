import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bloc/load_cubit.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/async_view.dart';
import '../../../../core/widgets/form_controls.dart';
import '../../data/store_repository.dart';
import '../widgets/store_widgets.dart';

const _sourceLabels = {'digital_product': 'Digital products', 'live_stream': 'Live tickets', 'call': 'Calls', 'fanbox': 'FanBox'};
const _sourceColors = {'digital_product': Color(0xFFF4511E), 'live_stream': Color(0xFFDC2F2F), 'call': Color(0xFF2F6FEB), 'fanbox': Color(0xFFEC2A78)};

/// Creator: how the store is doing over 7 / 30 / 90 days.
class StoreAnalyticsScreen extends StatefulWidget {
  const StoreAnalyticsScreen({super.key});

  @override
  State<StoreAnalyticsScreen> createState() => _StoreAnalyticsScreenState();
}

class _StoreAnalyticsScreenState extends State<StoreAnalyticsScreen> {
  int _days = 30;
  late final LoadCubit<StoreAnalytics> _cubit = LoadCubit<StoreAnalytics>(() => sl<StoreRepository>().analytics(_days));

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: Builder(
        builder: (context) {
          final cubit = context.watch<LoadCubit<StoreAnalytics>>();
          return Scaffold(
            appBar: AppBar(title: const Text('Store analytics')),
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.sm),
                  child: ChoicePills<int>(
                    options: const [7, 30, 90],
                    selected: {_days},
                    labelOf: (d) => '$d days',
                    onChanged: (d) {
                      setState(() => _days = d);
                      _cubit.refresh();
                    },
                  ),
                ),
                Expanded(
                  child: AsyncView<StoreAnalytics>(
                    state: cubit.state,
                    onRetry: cubit.load,
                    builder: (a) => AppRefresh(onRefresh: cubit.refresh, child: _Body(a: a)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.a});

  final StoreAnalytics a;

  @override
  Widget build(BuildContext context) {
    final maxSource = a.bySource.values.fold<int>(1, (m, s) => s.gross > m ? s.gross : m);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, AppSpacing.huge),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.sm,
          crossAxisSpacing: AppSpacing.sm,
          childAspectRatio: 1.45,
          children: [
            StoreStat(label: 'You earned', value: Fmt.money(a.totals.net), icon: AppIcons.rupee, color: AppColors.success),
            StoreStat(label: 'Sales (gross)', value: Fmt.money(a.totals.gross), icon: AppIcons.chartLine),
            StoreStat(label: 'Store views · ${a.uniqueVisitors} people', value: Fmt.compact(a.views), icon: AppIcons.eye, color: AppColors.info),
            StoreStat(label: 'Bought · ${a.conversionRate}% of visitors', value: '${a.customers}', icon: AppIcons.users, color: const Color(0xFFEC2A78)),
          ],
        ).animate().fadeIn(duration: 300.ms),
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Daily earnings', style: context.text.titleMedium),
              const SizedBox(height: AppSpacing.md),
              SizedBox(height: 150, child: _BarChart(points: a.daily)),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Where it comes from', style: context.text.titleMedium),
              const SizedBox(height: AppSpacing.md),
              for (final key in _sourceLabels.keys)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(_sourceLabels[key]!, style: context.text.titleSmall)),
                          Text('${Fmt.money(a.bySource[key]!.gross)} · ${a.bySource[key]!.orders}', style: context.text.bodySmall),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: a.bySource[key]!.gross / maxSource,
                          minHeight: 8,
                          color: _sourceColors[key],
                          backgroundColor: context.palette.surfaceMuted,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (a.topItems.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Top sellers', style: context.text.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                for (final (i, t) in a.topItems.indexed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Text('${i + 1}', style: context.text.titleSmall?.copyWith(color: AppColors.primary)),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(color: context.palette.textPrimary))),
                        Text('${Fmt.money(t.gross)} · ${t.orders}', style: context.text.bodySmall),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.sm,
          crossAxisSpacing: AppSpacing.sm,
          childAspectRatio: 1.45,
          children: [
            StoreStat(label: '${a.liveCount} lives · peak ${a.livePeak}', value: '${a.liveJoins} joins', icon: AppIcons.broadcast, color: AppColors.error),
            StoreStat(label: '${a.callsCompleted} calls · ${Fmt.money(a.callEarnings)}', value: '${a.callMinutes} min', icon: AppIcons.phone, color: AppColors.info),
            StoreStat(label: '${a.fanboxSupporters} supporters', value: Fmt.money(a.fanboxGross), icon: AppIcons.gift, color: const Color(0xFFEC2A78)),
            StoreStat(label: 'Affiliate · ${Fmt.money(a.affiliateConfirmed)} confirmed', value: '${a.affiliateClicks} clicks', icon: AppIcons.link, color: AppColors.warning),
          ],
        ),
      ],
    );
  }
}

/// Simple animated bar chart of daily net earnings.
class _BarChart extends StatelessWidget {
  const _BarChart({required this.points});

  final List<DayPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return Center(child: Text('No data yet', style: context.text.bodySmall));
    final max = points.fold<int>(1, (m, p) => p.net > m ? p.net : m);
    final palette = context.palette;
    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (i, p) in points.indexed)
                Expanded(
                  child: Tooltip(
                    message: '${p.date}\n${Fmt.money(p.net)} · ${p.orders} orders · ${p.views} views',
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: points.length > 40 ? 0.5 : 1.5),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: p.net / max),
                        duration: Duration(milliseconds: 400 + (i * 12).clamp(0, 500)),
                        curve: Curves.easeOutCubic,
                        builder: (context, v, _) => FractionallySizedBox(
                          heightFactor: v == 0 ? 0.02 : v,
                          alignment: Alignment.bottomCenter,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                              gradient: p.net == 0
                                  ? LinearGradient(colors: [palette.surfaceMuted, palette.surfaceMuted])
                                  : const LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(points.first.date.substring(5), style: context.text.bodySmall),
            const Spacer(),
            Text('Peak ${Fmt.money(max == 1 ? 0 : max)}', style: context.text.bodySmall),
            const Spacer(),
            Text(points.last.date.substring(5), style: context.text.bodySmall),
          ],
        ),
      ],
    );
  }
}
