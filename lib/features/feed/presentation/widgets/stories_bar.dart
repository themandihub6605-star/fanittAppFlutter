// File: lib/features/feed/presentation/widgets/stories_bar.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../store/data/store_repository.dart';
import '../../data/story_repository.dart';
import '../story_viewer_screen.dart';

// LIVE ring: spins, so a live creator stands out from normal stories.
const _liveRing = SweepGradient(colors: [Color(0xFFFF3B5C), AppColors.primary, Color(0xFFFFB020), Color(0xFFEC2A78), Color(0xFFFF3B5C)]);

const _ring = LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFFF4511E), Color(0xFFEC2A78), Color(0xFF7C4DFF)]);

/// Story cards at the top of the feed (Facebook style). "Create story" /
/// "Your story" first for creators and brands, then people you follow who
/// are LIVE right now (LIVE tag → opens the live), then their stories.
class StoriesBar extends StatefulWidget {
  const StoriesBar({super.key, required this.canPost, required this.onAddStory, this.refresh});

  final bool canPost;
  final Future<bool> Function() onAddStory;

  /// Fires when the feed is pulled to refresh.
  final Listenable? refresh;

  @override
  State<StoriesBar> createState() => _StoriesBarState();
}

class _StoriesBarState extends State<StoriesBar> {
  List<StoryGroup>? _groups;
  List<({LiveStream live, String hostId})> _lives = const [];

  @override
  void initState() {
    super.initState();
    _load();
    widget.refresh?.addListener(_load);
  }

  @override
  void dispose() {
    widget.refresh?.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    _loadLives();
    try {
      final groups = await StoryRepository.i.feed();
      if (mounted) setState(() => _groups = groups);
    } catch (_) {
      if (mounted && _groups == null) setState(() => _groups = const []);
    }
  }

  /// Followed creators who are live now (quietly empty on any error).
  Future<void> _loadLives() async {
    try {
      final lives = await sl<StoreRepository>().followingLives();
      if (mounted) setState(() => _lives = lives.where((l) => l.live.isLive && !l.live.isHost).toList());
    } catch (_) {
      // Stories still show.
    }
  }

  Future<void> _openLive(LiveStream live) async {
    HapticFeedback.selectionClick();
    await context.push(AppRoutes.liveDetail(live.id));
    if (mounted) _loadLives();
  }

  Future<void> _open(int index) async {
    final groups = _groups ?? const <StoryGroup>[];
    HapticFeedback.selectionClick();
    final updated = await StoryViewerScreen.open(context, groups: groups, index: index);
    if (!mounted) return;
    if (updated != null) setState(() => _groups = updated);
    if (updated == null || updated.length != groups.length) _load();
  }

  Future<void> _add() async {
    if (await widget.onAddStory() && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    if (groups == null) return const SizedBox(height: _StoryCard.height + 20);
    final mineIndex = groups.indexWhere((g) => g.isMine);
    final liveHosts = {for (final l in _lives) l.hostId};
    // Someone live shows once — as the LIVE card, not also as a story.
    final others = [for (var i = 0; i < groups.length; i++) if (i != mineIndex && !liveHosts.contains(groups[i].author.userId)) i];
    if (!widget.canPost && others.isEmpty && _lives.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: _StoryCard.height + 20,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        children: [
          if (widget.canPost)
            mineIndex >= 0
                ? _StoryCard(
              name: 'Your story',
              avatarUrl: groups[mineIndex].author.avatarUrl,
              initials: groups[mineIndex].author.initials,
              posterUrl: _posterOf(groups[mineIndex]),
              unseen: false,
              onTap: () => _open(mineIndex),
              onAdd: _add,
            )
                : _CreateStoryCard(onTap: _add),
          for (final (i, l) in _lives.indexed)
            _StoryCard(
              name: l.live.hostName.isNotEmpty ? l.live.hostName : (l.live.storeName ?? 'Live'),
              avatarUrl: _avatarFor(l, groups),
              initials: (l.live.hostName.trim().isEmpty ? '?' : l.live.hostName.trim()[0].toUpperCase()),
              posterUrl: l.live.coverUrl.isNotEmpty ? l.live.coverUrl : _avatarFor(l, groups),
              unseen: true,
              live: true,
              onTap: () => _openLive(l.live),
            ).animate(delay: (60 * i.clamp(0, 6)).ms).fadeIn(duration: 300.ms),
          for (final i in others)
            _StoryCard(
              name: groups[i].author.name,
              avatarUrl: groups[i].author.avatarUrl,
              initials: groups[i].author.initials,
              posterUrl: _posterOf(groups[i]),
              unseen: groups[i].hasUnseen,
              onTap: () => _open(i),
            ),
        ],
      ),
    );
  }
}

/// The picture a story card shows: the first unseen story (video poster or photo).
String _posterOf(StoryGroup g) {
  if (g.stories.isEmpty) return g.author.avatarUrl;
  final s = g.stories[g.firstUnseen.clamp(0, g.stories.length - 1)];
  final url = s.isVideo ? s.thumbnailUrl : s.url;
  return url.isNotEmpty ? url : g.author.avatarUrl;
}

/// Facebook-style tall story card: the story picture, the person's photo in
/// a ring top-left, their name bottom-left. LIVE cards get a red tag.
class _StoryCard extends StatelessWidget {
  const _StoryCard({
    required this.name,
    required this.avatarUrl,
    required this.initials,
    required this.posterUrl,
    required this.unseen,
    required this.onTap,
    this.live = false,
    this.onAdd,
  });

  static const double width = 112;
  static const double height = 190;

  final String name;
  final String avatarUrl;
  final String initials;
  final String posterUrl;
  final bool unseen;
  final bool live;
  final VoidCallback onTap;

  /// Your own story: small + to add another.
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: palette.surfaceMuted,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (posterUrl.isNotEmpty) AppNetworkImage(url: posterUrl, fit: BoxFit.cover),
              // Shade so the name reads on any picture.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x40000000), Color(0x00000000), Color(0x00000000), Color(0xA6000000)],
                    stops: [0, 0.3, 0.55, 1],
                  ),
                ),
              ),
              Positioned(
                left: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: unseen ? (live ? _liveRing : _ring) : null,
                    color: unseen ? null : Colors.white.withValues(alpha: 0.7),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(1.5),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: palette.surface),
                    child: ClipOval(
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: avatarUrl.isEmpty
                            ? ColoredBox(
                          color: palette.surfaceMuted,
                          child: Center(child: Text(initials, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: palette.textSecondary))),
                        )
                            : AppNetworkImage(url: avatarUrl, fit: BoxFit.cover),
                      ),
                    ),
                  ),
                ),
              ),
              if (live)
                Positioned(
                  right: 8,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFFF3B5C), borderRadius: BorderRadius.circular(5)),
                    child: const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
                  ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 1, end: 0.6, duration: 800.ms),
                ),
              if (onAdd != null)
                Positioned(
                  right: 6,
                  top: 6,
                  child: GestureDetector(
                    onTap: onAdd,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                      child: const Icon(AppIcons.plus, size: 13, color: Colors.white),
                    ),
                  ),
                ),
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700, height: 1.2, shadows: [Shadow(color: Color(0x80000000), blurRadius: 6)]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Create story" card: your photo on top, a + on the line, the label below.
class _CreateStoryCard extends StatelessWidget {
  const _CreateStoryCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final auth = context.watch<AuthBloc>().state;
    final user = auth is AuthAuthenticated ? auth.user : null;
    final avatar = user?.avatarUrl ?? '';
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: _StoryCard.width,
          height: _StoryCard.height,
          decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: palette.border)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Expanded(
                flex: 7,
                child: SizedBox(
                  width: double.infinity,
                  child: avatar.isEmpty
                      ? ColoredBox(
                    color: palette.surfaceMuted,
                    child: Center(child: Icon(AppIcons.user, size: 36, color: palette.textTertiary)),
                  )
                      : AppNetworkImage(url: avatar, fit: BoxFit.cover),
                ),
              ),
              Expanded(
                flex: 3,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    Positioned(
                      top: -18,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle, border: Border.all(color: palette.surface, width: 3)),
                        child: const Icon(AppIcons.plus, size: 18, color: Colors.white),
                      ),
                    ),
                    Align(
                      alignment: const Alignment(0, 0.55),
                      child: Text('Create story', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: palette.textPrimary)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Host photo: from the live, else from their story, else the cover.
String _avatarFor(({LiveStream live, String hostId}) l, List<StoryGroup> groups) {
  if (l.live.hostAvatarUrl.isNotEmpty) return l.live.hostAvatarUrl;
  for (final g in groups) {
    if (g.author.userId == l.hostId && g.author.avatarUrl.isNotEmpty) return g.author.avatarUrl;
  }
  return (l.live.storeLogoUrl ?? '').isNotEmpty ? l.live.storeLogoUrl! : l.live.coverUrl;
}