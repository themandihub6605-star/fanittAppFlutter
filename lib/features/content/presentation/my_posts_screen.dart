import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/bloc/action_cubit.dart';
import '../../../core/bloc/load_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/action_scope.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/media_aspect.dart';
import '../../../core/widgets/stream_video_player.dart';
import '../data/content_repository.dart';
import 'create_post_screen.dart';

class MyPostsScreen extends StatelessWidget {
  const MyPostsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ActionScope(
      child: BlocProvider(
        create: (_) => LoadCubit<List<Post>>(sl<ContentRepository>().myPosts),
        child: const _PostsView(),
      ),
    );
  }
}

class _PostsView extends StatelessWidget {
  const _PostsView();

  Future<void> _create(BuildContext context) async {
    final created = await showCreatePostSheet(context);
    if (created && context.mounted) {
      AppSnackbar.success(context, 'Post published');
      context.read<LoadCubit<List<Post>>>().refresh();
    }
  }

  Future<void> _delete(BuildContext context, Post post) async {
    final ok = await confirmAction(context, title: 'Delete this post?', message: 'It’s removed from your profile for everyone.', confirmLabel: 'Delete', destructive: true);
    if (!ok || !context.mounted) return;
    final done = await context.read<ActionCubit>().run('delete-${post.id}', () async {
      await sl<ContentRepository>().deletePost(post.id);
      return true;
    }, success: 'Post deleted');
    if (done != null && context.mounted) context.read<LoadCubit<List<Post>>>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<List<Post>>>();
    final posts = cubit.state.data ?? const <Post>[];
    final canAdd = cubit.state.data != null && posts.length < ContentRepository.maxPosts;

    return Scaffold(
      appBar: AppBar(title: const Text('My posts')),
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(onPressed: () => _create(context), icon: const Icon(AppIcons.plus), label: const Text('New post'))
          : null,
      body: AsyncView<List<Post>>(
        state: cubit.state,
        onRetry: cubit.load,
        builder: (posts) => AppRefresh(
          onRefresh: cubit.refresh,
          child: posts.isEmpty
              ? const ScrollableMessage(
            child: MessageView(
              icon: AppIcons.image,
              title: 'Show brands your work',
              message: 'Add up to 5 posts with photos or videos. They appear on your public profile.',
            ),
          )
              : ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, 96),
            itemCount: posts.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Text('${posts.length} of ${ContentRepository.maxPosts} posts used', style: context.text.bodySmall);
              }
              final post = posts[index - 1];
              return _PostCard(post: post, onDelete: () => _delete(context, post));
            },
          ),
        ),
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post, required this.onDelete});

  final Post post;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Each post in its real shape.
          AspectRatio(
            aspectRatio: MediaAspect.clamp(post.media.first.aspectRatio ?? 1),
            child: ColoredBox(
              color: const Color(0xFF0E0E14),
              child: PageView(
                children: [
                  for (final media in post.media)
                    media.isVideo
                        ? StreamVideoPlayer(key: ValueKey(media.url), url: media.url, fit: BoxFit.contain)
                        : AppNetworkImage(url: media.url, fit: BoxFit.contain),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (post.caption.isNotEmpty) Text(post.caption, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary)),
                      Text('${post.likeCount} likes · ${Fmt.relative(post.createdAt)}${post.media.length > 1 ? ' · ${post.media.length} items' : ''}', style: context.text.bodySmall),
                    ],
                  ),
                ),
                IconButton(tooltip: 'Delete', icon: const Icon(AppIcons.trash, size: 20), onPressed: onDelete),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the full-screen "New post" composer. Returns true when a post was
/// published. Used by My posts and the Feed.
Future<bool> showCreatePostSheet(BuildContext context) => CreatePostScreen.open(context);