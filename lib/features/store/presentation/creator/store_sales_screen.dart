import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bloc/load_cubit.dart';
import '../../../../core/bloc/paged_cubit.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/async_view.dart';
import '../../../../core/widgets/paged_list_view.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../data/store_repository.dart';
import '../widgets/store_widgets.dart';

/// Everyone who bought from the creator, newest first, with a 30-day summary.
class StoreSalesScreen extends StatelessWidget {
  const StoreSalesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = sl<StoreRepository>();
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => LoadCubit<StoreSummary>(repo.summary)),
        BlocProvider(create: (_) => PagedCubit<StoreOrder>((page) => repo.sales(page: page))),
      ],
      child: Builder(
        builder: (context) {
          final summary = context.watch<LoadCubit<StoreSummary>>().state.data;
          return Scaffold(
            appBar: AppBar(title: const Text('Sales & orders')),
            body: Column(
              children: [
                if (summary != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.sm),
                    child: Row(
                      children: [
                        Expanded(child: StoreStat(label: 'Total sales', value: Fmt.money(summary.stats.grossSales), icon: AppIcons.chartLine)),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: StoreStat(label: 'You earned', value: Fmt.money(summary.stats.netEarnings), icon: AppIcons.rupee, color: AppColors.success)),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: StoreStat(
                            label: 'Last 30 days',
                            value: Fmt.money(summary.last30Days.fold<int>(0, (s, d) => s + d.net)),
                            icon: AppIcons.calendar,
                            color: AppColors.info,
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: PagedListView<StoreOrder>(
                    cubit: context.read<PagedCubit<StoreOrder>>(),
                    spacing: AppSpacing.sm,
                    empty: const MessageView(icon: AppIcons.receipt, title: 'No sales yet', message: 'Share your store link to get your first buyer.'),
                    itemBuilder: (context, o) => _SaleTile(order: o),
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

class _SaleTile extends StatelessWidget {
  const _SaleTile({required this.order});

  final StoreOrder order;

  @override
  Widget build(BuildContext context) {
    final refunded = order.status == 'refunded';
    return AppCard(
      child: Row(
        children: [
          UserAvatar(initials: (order.buyerName ?? '?').trim().isEmpty ? '?' : order.buyerName!.trim()[0].toUpperCase(), imageUrl: order.buyerAvatarUrl, size: 40),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(order.itemTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall),
                Text(
                  '${order.buyerName ?? 'Buyer'} · ${order.paidAt == null ? '' : Fmt.relative(order.paidAt!)}',
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                order.amount == 0 ? 'Free' : '+${Fmt.money(order.creatorEarning)}',
                style: context.text.titleSmall?.copyWith(
                  color: refunded ? context.palette.textTertiary : AppColors.success,
                  decoration: refunded ? TextDecoration.lineThrough : null,
                ),
              ),
              Text(refunded ? 'Refunded' : (order.amount == 0 ? '' : 'of ${Fmt.money(order.amount)}'), style: context.text.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}
