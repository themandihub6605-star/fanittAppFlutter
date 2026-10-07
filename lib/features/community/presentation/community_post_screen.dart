import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/bloc/load_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/async_view.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../data/community_repository.dart';
import 'widgets/community_post_card.dart';
import 'widgets/community_widgets.dart';

/// A single community post — opened from notifications.
class CommunityPostScreen extends StatelessWidget {
  const CommunityPostScreen({super.key, required this.postId});

  final String postId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LoadCubit<CommunityPost>(() => sl<CommunityRepository>().post(postId)),
      child: Builder(
        builder: (context) {
          final cubit = context.watch<LoadCubit<CommunityPost>>();
          final auth = context.watch<AuthBloc>().state;
          final myId = auth is AuthAuthenticated ? auth.user.id : null;
          return Scaffold(
            appBar: AppBar(title: const Text('Post')),
            body: AsyncView<CommunityPost>(
              state: cubit.state,
              onRetry: cubit.load,
              builder: (post) {
                final community = post.community;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xxl),
                  children: [
                    if (community != null) ...[
                      AppCard(
                        onTap: () => context.push(AppRoutes.communityDetail(community.slug)),
                        child: Row(
                          children: [
                            CommunityIcon(name: community.name, url: community.iconUrl, size: 40),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(child: Text(community.name, style: context.text.titleSmall, overflow: TextOverflow.ellipsis)),
                            Icon(AppIcons.chevronRight, size: 18, color: context.palette.textTertiary),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    CommunityPostCard(
                      post: post,
                      myUserId: myId,
                      canInteract: community?.isMember ?? false,
                      canModerate: community?.canModerate ?? false,
                      onChanged: cubit.replace,
                      onDeleted: () => context.pop(),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}