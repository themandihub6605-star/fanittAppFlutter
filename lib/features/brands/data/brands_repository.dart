import '../../../core/models/common_models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';
import '../../campaigns/data/campaign_models.dart';
import '../../profile/data/profile_models.dart';

class BrandListItem {
  const BrandListItem({required this.profile, required this.logoUrl, required this.isPro, required this.followerCount});

  factory BrandListItem.fromJson(Map<String, dynamic> json) {
    final user = J.map(json, 'user');
    final profile = BrandProfile.fromJson(json);
    return BrandListItem(
      profile: profile,
      logoUrl: profile.logoUrl ?? (user == null ? null : J.strOrNull(user, 'avatarUrl')),
      isPro: J.boolean(json, 'isProPlan'),
      followerCount: J.integer(json, 'followerCount'),
    );
  }

  final BrandProfile profile;
  final String? logoUrl;
  final bool isPro;
  final int followerCount;
}

class BrandPublicProfile {
  const BrandPublicProfile({
    required this.brand,
    required this.campaigns,
    required this.campaignsPosted,
    required this.reviews,
    required this.isFollowing,
    required this.followerCount,
  });

  final BrandProfile brand;
  final List<Campaign> campaigns;
  final int campaignsPosted;
  final List<Review> reviews;
  final bool isFollowing;
  final int followerCount;

  BrandPublicProfile copyWith({bool? isFollowing, int? followerCount}) => BrandPublicProfile(
    brand: brand,
    campaigns: campaigns,
    campaignsPosted: campaignsPosted,
    reviews: reviews,
    isFollowing: isFollowing ?? this.isFollowing,
    followerCount: followerCount ?? this.followerCount,
  );
}

class BrandsRepository {
  const BrandsRepository(this._api);

  final ApiClient _api;

  Future<Paged<BrandListItem>> list({String? search, List<String>? ids, int page = 1}) async => (await _api.get(
    '/brands',
    query: {'page': page, 'limit': 20, if (search != null && search.isNotEmpty) 'search': search, if (ids != null && ids.isNotEmpty) 'ids': ids.join(',')},
    parser: (d) {
      final m = J.asMap(d);
      final total = J.integer(m, 'total');
      final limit = J.integer(m, 'limit', 20);
      return Paged(
        items: J.list(m, 'brands', BrandListItem.fromJson),
        page: J.integer(m, 'page', 1),
        pages: limit == 0 ? 1 : (total / limit).ceil().clamp(1, 1 << 20).toInt(),
        total: total,
      );
    },
  ))
      .data;

  /// [myUserId] decides the follow state from the followers list.
  Future<BrandPublicProfile> bySlug(String slug, {required String myUserId}) async {
    final data = (await _api.get('/brands/slug/$slug', parser: (d) => J.asMap(d))).data;
    final brandJson = J.map(data, 'brand') ?? const <String, dynamic>{};
    final brand = BrandProfile.fromJson(brandJson);
    final followers = (brandJson['followers'] as List<dynamic>? ?? const []).map((f) => f.toString()).toSet();
    final reviews = brand.userId.isEmpty
        ? const <Review>[]
        : (await _api.get('/reviews/user/${brand.userId}', parser: (d) => J.listOf(d, Review.fromJson))).data;
    return BrandPublicProfile(
      brand: brand,
      campaigns: J.list(data, 'campaigns', Campaign.fromJson),
      campaignsPosted: J.integer(J.map(data, 'stats') ?? const {}, 'campaignsPosted'),
      reviews: reviews,
      isFollowing: followers.contains(myUserId),
      followerCount: J.integer(brandJson, 'followerCount'),
    );
  }

  Future<bool> toggleFollow(String brandProfileId) async =>
      (await _api.post('/brands/$brandProfileId/follow', parser: (d) => J.boolean(J.asMap(d), 'following'))).data;
}