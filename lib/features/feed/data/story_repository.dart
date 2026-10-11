import 'package:dio/dio.dart';

import '../../../core/di/injection.dart';
import '../../../core/models/common_models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/multipart.dart';
import '../../../core/services/media_picker.dart';
import '../../../core/utils/json.dart';

// 24-hour stories by creators and brands (backend: /api/stories).

class StoryAuthor {
  const StoryAuthor({
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.isBrand,
    required this.profileId,
    required this.slug,
    required this.verified,
    required this.isFollowing,
  });

  factory StoryAuthor.fromJson(Map<String, dynamic> json) => StoryAuthor(
    userId: J.str(json, '_id'),
    name: J.str(json, 'name'),
    avatarUrl: J.str(json, 'avatarUrl'),
    isBrand: J.str(json, 'role') == 'brand',
    profileId: J.str(json, 'profileId'),
    slug: J.str(json, 'slug'),
    verified: J.boolean(json, 'verified'),
    isFollowing: J.boolean(json, 'isFollowing'),
  );

  final String userId;
  final String name;
  final String avatarUrl;
  final bool isBrand;
  final String profileId;
  final String slug;
  final bool verified;
  final bool isFollowing;

  String get initials => name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
  String get profileRoute => isBrand ? '/app/brands/$slug' : '/app/creators/$slug';
}

class Story {
  const Story({
    required this.id,
    required this.url,
    required this.isVideo,
    required this.thumbnailUrl,
    required this.duration,
    required this.caption,
    required this.createdAt,
    required this.viewCount,
    required this.seen,
  });

  factory Story.fromJson(Map<String, dynamic> json) {
    final media = J.map(json, 'media') ?? const <String, dynamic>{};
    return Story(
      id: J.id(json),
      url: J.str(media, 'url'),
      isVideo: J.str(media, 'type') == 'video',
      thumbnailUrl: J.str(media, 'thumbnailUrl'),
      duration: J.integer(media, 'duration'),
      caption: J.str(json, 'caption'),
      createdAt: J.date(json, 'createdAt') ?? DateTime.now(),
      viewCount: J.integer(json, 'viewCount'),
      seen: J.boolean(json, 'seen'),
    );
  }

  final String id;
  final String url;
  final bool isVideo;
  final String thumbnailUrl;
  final int duration;
  final String caption;
  final DateTime createdAt;
  final int viewCount;
  final bool seen;

  Story markSeen() => Story(
    id: id,
    url: url,
    isVideo: isVideo,
    thumbnailUrl: thumbnailUrl,
    duration: duration,
    caption: caption,
    createdAt: createdAt,
    viewCount: viewCount,
    seen: true,
  );
}

/// One author's ring: all their active stories, oldest first.
class StoryGroup {
  const StoryGroup({required this.author, required this.stories, required this.isMine});

  factory StoryGroup.fromJson(Map<String, dynamic> json) => StoryGroup(
    author: StoryAuthor.fromJson(J.map(json, 'author') ?? const <String, dynamic>{}),
    stories: J.list(json, 'stories', Story.fromJson),
    isMine: J.boolean(json, 'isMine'),
  );

  final StoryAuthor author;
  final List<Story> stories;
  final bool isMine;

  bool get hasUnseen => stories.any((s) => !s.seen);

  /// Where to start watching: the first story not seen yet.
  int get firstUnseen {
    final i = stories.indexWhere((s) => !s.seen);
    return i < 0 ? 0 : i;
  }

  StoryGroup withSeen(String storyId) => StoryGroup(
    author: author,
    isMine: isMine,
    stories: [for (final s in stories) s.id == storyId ? s.markSeen() : s],
  );
}

class StoryRepository {
  StoryRepository._(this._api);

  static StoryRepository? _instance;
  static StoryRepository get i => _instance ??= StoryRepository._(sl<ApiClient>());

  final ApiClient _api;

  static const videoMaxSeconds = 60;

  /// Rings for the feed: mine first, then unseen, then seen.
  Future<List<StoryGroup>> feed() async => (await _api.get('/stories', parser: (d) => J.listOf(d, StoryGroup.fromJson))).data;

  Future<StoryGroup?> mine() async => (await _api.get('/stories/me', parser: (d) => d == null ? null : StoryGroup.fromJson(J.asMap(d)))).data;

  Future<StoryGroup> create({required PickedMedia media, String caption = '', int duration = 0}) async {
    final form = FormData.fromMap({'caption': caption, if (duration > 0) 'duration': duration});
    form.files.add(MapEntry('media', await multipartFrom(media)));
    return (await _api.post('/stories', data: form, parser: (d) => StoryGroup.fromJson(J.asMap(d)))).data;
  }

  /// Marks a story seen (fire and forget).
  Future<void> markSeen(String id) async {
    try {
      await _api.post('/stories/$id/view', parser: (_) => null);
    } catch (_) {}
  }

  /// Who saw my story, latest first.
  Future<List<StoryViewer>> viewers(String id) async => (await _api.get('/stories/$id/viewers', parser: (d) => J.listOf(d, StoryViewer.fromJson))).data;

  Future<void> delete(String id) async => _api.delete('/stories/$id', parser: (_) => null);
}

/// Someone who saw my story. [slug] is set when they are a creator or brand
/// (fans have no public profile).
class StoryViewer {
  const StoryViewer({required this.user, this.isBrand = false, this.slug = '', this.profileId = '', this.isFollowing = false});

  factory StoryViewer.fromJson(Map<String, dynamic> json) {
    final p = J.map(json, 'profile');
    return StoryViewer(
      user: UserLite.fromJson(json),
      isBrand: p != null && J.str(p, 'role') == 'brand',
      slug: p == null ? '' : J.str(p, 'slug'),
      profileId: p == null ? '' : J.str(p, 'profileId'),
      isFollowing: p != null && J.boolean(p, 'isFollowing'),
    );
  }

  final UserLite user;
  final bool isBrand;
  final String slug;
  final String profileId;
  final bool isFollowing;

  bool get hasProfile => slug.isNotEmpty;
}