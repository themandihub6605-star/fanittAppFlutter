import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../../core/widgets/stream_video_player.dart';
import '../../../content/data/content_repository.dart';
import '../reels_screen.dart';

/// "Reels" row inside the feed: the 10 latest short videos as tall cards,
/// then a "See more" card. Tapping a reel opens the full-screen player on it.
class ReelsRow extends StatelessWidget {
  const ReelsRow({super.key, required this.reels});

  final List<Post> reels;

  static const _cardWidth = 118.0;
  static const _cardHeight = 210.0;

  @override
  Widget build(BuildContext context) {
    if (reels.isEmpty) return const SizedBox.shrink();
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
                  child: const Icon(AppIcons.video, size: 16, color: AppColors.primary),
                ),
                const SizedBox(width: 8),
                Text('Reels', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const Spacer(),
                TextButton(onPressed: () => ReelsScreen.open(context), child: const Text('See all')),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: _cardHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
              itemCount: reels.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                if (i == reels.length) {
                  return GestureDetector(
                    onTap: () => ReelsScreen.open(context),
                    child: Container(
                      width: _cardWidth,
                      decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(14), border: Border.all(color: palette.border)),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]), shape: BoxShape.circle),
                            child: const Icon(AppIcons.chevronRight, color: Colors.white),
                          ),
                          const SizedBox(height: 8),
                          Text('See more', style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                          Text('reels', style: context.text.bodySmall),
                        ],
                      ),
                    ),
                  );
                }
                return _ReelCard(reel: reels[i], width: _cardWidth);
              },
            ),
          ),
        ],
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
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        ReelsScreen.open(context, startId: reel.id);
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: width,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: Colors.black, child: AppNetworkImage(url: poster, fit: BoxFit.cover, placeholderIcon: AppIcons.video)),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0x00000000), Color(0xCC000000)], stops: [0, 0.55, 1]),
                ),
              ),
              const Positioned(top: 8, right: 8, child: Icon(AppIcons.play, color: Colors.white, size: 16)),
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(reel.creatorName ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                    if (reel.viewCount > 0)
                      Row(
                        children: [
                          const Icon(AppIcons.eye, color: Colors.white70, size: 11),
                          const SizedBox(width: 3),
                          Text(Fmt.compact(reel.viewCount), style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                        ],
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