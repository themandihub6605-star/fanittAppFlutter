import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../../core/di/injection.dart';
import '../../../core/models/common_models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/services/share_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/stream_video_player.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../brands/data/brands_repository.dart';
import '../../content/data/content_repository.dart';
import '../../creators/data/creators_repository.dart';
import 'likers_sheet.dart';

/// Full-screen reels: swipe up / down, one reel at a time, playing with
/// sound. Like (double tap too), save, share, follow and the caption are
/// on the video. [startId] opens the player on that reel.
class ReelsScreen extends StatefulWidget {
  const ReelsScreen({super.key, this.startId});

  final String? startId;

  static Future<void> open(BuildContext context, {String? startId}) {
    // Pause any feed video before the reels take over.
    VideoPlaybackCoordinator.instance.pauseActive();
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(builder: (_) => ReelsScreen(startId: startId)),
    );
  }

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
  final _pages = PageController();
  final List<Post> _reels = [];
  final Set<String> _viewed = {};
  int _page = 0;
  int _current = 0;
  bool _hasMore = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    _loadMore();
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final next = _page + 1;
      final res = await sl<ContentRepository>().reels(page: next, start: widget.startId);
      if (!mounted) return;
      final known = _reels.map((r) => r.id).toSet();
      setState(() {
        _page = next;
        _reels.addAll(res.items.where((r) => !known.contains(r.id)));
        _hasMore = res.hasMore;
        _loading = false;
      });
      if (_page == 1 && _reels.isNotEmpty) _countView(0);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.displayMessage;
        });
      }
    }
  }

  void _countView(int i) {
    final id = _reels[i].id;
    if (_viewed.add(id)) sl<ContentRepository>().viewReel(id);
  }

  void _onPage(int i) {
    setState(() => _current = i);
    _countView(i);
    if (i >= _reels.length - 3) _loadMore();
  }

  void _replace(Post updated) {
    if (!mounted) return;
    final i = _reels.indexWhere((r) => r.id == updated.id);
    if (i >= 0) setState(() => _reels[i] = updated);
  }

  /// Follow changes apply to every reel by the same author.
  void _setFollowing(Post reel, bool following) {
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < _reels.length; i++) {
        if (_reels[i].creatorId == reel.creatorId) _reels[i] = _reels[i].copyWith(isFollowingCreator: following);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text('Reels', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        ),
        body: _reels.isEmpty
            ? Center(
          child: _loading
              ? const CircularProgressIndicator(color: Colors.white)
              : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(AppIcons.video, color: Colors.white54, size: 48),
              const SizedBox(height: 12),
              Text(_error ?? 'No reels yet', style: const TextStyle(color: Colors.white70)),
              if (_error != null) TextButton(onPressed: _loadMore, child: const Text('Try again')),
            ],
          ),
        )
            : PageView.builder(
          controller: _pages,
          scrollDirection: Axis.vertical,
          itemCount: _reels.length,
          onPageChanged: _onPage,
          itemBuilder: (context, i) => _ReelPage(
            key: ValueKey(_reels[i].id),
            reel: _reels[i],
            active: i == _current,
            onChanged: _replace,
            onFollowChanged: (f) => _setFollowing(_reels[i], f),
          ),
        ),
      ),
    );
  }
}

class _ReelPage extends StatefulWidget {
  const _ReelPage({super.key, required this.reel, required this.active, required this.onChanged, required this.onFollowChanged});

  final Post reel;
  final bool active;
  final ValueChanged<Post> onChanged;
  final ValueChanged<bool> onFollowChanged;

  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage> {
  VideoPlayerController? _video;
  bool _failed = false;
  bool _pausedByUser = false;
  bool _heart = false;
  bool _captionOpen = false;
  bool _busy = false;

  Post get reel => widget.reel;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final url = reel.cover?.url;
    if (url == null) return;
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    _video = c;
    try {
      await c.initialize();
      await c.setLooping(true);
      if (!mounted) return;
      setState(() {});
      if (widget.active) c.play();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didUpdateWidget(covariant _ReelPage old) {
    super.didUpdateWidget(old);
    final c = _video;
    if (c == null || !c.value.isInitialized) return;
    if (widget.active && !old.active) {
      _pausedByUser = false;
      c.seekTo(Duration.zero);
      c.play();
    } else if (!widget.active && old.active) {
      c.pause();
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  String? get _myId {
    final auth = context.read<AuthBloc>().state;
    return auth is AuthAuthenticated ? auth.user.id : null;
  }

  void _togglePlay() {
    final c = _video;
    if (c == null || !c.value.isInitialized) return;
    setState(() => _pausedByUser = c.value.isPlaying);
    c.value.isPlaying ? c.pause() : c.play();
  }

  Future<void> _like({bool fromDoubleTap = false}) async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) return;
    final me = UserLite(id: auth.user.id, name: auth.user.name, avatarUrl: auth.user.avatarUrl, role: auth.user.role);
    final liked = reel.likedByUser(me.id);
    if (fromDoubleTap) {
      setState(() => _heart = true);
      Future.delayed(const Duration(milliseconds: 650), () {
        if (mounted) setState(() => _heart = false);
      });
      if (liked) return;
    }
    if (_busy) return;
    HapticFeedback.lightImpact();
    final before = reel;
    widget.onChanged(reel.withLike(me: me, liked: !liked, count: reel.likeCount + (liked ? -1 : 1)));
    _busy = true;
    try {
      final r = await sl<ContentRepository>().toggleLike(before.id);
      widget.onChanged(before.withLike(me: me, liked: r.liked, count: r.likeCount));
    } on ApiException catch (e) {
      widget.onChanged(before);
      if (mounted) AppSnackbar.error(context, e.displayMessage);
    } finally {
      _busy = false;
    }
  }

  Future<void> _save() async {
    HapticFeedback.selectionClick();
    final before = reel;
    widget.onChanged(reel.copyWith(isSaved: !reel.isSaved));
    try {
      final saved = await sl<ContentRepository>().toggleSave(before.id);
      widget.onChanged(before.copyWith(isSaved: saved));
      if (mounted && saved) AppSnackbar.success(context, 'Saved');
    } on ApiException catch (e) {
      widget.onChanged(before);
      if (mounted) AppSnackbar.error(context, e.displayMessage);
    }
  }

  Future<void> _follow() async {
    final id = reel.creatorId;
    if (id == null) return;
    HapticFeedback.selectionClick();
    final was = reel.isFollowingCreator;
    widget.onFollowChanged(!was);
    try {
      final now = reel.isBrand ? await sl<BrandsRepository>().toggleFollow(id) : (await sl<CreatorsRepository>().toggleFollow(id)).following;
      widget.onFollowChanged(now);
    } on ApiException catch (e) {
      widget.onFollowChanged(was);
      if (mounted) AppSnackbar.error(context, e.displayMessage);
    }
  }

  void _openAuthor() {
    final route = reel.authorRoute;
    if (route == null) return;
    _video?.pause();
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push(route);
  }

  @override
  Widget build(BuildContext context) {
    final c = _video;
    final myId = _myId;
    final liked = myId != null && reel.likedByUser(myId);
    final mine = myId != null && reel.creatorUserId == myId;
    final m = reel.cover;
    final poster = m == null ? '' : (m.thumbnailUrl.isNotEmpty ? m.thumbnailUrl : StreamVideoPlayer.thumbnailFor(m.url) ?? '');
    final name = reel.creatorName ?? '';
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Video
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _togglePlay,
          onDoubleTap: () => _like(fromDoubleTap: true),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (poster.isNotEmpty) AppNetworkImage(url: poster, fit: BoxFit.cover),
              if (c != null && c.value.isInitialized)
                FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c))),
              if (c == null || (!c.value.isInitialized && !_failed)) const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4)),
              if (_failed)
                const Center(child: Text('Couldn’t play this reel.\nIt may still be processing.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70))),
              if (_pausedByUser)
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), shape: BoxShape.circle),
                    child: const Icon(AppIcons.play, color: Colors.white, size: 34),
                  ),
                ),
              IgnorePointer(
                child: Center(
                  child: AnimatedScale(
                    scale: _heart ? 1 : 0,
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutBack,
                    child: const Icon(AppIcons.heartFilled, size: 110, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Bottom shade
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 260,
          child: IgnorePointer(
            child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xB3000000), Color(0x00000000)]))),
          ),
        ),

        // Actions on the right
        Positioned(
          right: 10,
          bottom: 24 + bottomInset,
          child: Column(
            children: [
              _SideAction(
                icon: liked ? AppIcons.heartFilled : AppIcons.heart,
                color: liked ? AppColors.error : Colors.white,
                label: Fmt.compact(reel.likeCount),
                onTap: () => _like(),
                onLongPress: reel.likeCount > 0 ? () => showLikersSheet(context, postId: reel.id, likeCount: reel.likeCount) : null,
              ),
              const SizedBox(height: 18),
              _SideAction(icon: reel.isSaved ? AppIcons.bookmarkFilled : AppIcons.bookmark, label: reel.isSaved ? 'Saved' : 'Save', onTap: _save),
              const SizedBox(height: 18),
              Builder(
                builder: (ctx) => _SideAction(
                  icon: AppIcons.share,
                  label: 'Share',
                  onTap: () => ShareService.send(ctx, ShareService.post(id: reel.id, creator: name.isEmpty ? 'A creator' : name, caption: reel.caption, mine: mine)),
                ),
              ),
              if (reel.viewCount > 0) ...[
                const SizedBox(height: 18),
                _SideAction(icon: AppIcons.eye, label: Fmt.compact(reel.viewCount), onTap: () {}),
              ],
            ],
          ),
        ),

        // Author + caption
        Positioned(
          left: 14,
          right: 76,
          bottom: 22 + bottomInset,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: GestureDetector(
                      onTap: _openAuthor,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          UserAvatar(initials: name.isEmpty ? '?' : name[0].toUpperCase(), imageUrl: reel.creatorAvatarUrl, size: 34),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14.5)),
                          ),
                          if (reel.verified) ...[
                            const SizedBox(width: 4),
                            const Icon(AppIcons.sealCheck, size: 14, color: Color(0xFF60A5FA)),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (!mine && reel.creatorId != null) ...[
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _follow,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: reel.isFollowingCreator ? Colors.transparent : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white),
                        ),
                        child: Text(
                          reel.isFollowingCreator ? 'Following' : 'Follow',
                          style: TextStyle(color: reel.isFollowingCreator ? Colors.white : Colors.black, fontWeight: FontWeight.w800, fontSize: 12.5),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (reel.caption.isNotEmpty) ...[
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => setState(() => _captionOpen = !_captionOpen),
                  child: Text(
                    reel.caption,
                    maxLines: _captionOpen ? 8 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.35),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              if (c != null && c.value.isInitialized)
                VideoProgressIndicator(
                  c,
                  allowScrubbing: true,
                  padding: EdgeInsets.zero,
                  colors: const VideoProgressColors(playedColor: Colors.white, bufferedColor: Colors.white38, backgroundColor: Colors.white12),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SideAction extends StatelessWidget {
  const _SideAction({required this.icon, required this.label, required this.onTap, this.color = Colors.white, this.onLongPress});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        children: [
          Icon(icon, color: color, size: 30, shadows: const [Shadow(color: Colors.black45, blurRadius: 8)]),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, shadows: [Shadow(color: Colors.black45, blurRadius: 6)])),
        ],
      ),
    );
  }
}