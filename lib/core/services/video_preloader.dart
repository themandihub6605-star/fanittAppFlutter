// File: lib/core/services/video_preloader.dart
import 'package:video_player/video_player.dart';

/// Gets videos ready BEFORE they're shown, so stories / reels / feed videos
/// start playing straight away instead of showing a spinner.
///
///   VideoPreloader.i.preload(url)  → starts loading in the background
///   VideoPreloader.i.take(url)     → hands over that controller (or null)
///
/// Whoever takes a controller owns it and must dispose it. At most [_max]
/// videos wait here; the oldest is dropped (phones only have a few video
/// decoders).
class VideoPreloader {
  VideoPreloader._();

  static final VideoPreloader i = VideoPreloader._();

  static const int _max = 3;

  final Map<String, PreloadedVideo> _ready = {};

  /// Cloudflare Stream: start on a lighter quality so the first frame comes
  /// fast — the player moves up to HD by itself once it's playing.
  static String fastUrl(String url) {
    final isStreamHls = url.contains('.m3u8') && (url.contains('cloudflarestream.com') || url.contains('videodelivery.net'));
    if (!isStreamHls || url.contains('clientBandwidthHint')) return url;
    return '$url${url.contains('?') ? '&' : '?'}clientBandwidthHint=1.5';
  }

  /// A new, not-yet-initialized controller set up the same way everywhere.
  static VideoPlayerController create(String url) => VideoPlayerController.networkUrl(
    Uri.parse(fastUrl(url)),
    formatHint: url.contains('.m3u8') ? VideoFormat.hls : null,
    videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
  );

  /// Start loading [url] in the background (no-op if already waiting).
  void preload(String url) {
    if (url.isEmpty || _ready.containsKey(url)) return;
    final controller = create(url);
    final ready = controller.initialize().then((_) => controller.setVolume(0)).catchError((Object _) {
      // A failed preload is simply dropped; the screen loads it normally.
      final entry = _ready[url];
      if (entry != null && entry.controller == controller) {
        _ready.remove(url);
        controller.dispose();
      }
    });
    _ready[url] = PreloadedVideo(controller, ready);
    while (_ready.length > _max) {
      final oldest = _ready.keys.first;
      _ready.remove(oldest)?.controller.dispose();
    }
  }

  /// Hands over a preloaded controller for [url] (still loading or ready),
  /// or null. The caller now owns it.
  PreloadedVideo? take(String url) => _ready.remove(url);

  /// Gets a controller for [url] — the preloaded one when there is one —
  /// and waits until it's ready. Throws if the video can't load.
  Future<VideoPlayerController> obtain(String url) async {
    final pre = take(url);
    if (pre != null) {
      await pre.ready;
      if (pre.controller.value.isInitialized) return pre.controller;
      await pre.controller.dispose();
    }
    final controller = create(url);
    try {
      await controller.initialize();
    } catch (_) {
      await controller.dispose();
      rethrow;
    }
    return controller;
  }

  /// Drop everything waiting (e.g. leaving a screen).
  void clear() {
    for (final entry in _ready.values) {
      entry.controller.dispose();
    }
    _ready.clear();
  }
}

class PreloadedVideo {
  const PreloadedVideo(this.controller, this.ready);

  final VideoPlayerController controller;

  /// Completes when loading finished (successfully or not).
  final Future<void> ready;
}