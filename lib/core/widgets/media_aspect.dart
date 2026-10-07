import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

import 'stream_video_player.dart';

/// Finds the real shape (width ÷ height) of photos and videos so the feed
/// can show each one as it is — portrait stays portrait, landscape stays
/// landscape. Results are cached for the whole session.
abstract final class MediaAspect {
  static final Map<String, double> _cache = {};
  static final Map<String, Future<double?>> _pending = {};

  /// Feed limits: from 9:16 (tall video) to 1.91:1 (wide photo).
  static const double minRatio = 9 / 16;
  static const double maxRatio = 1.91;

  static double clamp(double ratio) => ratio.clamp(minRatio, maxRatio).toDouble();

  static double? cached(String url) => _cache[url];

  /// Ratio for a network photo or video. Videos use Cloudflare Stream's
  /// still frame, which has the same shape as the video.
  static Future<double?> ofNetwork(String url, {required bool isVideo}) {
    final hit = _cache[url];
    if (hit != null) return Future.value(hit);
    return _pending.putIfAbsent(url, () async {
      final imageUrl = isVideo ? StreamVideoPlayer.thumbnailFor(url) : url;
      if (imageUrl == null) return null;
      final ratio = await _ratioOf(CachedNetworkImageProvider(imageUrl));
      if (ratio != null) _cache[url] = ratio;
      _pending.remove(url);
      return ratio;
    });
  }

  /// Ratio for a local photo (before upload).
  static Future<double?> ofFile(String path) => _ratioOf(FileImage(File(path)));

  static Future<double?> _ratioOf(ImageProvider provider) {
    final completer = Completer<double?>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
          (info, _) {
        final w = info.image.width.toDouble();
        final h = info.image.height.toDouble();
        if (!completer.isCompleted) completer.complete(h == 0 ? null : w / h);
        stream.removeListener(listener);
      },
      onError: (_, _) {
        if (!completer.isCompleted) completer.complete(null);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return completer.future.timeout(const Duration(seconds: 10), onTimeout: () => null);
  }
}