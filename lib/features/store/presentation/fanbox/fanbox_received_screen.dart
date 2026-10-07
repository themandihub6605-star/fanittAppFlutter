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
import '../../../../core/widgets/user_avatar.dart';
import '../../data/store_repository.dart';
import '../widgets/store_widgets.dart';

/// Creator: FanBox tips received, with supporters' messages.
class FanBoxReceivedScreen extends StatelessWidget {
  const FanBoxReceivedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LoadCubit<FanBoxReceived>(() => sl<StoreRepository>().fanboxReceived()),
      child: Builder(
        builder: (context) {
          final cubit = context.watch<LoadCubit<FanBoxReceived>>();
          return Scaffold(
            appBar: AppBar(title: const Text('FanBox')),
            body: AsyncView<FanBoxReceived>(
              state: cubit.state,
              onRetry: cubit.load,
              builder: (data) => AppRefresh(
                onRefresh: cubit.refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.huge),
                  children: [
                    Row(
                      children: [
                        Expanded(child: StoreStat(label: 'You received', value: Fmt.money(data.net), icon: AppIcons.gift, color: AppColors.success)),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: StoreStat(label: 'FanBoxes', value: '${data.count}', icon: AppIcons.heartFilled, color: const Color(0xFFEC2A78))),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: StoreStat(label: 'Supporters', value: '${data.supporters}', icon: AppIcons.users)),
                      ],
                    ).animate().fadeIn(duration: 300.ms),
                    const SizedBox(height: AppSpacing.lg),
                    if (data.items.isEmpty)
                      const MessageView(icon: AppIcons.gift, title: 'No FanBox yet', message: 'Fans can send you a FanBox from your store, your lives and your profile.')
                    else
                      for (final (i, f) in data.items.indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: AppCard(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                UserAvatar(initials: f.name.isEmpty ? '?' : f.name[0].toUpperCase(), imageUrl: f.avatarUrl, size: 40),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(f.name, style: context.text.titleSmall),
                                      if (f.message.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text('“${f.message}”', style: context.text.bodyMedium?.copyWith(color: context.palette.textPrimary, fontStyle: FontStyle.italic)),
                                      ],
                                      if (f.paidAt != null) Text(Fmt.relative(f.paidAt!), style: context.text.bodySmall),
                                    ],
                                  ),
                                ),
                                Text('+${Fmt.money(f.creatorEarning)}', style: context.text.titleSmall?.copyWith(color: AppColors.success)),
                              ],
                            ),
                          ),
                        ).animate(delay: (40 * i.clamp(0, 10)).ms).fadeIn(duration: 250.ms).slideX(begin: 0.04),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
