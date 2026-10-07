import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';

import '../../../core/models/common_models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/multipart.dart';
import '../../../core/services/media_picker.dart';
import '../../../core/utils/json.dart';

class PostMedia extends Equatable {
  const PostMedia({required this.url, required this.isVideo, this.aspectRatio});

  factory PostMedia.fromJson(Map<String, dynamic> json) => PostMedia(
    url: J.str(json, 'url'),
    isVideo: J.str(json, 'type') == 'video',
    aspectRatio: (json['aspectRatio'] as num?)?.toDouble(),
  );

  final String url;
  final bool isVideo;

  /// Width ÷ height saved at upload (null for older posts).
  final double? aspectRatio;

  @override
  List<Object?> get props => [url];
}

class Post extends Equatable {
  const Post({
    required this.id,
    required this.media,
    required this.caption,
    required this.likeCount,
    required this.createdAt,
    this.likedBy = const {},
    this.likePreview = const [],
    this.creatorId,
    this.creatorUserId,
    this.creatorName,
    this.creatorAvatarUrl,
    this.creatorSlug,
    this.isFollowingCreator = false,
    this.isSaved = false,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    final creator = J.map(json, 'creator');
    final creatorUser = creator == null ? null : J.map(creator, 'user');
    return Post(
      id: J.id(json),
      media: J.list(json, 'mediaItems', PostMedia.fromJson),
      caption: J.str(json, 'caption'),
      likeCount: J.integer(json, 'likeCount'),
      createdAt: J.date(json, 'createdAt') ?? DateTime.now(),
      likedBy: (json['likedBy'] as List<dynamic>? ?? const []).map((e) => e.toString()).toSet(),
      likePreview: J.list(json, 'likePreview', UserLite.fromJson),
      creatorId: creator == null ? J.strOrNull(json, 'creator') : J.id(creator),
      creatorUserId: creator == null ? null : J.refId(creator, 'user'),
      creatorName: creatorUser == null ? null : J.strOrNull(creatorUser, 'name'),
      creatorAvatarUrl: creatorUser == null ? null : J.strOrNull(creatorUser, 'avatarUrl'),
      creatorSlug: creator == null ? null : J.strOrNull(creator, 'slug'),
      isFollowingCreator: creator == null ? false : J.boolean(creator, 'isFollowing'),
      isSaved: J.boolean(json, 'isSaved'),
    );
  }

  final String id;
  final List<PostMedia> media;
  final String caption;
  final int likeCount;
  final DateTime createdAt;
  final Set<String> likedBy;

  /// First few people who liked it (name + avatar), for "Liked by …".
  final List<UserLite> likePreview;

  /// Creator profile id (used for follow / unfollow).
  final String? creatorId;

  /// The creator's user id (to hide Follow on your own posts).
  final String? creatorUserId;
  final String? creatorName;
  final String? creatorAvatarUrl;
  final String? creatorSlug;
  final bool isFollowingCreator;

  /// The current user saved this post.
  final bool isSaved;

  bool likedByUser(String userId) => likedBy.contains(userId);

  Post copyWith({
    int? likeCount,
    Set<String>? likedBy,
    List<UserLite>? likePreview,
    bool? isFollowingCreator,
    bool? isSaved,
  }) =>
      Post(
        id: id,
        media: media,
        caption: caption,
        likeCount: likeCount ?? this.likeCount,
        createdAt: createdAt,
        likedBy: likedBy ?? this.likedBy,
        likePreview: likePreview ?? this.likePreview,
        creatorId: creatorId,
        creatorUserId: creatorUserId,
        creatorName: creatorName,
        creatorAvatarUrl: creatorAvatarUrl,
        creatorSlug: creatorSlug,
        isFollowingCreator: isFollowingCreator ?? this.isFollowingCreator,
        isSaved: isSaved ?? this.isSaved,
      );

  /// Local like/unlike, keeping the "Liked by" preview in step.
  Post withLike({required UserLite me, required bool liked, required int count}) {
    final preview = likePreview.where((u) => u.id != me.id).toList();
    if (liked) preview.insert(0, me);
    return copyWith(
      likeCount: count < 0 ? 0 : count,
      likedBy: liked ? {...likedBy, me.id} : ({...likedBy}..remove(me.id)),
      likePreview: preview.take(3).toList(),
    );
  }

  @override
  List<Object?> get props => [id, caption, likeCount, likedBy, likePreview, isFollowingCreator, isSaved];
}

enum SessionType {
  free('free', 'Free'),
  paid('paid', 'Paid group'),
  oneToOne('one_to_one', '1:1 call');

  const SessionType(this.value, this.label);
  final String value;
  final String label;

  static SessionType from(String? v) => SessionType.values.firstWhere((t) => t.value == v, orElse: () => SessionType.free);
}

class LiveSession extends Equatable {
  const LiveSession({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.price,
    required this.scheduledAt,
    required this.durationMinutes,
    required this.maxParticipants,
    required this.bookedCount,
    required this.isLive,
    required this.isCompleted,
    required this.isCancelled,
    this.coverImageUrl,
    this.startUrl,
    this.category,
  });

  factory LiveSession.fromJson(Map<String, dynamic> json) => LiveSession(
    id: J.id(json),
    title: J.str(json, 'title'),
    description: J.str(json, 'description'),
    type: SessionType.from(J.strOrNull(json, 'type')),
    price: J.integer(json, 'price'),
    scheduledAt: J.date(json, 'scheduledAt') ?? DateTime.now(),
    durationMinutes: J.integer(json, 'durationMinutes'),
    maxParticipants: J.integer(json, 'maxParticipants'),
    bookedCount: J.integer(json, 'bookedCount'),
    isLive: J.boolean(json, 'isLive'),
    isCompleted: J.boolean(json, 'isCompleted'),
    isCancelled: J.boolean(json, 'isCancelled'),
    coverImageUrl: J.strOrNull(json, 'coverImageUrl'),
    startUrl: J.strOrNull(json, 'zoomStartUrl'),
    category: Category.fromRef(json, 'category'),
  );

  final String id;
  final String title;
  final String description;
  final SessionType type;
  final int price;
  final DateTime scheduledAt;
  final int durationMinutes;
  final int maxParticipants;
  final int bookedCount;
  final bool isLive;
  final bool isCompleted;
  final bool isCancelled;
  final String? coverImageUrl;

  /// Zoom host link — only returned to the session's owner.
  final String? startUrl;
  final Category? category;

  @override
  List<Object?> get props => [id, isLive, isCompleted, isCancelled, bookedCount];
}

class Tip extends Equatable {
  const Tip({required this.id, required this.amount, required this.message, required this.createdAt, this.from});

  factory Tip.fromJson(Map<String, dynamic> json) {
    final from = J.map(json, 'fromUser');
    return Tip(
      id: J.id(json),
      amount: J.integer(json, 'amount'),
      message: J.str(json, 'message'),
      createdAt: J.date(json, 'createdAt') ?? DateTime.now(),
      from: from == null ? null : UserLite.fromJson(from),
    );
  }

  final String id;
  final int amount;
  final String message;
  final DateTime createdAt;
  final UserLite? from;

  @override
  List<Object?> get props => [id];
}

class ContentRepository {
  const ContentRepository(this._api);

  final ApiClient _api;

  static const maxPosts = 5;
  static const maxMediaPerPost = 5;

  Future<List<Post>> myPosts() async => (await _api.get('/posts/me', parser: (d) => J.listOf(d, Post.fromJson))).data;

  Future<List<Post>> creatorPosts(String creatorProfileId) async =>
      (await _api.get('/posts/creator/$creatorProfileId', parser: (d) => J.listOf(d, Post.fromJson))).data;

  Future<Post> createPost({required List<PickedMedia> media, String caption = '', List<double?> aspectRatios = const []}) async {
    final form = FormData.fromMap({
      'caption': caption,
      if (aspectRatios.isNotEmpty) 'aspectRatios': jsonEncode(aspectRatios),
    });
    for (final item in media) {
      form.files.add(MapEntry('media', await multipartFrom(item)));
    }
    return (await _api.post('/posts', data: form, parser: (d) => Post.fromJson(J.asMap(d)))).data;
  }

  Future<void> deletePost(String id) async {
    await _api.delete('/posts/$id', parser: (_) => null);
  }

  Future<String> uploadSessionBanner(PickedMedia image) async {
    final form = FormData.fromMap({'banner': await multipartFrom(image)});
    return (await _api.post('/sessions/upload-banner', data: form, parser: (d) => J.str(J.asMap(d), 'coverImageUrl'))).data;
  }

  Future<LiveSession> createSession({
    required String title,
    required String description,
    required String categoryId,
    required SessionType type,
    required int price,
    required DateTime scheduledAt,
    required int durationMinutes,
    required int maxParticipants,
    String? coverImageUrl,
  }) async {
    final response = await _api.post(
      '/sessions',
      data: {
        'title': title,
        if (description.isNotEmpty) 'description': description,
        'category': categoryId,
        'type': type.value,
        'price': type == SessionType.free ? 0 : price,
        'scheduledAt': scheduledAt.toUtc().toIso8601String(),
        'durationMinutes': durationMinutes,
        'maxParticipants': maxParticipants,
        if (coverImageUrl != null) 'coverImageUrl': coverImageUrl,
      },
      parser: (d) => LiveSession.fromJson(J.asMap(d)),
    );
    return response.data;
  }

  /// Edit a session (cover, details) or postpone it with [scheduledAt].
  /// Everyone who booked is told about a new time.
  Future<LiveSession> updateSession(
      String id, {
        String? title,
        String? description,
        DateTime? scheduledAt,
        int? durationMinutes,
        int? maxParticipants,
        String? coverImageUrl,
        String? rescheduleNote,
      }) async =>
      (await _api.patch(
        '/sessions/$id',
        data: {
          if (title != null) 'title': title,
          if (description != null) 'description': description,
          if (scheduledAt != null) 'scheduledAt': scheduledAt.toUtc().toIso8601String(),
          if (durationMinutes != null) 'durationMinutes': durationMinutes,
          if (maxParticipants != null) 'maxParticipants': maxParticipants,
          if (coverImageUrl != null) 'coverImageUrl': coverImageUrl,
          if (rescheduleNote != null && rescheduleNote.isNotEmpty) 'rescheduleNote': rescheduleNote,
        },
        parser: (d) => LiveSession.fromJson(J.asMap(d)),
      ))
          .data;

  Future<void> cancelSession(String id) async {
    await _api.delete('/sessions/$id', parser: (_) => null);
  }

  Future<void> goLive(String id) async {
    await _api.patch('/sessions/$id/go-live', parser: (_) => null);
  }

  Future<void> endLive(String id) async {
    await _api.patch('/sessions/$id/end-live', parser: (_) => null);
  }

  Future<List<Post>> feed({int limit = 30}) async =>
      (await _api.get('/posts/feed', query: {'limit': limit}, parser: (d) => J.listOf(d, Post.fromJson))).data;

  /// One post (opened from a shared link).
  Future<Post> post(String id) async => (await _api.get('/posts/$id', parser: (d) => Post.fromJson(J.asMap(d)))).data;

  /// Posts the current user saved.
  Future<List<Post>> savedPosts() async => (await _api.get('/posts/saved', parser: (d) => J.listOf(d, Post.fromJson))).data;

  /// Saves or unsaves a post. Returns whether it's saved now.
  Future<bool> toggleSave(String postId) async =>
      (await _api.post('/posts/$postId/save', parser: (d) => J.boolean(J.asMap(d), 'saved'))).data;

  Future<({bool liked, int likeCount})> toggleLike(String postId) async =>
      (await _api.post('/posts/$postId/like', parser: (d) {
        final m = J.asMap(d);
        return (liked: J.boolean(m, 'liked'), likeCount: J.integer(m, 'likeCount'));
      }))
          .data;

  /// FanBox gifts a creator received.
  Future<List<Tip>> gifts(String creatorProfileId) async =>
      (await _api.get('/gifts/creator/$creatorProfileId', parser: (d) => J.listOf(d, Tip.fromJson))).data;

  /// Tips fans sent during a live session.
  Future<List<Tip>> sessionTips(String sessionId) async =>
      (await _api.get('/donations/session/$sessionId', parser: (d) => J.listOf(d, Tip.fromJson))).data;

  /// Everyone who liked a post.
  Future<List<UserLite>> likers(String postId) async =>
      (await _api.get('/posts/$postId/likes', parser: (d) => J.listOf(d, UserLite.fromJson))).data;
}