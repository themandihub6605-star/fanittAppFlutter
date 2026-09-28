import '../../../core/models/common_models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';
import '../../content/data/content_repository.dart';
import '../../profile/data/profile_models.dart';

class CreatorPublicProfile {
  const CreatorPublicProfile({
    required this.creator,
    required this.reviews,
    required this.projectsCompleted,
    required this.posts,
  });

  final CreatorProfile creator;
  final List<Review> reviews;
  final int projectsCompleted;
  final List<Post> posts;
}

class CreatorsRepository {
  const CreatorsRepository(this._api, this._content);

  final ApiClient _api;
  final ContentRepository _content;

  Future<Paged<CreatorProfile>> list({String? search, String? categoryId, int page = 1}) async =>
      (await _api.get(
        '/creators',
        query: {
          'page': page,
          'limit': 20,
          if (search != null && search.isNotEmpty) 'search': search,
          if (categoryId != null) 'category': categoryId,
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
    final creator = CreatorProfile.fromJson(J.map(profile, 'creator') ?? const {});
    final posts = await _content.creatorPosts(creator.id);
    return CreatorPublicProfile(
      creator: creator,
      reviews: J.list(profile, 'reviews', Review.fromJson),
      projectsCompleted: J.integer(J.map(profile, 'stats') ?? const {}, 'projectsCompletedCount'),
      posts: posts,
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
