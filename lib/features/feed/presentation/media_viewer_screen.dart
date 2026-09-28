import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/stream_video_player.dart';
import '../../content/data/content_repository.dart';

/// Full-screen viewer for a post's photos and videos. Swipe between items,
/// pinch to zoom photos. A video continues from where it was in the feed,
/// and the viewer returns the position of that video so the feed resumes
/// from the same moment.
class MediaViewerScreen extends StatefulWidget {
  const MediaViewerScreen({super.key, required this.media, required this.initialIndex, this.initialPosition});

  final List<PostMedia> media;
  final int initialIndex;
  final Duration? initialPosition;

  static Future<Duration?> open(
      BuildContext context, {
        required List<PostMedia> media,
        required int index,
        Duration? position,
      }) {
    return Navigator.of(context, rootNavigator: true).push<Duration?>(
      PageRouteBuilder<Duration?>(
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, _, _) => MediaViewerScreen(media: media, initialIndex: index, initialPosition: position),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  late final PageController _pageController = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  late Duration? _initialVideoPosition = widget.initialPosition;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).pop(_initialVideoPosition);

  @override
  Widget build(BuildContext context) {
    final total = widget.media.length;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _close();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              PageView.builder(
                controller: _pageController,
                itemCount: total,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  final item = widget.media[i];
                  if (item.isVideo) {
                    return StreamVideoPlayer(
                      key: ValueKey('viewer-${item.url}'),
                      url: item.url,
                      fit: BoxFit.contain,
                      followsAutoplaySetting: false,
                      startAt: i == widget.initialIndex ? widget.initialPosition : null,
                      onPosition: i == widget.initialIndex ? (p) => _initialVideoPosition = p : null,
                    );
                  }
                  return InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Center(child: AppNetworkImage(url: item.url, fit: BoxFit.contain)),
                  );
                },
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Close',
                        onPressed: _close,
                        style: IconButton.styleFrom(backgroundColor: Colors.black.withValues(alpha: 0.4)),
                        icon: const Icon(AppIcons.close, color: Colors.white),
                      ),
                      const Spacer(),
                      if (total > 1)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            '${_index + 1}/$total',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}