import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/bloc/load_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/models/common_models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/services/share_service.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../core/enums/user_role.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../content/data/content_repository.dart';
import '../../brands/data/brands_repository.dart';
import '../../content/presentation/create_post_screen.dart';
import '../../creators/data/creators_repository.dart';
import 'likers_sheet.dart';
import 'media_viewer_screen.dart';
import 'widgets/post_media_grid.dart';
import 'widgets/reels_row.dart';
import 'widgets/stories_bar.dart';
import 'activity_screen.dart';

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

class _FeedView extends StatefulWidget {
  const _FeedView({required this.savedOnly, this.single = false});

  final bool savedOnly;
  final bool single;

  @override
  State<_FeedView> createState() => _FeedViewState();
}

class _FeedViewState extends State<_FeedView> {
  static const _pageSize = 15;

  /// Reels row sits after this many posts.
  static const _reelsAfter = 2;

  final _scroll = ScrollController();
  final _storiesTick = ValueNotifier<int>(0);
  List<Post> _reels = const [];
  int _page = 1;
  bool _hasMore = true;
  bool _loadingMore = false;

  bool get _isMainFeed => !widget.savedOnly && !widget.single;

  @override
  void initState() {
    super.initState();
    if (_isMainFeed) {
      _scroll.addListener(_onScroll);
      _loadReels();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _storiesTick.dispose();
    super.dispose();
  }

  Future<void> _loadReels() async {
    try {
      final res = await sl<ContentRepository>().reels(limit: 10);
      if (mounted) setState(() => _reels = res.items);
    } catch (_) {}
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < 800) _loadMore();
  }

  Future<void> _loadMore() async {
    final cubit = context.read<LoadCubit<List<Post>>>();
    final current = cubit.state.data;
    if (current == null || _loadingMore || !_hasMore) return;
    if (current.length < _page * _pageSize) {
      _hasMore = false;
      return;
    }
    setState(() => _loadingMore = true);
    try {
      final next = await sl<ContentRepository>().feed(page: _page + 1, limit: _pageSize);
      if (!mounted) return;
      final known = current.map((p) => p.id).toSet();
      cubit.replace([...cubit.state.data ?? current, ...next.where((p) => !known.contains(p.id))]);
      _page++;
      _hasMore = next.length == _pageSize;
    } catch (_) {
      // Keep what we have; scrolling again retries.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _refresh() async {
    _page = 1;
    _hasMore = true;
    _storiesTick.value++;
    await Future.wait([context.read<LoadCubit<List<Post>>>().refresh(), if (_isMainFeed) _loadReels()]);
  }

  Future<void> _create() async {
    final made = await showCreateChooser(context);
    if (made == null || !mounted) return;
    switch (made) {
      case CreateMode.post:
        _page = 1;
        _hasMore = true;
        context.read<LoadCubit<List<Post>>>().refresh();
      case CreateMode.reel:
        _loadReels();
      case CreateMode.story:
        _storiesTick.value++;
    }
  }

  Future<bool> _addStory() async {
    final done = await CreatePostScreen.open(context, mode: CreateMode.story);
    return done;
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<List<Post>>>();
    final auth = context.watch<AuthBloc>().state;
    // Creators and brands can post (backend rule).
    final canPost = auth is AuthAuthenticated && (auth.user.role == UserRole.creator || auth.user.role == UserRole.brand);
    final showCreate = canPost && _isMainFeed;

    return Scaffold(
      // Main feed: just "+" (create) on the left and ♥ (activity) on the right.
      appBar: AppBar(
        centerTitle: true,
        automaticallyImplyLeading: !_isMainFeed,
        leading: showCreate
            ? IconButton(
          tooltip: 'Create',
          onPressed: () {
            HapticFeedback.selectionClick();
            _create();
          },
          icon: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), border: Border.all(color: context.palette.textPrimary, width: 1.8)),
            child: Icon(AppIcons.plus, size: 17, color: context.palette.textPrimary),
          ),
        )
            : null,
        // Main feed: no title — just + and ♥.
        title: _isMainFeed
            ? null
            : Text(
          widget.single ? 'Post' : 'Saved posts',
          style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4),
        ),
        actions: [
          if (_isMainFeed && auth is AuthAuthenticated) const ActivityButton(),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: AsyncView<List<Post>>(
        state: cubit.state,
        onRetry: cubit.load,
        builder: (posts) {
          final rows = <Widget>[
            if (_isMainFeed) StoriesBar(canPost: canPost, onAddStory: _addStory, refresh: _storiesTick),
            // A little room between the stories and the first post.
            if (_isMainFeed) const SizedBox(height: AppSpacing.sm),
          ];
          for (var i = 0; i < posts.length; i++) {
            if (i > 0 || rows.isNotEmpty) rows.add(Divider(height: 1, thickness: 1, color: context.palette.border));
            rows.add(_FeedPost(key: ValueKey(posts[i].id), post: posts[i], savedOnly: widget.savedOnly));
            if (_isMainFeed && i == _reelsAfter - 1 && _reels.isNotEmpty) rows.add(ReelsRow(reels: _reels));
          }
          // Fewer posts than the slot: reels go at the end.
          if (_isMainFeed && posts.length < _reelsAfter && _reels.isNotEmpty) rows.add(ReelsRow(reels: _reels));
          if (posts.isEmpty && _reels.isEmpty) {
            rows.add(
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.huge),
                child: widget.savedOnly
                    ? const MessageView(icon: AppIcons.bookmark, title: 'No saved posts', message: 'Tap Save under any post to keep it here.')
                    : const MessageView(icon: AppIcons.image, title: 'No posts yet'),
              ),
            );
          }
          if (_loadingMore) {
            rows.add(const Padding(padding: EdgeInsets.all(AppSpacing.lg), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2)))));
          }
          return AppRefresh(
            onRefresh: _refresh,
            child: ListView(
              controller: _isMainFeed ? _scroll : null,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              children: rows,
            ),
          );
        },
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
  bool _likeBusy = false;
  bool _followBusy = false;
  bool _burst = false;

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
      final following = widget.post.isBrand
          ? await sl<BrandsRepository>().toggleFollow(creatorId)
          : (await sl<CreatorsRepository>().toggleFollow(creatorId)).following;
      cubit.replace(withFollowing(cubit.state.data ?? posts, following));
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
    final name = post.creatorName ?? (post.isBrand ? 'Brand' : 'Creator');

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
                    onTap: post.authorRoute == null ? null : () => context.push(post.authorRoute!),
                    child: Row(
                      children: [
                        UserAvatar(initials: name.substring(0, 1).toUpperCase(), imageUrl: post.creatorAvatarUrl, size: 34),
                        const SizedBox(width: AppSpacing.sm),
                        Flexible(child: Text(name, style: context.text.titleSmall, overflow: TextOverflow.ellipsis)),
                        if (post.verified) ...[
                          const SizedBox(width: 3),
                          const Icon(AppIcons.sealCheck, size: 14, color: AppColors.info),
                        ],
                        if (post.isBrand) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(color: AppColors.info.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                            child: const Text('Brand', style: TextStyle(color: AppColors.info, fontSize: 10, fontWeight: FontWeight.w800)),
                          ),
                        ],
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

          const SizedBox(height: AppSpacing.sm),

          // Media — every photo / video of the post together in one block.
          if (post.media.isNotEmpty)
          // Edge to edge — the media touches both sides of the screen.
            GestureDetector(
              onDoubleTap: () => _toggleLike(fromDoubleTap: true),
              child: PostMediaGrid(
                media: post.media,
                radius: 0,
                onOpen: _openViewer,
                overlay: Center(
                  child: AnimatedScale(
                    scale: _burst ? 1 : 0,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutBack,
                    child: const Icon(AppIcons.heartFilled, size: 96, color: Colors.white),
                  ),
                ),
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
              ShareService.post(id: post.id, creator: post.creatorName ?? (post.isBrand ? 'A brand' : 'A creator'), caption: post.caption, mine: post.creatorUserId == myId),
            ),
            onShowLikers: () => showLikersSheet(context, postId: post.id, likeCount: post.likeCount),
          ),

          // Caption under the actions (2 lines, then "See more").
          if (post.caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 2, AppSpacing.gutter, 0),
              child: _ExpandableCaption(text: post.caption),
            ),
        ],
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
    return TextButton(
      onPressed: busy ? null : onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: following ? context.palette.textSecondary : AppColors.primary,
      ),
      child: Text(following ? 'Following' : 'Follow', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
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
    final text = context.text.bodySmall?.copyWith(fontSize: 12.5, color: palette.textSecondary);
    final strong = text?.copyWith(color: palette.textPrimary, fontWeight: FontWeight.w700);

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter - 6, AppSpacing.xs, AppSpacing.gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          //  ♡ 12    ⌑ Save    ↗ Share
          Row(
            children: [
              _ActionButton(
                icon: liked ? AppIcons.heartFilled : AppIcons.heart,
                label: post.likeCount > 0 ? Fmt.compact(post.likeCount) : 'Like',
                active: liked,
                activeColor: AppColors.error,
                onTap: onLike,
              ),
              _ActionButton(
                icon: post.isSaved ? AppIcons.bookmarkFilled : AppIcons.bookmark,
                label: post.isSaved ? 'Saved' : 'Save',
                active: post.isSaved,
                activeColor: AppColors.primary,
                onTap: onSave,
              ),
              Builder(
                builder: (ctx) => _ActionButton(icon: AppIcons.share, label: 'Share', active: false, activeColor: AppColors.primary, onTap: () => onShare(ctx)),
              ),
            ],
          ),
          // "Liked by Riya and 12 others" — only when someone liked it.
          if (post.likeCount > 0)
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 2),
              child: GestureDetector(
                onTap: onShowLikers,
                child: Text.rich(
                  TextSpan(
                    style: text,
                    children: [
                      const TextSpan(text: 'Liked by '),
                      if (firstName != null) ...[
                        TextSpan(text: firstName, style: strong),
                        if (others > 0) TextSpan(text: ' and ${Fmt.compact(others)} ${others == 1 ? 'other' : 'others'}'),
                      ] else
                        TextSpan(text: '${Fmt.compact(post.likeCount)} ${post.likeCount == 1 ? 'person' : 'people'}', style: strong),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Icon + small text (count / label), Instagram-style.
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 23, color: color)
                .animate(key: ValueKey(active), target: active ? 1 : 0)
                .scaleXY(begin: 1, end: 1.25, duration: 130.ms, curve: Curves.easeOut)
                .then()
                .scaleXY(begin: 1.25, end: 1, duration: 150.ms, curve: Curves.easeIn),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: active ? activeColor : context.palette.textSecondary)),
            const SizedBox(width: 8),
          ],
        ),
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