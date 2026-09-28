import '../../../core/models/common_models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';

class ReviewRepository {
  const ReviewRepository(this._api);

  final ApiClient _api;

  Future<List<Review>> forUser(String userId) async =>
      (await _api.get('/reviews/user/$userId', parser: (d) => J.listOf(d, Review.fromJson))).data;

  /// Reviews the other side of a completed campaign.
  Future<void> reviewCampaign({required String toUserId, required String campaignId, required int rating, String comment = ''}) async {
    await _api.post(
      '/reviews',
      data: {'toUser': toUserId, 'relatedModel': 'Campaign', 'relatedId': campaignId, 'rating': rating, 'comment': comment},
      parser: (_) => null,
    );
  }
}
