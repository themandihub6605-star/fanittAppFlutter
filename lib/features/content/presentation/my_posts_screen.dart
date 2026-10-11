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
import '../../../core/widgets/async_view.dart';
import '../../feed/presentation/media_viewer_screen.dart';
import '../../feed/presentation/reels_screen.dart';
import '../../feed/presentation/widgets/post_media_grid.dart';
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
    final made = await showCreateChooser(context);
    if (made != null && made != CreateMode.story && context.mounted) context.read<LoadCubit<List<Post>>>().refresh();
  }

  Future<void> _delete(BuildContext context, Post post) async {
    final what = post.isReel ? 'reel' : 'post';
    final ok = await confirmAction(context, title: 'Delete this $what?', message: 'It’s removed from the feed and your profile for everyone.', confirmLabel: 'Delete', destructive: true);
    if (!ok || !context.mounted) return;
    final done = await context.read<ActionCubit>().run('delete-${post.id}', () async {
      await sl<ContentRepository>().deletePost(post.id);
      return true;
    }, success: post.isReel ? 'Reel deleted' : 'Post deleted');
    if (done != null && context.mounted) context.read<LoadCubit<List<Post>>>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<List<Post>>>();
    final posts = cubit.state.data ?? const <Post>[];
    final postCount = posts.where((p) => !p.isReel).length;
    final reelCount = posts.where((p) => p.isReel).length;
    final canAdd = cubit.state.data != null;

    return Scaffold(
      appBar: AppBar(title: const Text('My posts & reels')),
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(onPressed: () => _create(context), icon: const Icon(AppIcons.plus), label: const Text('Create'))
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
              title: 'Share your work',
              message: 'Post photos and videos, or a short reel. They show in the feed and on your profile.',
            ),
          )
              : ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, 96),
            itemCount: posts.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Text(
                  '$postCount of ${ContentRepository.maxPosts} posts · $reelCount of ${ContentRepository.maxReels} reels',
                  style: context.text.bodySmall,
                );
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
          // Reels: open the full-screen player. Posts: all media in one block.
          if (post.isReel)
            GestureDetector(
              onTap: () => ReelsScreen.open(context, startId: post.id),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: const Color(0xFF0E0E14), child: AppNetworkImage(url: post.cover?.thumbnailUrl ?? '', fit: BoxFit.cover, placeholderIcon: AppIcons.video)),
                    Center(
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle),
                        child: const Icon(AppIcons.play, color: Colors.white, size: 24),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      top: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(6)),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(AppIcons.video, color: Colors.white, size: 12),
                            SizedBox(width: 4),
                            Text('Reel', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: PostMediaGrid(
                media: post.media,
                onOpen: (i, {position}) => MediaViewerScreen.open(context, media: post.media, index: i, position: position),
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
                      Text(
                        '${post.likeCount} likes${post.isReel ? ' · ${post.viewCount} views' : ''} · ${Fmt.relative(post.createdAt)}${post.media.length > 1 ? ' · ${post.media.length} items' : ''}',
                        style: context.text.bodySmall,
                      ),
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