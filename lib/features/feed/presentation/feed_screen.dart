// File: lib/features/feed/presentation/feed_screen.dart
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
      // Main feed: big "Feed" title, then + (create) and ♥ (activity) as round buttons.
      appBar: AppBar(
        centerTitle: false,
        automaticallyImplyLeading: !_isMainFeed,
        titleSpacing: _isMainFeed ? AppSpacing.gutter : null,
        title: Text(
          _isMainFeed ? 'Feed' : (widget.single ? 'Post' : 'Saved posts'),
          style: context.text.titleLarge?.copyWith(fontSize: _isMainFeed ? 26 : null, fontWeight: FontWeight.w800, letterSpacing: _isMainFeed ? -0.8 : -0.4),
        ),
        actions: [
          if (showCreate)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  _create();
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]),
                    boxShadow: [BoxShadow(color: Color(0x59F4511E), blurRadius: 14, offset: Offset(0, 6))],
                  ),
                  child: const Icon(AppIcons.plus, size: 20, color: Colors.white),
                ),
              ),
            ),
          if (_isMainFeed && auth is AuthAuthenticated)
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(shape: BoxShape.circle, color: context.palette.surface, border: Border.all(color: context.palette.border.withValues(alpha: 0.8))),
              child: const Center(child: ActivityButton()),
            ),
          const SizedBox(width: AppSpacing.gutter - 4),
        ],
      ),
      body: AsyncView<List<Post>>(
        state: cubit.state,
        onRetry: cubit.load,
        builder: (posts) {
          final rows = <Widget>[
            if (_isMainFeed) StoriesBar(canPost: canPost, onAddStory: _addStory, refresh: _storiesTick),
            // A little room between the stories and the first post.
            if (_isMainFeed) const SizedBox(height: AppSpacing.md),
          ];
          for (var i = 0; i < posts.length; i++) {
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
    final palette = context.palette;
    final dark = context.isDark;
    final hasMedia = post.media.isNotEmpty;

    Widget header({required bool onMedia}) {
      final fg = onMedia ? Colors.white : palette.textPrimary;
      final sub = onMedia ? const Color(0xD9FFFFFF) : palette.textSecondary;
      return Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: post.authorRoute == null ? null : () => context.push(post.authorRoute!),
              child: Row(
                children: [
                  // Photo with the brand ring.
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFFF4511E), Color(0xFFEC2A78)])),
                    child: Container(
                      padding: const EdgeInsets.all(1.5),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: onMedia ? Colors.white : palette.surface),
                      child: UserAvatar(initials: name.substring(0, 1).toUpperCase(), imageUrl: post.creatorAvatarUrl, size: 36),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: fg, letterSpacing: -0.2, shadows: onMedia ? const [Shadow(color: Color(0x66000000), blurRadius: 8)] : null))),
                            if (post.verified) ...[
                              const SizedBox(width: 4),
                              Icon(AppIcons.sealCheck, size: 14, color: onMedia ? const Color(0xFF60A5FA) : AppColors.info),
                            ],
                            const SizedBox(width: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                gradient: post.isBrand ? null : const LinearGradient(colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]),
                                color: post.isBrand ? AppColors.info : null,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(post.isBrand ? 'BRAND' : 'CREATOR', style: const TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w900, letterSpacing: 0.4)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 1),
                        Text(Fmt.relative(post.createdAt), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: sub)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!isOwnPost && post.creatorId != null) ...[
            const SizedBox(width: 8),
            _FollowButton(following: post.isFollowingCreator, busy: _followBusy, onTap: _toggleFollow, onMedia: onMedia),
          ],
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(26),
          border: dark ? Border.all(color: palette.border.withValues(alpha: 0.5)) : null,
          boxShadow: dark ? null : const [BoxShadow(color: Color(0x14101828), blurRadius: 30, offset: Offset(0, 10))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasMedia)
              // Media with the creator on top of it.
                Stack(
                  children: [
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
                            child: const Icon(AppIcons.heartFilled, size: 96, color: Colors.white, shadows: [Shadow(color: Color(0x66000000), blurRadius: 20)]),
                          ),
                        ),
                      ),
                    ),
                    const Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: 110,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x8C000000), Color(0x00000000)])),
                        ),
                      ),
                    ),
                    Positioned(left: 12, right: 12, top: 12, child: header(onMedia: true)),
                  ],
                )
              else
                Padding(padding: const EdgeInsets.fromLTRB(14, 14, 14, 4), child: header(onMedia: false)),

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

              if (post.caption.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: _ExpandableCaption(text: post.caption, author: name),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _FollowButton extends StatelessWidget {
  const _FollowButton({required this.following, required this.busy, required this.onTap, this.onMedia = false});

  final bool following;
  final bool busy;
  final VoidCallback onTap;

  /// Glass style on top of a photo.
  final bool onMedia;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final Color fg;
    final BoxDecoration deco;
    if (onMedia) {
      fg = Colors.white;
      deco = BoxDecoration(
        color: Colors.white.withValues(alpha: following ? 0.12 : 0.22),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
      );
    } else if (following) {
      fg = palette.textSecondary;
      deco = BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(99));
    } else {
      fg = Colors.white;
      deco = BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]), borderRadius: BorderRadius.circular(99));
    }
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: deco,
        child: Text(following ? 'Following' : 'Follow', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: fg)),
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
    final text = TextStyle(fontSize: 12.5, color: palette.textSecondary);
    final strong = TextStyle(fontSize: 12.5, color: palette.textPrimary, fontWeight: FontWeight.w800);
    final faces = post.likePreview.take(3).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ♥ 1.2K    ↗ Share                         ⌑
          Row(
            children: [
              _ActionButton(
                icon: liked ? AppIcons.heartFilled : AppIcons.heart,
                label: post.likeCount > 0 ? Fmt.compact(post.likeCount) : 'Like',
                active: liked,
                activeColor: const Color(0xFFEC2A78),
                bold: true,
                onTap: onLike,
              ),
              Builder(
                builder: (ctx) => _ActionButton(icon: AppIcons.share, label: 'Share', active: false, activeColor: AppColors.primary, onTap: () => onShare(ctx)),
              ),
              const Spacer(),
              _ActionButton(
                icon: post.isSaved ? AppIcons.bookmarkFilled : AppIcons.bookmark,
                label: '',
                active: post.isSaved,
                activeColor: AppColors.primary,
                onTap: onSave,
              ),
            ],
          ),
          // "Liked by Riya and 12 others" with their faces.
          if (post.likeCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
              child: GestureDetector(
                onTap: onShowLikers,
                child: Row(
                  children: [
                    if (faces.isNotEmpty) ...[
                      SizedBox(
                        width: 20.0 + (faces.length - 1) * 13,
                        height: 22,
                        child: Stack(
                          children: [
                            for (final (i, f) in faces.indexed)
                              Positioned(
                                left: i * 13.0,
                                child: Container(
                                  padding: const EdgeInsets.all(1.5),
                                  decoration: BoxDecoration(shape: BoxShape.circle, color: palette.surface),
                                  child: UserAvatar(initials: f.name.isEmpty ? '?' : f.name[0].toUpperCase(), imageUrl: f.avatarUrl, size: 19),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: text,
                          children: [
                            const TextSpan(text: 'Liked by '),
                            if (firstName != null) ...[
                              TextSpan(text: firstName, style: strong),
                              if (others > 0) ...[
                                const TextSpan(text: ' and '),
                                TextSpan(text: '${Fmt.compact(others)} ${others == 1 ? 'other' : 'others'}', style: strong),
                              ],
                            ] else
                              TextSpan(text: '${Fmt.compact(post.likeCount)} ${post.likeCount == 1 ? 'person' : 'people'}', style: strong),
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
        ],
      ),
    );
  }
}

/// Icon + small text (count / label), Instagram-style.
class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, required this.active, required this.activeColor, required this.onTap, this.bold = false});

  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  /// Bold count (likes).
  final bool bold;

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
            Icon(icon, size: 25, color: color)
                .animate(key: ValueKey(active), target: active ? 1 : 0)
                .scaleXY(begin: 1, end: 1.25, duration: 130.ms, curve: Curves.easeOut)
                .then()
                .scaleXY(begin: 1.25, end: 1, duration: 150.ms, curve: Curves.easeIn),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w700, color: bold ? context.palette.textPrimary : context.palette.textSecondary)),
              const SizedBox(width: 10),
            ],
          ],
        ),
      ),
    );
  }
}

/// Caption limited to 2 lines with an inline "more" / "less".
class _ExpandableCaption extends StatefulWidget {
  const _ExpandableCaption({required this.text, this.author});

  final String text;

  /// Shown bold before the caption.
  final String? author;

  @override
  State<_ExpandableCaption> createState() => _ExpandableCaptionState();
}

class _ExpandableCaptionState extends State<_ExpandableCaption> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final style = context.text.bodyMedium?.copyWith(color: context.palette.textPrimary, height: 1.4, fontSize: 13.5);
    final span = TextSpan(
      style: style,
      children: [
        if (widget.author != null) TextSpan(text: '${widget.author}  ', style: const TextStyle(fontWeight: FontWeight.w800)),
        TextSpan(text: widget.text),
      ],
    );
    return LayoutBuilder(
      builder: (context, box) {
        final painter = TextPainter(
          text: span,
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
                Text.rich(
                  span,
                  maxLines: _expanded ? null : 2,
                  overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                ),
                if (overflows)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _expanded ? 'less' : 'more',
                      style: context.text.labelLarge?.copyWith(color: context.palette.textTertiary, fontWeight: FontWeight.w700),
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