import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/user_avatar.dart';
import '../data/story_repository.dart';

/// Full-screen stories: tap right / left for next / previous, hold to
/// pause, swipe sideways for the next person, swipe down to close.
/// Returns the groups with seen flags updated.
class StoryViewerScreen extends StatefulWidget {
  const StoryViewerScreen({super.key, required this.groups, required this.initialGroup});

  final List<StoryGroup> groups;
  final int initialGroup;

  static Future<List<StoryGroup>?> open(BuildContext context, {required List<StoryGroup> groups, required int index}) {
    return Navigator.of(context, rootNavigator: true).push<List<StoryGroup>>(
      PageRouteBuilder<List<StoryGroup>>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, _, _) => StoryViewerScreen(groups: groups, initialGroup: index),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(a), child: child)),
      ),
    );
  }

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> {
  late final PageController _pages = PageController(initialPage: widget.initialGroup);
  late List<StoryGroup> _groups = [...widget.groups];
  late int _group = widget.initialGroup;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pages.dispose();
    super.dispose();
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    Navigator.of(context).pop(_groups);
  }

  void _nextGroup() {
    if (_group >= _groups.length - 1) return _close();
    _pages.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  void _prevGroup() {
    if (_group == 0) return;
    _pages.previousPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  void _seen(int groupIndex, String storyId) {
    final g = _groups[groupIndex];
    if (g.stories.firstWhere((s) => s.id == storyId).seen) return;
    setState(() => _groups[groupIndex] = g.withSeen(storyId));
    if (!g.isMine) StoryRepository.i.markSeen(storyId);
  }

  void _removed(int groupIndex, String storyId) {
    final g = _groups[groupIndex];
    final left = [for (final s in g.stories) if (s.id != storyId) s];
    if (left.isEmpty) {
      _groups = [for (var i = 0; i < _groups.length; i++) if (i != groupIndex) _groups[i]];
      _close();
      return;
    }
    setState(() => _groups[groupIndex] = StoryGroup(author: g.author, stories: left, isMine: g.isMine));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) > 300) _close();
          },
          child: PageView.builder(
            controller: _pages,
            itemCount: _groups.length,
            onPageChanged: (i) => setState(() => _group = i),
            itemBuilder: (context, i) => _GroupPlayer(
              key: ValueKey(_groups[i].author.userId),
              group: _groups[i],
              active: i == _group,
              onDone: _nextGroup,
              onBack: _prevGroup,
              onClose: _close,
              onSeen: (id) => _seen(i, id),
              onRemoved: (id) => _removed(i, id),
            ),
          ),
        ),
      ),
    );
  }
}

/// One person's stories with the progress bars on top.
class _GroupPlayer extends StatefulWidget {
  const _GroupPlayer({
    super.key,
    required this.group,
    required this.active,
    required this.onDone,
    required this.onBack,
    required this.onClose,
    required this.onSeen,
    required this.onRemoved,
  });

  final StoryGroup group;
  final bool active;
  final VoidCallback onDone;
  final VoidCallback onBack;
  final VoidCallback onClose;
  final ValueChanged<String> onSeen;
  final ValueChanged<String> onRemoved;

  @override
  State<_GroupPlayer> createState() => _GroupPlayerState();
}

class _GroupPlayerState extends State<_GroupPlayer> with SingleTickerProviderStateMixin {
  static const _photoDuration = Duration(seconds: 5);

  late int _index = widget.group.firstUnseen;
  late final AnimationController _progress = AnimationController(vsync: this)..addStatusListener(_onProgressDone);
  VideoPlayerController? _video;
  bool _loading = false;
  bool _paused = false;

  Story get _story => widget.group.stories[_index.clamp(0, widget.group.stories.length - 1)];

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(covariant _GroupPlayer old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _start();
    } else if (!widget.active && old.active) {
      _progress.stop();
      _video?.pause();
    }
    if (_index >= widget.group.stories.length) _index = widget.group.stories.length - 1;
  }

  @override
  void dispose() {
    _progress.dispose();
    _video?.dispose();
    super.dispose();
  }

  void _onProgressDone(AnimationStatus status) {
    if (status == AnimationStatus.completed) _next();
  }

  Future<void> _start() async {
    _progress.stop();
    _progress.value = 0;
    final old = _video;
    _video = null;
    old?.dispose();
    final story = _story;
    // After this frame — the parent may be building right now.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onSeen(story.id);
    });

    if (!story.isVideo) {
      setState(() => _loading = false);
      _progress.duration = _photoDuration;
      if (!_paused) _progress.forward(from: 0);
      return;
    }
    setState(() => _loading = true);
    final c = VideoPlayerController.networkUrl(Uri.parse(story.url));
    _video = c;
    try {
      await c.initialize();
    } catch (_) {
      if (!mounted || _video != c) return;
      setState(() => _loading = false);
      _progress.duration = _photoDuration; // show the poster, then move on
      _progress.forward(from: 0);
      return;
    }
    if (!mounted || _video != c) return;
    final length = c.value.duration;
    _progress.duration = length.inMilliseconds > 0 ? length : _photoDuration;
    setState(() => _loading = false);
    if (widget.active && !_paused) {
      await c.play();
      if (!mounted || _video != c) return;
      _progress.forward(from: 0);
    }
  }

  void _next() {
    if (_index < widget.group.stories.length - 1) {
      setState(() => _index++);
      _start();
    } else {
      widget.onDone();
    }
  }

  void _prev() {
    if (_index > 0) {
      setState(() => _index--);
      _start();
    } else {
      widget.onBack();
      // First story of the first person: just restart it.
      if (_progress.duration != null && !_loading) {
        _video?.seekTo(Duration.zero);
        if (!_paused) _progress.forward(from: 0);
      }
    }
  }

  void _pause(bool pause) {
    setState(() => _paused = pause);
    if (pause) {
      _progress.stop();
      _video?.pause();
    } else if (!_loading) {
      _progress.forward();
      _video?.play();
    }
  }

  Future<void> _ownerMenu() async {
    _pause(true);
    final story = _story;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(AppIcons.eye), title: Text('Seen by ${story.viewCount}'), onTap: () => Navigator.pop(ctx, 'viewers')),
            ListTile(leading: const Icon(AppIcons.trash, color: Colors.red), title: const Text('Delete story', style: TextStyle(color: Colors.red)), onTap: () => Navigator.pop(ctx, 'delete')),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'viewers') {
      await _showViewers(story);
    } else if (action == 'delete') {
      final ok = await confirmAction(context, title: 'Delete this story?', message: 'It disappears for everyone right away.', confirmLabel: 'Delete', destructive: true);
      if (ok) {
        try {
          await StoryRepository.i.delete(story.id);
          if (!mounted) return;
          AppSnackbar.success(context, 'Story deleted');
          final wasLast = widget.group.stories.length == 1;
          widget.onRemoved(story.id);
          if (wasLast) return;
          if (_index >= widget.group.stories.length - 1) _index = (widget.group.stories.length - 2).clamp(0, 999);
          _paused = false;
          // The parent rebuilds this player with the story removed first.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _start();
          });
          return;
        } on ApiException catch (e) {
          if (mounted) AppSnackbar.error(context, e.displayMessage);
        }
      }
    }
    if (mounted) _pause(false);
  }

  Future<void> _showViewers(Story story) async {
    List<StoryViewer> viewers = const [];
    try {
      viewers = await StoryRepository.i.viewers(story.id);
    } catch (_) {}
    if (!mounted) return;
    // Tap a creator / brand → their profile (opens over the story; back returns here).
    final picked = await showModalBottomSheet<StoryViewer>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: 380,
          child: viewers.isEmpty
              ? const Center(child: Text('No views yet'))
              : ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Text('Seen by ${viewers.length}', style: Theme.of(ctx).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              ),
              for (final v in viewers)
                ListTile(
                  onTap: v.hasProfile ? () => Navigator.pop(ctx, v) : null,
                  leading: UserAvatar(initials: v.user.name.isEmpty ? '?' : v.user.name[0].toUpperCase(), imageUrl: v.user.avatarUrl, size: 40),
                  title: Text(v.user.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(!v.hasProfile ? 'Fan' : (v.isBrand ? 'Brand' : 'Creator') + (v.isFollowing ? ' · Following' : '')),
                  trailing: v.hasProfile ? const Icon(AppIcons.chevronRight, size: 18) : null,
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await context.push(picked.isBrand ? AppRoutes.brandProfile(picked.slug) : AppRoutes.creatorProfile(picked.slug));
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    final story = _story;
    final video = _video;
    final poster = story.isVideo ? story.thumbnailUrl : story.url;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        final w = MediaQuery.sizeOf(context).width;
        d.localPosition.dx < w * 0.3 ? _prev() : _next();
      },
      onLongPressStart: (_) => _pause(true),
      onLongPressEnd: (_) => _pause(false),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Media
          if (video != null && video.value.isInitialized)
            FittedBox(fit: BoxFit.contain, child: SizedBox(width: video.value.size.width, height: video.value.size.height, child: VideoPlayer(video)))
          else if (poster.isNotEmpty)
            AppNetworkImage(url: poster, fit: BoxFit.contain),
          if (_loading) const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4)),

          // Top shade + bars + author
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 140,
            child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x99000000), Color(0x00000000)]))),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      for (var i = 0; i < g.stories.length; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: SizedBox(
                              height: 2.6,
                              child: i == _index
                                  ? AnimatedBuilder(
                                animation: _progress,
                                builder: (_, _) => LinearProgressIndicator(value: _progress.value, backgroundColor: Colors.white30, valueColor: const AlwaysStoppedAnimation(Colors.white)),
                              )
                                  : ColoredBox(color: i < _index ? Colors.white : Colors.white30),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            final router = GoRouter.of(context);
                            widget.onClose();
                            router.push(g.author.profileRoute);
                          },
                          child: Row(
                            children: [
                              UserAvatar(initials: g.author.initials, imageUrl: g.author.avatarUrl, size: 34),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(g.isMine ? 'Your story' : g.author.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                              ),
                              if (g.author.verified) ...[
                                const SizedBox(width: 4),
                                const Icon(AppIcons.sealCheck, size: 14, color: Color(0xFF60A5FA)),
                              ],
                              const SizedBox(width: 8),
                              Text(Fmt.relative(story.createdAt), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                      if (g.isMine) IconButton(tooltip: 'More', icon: const Icon(AppIcons.dotsThree, color: Colors.white), onPressed: _ownerMenu),
                      IconButton(tooltip: 'Close', icon: const Icon(AppIcons.close, color: Colors.white), onPressed: widget.onClose),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Caption + my view count
          if (story.caption.isNotEmpty || g.isMine)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(16, 40, 16, 20 + MediaQuery.paddingOf(context).bottom),
                decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xAA000000), Color(0x00000000)])),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (story.caption.isNotEmpty) Text(story.caption, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.35)),
                    if (g.isMine) ...[
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () async {
                          _pause(true);
                          await _showViewers(story);
                          if (mounted) _pause(false);
                        },
                        child: Row(
                          children: [
                            const Icon(AppIcons.eye, color: Colors.white, size: 18),
                            const SizedBox(width: 6),
                            Text('${story.viewCount} ${story.viewCount == 1 ? 'view' : 'views'}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}