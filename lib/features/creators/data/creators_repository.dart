import '../../../core/models/common_models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';
import '../../content/data/content_repository.dart';
import '../../profile/data/profile_models.dart';

/// A creator's Fanitt Store, if they have an active one.
class CreatorStoreRef {
  const CreatorStoreRef({required this.slug, required this.name, required this.logoUrl, required this.tagline, required this.isOpen});

  factory CreatorStoreRef.fromJson(Map<String, dynamic> json) => CreatorStoreRef(
    slug: J.str(json, 'slug'),
    name: J.str(json, 'name'),
    logoUrl: J.str(json, 'logoUrl'),
    tagline: J.str(json, 'tagline'),
    isOpen: J.boolean(json, 'isOpen', true),
  );

  final String slug;
  final String name;
  final String logoUrl;
  final String tagline;
  final bool isOpen;
}

/// An upcoming live session on a creator's profile.
class CreatorSessionRef {
  const CreatorSessionRef({required this.id, required this.title, required this.scheduledAt, required this.price, required this.durationMinutes});

  factory CreatorSessionRef.fromJson(Map<String, dynamic> json) => CreatorSessionRef(
    id: J.id(json),
    title: J.str(json, 'title'),
    scheduledAt: J.date(json, 'scheduledAt'),
    price: J.integer(json, 'price'),
    durationMinutes: J.integer(json, 'durationMinutes'),
  );

  final String id;
  final String title;
  final DateTime? scheduledAt;
  final int price;
  final int durationMinutes;
}

class CreatorPublicProfile {
  const CreatorPublicProfile({
    required this.creator,
    required this.reviews,
    required this.projectsCompleted,
    required this.posts,
    this.store,
    this.sessions = const [],
    this.portfolioImages = const [],
    this.onTimeDeliveryPercent = 100,
    this.isTopCreator = false,
    this.profileViews = 0,
    this.joinedAt,
  });

  final CreatorProfile creator;
  final List<Review> reviews;
  final int projectsCompleted;

  /// Posts AND reels (check [Post.isReel]).
  final List<Post> posts;
  final CreatorStoreRef? store;
  final List<CreatorSessionRef> sessions;
  final List<String> portfolioImages;
  final int onTimeDeliveryPercent;
  final bool isTopCreator;
  final int profileViews;
  final DateTime? joinedAt;

  CreatorPublicProfile withCreator(CreatorProfile updated) => CreatorPublicProfile(
    creator: updated,
    reviews: reviews,
    projectsCompleted: projectsCompleted,
    posts: posts,
    store: store,
    sessions: sessions,
    portfolioImages: portfolioImages,
    onTimeDeliveryPercent: onTimeDeliveryPercent,
    isTopCreator: isTopCreator,
    profileViews: profileViews,
    joinedAt: joinedAt,
  );
}

class CreatorsRepository {
  const CreatorsRepository(this._api, this._content);

  final ApiClient _api;
  final ContentRepository _content;

  /// [ids] = load exactly these creators (admin-pinned on the home screen).
  Future<Paged<CreatorProfile>> list({String? search, String? categoryId, List<String>? ids, int page = 1}) async =>
      (await _api.get(
        '/creators',
        query: {
          'page': page,
          'limit': 20,
          if (search != null && search.isNotEmpty) 'search': search,
          if (categoryId != null) 'category': categoryId,
          if (ids != null && ids.isNotEmpty) 'ids': ids.join(','),
        },
        parser: (d) {
          final m = J.asMap(d);
          return Paged(
            items: J.list(m, 'creators', CreatorProfile.fromJson),
            page: J.integer(m, 'page', 1),
            pages: J.integer(m, 'pages', 1),
            total: J.integer(m, 'total'),
          );
        },
      ))
          .data;

  Future<CreatorPublicProfile> bySlug(String slug) async {
    final profile = (await _api.get('/creators/$slug', parser: (d) => J.asMap(d))).data;
    final raw = J.map(profile, 'creator') ?? const <String, dynamic>{};
    final creator = CreatorProfile.fromJson(raw);
    final posts = await _content.creatorPosts(creator.id);
    final stats = J.map(profile, 'stats') ?? const <String, dynamic>{};
    final store = J.map(profile, 'store');
    return CreatorPublicProfile(
      creator: creator,
      reviews: J.list(profile, 'reviews', Review.fromJson),
      projectsCompleted: J.integer(stats, 'projectsCompletedCount'),
      posts: posts,
      store: store == null ? null : CreatorStoreRef.fromJson(store),
      sessions: J.list(profile, 'sessions', CreatorSessionRef.fromJson),
      portfolioImages: J.strings(raw, 'portfolioImages'),
      onTimeDeliveryPercent: J.integer(raw, 'onTimeDeliveryPercent', 100),
      isTopCreator: J.boolean(raw, 'isTopCreator'),
      profileViews: J.integer(stats, 'profileViews', J.integer(raw, 'profileViews')),
      joinedAt: J.date(raw, 'createdAt'),
    );
  }

  Future<({bool following, int followerCount})> toggleFollow(String creatorProfileId) async {
    final response = await _api.post('/creators/$creatorProfileId/follow', parser: (d) {
      final m = J.asMap(d);
      return (following: J.boolean(m, 'following'), followerCount: J.integer(m, 'followerCount'));
    });
    return response.data;
  }
}