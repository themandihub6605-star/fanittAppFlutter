import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../../core/widgets/stream_video_player.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../content/data/content_repository.dart';
import '../reels_screen.dart';

/// "Reels" row inside the feed: the 10 latest short videos as tall cards,
/// then a "See all" card. Tapping a reel opens the full-screen player on it.
class ReelsRow extends StatelessWidget {
  const ReelsRow({super.key, required this.reels});

  final List<Post> reels;

  static const _cardWidth = 132.0;
  static const _cardHeight = 228.0;

  @override
  Widget build(BuildContext context) {
    if (reels.isEmpty) return const SizedBox.shrink();
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter - 6, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Reels', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: -0.4, color: palette.textPrimary)),
                      Text('Short videos from creators', style: TextStyle(fontSize: 12.5, color: palette.textSecondary)),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => ReelsScreen.open(context),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Row(
                      children: [
                        Text('See all', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: palette.textSecondary)),
                        Icon(AppIcons.chevronRight, size: 15, color: palette.textSecondary),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: _cardHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: reels.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                if (i == reels.length) return const _SeeAllCard(width: _cardWidth);
                return _ReelCard(reel: reels[i], width: _cardWidth)
                    .animate(delay: (50 * i.clamp(0, 5)).ms)
                    .fadeIn(duration: 300.ms)
                    .slideX(begin: 0.1, curve: Curves.easeOutCubic);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SeeAllCard extends StatelessWidget {
  const _SeeAllCard({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        ReelsScreen.open(context);
      },
      child: Container(
        width: width,
        decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: palette.border)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), shape: BoxShape.circle),
              child: const Icon(AppIcons.playCircle, color: AppColors.primary, size: 24),
            ),
            const SizedBox(height: 10),
            Text('See all', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: palette.textPrimary)),
            Text('reels', style: TextStyle(fontSize: 12, color: palette.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _ReelCard extends StatelessWidget {
  const _ReelCard({required this.reel, required this.width});

  final Post reel;
  final double width;

  @override
  Widget build(BuildContext context) {
    final m = reel.cover;
    final poster = m == null ? '' : (m.thumbnailUrl.isNotEmpty ? m.thumbnailUrl : StreamVideoPlayer.thumbnailFor(m.url) ?? '');
    final name = reel.creatorName ?? '';
    final secs = m?.duration ?? 0;
    final length = secs > 0 ? '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}' : '';
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        ReelsScreen.open(context, startId: reel.id);
      },
      child: Container(
        width: width,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x14101828), blurRadius: 14, offset: Offset(0, 6))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: const Color(0xFF344054), child: AppNetworkImage(url: poster, fit: BoxFit.cover, placeholderIcon: AppIcons.video)),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x33101828), Color(0x00101828), Color(0xB3101828)],
                    stops: [0, 0.4, 1],
                  ),
                ),
              ),
              Positioned(
                left: 8,
                top: 8,
                child: _Glass(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(AppIcons.play, color: Colors.white, size: 10),
                      const SizedBox(width: 3),
                      Text(reel.viewCount > 0 ? Fmt.compact(reel.viewCount) : 'New', style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
              if (length.isNotEmpty)
                Positioned(right: 8, top: 8, child: _Glass(child: Text(length, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700)))),
              Positioned(
                left: 8,
                right: 8,
                bottom: 10,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(1.5),
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: UserAvatar(initials: name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(), imageUrl: reel.creatorAvatarUrl, size: 22),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
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

class _Glass extends StatelessWidget {
  const _Glass({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: const Color(0x66101828), borderRadius: BorderRadius.circular(99)),
      child: child,
    );
  }
}