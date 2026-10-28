// File: lib/features/feed/presentation/widgets/stories_bar.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../store/data/store_repository.dart';
import '../../data/story_repository.dart';
import '../story_viewer_screen.dart';

// LIVE ring: spins, so a live creator stands out from normal stories.
const _liveRing = SweepGradient(colors: [Color(0xFFFF3B5C), AppColors.primary, Color(0xFFFFB020), Color(0xFFEC2A78), Color(0xFFFF3B5C)]);

const _ring = LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFFF4511E), Color(0xFFEC2A78), Color(0xFF7C4DFF)]);

/// Round story rings at the top of the feed. "Your story" first for
/// creators and brands (tap + to add one), then people you follow who are
/// LIVE right now (spinning ring + LIVE tag → opens the live), then stories.
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
    if (groups == null) return const SizedBox(height: 96);
    final mineIndex = groups.indexWhere((g) => g.isMine);
    final liveHosts = {for (final l in _lives) l.hostId};
    // Someone live shows once — as the LIVE ring, not also as a story.
    final others = [for (var i = 0; i < groups.length; i++) if (i != mineIndex && !liveHosts.contains(groups[i].author.userId)) i];
    if (!widget.canPost && others.isEmpty && _lives.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 2, AppSpacing.gutter, 0),
        children: [
          if (widget.canPost)
            _Ring(
              label: 'Your story',
              avatarUrl: mineIndex >= 0 ? groups[mineIndex].author.avatarUrl : '',
              initials: mineIndex >= 0 ? groups[mineIndex].author.initials : '+',
              state: mineIndex >= 0 ? _RingState.seen : _RingState.none,
              showPlus: true,
              onTap: mineIndex >= 0 ? () => _open(mineIndex) : _add,
              onPlus: _add,
            ),
          for (final (i, l) in _lives.indexed)
            _LiveRing(
              name: l.live.hostName.isNotEmpty ? l.live.hostName : (l.live.storeName ?? 'Live'),
              avatarUrl: _avatarFor(l, groups),
              onTap: () => _openLive(l.live),
            ).animate(delay: (60 * i.clamp(0, 6)).ms).fadeIn(duration: 300.ms).scaleXY(begin: 0.85, curve: Curves.easeOutBack),
          for (final i in others)
            _Ring(
              label: groups[i].author.name,
              avatarUrl: groups[i].author.avatarUrl,
              initials: groups[i].author.initials,
              state: groups[i].hasUnseen ? _RingState.unseen : _RingState.seen,
              onTap: () => _open(i),
            ),
        ],
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

/// A followed creator who is live: spinning colour ring, soft breathing
/// glow and a pulsing LIVE tag. Tap → the live.
class _LiveRing extends StatelessWidget {
  const _LiveRing({required this.name, required this.avatarUrl, required this.onTap});

  final String name;
  final String avatarUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    const size = 64.0;
    final initials = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 70,
          child: Column(
            children: [
              SizedBox(
                width: size + 6,
                height: size + 6,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    // Breathing glow.
                    Container(
                      width: size + 4,
                      height: size + 4,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: const Color(0xFFFF3B5C).withValues(alpha: 0.35), blurRadius: 12, spreadRadius: 1)],
                      ),
                    ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 0.25, end: 1, duration: 1100.ms),
                    // Spinning ring.
                    Container(width: size + 6, height: size + 6, decoration: const BoxDecoration(shape: BoxShape.circle, gradient: _liveRing))
                        .animate(onPlay: (c) => c.repeat())
                        .rotate(duration: 2400.ms),
                    Container(
                      width: size + 1,
                      height: size + 1,
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: palette.background),
                      child: ClipOval(
                        child: avatarUrl.isEmpty
                            ? Container(
                          color: palette.surfaceMuted,
                          alignment: Alignment.center,
                          child: Text(initials, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: palette.textSecondary)),
                        )
                            : AppNetworkImage(url: avatarUrl, fit: BoxFit.cover),
                      ),
                    ),
                    Positioned(
                      bottom: -5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF3B5C),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: palette.background, width: 1.5),
                        ),
                        child: const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
                      ).animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(begin: 1, end: 1.1, duration: 700.ms, curve: Curves.easeInOut),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 7),
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(fontSize: 11.5, fontWeight: FontWeight.w700, color: palette.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }
}

enum _RingState { none, unseen, seen }

class _Ring extends StatelessWidget {
  const _Ring({required this.label, required this.avatarUrl, required this.initials, required this.state, required this.onTap, this.showPlus = false, this.onPlus});

  final String label;
  final String avatarUrl;
  final String initials;
  final _RingState state;
  final VoidCallback onTap;
  final bool showPlus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    const size = 64.0;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 70,
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: size + 6,
                    height: size + 6,
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: state == _RingState.unseen ? _ring : null,
                      color: state == _RingState.seen ? palette.border : (state == _RingState.none ? Colors.transparent : null),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: palette.background),
                      child: ClipOval(
                        child: avatarUrl.isEmpty
                            ? Container(
                          color: palette.surfaceMuted,
                          alignment: Alignment.center,
                          child: Text(initials, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: palette.textSecondary)),
                        )
                            : AppNetworkImage(url: avatarUrl, fit: BoxFit.cover),
                      ),
                    ),
                  ),
                  if (showPlus)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onTap: onPlus,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle, border: Border.all(color: palette.background, width: 2)),
                          child: const Icon(AppIcons.plus, size: 12, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(fontSize: 11.5, color: palette.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }
}