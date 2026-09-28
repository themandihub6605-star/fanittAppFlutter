import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/bloc/load_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/models/common_models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/stream_video_player.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../core/enums/user_role.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../content/data/content_repository.dart';
import '../../content/presentation/my_posts_screen.dart';
import '../../creators/data/creators_repository.dart';
import 'likers_sheet.dart';
import 'media_viewer_screen.dart';

class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LoadCubit<List<Post>>(sl<ContentRepository>().feed),
      child: const _FeedView(),
    );
  }
}

class _FeedView extends StatelessWidget {
  const _FeedView();

  Future<void> _createPost(BuildContext context) async {
    final created = await showCreatePostSheet(context);
    if (created && context.mounted) {
      AppSnackbar.success(context, 'Post published');
      context.read<LoadCubit<List<Post>>>().refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<List<Post>>>();
    final auth = context.watch<AuthBloc>().state;
    // Only creators can post (backend rule).
    final canPost = auth is AuthAuthenticated && auth.user.role == UserRole.creator;

    return Scaffold(
      floatingActionButton: canPost
          ? FloatingActionButton.extended(
        heroTag: 'feed-new-post',
        onPressed: () => _createPost(context),
        icon: const Icon(AppIcons.plus),
        label: const Text('Post'),
      ).animate().scale(begin: const Offset(0.6, 0.6), duration: 350.ms, curve: Curves.easeOutBack)
          : null,
      appBar: AppBar(
        title: const Text('Feed'),
        actions: [
          IconButton(
            tooltip: 'Find creators',
            icon: const Icon(AppIcons.search),
            onPressed: () => context.push(AppRoutes.creatorsDirectory),
          ),
          const _AutoplayToggle(),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: AsyncView<List<Post>>(
        state: cubit.state,
        onRetry: cubit.load,
        builder: (posts) => AppRefresh(
          onRefresh: cubit.refresh,
          child: posts.isEmpty
              ? const ScrollableMessage(child: MessageView(icon: AppIcons.image, title: 'No posts yet'))
              : ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            // Extra bottom space so the Post button never covers the last post.
            padding: const EdgeInsets.fromLTRB(0, AppSpacing.xs, 0, 96),
            itemCount: posts.length,
            separatorBuilder: (_, _) => Divider(height: 1, thickness: 1, color: context.palette.border),
            itemBuilder: (context, i) => _FeedPost(key: ValueKey(posts[i].id), post: posts[i]),
          ),
        ),
      ),
    );
  }
}

class _FeedPost extends StatefulWidget {
  const _FeedPost({super.key, required this.post});

  final Post post;

  @override
  State<_FeedPost> createState() => _FeedPostState();
}

class _FeedPostState extends State<_FeedPost> {
  late final bool _hasMultipleMedia = widget.post.media.length > 1;
  late final PageController _pageController = PageController(viewportFraction: _hasMultipleMedia ? 0.82 : 1);
  bool _likeBusy = false;
  bool _followBusy = false;
  bool _burst = false;
  int _mediaIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  UserLite? _me() {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) return null;
    final u = auth.user;
    return UserLite(id: u.id, name: u.name, avatarUrl: u.avatarUrl, role: u.role);
  }

  // --- Like ------------------------------------------------------------------

  Future<void> _toggleLike({bool fromDoubleTap = false}) async {
    final me = _me();
    if (me == null || _likeBusy) return;
    final liked = widget.post.likedByUser(me.id);
    if (fromDoubleTap) {
      setState(() => _burst = true);
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _burst = false);
      });
      if (liked) return;
    }
    HapticFeedback.lightImpact();
    final cubit = context.read<LoadCubit<List<Post>>>();
    final posts = cubit.state.data ?? const <Post>[];
    // Optimistic update, corrected by the server's count.
    cubit.replace([
      for (final p in posts)
        p.id == widget.post.id ? p.withLike(me: me, liked: !liked, count: p.likeCount + (liked ? -1 : 1)) : p,
    ]);
    _likeBusy = true;
    try {
      final result = await sl<ContentRepository>().toggleLike(widget.post.id);
      final latest = cubit.state.data ?? const <Post>[];
      cubit.replace([
        for (final p in latest) p.id == widget.post.id ? p.withLike(me: me, liked: result.liked, count: result.likeCount) : p,
      ]);
    } on ApiException catch (error) {
      cubit.replace(posts);
      if (mounted) AppSnackbar.error(context, error.displayMessage);
    } finally {
      _likeBusy = false;
    }
  }

  // --- Follow ----------------------------------------------------------------

  Future<void> _toggleFollow() async {
    final creatorId = widget.post.creatorId;
    if (creatorId == null || _followBusy) return;
    HapticFeedback.selectionClick();
    final cubit = context.read<LoadCubit<List<Post>>>();
    final posts = cubit.state.data ?? const <Post>[];
    final wasFollowing = widget.post.isFollowingCreator;

    // Update every post by this creator at once.
    List<Post> withFollowing(List<Post> list, bool following) => [
      for (final p in list) p.creatorId == creatorId ? p.copyWith(isFollowingCreator: following) : p,
    ];

    cubit.replace(withFollowing(posts, !wasFollowing));
    setState(() => _followBusy = true);
    try {
      final result = await sl<CreatorsRepository>().toggleFollow(creatorId);
      cubit.replace(withFollowing(cubit.state.data ?? posts, result.following));
    } on ApiException catch (error) {
      cubit.replace(withFollowing(cubit.state.data ?? posts, wasFollowing));
      if (mounted) AppSnackbar.error(context, error.displayMessage);
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  // --- Full screen -----------------------------------------------------------

  Future<Duration?> _openViewer(int index, {Duration? position}) {
    return MediaViewerScreen.open(context, media: widget.post.media, index: index, position: position);
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final auth = context.watch<AuthBloc>().state;
    final myId = auth is AuthAuthenticated ? auth.user.id : null;
    final liked = myId != null && post.likedByUser(myId);
    final isOwnPost = myId != null && post.creatorUserId == myId;
    final name = post.creatorName ?? 'Creator';
    final screenWidth = MediaQuery.sizeOf(context).width;
    // Item width shrinks to match viewportFraction; height mirrors it for a square-ish media.
    final itemWidth = _hasMultipleMedia ? screenWidth * 0.82 - AppSpacing.gutter : screenWidth - AppSpacing.gutter * 2;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: avatar, name, time, follow
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    onTap: post.creatorSlug == null ? null : () => context.push(AppRoutes.creatorProfile(post.creatorSlug!)),
                    child: Row(
                      children: [
                        UserAvatar(initials: name.substring(0, 1).toUpperCase(), imageUrl: post.creatorAvatarUrl, size: 34),
                        const SizedBox(width: AppSpacing.sm),
                        Flexible(child: Text(name, style: context.text.titleSmall, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: AppSpacing.xs),
                        Text(Fmt.relative(post.createdAt), style: context.text.bodySmall),
                      ],
                    ),
                  ),
                ),
                if (!isOwnPost && post.creatorId != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  _FollowButton(following: post.isFollowingCreator, busy: _followBusy, onTap: _toggleFollow),
                ],
              ],
            ),
          ),

          // Caption — above the media
          if (post.caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.sm),
              child: Text(post.caption, style: context.text.bodyMedium?.copyWith(color: context.palette.textPrimary)),
            ),

          // Media — full width for a single item, peeks the next one when there's more than one
          if (post.media.isNotEmpty)
            GestureDetector(
              onDoubleTap: () => _toggleLike(fromDoubleTap: true),
              child: SizedBox(
                height: itemWidth,
                child: Stack(
                  children: [
                    PageView.builder(
                      controller: _pageController,
                      padEnds: false,
                      itemCount: post.media.length,
                      onPageChanged: (i) => setState(() => _mediaIndex = i),
                      itemBuilder: (context, i) {
                        final m = post.media[i];
                        final isLast = i == post.media.length - 1;
                        return Padding(
                          padding: EdgeInsets.only(
                            left: i == 0 ? AppSpacing.gutter : AppSpacing.xxs,
                            right: isLast ? AppSpacing.gutter : AppSpacing.xxs,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            child: m.isVideo
                                ? StreamVideoPlayer(
                              key: ValueKey(m.url),
                              url: m.url,
                              showProgress: false,
                              showPlayPauseButton: true,
                              onTap: (position) => _openViewer(i, position: position),
                            )
                                : GestureDetector(
                              onTap: () => _openViewer(i),
                              child: AppNetworkImage(url: m.url),
                            ),
                          ),
                        );
                      },
                    ),
                    if (_hasMultipleMedia)
                      Positioned(
                        top: AppSpacing.sm,
                        right: AppSpacing.gutter + AppSpacing.xs,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            '${_mediaIndex + 1}/${post.media.length}',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    IgnorePointer(
                      child: Center(
                        child: AnimatedScale(
                          scale: _burst ? 1 : 0,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutBack,
                          child: const Icon(AppIcons.heartFilled, size: 96, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Like + "Liked by …" in one row
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter - 4, AppSpacing.xs, AppSpacing.gutter, 0),
            child: Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  onTap: _toggleLike,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                          child: Icon(
                            liked ? AppIcons.heartFilled : AppIcons.heart,
                            key: ValueKey(liked),
                            size: 24,
                            color: liked ? AppColors.error : null,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text('${post.likeCount}', style: context.text.labelMedium),
                      ],
                    ),
                  ),
                ),
                if (post.likeCount > 0) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _LikedByRow(
                      post: post,
                      myId: myId,
                      onTap: () => showLikersSheet(context, postId: post.id, likeCount: post.likeCount),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// App-bar switch: pause every video / let them autoplay again.
class _AutoplayToggle extends StatelessWidget {
  const _AutoplayToggle();

  @override
  Widget build(BuildContext context) {
    final coordinator = VideoPlaybackCoordinator.instance;
    return ValueListenableBuilder<bool>(
      valueListenable: coordinator.autoplay,
      builder: (context, autoplay, _) => IconButton(
        tooltip: autoplay ? 'Pause all videos' : 'Autoplay videos',
        icon: Icon(autoplay ? AppIcons.pauseCircle : AppIcons.playCircle),
        onPressed: () {
          HapticFeedback.selectionClick();
          coordinator.autoplay.value = !autoplay;
          if (autoplay) {
            coordinator.pauseActive();
            AppSnackbar.info(context, 'All videos paused. Tap ▶ on a video to play it.');
          } else {
            AppSnackbar.info(context, 'Videos will play automatically.');
          }
        },
      ),
    );
  }
}

class _FollowButton extends StatelessWidget {
  const _FollowButton({required this.following, required this.busy, required this.onTap});

  final bool following;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AnimatedContainer(
      duration: AppDurations.fast,
      height: 32,
      decoration: BoxDecoration(
        color: following ? Colors.transparent : AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: following ? palette.borderStrong : AppColors.primary),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              child: Text(
                following ? 'Following' : 'Follow',
                style: context.text.labelMedium?.copyWith(color: following ? palette.textPrimary : Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Liked by Priya and 12 others" with overlapping avatars.
class _LikedByRow extends StatelessWidget {
  const _LikedByRow({required this.post, required this.myId, required this.onTap});

  final Post post;
  final String? myId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final preview = post.likePreview.take(3).toList();
    final first = preview.isEmpty ? null : preview.first;
    final firstName = first == null ? null : (first.id == myId ? 'you' : first.name);
    final others = post.likeCount - (first == null ? 0 : 1);

    final baseStyle = context.text.bodySmall?.copyWith(color: palette.textSecondary);
    final boldStyle = context.text.labelMedium?.copyWith(color: palette.textPrimary);

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            if (preview.isNotEmpty) ...[
              SizedBox(
                width: 20.0 + (preview.length - 1) * 14,
                height: 22,
                child: Stack(
                  children: [
                    for (final (i, user) in preview.indexed)
                      Positioned(
                        left: i * 14.0,
                        child: Container(
                          padding: const EdgeInsets.all(1.5),
                          decoration: BoxDecoration(color: palette.background, shape: BoxShape.circle),
                          child: UserAvatar(initials: user.initials, imageUrl: user.avatarUrl, size: 19),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: baseStyle,
                  children: [
                    const TextSpan(text: 'Liked by '),
                    if (firstName != null) ...[
                      TextSpan(text: firstName, style: boldStyle),
                      if (others > 0) ...[
                        const TextSpan(text: ' and '),
                        TextSpan(text: '$others ${others == 1 ? 'other' : 'others'}', style: boldStyle),
                      ],
                    ] else
                      TextSpan(text: '${post.likeCount} ${post.likeCount == 1 ? 'person' : 'people'}', style: boldStyle),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}