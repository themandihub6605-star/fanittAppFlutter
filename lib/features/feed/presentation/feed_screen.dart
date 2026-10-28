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
import '../../../core/widgets/report_sheet.dart';
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
    // Posts I reported and people I blocked stay hidden.
    final auth = context.read<AuthBloc>().state;
    final myId = auth is AuthAuthenticated ? auth.user.id : null;
    ReportedItems.instance.ensureLoaded(userId: myId);
    BlockedUsers.instance.ensureLoaded(userId: myId);
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
      setState(() => _hasMore = false);
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
    HapticFeedback.selectionClick();
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

  Future<bool> _addStory() => CreatePostScreen.open(context, mode: CreateMode.story);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final cubit = context.watch<LoadCubit<List<Post>>>();
    final state = cubit.state;
    final auth = context.watch<AuthBloc>().state;
    // Creators and brands can post (backend rule).
    final canPost = auth is AuthAuthenticated && (auth.user.role == UserRole.creator || auth.user.role == UserRole.brand);
    final showCreate = canPost && _isMainFeed;
    final firstName = auth is AuthAuthenticated ? auth.user.name.trim().split(' ').first : '';
    final posts = state.data;
    final canPop = Navigator.of(context).canPop();

    final slivers = <Widget>[
      // Header: big title + round buttons. Floats back in on scroll up.
      SliverAppBar(
        floating: true,
        snap: true,
        automaticallyImplyLeading: false,
        backgroundColor: palette.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 72,
        titleSpacing: _isMainFeed && !canPop ? AppSpacing.gutter : 12,
        title: _isMainFeed
            ? Row(
          children: [
            // Opened as a page (e.g. brands from Home) → a way back.
            if (canPop) ...[
              _RoundButton(icon: AppIcons.back, onTap: () => Navigator.of(context).maybePop()),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Feed', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.9, height: 1.1, color: palette.textPrimary)),
                  const SizedBox(height: 2),
                  Text(
                    firstName.isEmpty ? 'Fresh from creators and brands' : 'Hi $firstName — here’s what’s new',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: palette.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        )
            : Row(
          children: [
            _RoundButton(icon: AppIcons.back, onTap: () => Navigator.of(context).maybePop()),
            const SizedBox(width: 12),
            Text(widget.single ? 'Post' : 'Saved posts', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5, color: palette.textPrimary)),
          ],
        ),
        actions: [
          if (showCreate) _RoundButton(icon: AppIcons.plus, onTap: _create),
          if (_isMainFeed && auth is AuthAuthenticated) ...[
            const SizedBox(width: 10),
            const _RoundShell(child: ActivityButton()),
          ],
          const SizedBox(width: AppSpacing.gutter - 4),
        ],
      ),
    ];

    if (posts == null) {
      slivers.add(
        state.isFailure
            ? SliverFillRemaining(hasScrollBody: false, child: ErrorView(message: state.errorMessage ?? 'Something went wrong', onRetry: cubit.load))
            : const SliverToBoxAdapter(child: _FeedSkeleton()),
      );
    } else {
      if (_isMainFeed) {
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: StoriesBar(canPost: canPost, onAddStory: _addStory, refresh: _storiesTick),
            ),
          ),
        );
      }
      if (posts.isEmpty && _reels.isEmpty) {
        slivers.add(
          SliverFillRemaining(
            hasScrollBody: false,
            child: widget.savedOnly
                ? const MessageView(icon: AppIcons.bookmark, title: 'No saved posts', message: 'Tap the bookmark on any post to keep it here.')
                : const MessageView(icon: AppIcons.image, title: 'No posts yet', message: 'Follow creators and brands to fill your feed.'),
          ),
        );
      } else {
        slivers.add(
          SliverList.builder(
            itemCount: posts.length,
            itemBuilder: (context, i) {
              final card = _FeedPost(key: ValueKey(posts[i].id), post: posts[i], savedOnly: widget.savedOnly);
              final withReels = _isMainFeed && _reels.isNotEmpty && (i == _reelsAfter - 1 || (posts.length < _reelsAfter && i == posts.length - 1));
              final animated = i < 4 ? card.animate(delay: (60 * i).ms).fadeIn(duration: 350.ms).slideY(begin: 0.04, curve: Curves.easeOutCubic) : card;
              if (!withReels) return animated;
              return Column(mainAxisSize: MainAxisSize.min, children: [animated, ReelsRow(reels: _reels)]);
            },
          ),
        );
        if (posts.isEmpty && _isMainFeed) slivers.add(SliverToBoxAdapter(child: ReelsRow(reels: _reels)));
      }
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 8, AppSpacing.gutter, 28),
            child: Center(
              child: _loadingMore
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2))
                  : (_isMainFeed && !_hasMore && posts.length > 3 ? const _CaughtUp() : const SizedBox.shrink()),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        bottom: false,
        child: AppRefresh(
          onRefresh: _refresh,
          child: CustomScrollView(
            controller: _isMainFeed ? _scroll : null,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: slivers,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Post card
// ---------------------------------------------------------------------------

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
  bool _saveBusy = false;
  bool _burst = false;

  @override
  void initState() {
    super.initState();
    ReportedItems.instance.addListener(_onReported);
    BlockedUsers.instance.addListener(_onReported);
  }

  @override
  void dispose() {
    ReportedItems.instance.removeListener(_onReported);
    BlockedUsers.instance.removeListener(_onReported);
    super.dispose();
  }

  void _onReported() {
    if (mounted) setState(() {});
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
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) setState(() => _burst = false);
      });
      if (liked) return;
    }
    HapticFeedback.lightImpact();
    final cubit = context.read<LoadCubit<List<Post>>>();
    final posts = cubit.state.data ?? const <Post>[];
    // Optimistic update, corrected by the server's count.
    cubit.replace([
      for (final p in posts) p.id == widget.post.id ? p.withLike(me: me, liked: !liked, count: p.likeCount + (liked ? -1 : 1)) : p,
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

  Future<Duration?> _openViewer(int index, {Duration? position}) {
    return MediaViewerScreen.open(context, media: widget.post.media, index: index, position: position);
  }

  void _share(BuildContext ctx, String? myId) {
    final post = widget.post;
    ShareService.send(
      ctx,
      ShareService.post(id: post.id, creator: post.creatorName ?? (post.isBrand ? 'A brand' : 'A creator'), caption: post.caption, mine: post.creatorUserId == myId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final post = widget.post;
    final auth = context.watch<AuthBloc>().state;
    final myId = auth is AuthAuthenticated ? auth.user.id : null;
    final liked = myId != null && post.likedByUser(myId);
    final isOwnPost = myId != null && post.creatorUserId == myId;
    final name = post.creatorName ?? (post.isBrand ? 'Brand' : 'Creator');
    final hasMedia = post.media.isNotEmpty;
    void openAuthor() {
      if (post.authorRoute == null) return;
      HapticFeedback.selectionClick();
      context.push(post.authorRoute!);
    }

    // Reported by me → gone from my feed straight away.
    if (ReportedItems.instance.has(ReportType.post, post.id)) return const SizedBox.shrink();
    // Blocked either way → hidden.
    if (BlockedUsers.instance.isHidden(post.creatorUserId)) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.border),
        boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x0D101828), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: avatar · name ✓ · Brand tag · time — Follow
          Padding(
            padding: EdgeInsets.fromLTRB(14, 14, !isOwnPost && myId != null ? 2 : 12, 12),
            child: Row(
              children: [
                GestureDetector(
                  onTap: openAuthor,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: post.isFollowingCreator ? AppColors.primary.withValues(alpha: 0.45) : palette.border, width: 1.5)),
                    child: UserAvatar(initials: name.substring(0, 1).toUpperCase(), imageUrl: post.creatorAvatarUrl, size: 38),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: openAuthor,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: palette.textPrimary)),
                            ),
                            if (post.verified) ...[
                              const SizedBox(width: 4),
                              const Icon(AppIcons.sealCheck, size: 15, color: AppColors.info),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (post.isBrand) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(color: AppColors.info.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(5)),
                                child: const Text('Brand', style: TextStyle(color: AppColors.info, fontSize: 10, fontWeight: FontWeight.w800)),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Icon(AppIcons.clock, size: 11, color: palette.textTertiary),
                            const SizedBox(width: 3),
                            Text(Fmt.relative(post.createdAt), style: TextStyle(fontSize: 12, color: palette.textTertiary)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (!isOwnPost && post.creatorId != null) ...[
                  const SizedBox(width: 8),
                  _FollowButton(following: post.isFollowingCreator, busy: _followBusy, onTap: _toggleFollow),
                ],
                // ⋮ Report / Block (needed for App Store UGC rules).
                if (!isOwnPost && myId != null)
                  IconButton(
                    tooltip: 'More',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(AppIcons.dotsThree, color: palette.textSecondary, size: 22),
                    onPressed: () => showContentActions(context, type: ReportType.post, id: post.id, name: name, userId: post.creatorUserId),
                  ),
              ],
            ),
          ),

          // Caption first — reads like a story, then the picture.
          if (post.caption.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, hasMedia ? 12 : 6),
              child: _ExpandableCaption(text: post.caption, large: !hasMedia),
            ),

          // Media — framed inside the card with soft corners.
          if (hasMedia)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: GestureDetector(
                onDoubleTap: () => _toggleLike(fromDoubleTap: true),
                child: PostMediaGrid(
                  media: post.media,
                  radius: 18,
                  onOpen: _openViewer,
                  overlay: Center(
                    child: AnimatedScale(
                      scale: _burst ? 1 : 0,
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutBack,
                      child: AnimatedOpacity(
                        opacity: _burst ? 1 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          width: 104,
                          height: 104,
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), shape: BoxShape.circle),
                          child: const Icon(AppIcons.heartFilled, size: 60, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Like · Share ............ Save
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                _ActionPill(
                  icon: liked ? AppIcons.heartFilled : AppIcons.heart,
                  label: post.likeCount > 0 ? Fmt.compact(post.likeCount) : 'Like',
                  active: liked,
                  onTap: _toggleLike,
                ),
                const SizedBox(width: 8),
                Builder(builder: (ctx) => _ActionPill(icon: AppIcons.share, label: 'Share', active: false, onTap: () => _share(ctx, myId))),
                const Spacer(),
                _SaveButton(saved: post.isSaved, onTap: _toggleSave),
              ],
            ),
          ),

          // Liked by …
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: post.likeCount > 0
                ? _LikedBy(post: post, myId: myId, onTap: () => showLikersSheet(context, postId: post.id, likeCount: post.likeCount))
                : Text('Be the first to like this', style: TextStyle(fontSize: 12.5, color: palette.textTertiary)),
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
    final palette = context.palette;
    final color = following ? palette.textSecondary : AppColors.primary;
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: following ? palette.background : AppColors.primary.withValues(alpha: context.isDark ? 0.18 : 0.07),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: following ? palette.border : AppColors.primary.withValues(alpha: 0.35)),
        ),
        child: busy
            ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: color))
            : Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(following ? AppIcons.check : AppIcons.plus, size: 13, color: color),
            const SizedBox(width: 4),
            Text(following ? 'Following' : 'Follow', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      ),
    );
  }
}

/// Soft pill: icon + count / label.
class _ActionPill extends StatelessWidget {
  const _ActionPill({required this.icon, required this.label, required this.active, required this.onTap});

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = active ? AppColors.primary : palette.textPrimary;
    return Material(
      color: active ? AppColors.primary.withValues(alpha: context.isDark ? 0.18 : 0.07) : palette.background,
      shape: StadiumBorder(side: BorderSide(color: active ? AppColors.primary.withValues(alpha: 0.3) : palette.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19, color: color)
                  .animate(key: ValueKey(active), target: active ? 1 : 0)
                  .scaleXY(begin: 1, end: 1.3, duration: 130.ms, curve: Curves.easeOut)
                  .then()
                  .scaleXY(begin: 1.3, end: 1, duration: 160.ms, curve: Curves.easeIn),
              const SizedBox(width: 6),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(a), child: child)),
                child: Text(label, key: ValueKey(label), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: active ? AppColors.primary : palette.textPrimary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.saved, required this.onTap});

  final bool saved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: saved ? AppColors.primary.withValues(alpha: context.isDark ? 0.18 : 0.07) : palette.background,
      shape: CircleBorder(side: BorderSide(color: saved ? AppColors.primary.withValues(alpha: 0.3) : palette.border)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(saved ? AppIcons.bookmarkFilled : AppIcons.bookmark, size: 18, color: saved ? AppColors.primary : palette.textPrimary)
              .animate(key: ValueKey(saved), target: saved ? 1 : 0)
              .scaleXY(begin: 1, end: 1.25, duration: 130.ms)
              .then()
              .scaleXY(begin: 1.25, end: 1, duration: 150.ms),
        ),
      ),
    );
  }
}

/// Overlapping faces + "Liked by Riya and 12 others".
class _LikedBy extends StatelessWidget {
  const _LikedBy({required this.post, required this.myId, required this.onTap});

  final Post post;
  final String? myId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final faces = post.likePreview.take(3).toList();
    final first = faces.isEmpty ? null : faces.first;
    final firstName = first == null ? null : (first.id == myId ? 'You' : first.name);
    final others = post.likeCount - (first == null ? 0 : 1);
    final text = TextStyle(fontSize: 12.5, color: palette.textSecondary);
    final strong = text.copyWith(color: palette.textPrimary, fontWeight: FontWeight.w800);
    const size = 22.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        children: [
          if (faces.isNotEmpty) ...[
            SizedBox(
              width: size + (faces.length - 1) * 14 + 4,
              height: size + 4,
              child: Stack(
                children: [
                  for (var i = faces.length - 1; i >= 0; i--)
                    Positioned(
                      left: i * 14.0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(color: palette.surface, shape: BoxShape.circle),
                        child: UserAvatar(initials: faces[i].name.isEmpty ? '?' : faces[i].name.substring(0, 1).toUpperCase(), imageUrl: faces[i].avatarUrl, size: size),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
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
    );
  }
}

/// Caption limited to a few lines with "See more" / "See less".
class _ExpandableCaption extends StatefulWidget {
  const _ExpandableCaption({required this.text, this.large = false});

  final String text;

  /// Text-only post: bigger type, more lines before cutting.
  final bool large;

  @override
  State<_ExpandableCaption> createState() => _ExpandableCaptionState();
}

class _ExpandableCaptionState extends State<_ExpandableCaption> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final lines = widget.large ? 6 : 3;
    final style = TextStyle(
      fontSize: widget.large ? 16 : 14.5,
      height: 1.45,
      fontWeight: widget.large ? FontWeight.w500 : FontWeight.w400,
      color: palette.textPrimary,
    );
    return LayoutBuilder(
      builder: (context, box) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: lines,
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
                Text(widget.text, style: style, maxLines: _expanded ? null : lines, overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis),
                if (overflows)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_expanded ? 'See less' : 'See more', style: TextStyle(fontSize: 13, color: palette.textSecondary, fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Small pieces
// ---------------------------------------------------------------------------

/// White round button with a thin border.
class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surface,
      shape: CircleBorder(side: BorderSide(color: palette.border)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: SizedBox(width: 42, height: 42, child: Icon(icon, size: 19, color: palette.textPrimary)),
      ),
    );
  }
}

/// Same white circle around a widget that brings its own tap (Activity ♥).
class _RoundShell extends StatelessWidget {
  const _RoundShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(color: palette.surface, shape: BoxShape.circle, border: Border.all(color: palette.border)),
      child: ClipOval(
        child: IconTheme.merge(
          data: const IconThemeData(size: 20),
          child: Theme(
            data: Theme.of(context).copyWith(
              iconButtonTheme: IconButtonThemeData(
                style: IconButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(42, 42), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              ),
            ),
            child: Center(child: Transform.scale(scale: 0.8, child: child)),
          ),
        ),
      ),
    );
  }
}

class _CaughtUp extends StatelessWidget {
  const _CaughtUp();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: const Icon(AppIcons.checkCircle, color: AppColors.success, size: 24),
        ),
        const SizedBox(height: 10),
        Text('You’re all caught up', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: palette.textPrimary)),
        const SizedBox(height: 2),
        Text('You’ve seen all the new posts', style: TextStyle(fontSize: 12.5, color: palette.textSecondary)),
      ],
    ).animate().fadeIn(duration: 400.ms);
  }
}

class _FeedSkeleton extends StatelessWidget {
  const _FeedSkeleton();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget box(double w, double h, {double r = 10, bool circle = false}) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(color: palette.surfaceMuted, shape: circle ? BoxShape.circle : BoxShape.rectangle, borderRadius: circle ? null : BorderRadius.circular(r)),
    );
    final width = MediaQuery.sizeOf(context).width;
    Widget card() => Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: palette.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [box(42, 42, circle: true), const SizedBox(width: 10), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [box(120, 12), const SizedBox(height: 6), box(70, 10)])]),
          const SizedBox(height: 14),
          box(width * 0.7, 12),
          const SizedBox(height: 12),
          box(double.infinity, width * 0.8, r: 18),
          const SizedBox(height: 12),
          Row(children: [box(70, 34, r: 99), const SizedBox(width: 8), box(80, 34, r: 99), const Spacer(), box(38, 38, circle: true)]),
        ],
      ),
    );
    return Column(
      children: [
        SizedBox(
          height: 104,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [for (var i = 0; i < 6; i++) Padding(padding: const EdgeInsets.only(right: 14), child: Column(children: [box(64, 64, circle: true), const SizedBox(height: 8), box(48, 8)]))],
          ),
        ),
        const SizedBox(height: 6),
        card(),
        card(),
      ],
    ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1200.ms, color: palette.surface.withValues(alpha: 0.6));
  }
}