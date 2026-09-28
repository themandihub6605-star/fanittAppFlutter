import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/multipart.dart';
import '../../../core/services/media_picker.dart';
import '../../../core/utils/json.dart';
import '../../../core/models/common_models.dart';
import 'profile_models.dart';

class FollowingItem {
  const FollowingItem({required this.id, required this.isCreator, required this.slug, required this.name, this.avatarUrl, this.subtitle});

  factory FollowingItem.fromJson(Map<String, dynamic> json) => FollowingItem(
        id: J.id(json),
        isCreator: J.str(json, 'type') == 'creator',
        slug: J.str(json, 'slug'),
        name: J.str(json, 'name'),
        avatarUrl: J.strOrNull(json, 'avatarUrl'),
        subtitle: J.strOrNull(json, 'subtitle'),
      );

  final String id;
  final bool isCreator;
  final String slug;
  final String name;
  final String? avatarUrl;
  final String? subtitle;
}

class ReferralSummary {
  const ReferralSummary({required this.code, required this.people, required this.totalEarned});

  final String code;
  final List<(UserLite, DateTime)> people;
  final int totalEarned;
}

/// The signed-in user's own creator / brand / agency profile.
class ProfileRepository {
  const ProfileRepository(this._api);

  final ApiClient _api;

  Future<CreatorProfile> creator() async =>
      (await _api.get('/creators/me', parser: (d) => CreatorProfile.fromJson(J.asMap(d)))).data;

  Future<CreatorProfile> updateCreator(Map<String, dynamic> body) async =>
      (await _api.patch('/creators/me', data: body, parser: (d) => CreatorProfile.fromJson(J.asMap(d)))).data;

  Future<BrandProfile> brand() async =>
      (await _api.get('/brands/me', parser: (d) => BrandProfile.fromJson(J.asMap(d)))).data;

  Future<BrandProfile> updateBrand(Map<String, dynamic> body) async =>
      (await _api.patch('/brands/me', data: body, parser: (d) => BrandProfile.fromJson(J.asMap(d)))).data;

  Future<AgencyProfile> agency() async =>
      (await _api.get('/agency/me', parser: (d) => AgencyProfile.fromJson(J.asMap(d)))).data;

  Future<AgencyProfile> updateAgency(Map<String, dynamic> body) async =>
      (await _api.patch('/agency/me', data: body, parser: (d) => AgencyProfile.fromJson(J.asMap(d)))).data;

  Future<String> uploadAvatar(PickedMedia file) async {
    final form = FormData.fromMap({'avatar': await multipartFrom(file)});
    return (await _api.patch('/users/me/avatar', data: form, parser: (d) => J.str(J.asMap(d), 'avatarUrl'))).data;
  }

  Future<String> uploadBrandLogo(PickedMedia file) async {
    final form = FormData.fromMap({'logo': await multipartFrom(file)});
    return (await _api.post('/brands/upload-logo', data: form, parser: (d) => J.str(J.asMap(d), 'logoUrl'))).data;
  }

  Future<String> uploadAgencyDocument(PickedMedia file) async {
    final form = FormData.fromMap({'document': await multipartFrom(file)});
    return (await _api.post('/agency/upload-document', data: form, parser: (d) => J.str(J.asMap(d), 'documentUrl'))).data;
  }

  Future<void> linkAgency({required bool asCreator, required String referralCode}) async {
    await _api.post(
      asCreator ? '/agency/link-creator' : '/agency/link-brand',
      data: {'referralCode': referralCode},
      parser: (_) => null,
    );
  }

  Future<void> updateAccount({String? name, String? phone}) async {
    await _api.patch(
      '/users/me',
      data: {if (name != null) 'name': name, if (phone != null) 'phone': phone},
      parser: (_) => null,
    );
  }

  Future<ReferralSummary> myReferrals() async => (await _api.get('/users/me/referrals', parser: (d) {
        final m = J.asMap(d);
        return ReferralSummary(
          code: J.str(m, 'referralCode'),
          totalEarned: J.integer(m, 'totalEarned'),
          people: J.list(m, 'referredUsers', (u) => (UserLite.fromJson(u), J.date(u, 'createdAt') ?? DateTime.now())),
        );
      }))
          .data;

  Future<void> changePassword({required String current, required String next}) async {
    await _api.patch('/users/me/password', data: {'currentPassword': current, 'newPassword': next}, parser: (_) => null);
  }

  Future<void> deleteAccount() async {
    await _api.delete('/users/me', parser: (_) => null);
  }

  Future<List<FollowingItem>> following() async =>
      (await _api.get('/users/me/following', parser: (d) => J.listOf(d, FollowingItem.fromJson))).data;

  Future<void> completeOnboarding() async {
    await _api.post('/auth/complete-onboarding', parser: (_) => null);
  }

  Future<PublicStats> publicStats() async =>
      (await _api.get('/stats/public', parser: (d) => PublicStats.fromJson(J.asMap(d)))).data;
}

class PublicStats {
  const PublicStats({required this.creators, required this.brands, required this.paidOut});

  factory PublicStats.fromJson(Map<String, dynamic> json) => PublicStats(
        creators: J.integer(json, 'activeCreators'),
        brands: J.integer(json, 'activeBrands'),
        paidOut: J.integer(json, 'totalPaidOut'),
      );

  final int creators;
  final int brands;
  final int paidOut;
}
