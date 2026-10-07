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
import '../../../core/services/share_service.dart';
import '../../../core/widgets/media_aspect.dart';
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
  const FeedScreen({super.key, this.savedOnly = false, this.postId});

  /// Shows only the posts the user saved (Saved posts screen).
  final bool savedOnly;

  /// Shows just this one post (opened from a shared link).
  final String? postId;

  @override
  Widget build(BuildContext context) {
    final repo = sl<ContentRepository>();
    final id = postId;
    return BlocProvider(
      create: (_) => LoadCubit<List<Post>>(id != null ? () async => [await repo.post(id)] : (savedOnly ? repo.savedPosts : repo.feed)),
      child: _FeedView(savedOnly: savedOnly, single: id != null),
    );
  }
}

class _FeedView extends StatelessWidget {
  const _FeedView({required this.savedOnly, this.single = false});

  final bool savedOnly;
  final bool single;

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
    final canPost = !savedOnly && !single && auth is AuthAuthenticated && auth.user.role == UserRole.creator;

    return Scaffold(
      appBar: AppBar(
        title: Text(single ? 'Post' : (savedOnly ? 'Saved posts' : 'Feed')),
        actions: [
          if (!savedOnly && !single) ...[
            IconButton(
              tooltip: 'Find creators',
              icon: const Icon(AppIcons.search),
              onPressed: () => context.push(AppRoutes.creatorsDirectory),
            ),
            IconButton(
              tooltip: 'Saved posts',
              icon: const Icon(AppIcons.bookmark),
              onPressed: () => context.push(AppRoutes.savedPosts),
            ),
          ],
          const _AutoplayToggle(),
          if (canPost) ...[
            const SizedBox(width: AppSpacing.xxs),
            _NewPostButton(onTap: () => _createPost(context)),
          ],
          const SizedBox(width: AppSpacing.md),
        ],
      ),
      body: AsyncView<List<Post>>(
        state: cubit.state,
        onRetry: cubit.load,
        builder: (posts) => AppRefresh(
          onRefresh: cubit.refresh,
          child: posts.isEmpty
              ? ScrollableMessage(
            child: savedOnly
                ? const MessageView(icon: AppIcons.bookmark, title: 'No saved posts', message: 'Tap Save under any post to keep it here.')
                : const MessageView(icon: AppIcons.image, title: 'No posts yet'),
          )
              : ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(0, AppSpacing.xs, 0, AppSpacing.xl),
            itemCount: posts.length,
            separatorBuilder: (_, _) => Divider(height: 1, thickness: 1, color: context.palette.border),
            itemBuilder: (context, i) => _FeedPost(key: ValueKey(posts[i].id), post: posts[i], savedOnly: savedOnly),
          ),
        ),
      ),
    );
  }
}

class _FeedPost extends StatefulWidget {
  const _FeedPost({super.key, required this.post, this.savedOnly = false});

  final Post post;
  final bool savedOnly;

  @override
  State<_FeedPost> createState() => _FeedPostState();
}

class _FeedPostState extends State<_FeedPost> {
  late final bool _hasMultipleMedia = widget.post.media.length > 1;
  late final PageController _pageController = PageController();
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

  // --- Save ------------------------------------------------------------------

  bool _saveBusy = false;

  Future<void> _toggleSave() async {
    if (_saveBusy) return;
    HapticFeedback.selectionClick();
    final cubit = context.read<LoadCubit<List<Post>>>();
    final posts = cubit.state.data ?? const <Post>[];
    final wasSaved = widget.post.isSaved;
    List<Post> apply(List<Post> list, bool saved) => [
      for (final p in list)
        if (p.id == widget.post.id) ...[
          // On the Saved screen, unsaving removes the post.
          if (!(widget.savedOnly && !saved)) p.copyWith(isSaved: saved),
        ] else
          p,
    ];
    cubit.replace(apply(posts, !wasSaved));
    _saveBusy = true;
    try {
      final saved = await sl<ContentRepository>().toggleSave(widget.post.id);
      if (!widget.savedOnly) cubit.replace(apply(cubit.state.data ?? posts, saved));
      if (mounted && saved) AppSnackbar.success(context, 'Saved');
    } on ApiException catch (error) {
      cubit.replace(posts);
      if (mounted) AppSnackbar.error(context, error.displayMessage);
    } finally {
      _saveBusy = false;
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

          // Caption — above the media (2 lines, then "more"). Without a
          // caption there's still a gap between the name and the media.
          if (post.caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.sm, AppSpacing.gutter, AppSpacing.sm),
              child: _ExpandableCaption(text: post.caption),
            )
          else
            const SizedBox(height: AppSpacing.sm),

          // Media — every post keeps its real shape (tall, square or wide).
          if (post.media.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
              child: GestureDetector(
                onDoubleTap: () => _toggleLike(fromDoubleTap: true),
                child: _AdaptiveMedia(
                  media: post.media,
                  controller: _pageController,
                  index: _mediaIndex,
                  burst: _burst,
                  onPageChanged: (i) => setState(() => _mediaIndex = i),
                  onOpen: _openViewer,
                ),
              ),
            ),
          if (_hasMultipleMedia)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < post.media.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _mediaIndex ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _mediaIndex ? AppColors.primary : context.palette.border,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ),

          // Likes summary + Like | Save
          _PostActions(
            post: post,
            liked: liked,
            myId: myId,
            onLike: () => _toggleLike(),
            onSave: _toggleSave,
            onShare: (ctx) => ShareService.send(
              ctx,
              ShareService.post(id: post.id, creator: post.creatorName ?? 'A creator', caption: post.caption, mine: post.creatorUserId == myId),
            ),
            onShowLikers: () => showLikersSheet(context, postId: post.id, likeCount: post.likeCount),
          ),
        ],
      ),
    );
  }
}

/// Shows a post's media at its real shape. The box takes the shape of the
/// first item (clamped between 9:16 and 1.91:1); every item is shown whole
/// (never cropped) on a dark background.
class _AdaptiveMedia extends StatefulWidget {
  const _AdaptiveMedia({
    required this.media,
    required this.controller,
    required this.index,
    required this.burst,
    required this.onPageChanged,
    required this.onOpen,
  });

  final List<PostMedia> media;
  final PageController controller;
  final int index;
  final bool burst;
  final ValueChanged<int> onPageChanged;
  final Future<Duration?> Function(int index, {Duration? position}) onOpen;

  @override
  State<_AdaptiveMedia> createState() => _AdaptiveMediaState();
}

class _AdaptiveMediaState extends State<_AdaptiveMedia> {
  double? _ratio;

  @override
  void initState() {
    super.initState();
    final first = widget.media.first;
    _ratio = first.aspectRatio ?? MediaAspect.cached(first.url);
    if (_ratio == null) {
      MediaAspect.ofNetwork(first.url, isVideo: first.isVideo).then((r) {
        if (mounted && r != null) setState(() => _ratio = r);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final multiple = widget.media.length > 1;
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        // Unknown shape for an old post: start square, then glide to the real one.
        final height = width / MediaAspect.clamp(_ratio ?? 1);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          height: height,
          decoration: BoxDecoration(color: const Color(0xFF0E0E14), borderRadius: BorderRadius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                controller: widget.controller,
                itemCount: widget.media.length,
                onPageChanged: widget.onPageChanged,
                itemBuilder: (context, i) {
                  final m = widget.media[i];
                  return m.isVideo
                      ? StreamVideoPlayer(
                    key: ValueKey(m.url),
                    url: m.url,
                    fit: BoxFit.contain,
                    showProgress: false,
                    showPlayPauseButton: true,
                    onTap: (position) => widget.onOpen(i, position: position),
                  )
                      : GestureDetector(
                    onTap: () => widget.onOpen(i),
                    child: AppNetworkImage(url: m.url, fit: BoxFit.contain),
                  );
                },
              ),
              if (multiple)
                Positioned(
                  top: AppSpacing.sm,
                  right: AppSpacing.sm,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(AppRadius.pill)),
                    child: Text('${widget.index + 1}/${widget.media.length}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                ),
              IgnorePointer(
                child: Center(
                  child: AnimatedScale(
                    scale: widget.burst ? 1 : 0,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutBack,
                    child: const Icon(AppIcons.heartFilled, size: 96, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
/// Under every post:
///   ❤ Riya and 127 others                (tap to see who liked it)
///   ───────────────────────────────────────
///   [ ♡ Like ]          │          [ ⌑ Save ]
class _PostActions extends StatelessWidget {
  const _PostActions({
    required this.post,
    required this.liked,
    required this.myId,
    required this.onLike,
    required this.onSave,
    required this.onShare,
    required this.onShowLikers,
  });

  final Post post;
  final bool liked;
  final String? myId;
  final VoidCallback onLike;
  final VoidCallback onSave;
  final void Function(BuildContext context) onShare;
  final VoidCallback onShowLikers;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final first = post.likePreview.isEmpty ? null : post.likePreview.first;
    final firstName = first == null ? null : (first.id == myId ? 'You' : first.name);
    final others = post.likeCount - (first == null ? 0 : 1);
    final text = context.text.bodySmall?.copyWith(fontSize: 13, color: palette.textSecondary);
    final strong = text?.copyWith(color: palette.textPrimary, fontWeight: FontWeight.w600);

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.sm, AppSpacing.gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Likes summary
          InkWell(
            onTap: post.likeCount > 0 ? onShowLikers : null,
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 32,
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                    child: const Icon(AppIcons.heartFilled, size: 11, color: Colors.white),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: post.likeCount == 0
                        ? Text('Be the first to like this', style: text)
                        : Text.rich(
                      TextSpan(
                        style: text,
                        children: [
                          if (firstName != null) ...[
                            TextSpan(text: firstName, style: strong),
                            if (others > 0) TextSpan(text: ' and ${Fmt.compact(others)} ${others == 1 ? 'other' : 'others'}'),
                          ] else
                            TextSpan(text: '${Fmt.compact(post.likeCount)} ${post.likeCount == 1 ? 'like' : 'likes'}', style: strong),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Divider(height: 1, thickness: 1, color: palette.border),
          // Like | Save
          SizedBox(
            height: 48,
            child: Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: liked ? AppIcons.heartFilled : AppIcons.heart,
                    label: 'Like',
                    active: liked,
                    activeColor: AppColors.error,
                    onTap: onLike,
                  ),
                ),
                Container(width: 1, height: 22, color: palette.border),
                Expanded(
                  child: _ActionButton(
                    icon: post.isSaved ? AppIcons.bookmarkFilled : AppIcons.bookmark,
                    label: post.isSaved ? 'Saved' : 'Save',
                    active: post.isSaved,
                    activeColor: AppColors.primary,
                    onTap: onSave,
                  ),
                ),
                Container(width: 1, height: 22, color: palette.border),
                Expanded(
                  child: Builder(
                    builder: (ctx) => _ActionButton(
                      icon: AppIcons.share,
                      label: 'Share',
                      active: false,
                      activeColor: AppColors.primary,
                      onTap: () => onShare(ctx),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, required this.active, required this.activeColor, required this.onTap});

  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? activeColor : context.palette.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 21, color: color)
              .animate(key: ValueKey(active), target: active ? 1 : 0)
              .scaleXY(begin: 1, end: 1.3, duration: 140.ms, curve: Curves.easeOut)
              .then()
              .scaleXY(begin: 1.3, end: 1, duration: 160.ms, curve: Curves.easeIn),
          const SizedBox(width: 8),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            style: (context.text.labelLarge ?? const TextStyle()).copyWith(fontWeight: FontWeight.w600, color: color),
            child: Text(label),
          ),
        ],
      ),
    );
  }
}

/// Caption limited to 2 lines with an inline "more" / "less".
class _ExpandableCaption extends StatefulWidget {
  const _ExpandableCaption({required this.text});

  final String text;

  @override
  State<_ExpandableCaption> createState() => _ExpandableCaptionState();
}

class _ExpandableCaptionState extends State<_ExpandableCaption> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final style = context.text.bodyMedium?.copyWith(color: context.palette.textPrimary, height: 1.4);
    return LayoutBuilder(
      builder: (context, box) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 2,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: box.maxWidth);
        final overflows = painter.didExceedMaxLines;

        return GestureDetector(
          onTap: overflows ? () => setState(() => _expanded = !_expanded) : null,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.text,
                  style: style,
                  maxLines: _expanded ? null : 2,
                  overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                ),
                if (overflows)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _expanded ? 'See less' : 'See more',
                      style: context.text.labelLarge?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Gradient "Post" button for the app bar (creators only).
class _NewPostButton extends StatelessWidget {
  const _NewPostButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFF4511E), Color(0xFFEC2A78)])),
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(AppIcons.plus, color: Colors.white, size: 18),
                SizedBox(width: 4),
                Text('Post', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      ),
    ).animate().scale(begin: const Offset(0.7, 0.7), duration: 320.ms, curve: Curves.easeOutBack);
  }
}