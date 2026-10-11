import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../../core/widgets/media_aspect.dart';
import '../../../../core/widgets/stream_video_player.dart';
import '../../../content/data/content_repository.dart';

/// All of a post's photos and videos in ONE block (no swiping):
///
///   1 item   its real shape, but never taller than 4:5 (long / tall
///            videos don't take the whole screen)
///   2 items  side by side
///   3 items  one big on the left, two stacked on the right
///   4 items  2 × 2
///   5+       two on top, three below — the last one shows "+N"
///
/// Tapping any tile opens the full-screen viewer at that item.
class PostMediaGrid extends StatefulWidget {
  const PostMediaGrid({super.key, required this.media, required this.onOpen, this.overlay, this.radius = 16});

  final List<PostMedia> media;
  final Future<Duration?> Function(int index, {Duration? position}) onOpen;

  /// Drawn on top (e.g. the double-tap heart).
  final Widget? overlay;

  /// Corner rounding (0 = edge to edge, as in the feed).
  final double radius;

  /// Tallest a post may be: width ÷ height = 4:5.
  static const double minRatio = 4 / 5;

  @override
  State<PostMediaGrid> createState() => _PostMediaGridState();
}

class _PostMediaGridState extends State<PostMediaGrid> {
  double? _ratio; // only used for a single item

  @override
  void initState() {
    super.initState();
    if (widget.media.length == 1) {
      final m = widget.media.first;
      _ratio = m.aspectRatio ?? MediaAspect.cached(m.url);
      if (_ratio == null) {
        MediaAspect.ofNetwork(m.url, isVideo: m.isVideo).then((r) {
          if (mounted && r != null) setState(() => _ratio = r);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.media;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final double height;
        if (items.length == 1) {
          final ratio = (_ratio ?? 1).clamp(PostMediaGrid.minRatio, MediaAspect.maxRatio).toDouble();
          height = w / ratio;
        } else if (items.length == 2) {
          height = w * 0.62;
        } else if (items.length == 3) {
          height = w * 0.78;
        } else if (items.length == 4) {
          height = w;
        } else {
          height = w * 0.9;
        }

        return AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          height: height,
          decoration: BoxDecoration(color: const Color(0xFF0E0E14), borderRadius: BorderRadius.circular(widget.radius)),
          clipBehavior: widget.radius > 0 ? Clip.antiAlias : Clip.hardEdge,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _layout(items),
              if (widget.overlay != null) IgnorePointer(child: widget.overlay!),
            ],
          ),
        );
      },
    );
  }

  Widget _layout(List<PostMedia> items) {
    const gap = 3.0;
    Widget tile(int i, {int extra = 0}) => _Tile(media: items[i], extra: extra, single: items.length == 1, onOpen: (pos) => widget.onOpen(i, position: pos));

    switch (items.length) {
      case 1:
        return tile(0);
      case 2:
        return Row(children: [Expanded(child: tile(0)), const SizedBox(width: gap), Expanded(child: tile(1))]);
      case 3:
        return Row(
          children: [
            Expanded(flex: 2, child: tile(0)),
            const SizedBox(width: gap),
            Expanded(child: Column(children: [Expanded(child: tile(1)), const SizedBox(height: gap), Expanded(child: tile(2))])),
          ],
        );
      case 4:
        return Column(
          children: [
            Expanded(child: Row(children: [Expanded(child: tile(0)), const SizedBox(width: gap), Expanded(child: tile(1))])),
            const SizedBox(height: gap),
            Expanded(child: Row(children: [Expanded(child: tile(2)), const SizedBox(width: gap), Expanded(child: tile(3))])),
          ],
        );
      default:
        final extra = items.length - 5;
        return Column(
          children: [
            Expanded(flex: 3, child: Row(children: [Expanded(child: tile(0)), const SizedBox(width: gap), Expanded(child: tile(1))])),
            const SizedBox(height: gap),
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Expanded(child: tile(2)),
                  const SizedBox(width: gap),
                  Expanded(child: tile(3)),
                  const SizedBox(width: gap),
                  Expanded(child: tile(4, extra: extra)),
                ],
              ),
            ),
          ],
        );
    }
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.media, required this.onOpen, this.extra = 0, this.single = false});

  final PostMedia media;
  final Future<Duration?> Function(Duration? position) onOpen;
  final int extra;
  final bool single;

  @override
  Widget build(BuildContext context) {
    final m = media;
    // A single video plays right in the feed; in a grid, videos show their
    // poster with a play badge and play full screen.
    if (m.isVideo && single) {
      return StreamVideoPlayer(
        key: ValueKey(m.url),
        url: m.url,
        fit: BoxFit.cover,
        showProgress: false,
        showPlayPauseButton: true,
        onTap: (position) => onOpen(position),
      );
    }
    final poster = m.isVideo ? (m.thumbnailUrl.isNotEmpty ? m.thumbnailUrl : StreamVideoPlayer.thumbnailFor(m.url) ?? '') : m.url;
    return GestureDetector(
      onTap: () => onOpen(null),
      child: Stack(
        fit: StackFit.expand,
        children: [
          AppNetworkImage(url: poster, fit: single ? BoxFit.contain : BoxFit.cover),
          if (m.isVideo)
            Center(
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle),
                child: const Icon(AppIcons.play, color: Colors.white, size: 18),
              ),
            ),
          if (m.isVideo && m.duration > 0)
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(5)),
                child: Text(_time(m.duration), style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700)),
              ),
            ),
          if (extra > 0)
            ColoredBox(
              color: Colors.black.withValues(alpha: 0.5),
              child: Center(child: Text('+$extra', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800))),
            ),
        ],
      ),
    );
  }

  static String _time(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}