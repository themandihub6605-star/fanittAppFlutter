import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/bloc/load_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../profile/data/profile_repository.dart';
import '../data/content_repository.dart';

/// FanBox gifts the creator received from fans.
class GiftsScreen extends StatelessWidget {
  const GiftsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LoadCubit<List<Tip>>(() async {
        final profile = await sl<ProfileRepository>().creator();
        return sl<ContentRepository>().gifts(profile.id);
      }),
      child: Builder(
        builder: (context) {
          final cubit = context.watch<LoadCubit<List<Tip>>>();
          return Scaffold(
            appBar: AppBar(title: const Text('FanBox gifts')),
            body: AsyncView<List<Tip>>(
              state: cubit.state,
              onRetry: cubit.load,
              builder: (gifts) {
                final total = gifts.fold<int>(0, (s, g) => s + g.amount);
                return AppRefresh(
                  onRefresh: cubit.refresh,
                  child: gifts.isEmpty
                      ? const ScrollableMessage(
                          child: MessageView(icon: AppIcons.gift, title: 'No gifts yet', message: 'Gifts fans send you from your profile appear here.'),
                        )
                      : ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xxl),
                          children: [
                            StatCard(label: 'Received from ${gifts.length} gift${gifts.length == 1 ? '' : 's'}', value: Fmt.money(total), icon: AppIcons.gift, accent: AppColors.primary),
                            const SizedBox(height: AppSpacing.md),
                            for (final g in gifts) ...[TipTile(tip: g), const SizedBox(height: AppSpacing.sm)],
                          ],
                        ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class TipTile extends StatelessWidget {
  const TipTile({super.key, required this.tip});

  final Tip tip;

  @override
  Widget build(BuildContext context) {
    final from = tip.from;
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(initials: from?.initials ?? '?', imageUrl: from?.avatarUrl, size: 40),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(from?.name ?? 'A fan', style: context.text.titleSmall),
                if (tip.message.isNotEmpty) Text(tip.message, style: context.text.bodyMedium?.copyWith(color: context.palette.textPrimary)),
                Text(Fmt.dateTime(tip.createdAt), style: context.text.bodySmall),
              ],
            ),
          ),
          Text(Fmt.money(tip.amount), style: context.text.titleSmall?.copyWith(color: AppColors.success)),
        ],
      ),
    );
  }
}
