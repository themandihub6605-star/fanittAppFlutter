import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/models/common_models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/multipart.dart';
import '../../../core/services/media_picker.dart';
import '../../../core/utils/json.dart';
import '../../store/data/store_repository.dart' show CheckoutStart, PayWith;
import 'community_models.dart';

export 'community_models.dart';

/// What the create / edit screen needs to know.
class CommunityConfig {
  const CommunityConfig({
    required this.requireSubscription,
    required this.hasSubscription,
    required this.planName,
    required this.paidEnabled,
    required this.canSell,
    required this.feePercent,
    required this.minPrice,
    required this.maxPrice,
  });

  factory CommunityConfig.fromJson(Map<String, dynamic> json) => CommunityConfig(
    requireSubscription: J.boolean(json, 'requireSubscription'),
    hasSubscription: J.boolean(json, 'hasSubscription'),
    planName: J.str(json, 'planName'),
    paidEnabled: J.boolean(json, 'paidCommunitiesEnabled', true),
    canSell: J.boolean(json, 'canSell'),
    feePercent: J.dbl(json, 'feePercent'),
    minPrice: J.integer(json, 'minPrice', 1000),
    maxPrice: J.integer(json, 'maxPrice', 10000000),
  );

  /// Admin switched on "paid plan needed to create a community".
  final bool requireSubscription;
  final bool hasSubscription;
  final String planName;

  /// Paid communities allowed at all, and this user may sell (creator).
  final bool paidEnabled;
  final bool canSell;

  /// Fanitt's cut of each payment, in %.
  final double feePercent;
  final int minPrice;
  final int maxPrice;

  bool get blocked => requireSubscription && !hasSubscription;
}

enum CommunitySort {
  trending('trending', 'Trending'),
  popular('popular', 'Popular'),
  newest('new', 'New');

  const CommunitySort(this.value, this.label);
  final String value;
  final String label;
}

class CommunityInput {
  const CommunityInput({
    this.name,
    this.description,
    this.categoryId,
    this.isPrivate,
    this.onlyModeratorsPost,
    this.chatEnabled,
    this.rules,
    this.icon,
    this.cover,
    this.isPaid,
    this.plans,
  });

  /// Paid community on/off, and every plan with its price (paise) —
  /// a plan that is off is sent with enabled: false.
  final bool? isPaid;
  final Map<CommunityPlanKey, ({bool enabled, int price})>? plans;

  final String? name;
  final String? description;
  final String? categoryId;
  final bool? isPrivate;
  final bool? onlyModeratorsPost;
  final bool? chatEnabled;
  final List<String>? rules;
  final PickedMedia? icon;
  final PickedMedia? cover;

  Future<FormData> toFormData() async {
    final form = FormData.fromMap({
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (categoryId != null) 'category': categoryId,
      if (isPrivate != null) 'visibility': isPrivate! ? 'private' : 'public',
      if (onlyModeratorsPost != null) 'postPermission': onlyModeratorsPost! ? 'moderators' : 'all',
      if (chatEnabled != null) 'chatEnabled': '$chatEnabled',
      if (rules != null) 'rules': jsonEncode(rules),
      if (isPaid != null) 'isPaid': '$isPaid',
      if (plans != null)
        'plans': jsonEncode({
          for (final e in plans!.entries) e.key.value: {'enabled': e.value.enabled, 'price': e.value.price},
        }),
    });
    if (icon != null) form.files.add(MapEntry('icon', await multipartFrom(icon!)));
    if (cover != null) form.files.add(MapEntry('cover', await multipartFrom(cover!)));
    return form;
  }
}

class NewCommunityPost {
  const NewCommunityPost({
    required this.text,
    this.media = const [],
    this.pollQuestion = '',
    this.pollOptions = const [],
    this.pollDays = 3,
    this.isAnnouncement = false,
    this.mentionIds = const [],
  });

  final String text;
  final List<PickedMedia> media;
  final String pollQuestion;
  final List<String> pollOptions;
  final int pollDays;
  final bool isAnnouncement;
  final List<String> mentionIds;

  bool get hasPoll => pollOptions.length >= 2;
}

class CommunityRepository {
  const CommunityRepository(this._api);

  final ApiClient _api;

  static Community _community(dynamic d) => Community.fromJson(J.asMap(d));

  // --- Communities ---------------------------------------------------------

  Future<Paged<Community>> list({String? search, String? categoryId, CommunitySort sort = CommunitySort.trending, List<String>? ids, int page = 1}) async =>
      (await _api.get(
        '/communities',
        query: {
          'page': page,
          if (ids != null && ids.isNotEmpty) 'ids': ids.join(','),
          'limit': 20,
          'sort': sort.value,
          if (search != null && search.isNotEmpty) 'search': search,
          if (categoryId != null) 'category': categoryId,
        },
        parser: (d) {
          final m = J.asMap(d);
          return Paged(
            items: J.list(m, 'communities', Community.fromJson),
            page: J.integer(m, 'page', 1),
            pages: J.integer(m, 'pages', 1),
            total: J.integer(m, 'total'),
          );
        },
      ))
          .data;

  Future<List<Community>> mine() async => (await _api.get('/communities/me', parser: (d) => J.listOf(d, Community.fromJson))).data;

  Future<Community> bySlug(String slugOrId) async => (await _api.get('/communities/$slugOrId', parser: _community)).data;

  Future<Community> create(CommunityInput input) async =>
      (await _api.post('/communities', data: await input.toFormData(), parser: _community)).data;

  Future<Community> update(String id, CommunityInput input) async =>
      (await _api.patch('/communities/$id', data: await input.toFormData(), parser: _community)).data;

  Future<void> delete(String id) async {
    await _api.delete('/communities/$id', parser: (_) => null);
  }

  /// Join / leave / request / cancel. Returns the new status (null = not a member).
  Future<MembershipStatus?> toggleJoin(String id) async => (await _api.post(
    '/communities/$id/join',
    parser: (d) => MembershipStatus.from(J.strOrNull(J.asMap(d), 'status')),
  ))
      .data;

  /// Starts buying a plan of a paid community — pay with
  /// payForStoreItem (store_checkout.dart), verify is the store's.
  Future<CheckoutStart> checkout(String id, CommunityPlanKey plan, {PayWith payWith = PayWith.razorpay}) async => (await _api.post(
    '/communities/$id/checkout',
    data: {'plan': plan.value, 'payWith': payWith.value},
    parser: (d) => CheckoutStart.fromJson(J.asMap(d)),
  ))
      .data;

  /// Rules for the create / edit screen.
  Future<CommunityConfig> config() async => (await _api.get('/communities/config', parser: (d) => CommunityConfig.fromJson(J.asMap(d)))).data;

  Future<void> setMuted(String id, bool muted) async {
    await _api.patch('/communities/$id/me', data: {'notificationsMuted': muted}, parser: (_) => null);
  }

  // --- Members -------------------------------------------------------------

  Future<Paged<CommunityMember>> members(String id, {MembershipStatus status = MembershipStatus.active, String? search, int page = 1}) async =>
      (await _api.get(
        '/communities/$id/members',
        query: {'status': status.name, 'page': page, if (search != null && search.isNotEmpty) 'search': search},
        parser: (d) {
          final m = J.asMap(d);
          return Paged(
            items: J.list(m, 'members', CommunityMember.fromJson),
            page: J.integer(m, 'page', 1),
            pages: J.integer(m, 'pages', 1),
            total: J.integer(m, 'total'),
          );
        },
      ))
          .data;

  Future<void> manageMember(String id, String userId, MemberAction action) async {
    await _api.patch('/communities/$id/members/$userId', data: {'action': action.value}, parser: (_) => null);
  }

  // --- Posts ---------------------------------------------------------------

  Future<Paged<CommunityPost>> posts(String id, {bool top = false, int page = 1}) async => (await _api.get(
    '/communities/$id/posts',
    query: {'page': page, 'sort': top ? 'top' : 'new'},
    parser: (d) {
      final m = J.asMap(d);
      return Paged(
        items: J.list(m, 'posts', CommunityPost.fromJson),
        page: J.integer(m, 'page', 1),
        pages: J.integer(m, 'pages', 1),
        total: J.integer(m, 'total'),
      );
    },
  ))
      .data;

  Future<CommunityPost> createPost(String id, NewCommunityPost input) async {
    final form = FormData.fromMap({
      'text': input.text,
      if (input.hasPoll)
        'poll': jsonEncode({'question': input.pollQuestion, 'options': input.pollOptions, 'durationHours': input.pollDays * 24}),
      if (input.isAnnouncement) 'isAnnouncement': 'true',
      if (input.mentionIds.isNotEmpty) 'mentions': jsonEncode(input.mentionIds),
    });
    for (final item in input.media) {
      form.files.add(MapEntry('media', await multipartFrom(item)));
    }
    return (await _api.post('/communities/$id/posts', data: form, parser: (d) => CommunityPost.fromJson(J.asMap(d)))).data;
  }

  Future<CommunityPost> post(String postId) async =>
      (await _api.get('/communities/posts/$postId', parser: (d) => CommunityPost.fromJson(J.asMap(d)))).data;

  Future<CommunityPost> editPost(String postId, String text) async => (await _api.patch(
    '/communities/posts/$postId',
    data: {'text': text},
    parser: (d) => CommunityPost.fromJson(J.asMap(d)),
  ))
      .data;

  Future<void> deletePost(String postId) async {
    await _api.delete('/communities/posts/$postId', parser: (_) => null);
  }

  Future<({bool liked, int likeCount})> likePost(String postId) async =>
      (await _api.post('/communities/posts/$postId/like', parser: (d) {
        final m = J.asMap(d);
        return (liked: J.boolean(m, 'liked'), likeCount: J.integer(m, 'likeCount'));
      }))
          .data;

  Future<bool> togglePin(String postId) async =>
      (await _api.post('/communities/posts/$postId/pin', parser: (d) => J.boolean(J.asMap(d), 'isPinned'))).data;

  Future<PostPoll> vote(String postId, int optionIndex) async => (await _api.post(
    '/communities/posts/$postId/vote',
    data: {'optionIndex': optionIndex},
    parser: (d) => PostPoll.fromJson(J.asMap(d))!,
  ))
      .data;

  // --- Comments ------------------------------------------------------------

  Future<Paged<CommunityComment>> comments(String postId, {int page = 1}) async => (await _api.get(
    '/communities/posts/$postId/comments',
    query: {'page': page},
    parser: (d) {
      final m = J.asMap(d);
      return Paged(
        items: J.list(m, 'comments', CommunityComment.fromJson),
        page: J.integer(m, 'page', 1),
        pages: J.integer(m, 'pages', 1),
        total: J.integer(m, 'total'),
      );
    },
  ))
      .data;

  Future<CommunityComment> addComment(String postId, String text, {String? parentId}) async => (await _api.post(
    '/communities/posts/$postId/comments',
    data: {'text': text, if (parentId != null) 'parentId': parentId},
    parser: (d) => CommunityComment.fromJson(J.asMap(d)),
  ))
      .data;

  /// Returns how many comments were removed (a comment plus its replies).
  Future<int> deleteComment(String commentId) async =>
      (await _api.delete('/communities/comments/$commentId', parser: (d) => J.integer(J.asMap(d), 'removed', 1))).data;

  Future<({bool liked, int likeCount})> likeComment(String commentId) async =>
      (await _api.post('/communities/comments/$commentId/like', parser: (d) {
        final m = J.asMap(d);
        return (liked: J.boolean(m, 'liked'), likeCount: J.integer(m, 'likeCount'));
      }))
          .data;

  // --- Chat ----------------------------------------------------------------

  Future<({List<CommunityChatMessage> messages, bool hasMore})> chat(String id, {DateTime? before}) async =>
      (await _api.get(
        '/communities/$id/chat',
        query: {if (before != null) 'before': before.toUtc().toIso8601String()},
        parser: (d) {
          final m = J.asMap(d);
          return (messages: J.list(m, 'messages', CommunityChatMessage.fromJson), hasMore: J.boolean(m, 'hasMore'));
        },
      ))
          .data;

  Future<CommunityChatMessage> sendChat(String id, String text) async => (await _api.post(
    '/communities/$id/chat',
    data: {'text': text},
    parser: (d) => CommunityChatMessage.fromJson(J.asMap(d)),
  ))
      .data;

  Future<void> markChatRead(String id) async {
    await _api.post('/communities/$id/chat/read', parser: (_) => null);
  }

  Future<void> deleteChat(String id, String messageId) async {
    await _api.delete('/communities/$id/chat/$messageId', parser: (_) => null);
  }
}