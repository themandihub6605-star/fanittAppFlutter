import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../../core/widgets/media_aspect.dart';
import '../../../../core/widgets/stream_video_player.dart';
import '../../../content/data/content_repository.dart';
import '../../../feed/presentation/media_viewer_screen.dart';
import '../../data/community_repository.dart';

/// Community post photos & videos with the same layout as the Feed:
/// each one keeps its real shape (portrait stays portrait, landscape stays
/// landscape, from 9:16 to 1.91:1), nothing is cropped, swipe between
/// several, tap to open full screen.
class CommunityPostMedia extends StatefulWidget {
  const CommunityPostMedia({super.key, required this.media});

  final List<CommunityMedia> media;

  @override
  State<CommunityPostMedia> createState() => _CommunityPostMediaState();
}

class _CommunityPostMediaState extends State<CommunityPostMedia> {
  /// Tallest shape shown in the post (4:5, like Instagram). Taller videos
  /// and photos are filled & cropped here; tapping opens them in full.
  static const double _tallestRatio = 4 / 5;

  final PageController _controller = PageController();
  int _index = 0;
  double? _ratio;

  List<PostMedia> get _asPostMedia => [for (final m in widget.media) PostMedia(url: m.url, isVideo: m.isVideo)];

  @override
  void initState() {
    super.initState();
    final first = widget.media.first;
    _ratio = MediaAspect.cached(first.url);
    if (_ratio == null) {
      MediaAspect.ofNetwork(first.url, isVideo: first.isVideo).then((r) {
        if (mounted && r != null) setState(() => _ratio = r);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Opens full screen; returns where the video was left so the inline
  /// player can continue from there.
  Future<Duration?> _open(int i, {Duration? position}) {
    return MediaViewerScreen.open(context, media: _asPostMedia, index: i, position: position);
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    final multiple = media.length > 1;
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        // Unknown shape at first: start square, then glide to the real one.
        final real = MediaAspect.clamp(_ratio ?? 1);
        final shown = real < _tallestRatio ? _tallestRatio : real;
        // Never taller than ~60% of the screen either.
        final maxHeight = MediaQuery.sizeOf(context).height * 0.6;
        final height = (width / shown).clamp(0.0, maxHeight).toDouble();
        // Cropped when the real shape is taller than the box.
        final cropped = width / real > height + 1;
        final fit = cropped ? BoxFit.cover : BoxFit.contain;
        return Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              height: height,
              decoration: BoxDecoration(color: const Color(0xFF0E0E14), borderRadius: BorderRadius.circular(16)),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    controller: _controller,
                    itemCount: media.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) {
                      final m = media[i];
                      return m.isVideo
                          ? StreamVideoPlayer(
                        key: ValueKey(m.url),
                        url: m.url,
                        fit: fit,
                        showProgress: false,
                        showPlayPauseButton: true,
                        onTap: (position) => _open(i, position: position),
                      )
                          : GestureDetector(
                        onTap: () => _open(i),
                        child: AppNetworkImage(url: m.url, fit: fit),
                      );
                    },
                  ),
                  // "See full" hint when part of it is hidden.
                  if (cropped)
                    Positioned(
                      left: AppSpacing.sm,
                      bottom: AppSpacing.sm,
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(AppRadius.pill)),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Icon(Icons.open_in_full_rounded, size: 12, color: Colors.white),
                              // SizedBox(width: 4),
                            //  Text('Tap to view full', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (multiple)
                    Positioned(
                      top: AppSpacing.sm,
                      right: AppSpacing.sm,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(AppRadius.pill)),
                        child: Text('${_index + 1}/${media.length}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                      ),
                    ),
                ],
              ),
            ),
            if (multiple) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < media.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 2.5),
                      width: i == _index ? 16 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _index ? const Color(0xFFEC2A78) : Theme.of(context).dividerColor,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}