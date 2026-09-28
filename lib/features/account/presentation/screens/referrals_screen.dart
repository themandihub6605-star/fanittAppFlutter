import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/bloc/load_cubit.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/async_view.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../profile/data/profile_repository.dart';

class ReferralsScreen extends StatelessWidget {
  const ReferralsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LoadCubit<ReferralSummary>(sl<ProfileRepository>().myReferrals),
      child: Builder(
        builder: (context) {
          final cubit = context.watch<LoadCubit<ReferralSummary>>();
          return Scaffold(
            appBar: AppBar(title: const Text('Refer & earn')),
            body: AsyncView<ReferralSummary>(
              state: cubit.state,
              onRetry: cubit.load,
              builder: (data) => AppRefresh(
                onRefresh: cubit.refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xxl),
                  children: [
                    AppCard(
                      color: context.palette.primarySoft,
                      borderColor: Colors.transparent,
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Earn a share of what your referrals make on their first transactions.', style: context.text.bodyMedium?.copyWith(color: context.palette.textPrimary)),
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            children: [
                              Expanded(child: Text(data.code, style: context.text.headlineSmall?.copyWith(color: AppColors.primary, letterSpacing: 2))),
                              IconButton(
                                tooltip: 'Copy',
                                icon: const Icon(AppIcons.copy, color: AppColors.primary),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: data.code));
                                  AppSnackbar.success(context, 'Code copied');
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          AppButton(
                            label: 'Share invite',
                            icon: AppIcons.shareNetwork,
                            onPressed: () => Share.share('Join me on Fanitt with my code ${data.code}: https://fanitt.com'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(child: StatCard(label: 'People joined', value: '${data.people.length}', icon: AppIcons.users)),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: StatCard(label: 'Earned', value: Fmt.money(data.totalEarned), icon: AppIcons.wallet, accent: AppColors.success)),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    const SectionHeader(title: 'Joined with your code'),
                    if (data.people.isEmpty)
                      Text('No one yet. Share your code to get started.', style: context.text.bodyMedium)
                    else
                      for (final (user, joined) in data.people)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: AppCard(
                            child: Row(
                              children: [
                                UserAvatar(initials: user.initials, imageUrl: user.avatarUrl, size: 40),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(user.name, style: context.text.titleSmall),
                                      Text('Joined ${Fmt.date(joined)}', style: context.text.bodySmall),
                                    ],
                                  ),
                                ),
                                if (user.role != null) StatusChip(label: user.role!.label, color: context.palette.textSecondary),
                              ],
                            ),
                          ),
                        ),
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
