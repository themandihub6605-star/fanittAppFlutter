import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/bloc/load_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/models/common_models.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../content/data/content_repository.dart';

/// "Liked by" list for a post.
Future<void> showLikersSheet(BuildContext context, {required String postId, required int likeCount}) {
  return showAppSheet<void>(
    context,
    builder: (_) => BlocProvider(
      create: (_) => LoadCubit<List<UserLite>>(() => sl<ContentRepository>().likers(postId)),
      child: _LikersSheet(likeCount: likeCount),
    ),
  );
}

class _LikersSheet extends StatelessWidget {
  const _LikersSheet({required this.likeCount});

  final int likeCount;

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<List<UserLite>>>();
    final height = MediaQuery.sizeOf(context).height * 0.55;

    return SheetBody(
      title: 'Likes',
      subtitle: '$likeCount ${likeCount == 1 ? 'person likes' : 'people like'} this post',
      child: SizedBox(
        height: height,
        child: AsyncView<List<UserLite>>(
          state: cubit.state,
          onRetry: cubit.load,
          builder: (users) => users.isEmpty
              ? const MessageView(icon: AppIcons.heart, title: 'No likes yet')
              : ListView.separated(
            itemCount: users.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
            itemBuilder: (context, i) {
              final user = users[i];
              return Row(
                children: [
                  UserAvatar(initials: user.initials, imageUrl: user.avatarUrl, size: 40),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      user.name,
                      style: context.text.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (user.role != null)
                    Text(user.role!.label, style: context.text.bodySmall?.copyWith(color: context.palette.textTertiary)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}