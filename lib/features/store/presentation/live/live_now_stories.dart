// File: lib/features/store/presentation/live/live_now_stories.dart
import 'dart:async';

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
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../data/live_call_models.dart';
import '../../../dashboard/presentation/home_discover.dart' show HomeSectionHeader;
import '../../data/store_repository.dart';

/// Live now first, then upcoming. Ended / cancelled are left out.
List<LiveStream> _liveFirst(List<LiveStream> all) => [
  for (final l in all) if (l.isLive) l,
  for (final l in all) if (l.status == LiveStatus.scheduled) l,
];

/// Home section: "Live now" header with See all, then creators who are live
/// (or about to be) — round photo, a small LIVE / time tag and the name.
/// Hidden when there's nothing. Refreshes every 30 s and on [refresh].
class LiveNowStories extends StatefulWidget {
  const LiveNowStories({super.key, this.refresh, this.title = 'Live now', this.subtitle = 'Join creators streaming right now'});

  final Listenable? refresh;
  final String title;
  final String subtitle;

  @override
  State<LiveNowStories> createState() => _LiveNowStoriesState();
}

class _LiveNowStoriesState extends State<LiveNowStories> {
  List<LiveStream> _lives = const [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
    widget.refresh?.addListener(_load);
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.refresh?.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final all = await sl<StoreRepository>().discoverLives(limit: 50);
      if (mounted) setState(() => _lives = _liveFirst(all));
    } catch (_) {
      // Offline: keep what we had.
    }
  }

  @override
  Widget build(BuildContext context) {
    final lives = _lives;
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: lives.isEmpty
          ? const SizedBox(width: double.infinity)
          : Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Blinking red dot before "Live now".
                  const Padding(padding: EdgeInsets.only(top: 8), child: _PulseDot()),
                  const SizedBox(width: 8),
                  Expanded(
                    child: HomeSectionHeader(title: widget.title, subtitle: widget.subtitle, padding: EdgeInsets.zero, onSeeAll: () => openLiveNowScreen(context)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 112,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                itemCount: lives.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, i) => LiveStoryAvatar(live: lives[i])
                    .animate(delay: (40 * i).ms)
                    .fadeIn(duration: 260.ms)
                    .scale(begin: const Offset(0.88, 0.88), curve: Curves.easeOutBack),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One creator: primary ring → white ring → primary ring → photo, a small
/// tag on the ring (LIVE, or the start time) and the name under it.
class LiveStoryAvatar extends StatelessWidget {
  const LiveStoryAvatar({super.key, required this.live, this.size = 72});

  final LiveStream live;
  final double size;

  String get _name {
    final n = live.hostName.trim().isNotEmpty ? live.hostName.trim() : (live.storeName ?? '').trim();
    return n.isEmpty ? 'Creator' : n;
  }

  String get _photo => live.hostAvatarUrl.isNotEmpty ? live.hostAvatarUrl : (live.storeLogoUrl ?? '');

  String get _initials {
    final parts = _name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return parts.length == 1 ? parts.first[0].toUpperCase() : '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  /// "LIVE" while on air; otherwise when it starts: 6:30 PM / Tomorrow / 28 Oct.
  String get _tag {
    if (live.isLive) return 'LIVE';
    final at = live.scheduledAt?.toLocal();
    if (at == null) return 'SOON';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final diff = day.difference(today).inDays;
    if (diff <= 0) return Fmt.time(at);
    if (diff == 1) return 'Tomorrow';
    return Fmt.shortDate(at);
  }

  Widget _ring(BuildContext context, String photo) {
    final palette = context.palette;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2.5),
      decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primary),
      child: Container(
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(shape: BoxShape.circle, color: palette.surface),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primary),
          child: UserAvatar(initials: _initials, imageUrl: photo.isEmpty ? null : photo, size: size - 14),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final photo = _photo;
    final isLive = live.isLive;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        context.push(AppRoutes.liveDetail(live.id));
      },
      child: SizedBox(
        width: size + 10,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.bottomCenter,
              children: [
                // Live: a soft glow that breathes behind the ring.
                if (isLive)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.55), blurRadius: 14, spreadRadius: 1)],
                      ),
                    )
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .fade(begin: 0.25, end: 1, duration: 900.ms, curve: Curves.easeInOut),
                  ),
                // Primary ring → white gap → primary ring → photo.
                if (isLive)
                  _ring(context, photo)
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .scaleXY(begin: 1, end: 1.05, duration: 900.ms, curve: Curves.easeInOut)
                else
                  _ring(context, photo),
                Positioned(
                  bottom: -7,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: isLive ? AppColors.primary : palette.textPrimary,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: palette.surface, width: 2),
                    ),
                    child: Text(
                      _tag,
                      maxLines: 1,
                      style: TextStyle(color: isLive ? Colors.white : palette.surface, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: isLive ? 0.6 : 0.1, height: 1.2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(_name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: context.text.labelMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _PulseDot extends StatelessWidget {
  const _PulseDot();

  @override
  Widget build(BuildContext context) {
    return Container(width: 9, height: 9, decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle))
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .fade(begin: 1, end: 0.3, duration: 700.ms);
  }
}

/// "View all" — every live and upcoming live, as round photos.
Future<void> openLiveNowScreen(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(builder: (_) => const LiveNowScreen()));
}

class LiveNowScreen extends StatefulWidget {
  const LiveNowScreen({super.key});

  @override
  State<LiveNowScreen> createState() => _LiveNowScreenState();
}

class _LiveNowScreenState extends State<LiveNowScreen> {
  List<LiveStream>? _lives;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await sl<StoreRepository>().discoverLives(limit: 100);
      if (mounted) {
        setState(() {
          _lives = _liveFirst(all);
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Couldn’t load lives. Pull down to try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final lives = _lives;
    final palette = context.palette;
    final now = [for (final l in lives ?? const <LiveStream>[]) if (l.isLive) l];
    final soon = [for (final l in lives ?? const <LiveStream>[]) if (!l.isLive) l];

    return Scaffold(
      appBar: AppBar(title: const Text('Lives')),
      body: RefreshIndicator.adaptive(
        color: AppColors.primary,
        onRefresh: _load,
        child: lives == null && _error == null
            ? const Center(child: CircularProgressIndicator.adaptive())
            : ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.sm, AppSpacing.gutter, AppSpacing.xxl),
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 120),
                child: Text(_error!, textAlign: TextAlign.center, style: context.text.bodyMedium?.copyWith(color: palette.textSecondary)),
              )
            else if (lives!.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 120),
                child: Column(
                  children: [
                    Icon(AppIcons.broadcast, size: 44, color: palette.textTertiary),
                    const SizedBox(height: AppSpacing.md),
                    Text('No lives right now', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('Creators show up here when they go live or schedule a live.', textAlign: TextAlign.center, style: context.text.bodySmall),
                  ],
                ),
              )
            else ...[
                if (now.isNotEmpty) ...[
                  _GroupTitle(title: 'Live now', count: now.length, pulse: true),
                  _AvatarGrid(lives: now),
                ],
                if (soon.isNotEmpty) ...[
                  if (now.isNotEmpty) const SizedBox(height: AppSpacing.lg),
                  _GroupTitle(title: 'Coming up', count: soon.length),
                  _AvatarGrid(lives: soon),
                ],
              ],
          ],
        ),
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle({required this.title, required this.count, this.pulse = false});

  final String title;
  final int count;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.md),
      child: Row(
        children: [
          if (pulse) ...[const _PulseDot(), const SizedBox(width: 8)],
          Text(title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(width: 6),
          Text('· $count', style: context.text.bodyMedium?.copyWith(color: context.palette.textSecondary)),
        ],
      ),
    );
  }
}

/// 4 per row (3 on narrow phones), round photos with names.
class _AvatarGrid extends StatelessWidget {
  const _AvatarGrid({required this.lives});

  final List<LiveStream> lives;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth < 340 ? 3 : 4;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: lives.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 16, crossAxisSpacing: 8, mainAxisExtent: 112),
          itemBuilder: (context, i) => Center(
            child: LiveStoryAvatar(live: lives[i], size: 64).animate(delay: (25 * i).ms).fadeIn(duration: 220.ms).scale(begin: const Offset(0.9, 0.9)),
          ),
        );
      },
    );
  }
}