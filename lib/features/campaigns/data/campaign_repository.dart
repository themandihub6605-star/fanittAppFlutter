import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/models/common_models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/multipart.dart';
import '../../../core/services/media_picker.dart';
import '../../../core/utils/json.dart';
import 'campaign_models.dart';

class RazorpayOrder {
  const RazorpayOrder({required this.id, required this.amount});

  factory RazorpayOrder.fromJson(Map<String, dynamic> json) {
    final order = J.map(json, 'order') ?? json;
    return RazorpayOrder(id: J.str(order, 'id'), amount: J.integer(order, 'amount'));
  }

  final String id;
  final int amount;
}

class CampaignRepository {
  const CampaignRepository(this._api);

  final ApiClient _api;

  static Campaign _campaign(dynamic d) => Campaign.fromJson(J.asMap(d));

  // --- Discovery (creator) ---------------------------------------------------

  Future<Paged<Campaign>> list({String? categoryId, List<String>? ids, int page = 1}) async {
    final response = await _api.get(
      '/campaigns',
      query: {'page': page, 'limit': 20, if (categoryId != null) 'category': categoryId, if (ids != null && ids.isNotEmpty) 'ids': ids.join(',')},
      parser: (d) {
        final m = J.asMap(d);
        return Paged(
          items: J.list(m, 'campaigns', Campaign.fromJson),
          page: J.integer(m, 'page', 1),
          pages: J.integer(m, 'pages', 1),
          total: J.integer(m, 'total'),
        );
      },
    );
    return response.data;
  }

  Future<Campaign> byId(String id) async => (await _api.get('/campaigns/$id', parser: _campaign)).data;

  Future<List<Campaign>> saved() async =>
      (await _api.get('/campaigns/saved/me', parser: (d) => J.listOf(d, Campaign.fromJson))).data;

  Future<bool> toggleSave(String id) async =>
      (await _api.post('/campaigns/$id/save', parser: (d) => J.boolean(J.asMap(d), 'saved'))).data;

  Future<List<SuggestedCampaign>> suggested() async => (await _api.get(
    '/campaigns/suggested/me',
    parser: (d) => J.listOf(d, SuggestedCampaign.fromJson),
  ))
      .data;

  Future<(List<Proposal>, ProposalCounts)> myProposals() async {
    final response = await _api.get('/campaigns/proposals/me', parser: (d) {
      final m = J.asMap(d);
      return (J.list(m, 'proposals', Proposal.fromJson), ProposalCounts.fromJson(J.map(m, 'counts') ?? const {}));
    });
    return response.data;
  }

  Future<Proposal> apply(
      String campaignId, {
        required String pitch,
        int? quotedAmount,
        List<String> portfolioLinks = const [],
        String deliveryTimeline = '',
      }) async {
    final response = await _api.post(
      '/campaigns/$campaignId/apply',
      data: {
        'pitch': pitch,
        if (quotedAmount != null) 'quotedAmount': quotedAmount,
        if (portfolioLinks.isNotEmpty) 'portfolioLinks': portfolioLinks,
        if (deliveryTimeline.isNotEmpty) 'deliveryTimeline': deliveryTimeline,
      },
      parser: (d) => Proposal.fromJson(J.asMap(d)),
    );
    return response.data;
  }

  // --- Brand: drafts & publishing --------------------------------------------

  Future<Campaign> owned(String id) async => (await _api.get('/campaigns/$id/draft', parser: _campaign)).data;

  Future<Campaign> createDraft({
    required String title,
    required CampaignType type,
    required LocationType locationType,
    String? locationValue,
  }) async {
    final response = await _api.post(
      '/campaigns/draft',
      data: {
        'title': title,
        'campaignType': type.value,
        'locationType': locationType.value,
        if (locationValue != null && locationValue.isNotEmpty) 'locationValue': locationValue,
      },
      parser: _campaign,
    );
    return response.data;
  }

  Future<Campaign> updateDraft(String id, Map<String, dynamic> fields) async =>
      (await _api.patch('/campaigns/$id', data: fields, parser: _campaign)).data;

  Future<void> addProduct(
      String id, {
        required String name,
        required int price,
        required int quantity,
        String description = '',
        PickedMedia? image,
      }) async {
    final form = FormData.fromMap({
      'name': name,
      'description': description,
      'quantity': '$quantity',
      'price': '$price',
      if (image != null) 'image': await multipartFrom(image),
    });
    await _api.post('/campaigns/$id/products', data: form, parser: (_) => null);
  }

  Future<void> removeProduct(String id, String productId) async {
    await _api.delete('/campaigns/$id/products/$productId', parser: (_) => null);
  }

  Future<void> uploadMedia(String id, {PickedMedia? cover, List<PickedMedia> media = const []}) async {
    final form = FormData();
    if (cover != null) form.files.add(MapEntry('campaignImage', await multipartFrom(cover)));
    for (final item in media) {
      form.files.add(MapEntry('media', await multipartFrom(item)));
    }
    await _api.post('/campaigns/$id/media', data: form, parser: (_) => null);
  }

  /// Admin-set posting rules: minimum total budget (paise) and whether new
  /// campaigns wait for review.
  Future<({int minBudget, bool requiresApproval})> rules() async => (await _api.get(
    '/campaigns/rules',
    parser: (d) {
      final m = J.asMap(d);
      return (minBudget: J.integer(m, 'minCampaignBudget', 20000), requiresApproval: J.boolean(m, 'requireCampaignApproval', true));
    },
  ))
      .data;

  Future<Campaign> publish(String id) async =>
      (await _api.post('/campaigns/$id/publish', parser: _campaign)).data;

  // --- Brand: proposals ------------------------------------------------------

  Future<List<Proposal>> applications(String campaignId) async => (await _api.get(
    '/campaigns/$campaignId/applications',
    parser: (d) => J.listOf(d, Proposal.fromJson),
  ))
      .data;

  Future<void> decide(String campaignId, String applicationId, {required bool accept, String? reason}) async {
    await _api.patch(
      '/campaigns/$campaignId/applications/$applicationId',
      data: {'decision': accept ? 'accepted' : 'rejected', if (reason != null) 'rejectionReason': reason},
      parser: (_) => null,
    );
  }

  // --- Milestones ------------------------------------------------------------

  Future<List<Milestone>> milestones(String campaignId) async => (await _api.get(
    '/campaigns/$campaignId/milestones',
    parser: (d) => J.listOf(d, Milestone.fromJson),
  ))
      .data;

  Future<RazorpayOrder> fundMilestone(String milestoneId) async => (await _api.post(
    '/milestones/$milestoneId/fund',
    parser: (d) => RazorpayOrder.fromJson(J.asMap(d)),
  ))
      .data;

  Future<void> verifyMilestonePayment(
      String milestoneId, {
        required String orderId,
        required String paymentId,
        required String signature,
      }) async {
    await _api.post(
      '/milestones/$milestoneId/verify-payment',
      data: {'razorpayOrderId': orderId, 'razorpayPaymentId': paymentId, 'razorpaySignature': signature},
      parser: (_) => null,
    );
  }

  Future<void> approveMilestone(String milestoneId) async {
    await _api.patch('/milestones/$milestoneId/approve', parser: (_) => null);
  }

  Future<void> submitMilestone(
      String milestoneId, {
        required String description,
        List<String> links = const [],
        List<PickedMedia> files = const [],
      }) async {
    final form = FormData.fromMap({'description': description, 'links': jsonEncode(links)});
    for (final file in files) {
      form.files.add(MapEntry('files', await multipartFrom(file)));
    }
    await _api.patch('/milestones/$milestoneId/submit', data: form, parser: (_) => null);
  }

  Future<void> requestChanges(
      String milestoneId, {
        required String description,
        List<String> links = const [],
        List<PickedMedia> files = const [],
      }) async {
    final form = FormData.fromMap({'changeDescription': description, 'referenceLinks': jsonEncode(links)});
    for (final file in files) {
      form.files.add(MapEntry('files', await multipartFrom(file)));
    }
    await _api.patch('/milestones/$milestoneId/request-changes', data: form, parser: (_) => null);
  }

  Future<void> raiseDispute(String milestoneId, {required String reason, List<PickedMedia> files = const []}) async {
    final form = FormData.fromMap({'reason': reason});
    for (final file in files) {
      form.files.add(MapEntry('files', await multipartFrom(file)));
    }
    await _api.post('/milestones/$milestoneId/dispute', data: form, parser: (_) => null);
  }
}

class SuggestedCampaign {
  const SuggestedCampaign({required this.campaign, required this.score, required this.reasons});

  factory SuggestedCampaign.fromJson(Map<String, dynamic> json) => SuggestedCampaign(
    campaign: Campaign.fromJson(J.map(json, 'campaign') ?? const {}),
    score: J.integer(json, 'matchScore'),
    reasons: J.strings(json, 'matchReasons'),
  );

  final Campaign campaign;
  final int score;
  final List<String> reasons;
}