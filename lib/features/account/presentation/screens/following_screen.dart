import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/bloc/load_cubit.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/async_view.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../profile/data/profile_repository.dart';

class FollowingScreen extends StatelessWidget {
  const FollowingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LoadCubit<List<FollowingItem>>(sl<ProfileRepository>().following),
      child: Builder(
        builder: (context) {
          final cubit = context.watch<LoadCubit<List<FollowingItem>>>();
          return Scaffold(
            appBar: AppBar(title: const Text('Following')),
            body: AsyncView<List<FollowingItem>>(
              state: cubit.state,
              onRetry: cubit.load,
              builder: (items) => AppRefresh(
                onRefresh: cubit.refresh,
                child: items.isEmpty
                    ? const ScrollableMessage(child: MessageView(icon: AppIcons.userPlus, title: 'You’re not following anyone yet'))
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xxl),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, i) {
                          final item = items[i];
                          return AppCard(
                            onTap: item.slug.isEmpty
                                ? null
                                : () => context.push(item.isCreator ? AppRoutes.creatorProfile(item.slug) : AppRoutes.brandProfile(item.slug)),
                            child: Row(
                              children: [
                                UserAvatar(initials: item.name.isEmpty ? '?' : item.name.substring(0, 1).toUpperCase(), imageUrl: item.avatarUrl, size: 44),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item.name, style: context.text.titleSmall),
                                      if (item.subtitle != null) Text(item.subtitle!, style: context.text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    ],
                                  ),
                                ),
                                StatusChip(label: item.isCreator ? 'Creator' : 'Brand', color: item.isCreator ? AppColors.primary : AppColors.info),
                                const SizedBox(width: AppSpacing.xs),
                                Icon(AppIcons.chevronRight, size: 18, color: context.palette.textTertiary),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}
