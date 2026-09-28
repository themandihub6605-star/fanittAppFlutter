import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/bloc/action_cubit.dart';
import '../../../core/bloc/load_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/action_scope.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../campaigns/presentation/widgets/campaign_widgets.dart';
import '../../content/data/content_repository.dart';
import '../data/creators_repository.dart';

class CreatorProfileScreen extends StatelessWidget {
  const CreatorProfileScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context) {
    return ActionScope(
      child: BlocProvider(
        create: (_) => LoadCubit<CreatorPublicProfile>(() => sl<CreatorsRepository>().bySlug(slug)),
        child: const _ProfileView(),
      ),
    );
  }
}

class _ProfileView extends StatelessWidget {
  const _ProfileView();

  Future<void> _toggleFollow(BuildContext context, CreatorPublicProfile data) async {
    final cubit = context.read<LoadCubit<CreatorPublicProfile>>();
    final result = await context.read<ActionCubit>().run('follow', () => sl<CreatorsRepository>().toggleFollow(data.creator.id));
    if (result == null) return;
    HapticFeedback.lightImpact();
    cubit.replace(CreatorPublicProfile(
      creator: data.creator.copyWith(isFollowing: result.following, followerCount: result.followerCount),
      reviews: data.reviews,
      projectsCompleted: data.projectsCompleted,
      posts: data.posts,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<CreatorPublicProfile>>();
    final actions = context.watch<ActionCubit>().state;
    return Scaffold(
      appBar: AppBar(title: const Text('Creator')),
      body: AsyncView<CreatorPublicProfile>(
        state: cubit.state,
        onRetry: cubit.load,
        builder: (data) {
          final c = data.creator;
          final palette = context.palette;
          return AppRefresh(
            onRefresh: cubit.refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xxl),
              children: [
                Row(
                  children: [
                    UserAvatar(initials: c.initials, imageUrl: c.avatarUrl, size: 76),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.name, style: context.text.headlineSmall),
                          if (c.title.isNotEmpty) Text(c.title, style: context.text.bodyMedium),
                          const SizedBox(height: AppSpacing.xs),
                          Wrap(
                            spacing: AppSpacing.xs,
                            runSpacing: AppSpacing.xs,
                            children: [
                              if (c.category != null && c.category!.label.isNotEmpty) StatusChip(label: c.category!.label, color: palette.textSecondary),
                              if (c.isProPlan) StatusChip(label: c.planName, color: AppColors.primary, icon: AppIcons.crown),
                              if (c.isAvailableForWork) const StatusChip(label: 'Available', color: AppColors.success),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(child: StatCard(label: 'Followers', value: Fmt.compact(c.followerCount), icon: AppIcons.users)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: StatCard(label: 'Rating', value: c.reviewCount == 0 ? '—' : c.averageRating.toStringAsFixed(1), icon: AppIcons.star, accent: AppColors.warning)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: StatCard(label: 'Projects', value: '${data.projectsCompleted}', icon: AppIcons.checkCircle, accent: AppColors.success)),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                c.isFollowing
                    ? AppButton.secondary(label: 'Following', icon: AppIcons.check, isLoading: actions.isBusyWith('follow'), onPressed: actions.isBusy ? null : () => _toggleFollow(context, data))
                    : AppButton(label: 'Follow', icon: AppIcons.userPlus, isLoading: actions.isBusyWith('follow'), onPressed: actions.isBusy ? null : () => _toggleFollow(context, data)),
                if (c.bio.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xl),
                  const SectionHeader(title: 'About'),
                  Text(c.bio, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary)),
                ],
                if (c.skills.isNotEmpty || c.languages.isNotEmpty || c.location.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      if (c.location.isNotEmpty) StatusChip(label: c.location, color: palette.textSecondary, icon: AppIcons.mapPin),
                      for (final s in c.skills) StatusChip(label: s, color: palette.textSecondary),
                      for (final l in c.languages) StatusChip(label: l, color: palette.textSecondary, icon: AppIcons.translate),
                    ],
                  ),
                ],
                if (c.socials.values.isNotEmpty || c.portfolioLink.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xl),
                  const SectionHeader(title: 'Links'),
                  for (final link in [...c.socials.values.values, if (c.portfolioLink.isNotEmpty) c.portfolioLink]) LinkText(url: link),
                ],
                if (data.posts.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xl),
                  const SectionHeader(title: 'Posts'),
                  _PostGrid(posts: data.posts),
                ],
                const SizedBox(height: AppSpacing.xl),
                SectionHeader(title: 'Reviews${c.reviewCount > 0 ? ' (${c.reviewCount})' : ''}'),
                if (data.reviews.isEmpty)
                  Text('No reviews yet.', style: context.text.bodyMedium)
                else
                  for (final review in data.reviews) ...[
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(review.from?.name ?? 'Fanitt user', style: context.text.titleSmall)),
                              for (var i = 0; i < 5; i++)
                                Icon(i < review.rating ? AppIcons.starFilled : AppIcons.star, size: 14, color: AppColors.warning),
                            ],
                          ),
                          if (review.comment.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Text(review.comment, style: context.text.bodyMedium),
                          ],
                          const SizedBox(height: 4),
                          Text(Fmt.date(review.createdAt), style: context.text.bodySmall?.copyWith(color: palette.textTertiary)),
                        ],
                      ),
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

class _PostGrid extends StatelessWidget {
  const _PostGrid({required this.posts});

  final List<Post> posts;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.xs,
      crossAxisSpacing: AppSpacing.xs,
      children: [
        for (final post in posts)
          if (post.media.isNotEmpty && !post.media.first.isVideo)
            AppNetworkImage(url: post.media.first.url, radius: AppRadius.sm)
          else
            Container(
              decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.sm)),
              child: Icon(AppIcons.video, color: palette.textSecondary),
            ),
      ],
    );
  }
}
