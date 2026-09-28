import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';
import '../../campaigns/data/campaign_models.dart';
import '../../content/data/content_repository.dart';
import '../../wallet/data/wallet_repository.dart';

class CreatorDashboard {
  const CreatorDashboard({
    required this.creatorId,
    required this.totalEarnings,
    required this.thisMonthEarnings,
    required this.followerCount,
    required this.averageRating,
    required this.reviewCount,
    required this.profileViews,
    required this.upcomingSessions,
    required this.recentTransactions,
  });

  factory CreatorDashboard.fromJson(Map<String, dynamic> json, String myUserId) {
    final stats = J.map(json, 'stats') ?? const <String, dynamic>{};
    return CreatorDashboard(
      creatorId: J.str(json, 'creatorId'),
      totalEarnings: J.integer(stats, 'totalEarnings'),
      thisMonthEarnings: J.integer(stats, 'thisMonthEarnings'),
      followerCount: J.integer(stats, 'followerCount'),
      averageRating: J.dbl(stats, 'averageRating'),
      reviewCount: J.integer(stats, 'reviewCount'),
      profileViews: J.integer(stats, 'profileViews'),
      upcomingSessions: J.list(json, 'upcomingSessions', LiveSession.fromJson),
      recentTransactions: J.list(json, 'recentTransactions', (t) => WalletTransaction.fromJson(t, myUserId: myUserId)),
    );
  }

  final String creatorId;
  final int totalEarnings;
  final int thisMonthEarnings;
  final int followerCount;
  final double averageRating;
  final int reviewCount;
  final int profileViews;
  final List<LiveSession> upcomingSessions;
  final List<WalletTransaction> recentTransactions;
}

class BrandDashboard {
  const BrandDashboard({
    required this.totalCampaigns,
    required this.totalSpent,
    required this.averageRating,
    required this.profileViews,
    required this.campaigns,
    required this.inEscrow,
  });

  factory BrandDashboard.fromJson(Map<String, dynamic> json) {
    final stats = J.map(json, 'stats') ?? const <String, dynamic>{};
    final spend = J.list(json, 'spendBreakdown', (m) => m);
    final inEscrow = spend.where((m) => m['_id'] == 'in_escrow').fold<int>(0, (sum, m) => sum + J.integer(m, 'total'));
    return BrandDashboard(
      totalCampaigns: J.integer(stats, 'totalCampaigns'),
      totalSpent: J.integer(stats, 'totalSpent'),
      averageRating: J.dbl(stats, 'averageRating'),
      profileViews: J.integer(stats, 'profileViews'),
      campaigns: J.list(json, 'campaigns', Campaign.fromJson),
      inEscrow: inEscrow,
    );
  }

  final int totalCampaigns;
  final int totalSpent;
  final double averageRating;
  final int profileViews;
  final List<Campaign> campaigns;
  final int inEscrow;
}

class DashboardRepository {
  const DashboardRepository(this._api);

  final ApiClient _api;

  Future<CreatorDashboard> creator(String myUserId) async => (await _api.get(
        '/creators/me/dashboard',
        parser: (d) => CreatorDashboard.fromJson(J.asMap(d), myUserId),
      ))
          .data;

  Future<BrandDashboard> brand() async =>
      (await _api.get('/brands/me/dashboard', parser: (d) => BrandDashboard.fromJson(J.asMap(d)))).data;
}
