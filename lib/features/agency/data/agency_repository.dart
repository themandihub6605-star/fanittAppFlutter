import 'package:equatable/equatable.dart';

import '../../../core/enums/user_role.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';

class AgencyDashboard {
  const AgencyDashboard({
    required this.referralCode,
    required this.totalReferrals,
    required this.creatorCount,
    required this.brandCount,
    required this.totalCommission,
    required this.thisMonthCommission,
    required this.walletBalance,
    required this.verificationStatus,
  });

  factory AgencyDashboard.fromJson(Map<String, dynamic> json) {
    final stats = J.map(json, 'stats') ?? const <String, dynamic>{};
    return AgencyDashboard(
      referralCode: J.str(stats, 'referralCode'),
      totalReferrals: J.integer(stats, 'totalReferrals'),
      creatorCount: J.integer(stats, 'referredCreatorCount'),
      brandCount: J.integer(stats, 'referredBrandCount'),
      totalCommission: J.integer(stats, 'totalCommissionEarned'),
      thisMonthCommission: J.integer(stats, 'thisMonthCommission'),
      walletBalance: J.integer(stats, 'walletBalance'),
      verificationStatus: VerificationStatus.fromValue(J.strOrNull(stats, 'verificationStatus')) ?? VerificationStatus.unverified,
    );
  }

  final String referralCode;
  final int totalReferrals;
  final int creatorCount;
  final int brandCount;
  final int totalCommission;
  final int thisMonthCommission;
  final int walletBalance;
  final VerificationStatus verificationStatus;
}

class Referral extends Equatable {
  const Referral({required this.id, required this.isCreator, required this.name, required this.joinedAt, this.avatarUrl, this.totalEarnings});

  factory Referral.fromJson(Map<String, dynamic> json) => Referral(
        id: J.id(json),
        isCreator: J.str(json, 'type') == 'creator',
        name: J.str(json, 'name', 'Member'),
        avatarUrl: J.strOrNull(json, 'avatarUrl'),
        totalEarnings: J.integerOrNull(json, 'totalEarnings'),
        joinedAt: J.date(json, 'joinedAt') ?? DateTime.now(),
      );

  final String id;
  final bool isCreator;
  final String name;
  final String? avatarUrl;
  final int? totalEarnings;
  final DateTime joinedAt;

  @override
  List<Object?> get props => [id];
}

class AgencyRepository {
  const AgencyRepository(this._api);

  final ApiClient _api;

  Future<AgencyDashboard> dashboard() async =>
      (await _api.get('/agency/me/dashboard', parser: (d) => AgencyDashboard.fromJson(J.asMap(d)))).data;

  Future<List<Referral>> referrals() async =>
      (await _api.get('/agency/me/referrals', parser: (d) => J.listOf(d, Referral.fromJson))).data;
}
