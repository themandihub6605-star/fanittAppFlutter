import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_palette.dart';
import '../theme/app_spacing.dart';
import 'app_network_image.dart';

/// Makes sure only one video plays at a time across the whole app, and
/// holds the shared mute setting (like Instagram: mute once, all muted).
class VideoPlaybackCoordinator {
  VideoPlaybackCoordinator._();

  static final VideoPlaybackCoordinator instance = VideoPlaybackCoordinator._();

  VideoPlayerController? _active;

  /// Sound is on by default.
  final ValueNotifier<bool> muted = ValueNotifier<bool>(false);

  /// "Pause all videos": when false, feed videos don't start by themselves —
  /// users play the ones they want with each video's play button.
  final ValueNotifier<bool> autoplay = ValueNotifier<bool>(true);

  /// Pauses whatever is playing right now.
  void pauseActive() {
    final active = _active;
    if (active != null && active.value.isPlaying) active.pause();
  }

  /// Call right before playing — pauses whatever else was playing.
  void activate(VideoPlayerController controller) {
    final previous = _active;
    if (previous != null && previous != controller && previous.value.isPlaying) {
      previous.pause();
    }
    _active = controller;
  }

  void release(VideoPlayerController controller) {
    if (_active == controller) _active = null;
  }
}

/// Plays a post / campaign video (Cloudflare Stream HLS or a plain MP4).
///
/// - Autoplays when at least 60% of it is on screen, pauses when scrolled
///   away, when its tab is hidden, or when another screen covers it.
/// - Only one video plays at a time (see [VideoPlaybackCoordinator]).
/// - [onTap] lets the feed open the video full screen from the current
///   position; the returned position is resumed when the user comes back.
class StreamVideoPlayer extends StatefulWidget {
  const StreamVideoPlayer({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.autoPlay = true,
    this.startAt,
    this.onTap,
    this.onPosition,
    this.showProgress = true,
    this.showPlayPauseButton = false,
    this.followsAutoplaySetting = true,
  });

  final String url;
  final BoxFit fit;
  final bool autoPlay;

  /// Where to start playing (used when continuing in full screen).
  final Duration? startAt;

  /// Replaces tap-to-pause. Receives the current position; may return the
  /// position to continue from (e.g. after full screen closes).
  final Future<Duration?> Function(Duration position)? onTap;

  /// Reports the playback position while playing.
  final ValueChanged<Duration>? onPosition;

  final bool showProgress;

  /// Small play/pause button in the corner — for places where tapping the
  /// video does something else (the feed opens full screen).
  final bool showPlayPauseButton;

  /// Feed videos obey the global "pause all videos" switch; the full-screen
  /// viewer plays regardless because the user opened it on purpose.
  final bool followsAutoplaySetting;

  /// Cloudflare Stream serves a still frame next to every HLS manifest.
  static String? thumbnailFor(String url) {
    final manifest = RegExp(r'/manifest/video\.m3u8.*$');
    if (manifest.hasMatch(url)) return url.replaceFirst(manifest, '/thumbnails/thumbnail.jpg');
    return null;
  }

  static bool isVideoUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.m3u8') || lower.endsWith('.mp4') || lower.endsWith('.mov') || lower.endsWith('.webm');
  }

  @override
  State<StreamVideoPlayer> createState() => _StreamVideoPlayerState();
}

class _StreamVideoPlayerState extends State<StreamVideoPlayer> {
  static const double _playThreshold = 0.6;

  final Key _visibilityKey = UniqueKey();
  final VideoPlaybackCoordinator _coordinator = VideoPlaybackCoordinator.instance;

  VideoPlayerController? _controller;
  bool _loading = false;
  bool _failed = false;
  bool _showControls = false;
  bool _userPaused = false;
  bool _manualPlay = false;
  bool _routeVisible = true;
  double _visibleFraction = 0;

  bool get _ready => _controller?.value.isInitialized ?? false;
  bool get _playing => _controller?.value.isPlaying ?? false;
  bool get _muted => _coordinator.muted.value;
  bool get _autoplayAllowed => widget.autoPlay && (!widget.followsAutoplaySetting || _coordinator.autoplay.value);
  bool get _shouldPlay =>
      !_userPaused && _routeVisible && _visibleFraction >= _playThreshold && (_autoplayAllowed || _manualPlay);

  @override
  void initState() {
    super.initState();
    _coordinator.muted.addListener(_onMuteChanged);
    _coordinator.autoplay.addListener(_onAutoplayChanged);
  }

  void _onAutoplayChanged() {
    // Turning "pause all" on clears manual choices so everything stops.
    if (!_coordinator.autoplay.value) _manualPlay = false;
    _scheduleSync();
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Hidden tab (IndexedStack turns tickers off) or covered by another route.
    _routeVisible = TickerMode.of(context) && (ModalRoute.of(context)?.isCurrent ?? true);
    _scheduleSync();
  }

  @override
  void didUpdateWidget(covariant StreamVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _disposeController();
      _loading = false;
      _failed = false;
      _scheduleSync();
    }
  }

  @override
  void dispose() {
    _coordinator.muted.removeListener(_onMuteChanged);
    _coordinator.autoplay.removeListener(_onAutoplayChanged);
    _disposeController();
    super.dispose();
  }

  void _disposeController() {
    final controller = _controller;
    if (controller == null) return;
    controller.removeListener(_onTick);
    _coordinator.release(controller);
    controller.dispose();
    _controller = null;
  }

  void _onMuteChanged() {
    _controller?.setVolume(_muted ? 0 : 1);
    if (mounted) setState(() {});
  }

  void _onTick() {
    final value = _controller?.value;
    if (value == null || !mounted) return;
    if (value.hasError && !_failed) {
      setState(() => _failed = true);
      return;
    }
    if (value.isPlaying) widget.onPosition?.call(value.position);
    setState(() {});
  }

  /// Visibility/route changes can arrive during build — act after the frame.
  void _scheduleSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync();
    });
  }

  void _sync() {
    if (_shouldPlay) {
      if (!_ready) {
        if (!_failed) _start();
      } else if (!_playing) {
        _play();
      }
    } else if (_playing) {
      _controller?.pause();
    }
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    if (!mounted) return;
    final wasVisible = _visibleFraction >= _playThreshold;
    _visibleFraction = info.visibleFraction;
    // Scrolling it off screen forgets a manual pause/play, like Instagram.
    if (wasVisible && _visibleFraction < _playThreshold) {
      _userPaused = false;
      _manualPlay = false;
    }
    _sync();
  }

  void _play() {
    final controller = _controller;
    if (controller == null) return;
    _coordinator.activate(controller);
    controller.play();
  }

  Future<void> _start() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      formatHint: widget.url.contains('.m3u8') ? VideoFormat.hls : null,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
    );
    _controller = controller;

    try {
      await controller.initialize();
      if (!mounted || _controller != controller) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(true);
      await controller.setVolume(_muted ? 0 : 1);
      if (widget.startAt != null && widget.startAt! > Duration.zero) await controller.seekTo(widget.startAt!);
      controller.addListener(_onTick);
      setState(() => _loading = false);
      if (_shouldPlay) _play();
    } catch (_) {
      if (_controller == controller) _controller = null;
      await controller.dispose();
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _handleTap() async {
    if (_failed) {
      _start();
      return;
    }

    if (widget.onTap != null) {
      final position = _controller?.value.position ?? widget.startAt ?? Duration.zero;
      _controller?.pause();
      final resumeAt = await widget.onTap!(position);
      if (!mounted) return;
      if (resumeAt != null && _ready) await _controller!.seekTo(resumeAt);
      _scheduleSync();
      return;
    }

    _togglePlayPause();
  }

  /// Play/pause this one video, independent of the autoplay setting.
  void _togglePlayPause() {
    HapticFeedback.selectionClick();
    if (_playing) {
      _userPaused = true;
      _manualPlay = false;
      _controller!.pause();
    } else {
      _userPaused = false;
      _manualPlay = true;
      if (!_ready) {
        _start();
        return;
      }
      _play();
    }
    setState(() => _showControls = true);
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted && _playing) setState(() => _showControls = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final thumbnail = StreamVideoPlayer.thumbnailFor(widget.url);

    return VisibilityDetector(
      key: _visibilityKey,
      onVisibilityChanged: _onVisibilityChanged,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: Colors.black,
              child: thumbnail == null ? null : AppNetworkImage(url: thumbnail, fit: widget.fit, placeholderIcon: AppIcons.video),
            ),
            if (_ready)
              FittedBox(
                fit: widget.fit,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  child: VideoPlayer(_controller!),
                ),
              ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _handleTap,
                child: const SizedBox.expand(),
              ),
            ),
            Center(child: IgnorePointer(ignoring: !_failed, child: _centerOverlay(palette))),
            if (widget.showPlayPauseButton && !_failed)
              Positioned(
                left: AppSpacing.xs,
                bottom: widget.showProgress ? AppSpacing.md : AppSpacing.xs,
                child: _RoundButton(
                  icon: _playing ? AppIcons.pause : AppIcons.play,
                  tooltip: _playing ? 'Pause' : 'Play',
                  onTap: _togglePlayPause,
                ),
              ),
            if (_ready) ...[
              Positioned(
                right: AppSpacing.xs,
                bottom: widget.showProgress ? AppSpacing.md : AppSpacing.xs,
                child: _RoundButton(
                  icon: _muted ? AppIcons.speakerOff : AppIcons.speakerOn,
                  tooltip: _muted ? 'Unmute' : 'Mute',
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _coordinator.muted.value = !_muted;
                  },
                ),
              ),
              if (widget.showProgress)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: VideoProgressIndicator(
                    _controller!,
                    allowScrubbing: true,
                    padding: const EdgeInsets.only(top: 12),
                    colors: VideoProgressColors(
                      playedColor: AppColors.primary,
                      bufferedColor: Colors.white.withValues(alpha: 0.35),
                      backgroundColor: Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _centerOverlay(AppPalette palette) {
    if (_failed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RoundButton(icon: AppIcons.refresh, tooltip: 'Retry', onTap: _start, size: 56),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Couldn’t play this video.\nIt may still be processing.',
            textAlign: TextAlign.center,
            style: context.text.bodySmall?.copyWith(color: Colors.white),
          ),
        ],
      );
    }
    if (_loading || (_ready && _controller!.value.isBuffering && _playing)) {
      return const SizedBox(
        width: 36,
        height: 36,
        child: CircularProgressIndicator(strokeWidth: 2.6, valueColor: AlwaysStoppedAnimation(Colors.white)),
      );
    }
    final show = !_ready || !_playing || _showControls;
    return AnimatedOpacity(
      opacity: show ? 1 : 0,
      duration: AppDurations.normal,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
        child: Icon(_playing ? AppIcons.pause : AppIcons.play, color: Colors.white, size: 30),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap, required this.tooltip, this.size = 36});

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.45),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: size, height: size, child: Icon(icon, size: size * 0.5, color: Colors.white)),
        ),
      ),
    );
  }
}