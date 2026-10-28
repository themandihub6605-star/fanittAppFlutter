// File: lib/features/store/data/store_repository.dart
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:mime/mime.dart';

import '../../../core/config/app_config.dart';
import '../../../core/models/common_models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/multipart.dart';
import '../../../core/services/media_picker.dart';
import '../../../core/utils/json.dart';
import 'store_models.dart';

export 'store_models.dart';

/// How a buyer pays for a store item.
enum PayWith {
  razorpay('razorpay'),
  wallet('wallet');

  const PayWith(this.value);
  final String value;
}

/// All Fanitt Store API calls (backend: /api/store).
class StoreRepository {
  StoreRepository(this._api);

  final ApiClient _api;

  /// Separate client for uploading straight to file storage: no base URL,
  /// no auth header (the signed URL is the permission).
  final Dio _storageDio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 30), sendTimeout: const Duration(minutes: 30)));

  static MyStore _myStore(dynamic d) => MyStore.fromJson(J.asMap(d));
  static DigitalProduct _product(dynamic d) => DigitalProduct.fromJson(J.asMap(d));

  // ---------- config ----------

  Future<StoreConfig> config() async => (await _api.get('/store/config', parser: (d) => StoreConfig.fromJson(J.asMap(d)))).data;

  /// Image URL of the admin's Fanitt Store banner, or null when it's off.
  Future<String?> webBanner() async => (await _api.get(
    '/store/config',
    parser: (d) {
      final banner = J.map(J.asMap(d), 'webBanner');
      if (banner == null || !J.boolean(banner, 'enabled')) return null;
      final url = J.str(banner, 'imageUrl');
      return url.isEmpty ? null : url;
    },
  ))
      .data;

  // ---------- my store (creator) ----------

  Future<MyStore> myStore() async => (await _api.get('/store/me', parser: _myStore)).data;

  Future<MyStore> createStore({required String name, String? tagline, String? about}) async => (await _api.post(
    '/store/me',
    data: {'name': name, if (tagline != null) 'tagline': tagline, if (about != null) 'about': about},
    parser: _myStore,
  ))
      .data;

  Future<MyStore> updateStore({String? name, String? tagline, String? about, bool? isOpen}) async => (await _api.patch(
    '/store/me',
    data: {if (name != null) 'name': name, if (tagline != null) 'tagline': tagline, if (about != null) 'about': about, if (isOpen != null) 'isOpen': isOpen},
    parser: _myStore,
  ))
      .data;

  Future<MyStore> uploadStoreImage(PickedMedia image, {required bool banner}) async {
    final form = FormData()..files.add(MapEntry('image', await multipartFrom(image)));
    return (await _api.post(banner ? '/store/me/banner' : '/store/me/logo', data: form, parser: _myStore)).data;
  }

  Future<MyStore> savePayoutUpi(String upiId) async =>
      (await _api.put('/store/me/payout', data: {'method': 'upi', 'upiId': upiId}, parser: _myStore)).data;

  Future<MyStore> savePayoutBank({required String accountHolderName, required String accountNumber, required String ifsc, String? bankName}) async =>
      (await _api.put(
        '/store/me/payout',
        data: {
          'method': 'bank',
          'accountHolderName': accountHolderName,
          'accountNumber': accountNumber,
          'ifsc': ifsc,
          if (bankName != null && bankName.isNotEmpty) 'bankName': bankName,
        },
        parser: _myStore,
      ))
          .data;

  Future<MyStore> submitKyc({required String panNumber, required String panName, required String idType, required PickedMedia panDocument, required PickedMedia idDocument}) async {
    final form = FormData.fromMap({'panNumber': panNumber, 'panName': panName, 'idType': idType});
    form.files
      ..add(MapEntry('panDocument', await multipartFrom(panDocument)))
      ..add(MapEntry('idDocument', await multipartFrom(idDocument)));
    return (await _api.post('/store/me/kyc', data: form, parser: _myStore)).data;
  }

  Future<MyStore> acceptTerms(String version) async =>
      (await _api.post('/store/me/terms', data: {'accept': true, 'version': version}, parser: _myStore)).data;

  Future<StoreSummary> summary() async => (await _api.get('/store/me/summary', parser: (d) => StoreSummary.fromJson(J.asMap(d)))).data;

  Future<Paged<StoreOrder>> sales({int page = 1}) async => (await _api.get(
    '/store/me/sales',
    query: {'page': page},
    parser: (d) {
      final m = J.asMap(d);
      return Paged(items: J.list(m, 'orders', StoreOrder.fromJson), page: J.integer(m, 'page', 1), pages: J.integer(m, 'pages', 1), total: J.integer(m, 'total'));
    },
  ))
      .data;

  // ---------- my products (creator) ----------

  Future<List<DigitalProduct>> myProducts() async => (await _api.get('/store/me/products', parser: (d) => J.listOf(d, DigitalProduct.fromJson))).data;

  Future<DigitalProduct> myProduct(String id) async => (await _api.get('/store/me/products/$id', parser: _product)).data;

  Future<DigitalProduct> createProduct({required String title, required int price, String? description, String? category}) async => (await _api.post(
    '/store/me/products',
    data: {'title': title, 'price': price, if (description != null) 'description': description, if (category != null) 'category': category},
    parser: _product,
  ))
      .data;

  Future<DigitalProduct> updateProduct(String id, {String? title, int? price, String? description, String? category}) async => (await _api.patch(
    '/store/me/products/$id',
    data: {if (title != null) 'title': title, if (price != null) 'price': price, if (description != null) 'description': description, if (category != null) 'category': category},
    parser: _product,
  ))
      .data;

  Future<DigitalProduct> uploadCover(String id, PickedMedia image) async {
    final form = FormData()..files.add(MapEntry('image', await multipartFrom(image)));
    return (await _api.post('/store/me/products/$id/cover', data: form, parser: _product)).data;
  }

  /// Uploads one product file: signed link → PUT to storage → confirm.
  Future<DigitalProduct> uploadProductFile(String productId, PickedMedia file, {void Function(double progress)? onProgress, CancelToken? cancelToken}) async {
    final source = File(file.path);
    final size = await source.length();
    final mimeType = lookupMimeType(file.name) ?? lookupMimeType(file.path) ?? 'application/octet-stream';

    final ticket = (await _api.post(
      '/store/me/products/$productId/files/upload-url',
      data: {'fileName': file.name, 'mimeType': mimeType, 'size': size},
      parser: (d) {
        final m = J.asMap(d);
        return (url: J.str(m, 'uploadUrl'), key: J.str(m, 'key'));
      },
    ))
        .data;

    try {
      await _storageDio.put<void>(
        ticket.url,
        data: source.openRead(),
        cancelToken: cancelToken,
        options: Options(headers: {Headers.contentTypeHeader: mimeType, Headers.contentLengthHeader: size}),
        onSendProgress: (sent, total) {
          if (onProgress != null && total > 0) onProgress(sent / total);
        },
      );
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) throw const ApiException('Upload cancelled');
      throw const ApiException('Upload failed — check your connection and try again');
    }

    return (await _api.post('/store/me/products/$productId/files', data: {'key': ticket.key, 'fileName': file.name}, parser: _product)).data;
  }

  Future<DigitalProduct> removeFile(String productId, String fileId) async =>
      (await _api.delete('/store/me/products/$productId/files/$fileId', parser: _product)).data;

  Future<DigitalProduct> publish(String id) async => (await _api.post('/store/me/products/$id/publish', parser: _product)).data;

  Future<DigitalProduct> unpublish(String id) async => (await _api.post('/store/me/products/$id/unpublish', parser: _product)).data;

  Future<void> deleteProduct(String id) async {
    await _api.delete('/store/me/products/$id', parser: (_) => null);
  }

  Future<String> previewFileUrl(String productId, String fileId) async =>
      (await _api.get('/store/me/products/$productId/files/$fileId/preview', parser: (d) => J.str(J.asMap(d), 'url'))).data;

  // ---------- shopping ----------

  Future<Paged<StoreInfo>> stores({String? search, List<String>? ids, int page = 1}) async => (await _api.get(
    '/store/stores',
    query: {'page': page, if (search != null && search.isNotEmpty) 'search': search, if (ids != null && ids.isNotEmpty) 'ids': ids.join(',')},
    parser: (d) {
      final m = J.asMap(d);
      return Paged(items: J.list(m, 'stores', StoreInfo.fromJson), page: J.integer(m, 'page', 1), pages: J.integer(m, 'pages', 1), total: J.integer(m, 'total'));
    },
  ))
      .data;

  /// Every live product from every open store (marketplace).
  /// sort: new | popular | price_low | price_high · price: free | paid
  Future<Paged<DigitalProduct>> products({String? search, String? category, String? price, String sort = 'new', List<String>? ids, int page = 1}) async => (await _api.get(
    '/store/products',
    query: {
      'page': page,
      'sort': sort,
      if (search != null && search.isNotEmpty) 'search': search,
      if (category != null) 'category': category,
      if (price != null) 'price': price,
      if (ids != null && ids.isNotEmpty) 'ids': ids.join(','),
    },
    parser: (d) {
      final m = J.asMap(d);
      return Paged(items: J.list(m, 'products', DigitalProduct.fromJson), page: J.integer(m, 'page', 1), pages: J.integer(m, 'pages', 1), total: J.integer(m, 'total'));
    },
  ))
      .data;

  Future<StorePage> storePage(String slugOrUserId) async => (await _api.get('/store/stores/$slugOrUserId', parser: (d) => StorePage.fromJson(J.asMap(d)))).data;

  Future<ProductPage> productPage(String id) async => (await _api.get('/store/products/$id', parser: (d) => ProductPage.fromJson(J.asMap(d)))).data;

  Future<CheckoutStart> checkoutProduct(String id, {PayWith payWith = PayWith.razorpay}) async =>
      (await _api.post('/store/products/$id/checkout', data: {'payWith': payWith.value}, parser: (d) => CheckoutStart.fromJson(J.asMap(d)))).data;

  /// Confirms a Razorpay payment for any store order.
  Future<StoreOrder> verifyPayment(String orderId, {required String razorpayOrderId, required String paymentId, required String signature}) async => (await _api.post(
    '/store/orders/$orderId/verify',
    data: {'razorpayOrderId': razorpayOrderId, 'razorpayPaymentId': paymentId, 'razorpaySignature': signature},
    parser: (d) => StoreOrder.fromJson(J.asMap(d)),
  ))
      .data;

  Future<List<LibraryItem>> library() async => (await _api.get('/store/library', parser: (d) => J.listOf(d, LibraryItem.fromJson))).data;

  Future<String> downloadUrl(String productId, String fileId) async =>
      (await _api.get('/store/library/$productId/files/$fileId/download', parser: (d) => J.str(J.asMap(d), 'url'))).data;

  Future<Invoice> invoice(String orderId) async => (await _api.get('/store/orders/$orderId/invoice', parser: (d) => Invoice.fromJson(J.asMap(d)))).data;

  // ---------- live streams: creator ----------

  static LiveStream _live(dynamic d) => LiveStream.fromJson(J.asMap(d));

  Future<List<LiveStream>> myLives() async => (await _api.get('/store/me/lives', parser: (d) => J.listOf(d, LiveStream.fromJson))).data;

  Future<LiveStream> createLive({
    required String title,
    String? description,
    required int price,
    required bool isPrivate,
    String? privateMode,
    String? communityId,
    required bool chatEnabled,
    DateTime? scheduledAt,
  }) async =>
      (await _api.post(
        '/store/me/lives',
        data: {
          'title': title,
          if (description != null && description.isNotEmpty) 'description': description,
          'price': price,
          'visibility': isPrivate ? 'private' : 'public',
          if (isPrivate && privateMode != null) 'privateMode': privateMode,
          if (isPrivate && communityId != null) 'communityId': communityId,
          'chatEnabled': chatEnabled,
          if (scheduledAt != null) 'scheduledAt': scheduledAt.toUtc().toIso8601String(),
        },
        parser: _live,
      ))
          .data;

  /// The host's lives with tickets sold + latest buyers. tab: upcoming | past.
  Future<List<HostLive>> myHostLives({required String tab}) async =>
      (await _api.get('/store/me/lives', query: {'tab': tab}, parser: (d) => J.listOf(d, HostLive.fromJson))).data;

  /// Everyone who bought a ticket for one of the host's lives.
  Future<LiveTickets> liveTickets(String liveId) async => (await _api.get(
    '/store/me/lives/$liveId',
    parser: (d) {
      final m = J.asMap(d);
      return LiveTickets(live: LiveStream.fromJson(J.map(m, 'live') ?? const {}), tickets: J.list(m, 'tickets', LiveTicket.fromJson));
    },
  ))
      .data;

  /// Edits a scheduled live. A new time tells every ticket holder.
  Future<LiveStream> updateLive(String liveId, {String? title, String? description, DateTime? scheduledAt, bool? chatEnabled}) async => (await _api.patch(
    '/store/me/lives/$liveId',
    data: {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (scheduledAt != null) 'scheduledAt': scheduledAt.toUtc().toIso8601String(),
      if (chatEnabled != null) 'chatEnabled': chatEnabled,
    },
    parser: _live,
  ))
      .data;

  Future<LiveStream> uploadLiveCover(String liveId, PickedMedia image) async {
    final form = FormData()..files.add(MapEntry('image', await multipartFrom(image)));
    return (await _api.post('/store/me/lives/$liveId/cover', data: form, parser: _live)).data;
  }

  /// Goes live; returns the host's connection.
  Future<({LiveStream live, LiveConnection connection})> startLive(String liveId) async => (await _api.post(
    '/store/me/lives/$liveId/start',
    parser: (d) {
      final m = J.asMap(d);
      return (live: LiveStream.fromJson(J.map(m, 'live') ?? const {}), connection: LiveConnection.fromJson(J.map(m, 'connection')));
    },
  ))
      .data;

  Future<LiveStream> endLive(String liveId) async => (await _api.post('/store/me/lives/$liveId/end', parser: _live)).data;

  Future<void> cancelLive(String liveId, String reason) async {
    await _api.post('/store/me/lives/$liveId/cancel', data: {'reason': reason}, parser: (_) => null);
  }

  // ---------- live streams: viewers ----------

  Future<LiveDetail> liveDetail(String liveId, {String? invite}) async => (await _api.get(
    '/store/lives/$liveId',
    query: {if (invite != null && invite.isNotEmpty) 'invite': invite},
    parser: (d) => LiveDetail.fromJson(J.asMap(d)),
  ))
      .data;

  Future<List<LiveStream>> liveNow() async => (await _api.get(
    '/store/lives',
    query: {'status': 'live'},
    parser: (d) => J.list(J.asMap(d), 'lives', LiveStream.fromJson),
  ))
      .data;

  /// Live + upcoming lives this person can watch (public + their private
  /// ones: communities, invites, hand-picked). Used on the home screen.
  Future<List<LiveStream>> discoverLives({int limit = 20}) async => (await _api.get(
    '/store/lives/discover',
    query: {'limit': limit},
    parser: (d) => J.list(J.asMap(d), 'lives', LiveStream.fromJson),
  ))
      .data;

  /// Creators I follow who are live right now (feed stories), with each
  /// host's user id so the feed can put the LIVE ring on their story.
  Future<List<({LiveStream live, String hostId})>> followingLives() async => (await _api.get(
    '/store/lives/discover',
    query: {'following': '1', 'limit': 30},
    parser: (d) => J.list(J.asMap(d), 'lives', (j) => (live: LiveStream.fromJson(j), hostId: J.refId(j, 'host') ?? '')),
  ))
      .data;

  /// Lives made for one community (shown on its page; locked for non-members).
  Future<({List<LiveStream> lives, bool isMember})> communityLives(String communityId) async => (await _api.get(
    '/store/lives/community/$communityId',
    parser: (d) {
      final m = J.asMap(d);
      return (lives: J.list(m, 'lives', LiveStream.fromJson), isMember: J.boolean(m, 'isMember'));
    },
  ))
      .data;

  Future<CheckoutStart> buyLiveTicket(String liveId, {PayWith payWith = PayWith.razorpay, String? invite}) async => (await _api.post(
    '/store/lives/$liveId/checkout',
    data: {'payWith': payWith.value, if (invite != null && invite.isNotEmpty) 'invite': invite},
    parser: (d) => CheckoutStart.fromJson(J.asMap(d)),
  ))
      .data;

  /// Viewer (or host) connection for a running live.
  Future<({LiveConnection connection, bool isHost})> joinLive(String liveId, {String? invite}) async => (await _api.post(
    '/store/lives/$liveId/join',
    data: {if (invite != null && invite.isNotEmpty) 'invite': invite},
    parser: (d) {
      final m = J.asMap(d);
      return (connection: LiveConnection.fromJson(J.map(m, 'connection')), isHost: J.str(m, 'role') == 'host');
    },
  ))
      .data;

  // ---------- calls ----------

  static CallSession _call(dynamic d) => CallSession.fromJson(J.asMap(d));

  /// Creators taking 1-to-1 calls right now (online first), each with
  /// their audio / video rate per minute (0 = free).
  Future<List<({StoreInfo store, CallInfo calls, ExpertCreator creator})>> callCreators({int page = 1}) async => (await _api.get(
    '/store/calls/available',
    query: {'page': page},
    parser: (d) => J.list(
      J.asMap(d),
      'stores',
          (j) => (store: StoreInfo.fromJson(j), calls: CallInfo.fromJson(J.map(j, 'calls')), creator: ExpertCreator.fromJson(J.map(j, 'creator'), category: J.map(j, 'category'))),
    ),
  ))
      .data;

  /// "Talk 1:1 with experts" See all: experts taking calls, with filters.
  /// [category] = a category id · [online] = only online now. Page 1 also
  /// returns the categories that have experts (for the filter chips).
  Future<CallExpertsPage> callExperts({int page = 1, String? category, String? search, bool online = false}) async => (await _api.get(
    '/store/calls/available',
    query: {
      'page': page,
      if (category != null && category.isNotEmpty) 'category': category,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (online) 'online': '1',
    },
    parser: (d) {
      final m = J.asMap(d);
      return CallExpertsPage(
        items: J.list(m, 'stores', (j) {
          final c = J.map(j, 'category');
          return CallExpert(
            store: StoreInfo.fromJson(j),
            calls: CallInfo.fromJson(J.map(j, 'calls')),
            category: c == null ? '' : J.str(c, 'label'),
            creator: ExpertCreator.fromJson(J.map(j, 'creator'), category: c),
          );
        }),
        page: J.integer(m, 'page', 1),
        pages: J.integer(m, 'pages', 1),
        total: J.integer(m, 'total'),
        categories: J.list(m, 'categories', (j) => ExpertCategory(id: J.id(j), label: J.str(j, 'label'), count: J.integer(j, 'count'))),
      );
    },
  ))
      .data;

  Future<CallSettings> callSettings() async => (await _api.get('/store/me/calls/settings', parser: (d) => CallSettings.fromJson(J.asMap(d)))).data;

  Future<CallSettings> updateCallSettings({bool? enabled, bool? audioEnabled, bool? videoEnabled, int? audioRate, int? videoRate}) async => (await _api.patch(
    '/store/me/calls/settings',
    data: {
      if (enabled != null) 'enabled': enabled,
      if (audioEnabled != null) 'audioEnabled': audioEnabled,
      if (videoEnabled != null) 'videoEnabled': videoEnabled,
      if (audioRate != null) 'audioRate': audioRate,
      if (videoRate != null) 'videoRate': videoRate,
    },
    parser: (d) => CallSettings.fromJson(J.asMap(d)),
  ))
      .data;

  Future<CallSettings> setOnline(bool online) async =>
      (await _api.post('/store/me/calls/online', data: {'online': online}, parser: (d) => CallSettings.fromJson(J.asMap(d)))).data;

  /// Asks for a call. Returns the call plus how to pay for it.
  Future<({CallSession call, CheckoutStart checkout})> requestCall(String storeId, {required bool video, required int minutes, String? note, PayWith payWith = PayWith.razorpay}) async =>
      (await _api.post(
        '/store/stores/$storeId/calls',
        data: {'type': video ? 'video' : 'audio', 'minutes': minutes, if (note != null && note.isNotEmpty) 'note': note, 'payWith': payWith.value},
        parser: (d) {
          final m = J.asMap(d);
          return (call: CallSession.fromJson(J.map(m, 'call') ?? const {}), checkout: CheckoutStart.fromJson(m));
        },
      ))
          .data;

  Future<CallSession> call(String callId) async => (await _api.get('/store/calls/$callId', parser: _call)).data;

  Future<Paged<CallSession>> myCalls({required bool asHost, int page = 1}) async => (await _api.get(
    '/store/calls',
    query: {'role': asHost ? 'host' : 'caller', 'page': page},
    parser: (d) {
      final m = J.asMap(d);
      return Paged(items: J.list(m, 'calls', CallSession.fromJson), page: J.integer(m, 'page', 1), pages: J.integer(m, 'pages', 1), total: J.integer(m, 'total'));
    },
  ))
      .data;

  Future<CallSession> acceptCall(String callId) async => (await _api.post('/store/calls/$callId/accept', parser: _call)).data;

  Future<CallSession> declineCall(String callId) async => (await _api.post('/store/calls/$callId/decline', parser: _call)).data;

  Future<CallSession> cancelCall(String callId) async => (await _api.post('/store/calls/$callId/cancel', parser: _call)).data;

  Future<CallSession> endCall(String callId) async => (await _api.post('/store/calls/$callId/end', parser: _call)).data;

  Future<CallJoin> joinCall(String callId) async => (await _api.post(
    '/store/calls/$callId/join',
    parser: (d) {
      final m = J.asMap(d);
      return CallJoin(
        connection: LiveConnection.fromJson(J.map(m, 'connection')),
        call: CallSession.fromJson(J.map(m, 'call') ?? const {}),
        endsAt: J.date(m, 'endsAt'),
      );
    },
  ))
      .data;

  // ---------- affiliate: creator ----------

  static AffiliateProduct _aff(dynamic d) => AffiliateProduct.fromJson(J.asMap(d));

  /// Full https link for a /go/:id path (counts the click, then opens the shop).
  static String goUrl(String goPath) => '${AppConfig.socketUrl}$goPath';

  Future<LinkPreview> previewLink(String url) async =>
      (await _api.post('/store/me/affiliate/preview', data: {'url': url}, parser: (d) => LinkPreview.fromJson(J.asMap(d)))).data;

  Future<List<AffiliateProduct>> myAffiliateProducts() async =>
      (await _api.get('/store/me/affiliate/products', parser: (d) => J.listOf(d, AffiliateProduct.fromJson))).data;

  Future<AffiliateProduct> saveAffiliateProduct({
    String? id,
    required String url,
    required String title,
    String? description,
    String? imageUrl,
    int? price,
    String? merchant,
    String? category,
  }) async {
    final body = {
      'url': url,
      'title': title,
      'description': description ?? '',
      'imageUrl': imageUrl ?? '',
      'price': price,
      'merchant': merchant ?? '',
      'category': category ?? '',
    };
    return id == null
        ? (await _api.post('/store/me/affiliate/products', data: body, parser: _aff)).data
        : (await _api.patch('/store/me/affiliate/products/$id', data: body, parser: _aff)).data;
  }

  /// Ids of my affiliate products whose link stopped working (weekly check).
  Future<Set<String>> brokenAffiliateIds() async => (await _api.get(
    '/store/me/affiliate/products',
    parser: (d) => {
      for (final j in (d is List ? d : const []).whereType<Map<String, dynamic>>())
        if (J.boolean(j, 'linkBroken')) J.id(j),
    },
  ))
      .data;

  Future<AffiliateProduct> setAffiliateHidden(String id, bool hidden) async =>
      (await _api.patch('/store/me/affiliate/products/$id', data: {'hidden': hidden}, parser: _aff)).data;

  Future<AffiliateProduct> uploadAffiliateImage(String id, PickedMedia image) async {
    final form = FormData()..files.add(MapEntry('image', await multipartFrom(image)));
    return (await _api.post('/store/me/affiliate/products/$id/image', data: form, parser: _aff)).data;
  }

  Future<void> deleteAffiliateProduct(String id) async {
    await _api.delete('/store/me/affiliate/products/$id', parser: (_) => null);
  }

  Future<List<AffiliateCollection>> myCollections() async =>
      (await _api.get('/store/me/affiliate/collections', parser: (d) => J.listOf(d, AffiliateCollection.fromJson))).data;

  Future<AffiliateCollection> saveCollection({String? id, required String title, String? description, required List<String> productIds}) async {
    final body = {'title': title, 'description': description ?? '', 'productIds': productIds};
    final parser = (dynamic d) => AffiliateCollection.fromJson(J.asMap(d));
    return id == null
        ? (await _api.post('/store/me/affiliate/collections', data: body, parser: parser)).data
        : (await _api.patch('/store/me/affiliate/collections/$id', data: body, parser: parser)).data;
  }

  Future<void> deleteCollection(String id) async {
    await _api.delete('/store/me/affiliate/collections/$id', parser: (_) => null);
  }

  Future<AffiliateEarnings> affiliateEarnings() async =>
      (await _api.get('/store/me/affiliate/earnings', query: {'limit': 50}, parser: (d) => AffiliateEarnings.fromJson(J.asMap(d)))).data;

  Future<void> addAffiliateEarning({required int amount, required String merchant, String? productId, int orders = 1, String status = 'pending', String? note}) async {
    await _api.post(
      '/store/me/affiliate/earnings',
      data: {'amount': amount, 'merchant': merchant, if (productId != null) 'productId': productId, 'orders': orders, 'status': status, if (note != null && note.isNotEmpty) 'note': note},
      parser: (_) => null,
    );
  }

  Future<void> setAffiliateEarningStatus(String id, String status) async {
    await _api.patch('/store/me/affiliate/earnings/$id', data: {'status': status}, parser: (_) => null);
  }

  Future<void> deleteAffiliateEarning(String id) async {
    await _api.delete('/store/me/affiliate/earnings/$id', parser: (_) => null);
  }

  // ---------- FanBox ----------

  Future<FanBoxConfig> fanboxConfig() async => (await _api.get('/store/fanbox/config', parser: (d) => FanBoxConfig.fromJson(J.asMap(d)))).data;

  Future<CheckoutStart> sendFanBox({String? storeId, String? creatorId, required int amount, String? message, String context = 'store', PayWith payWith = PayWith.razorpay}) async =>
      (await _api.post(
        '/store/fanbox',
        data: {
          if (storeId != null) 'storeId': storeId,
          if (creatorId != null) 'creatorId': creatorId,
          'amount': amount,
          if (message != null && message.isNotEmpty) 'message': message,
          'context': context,
          'payWith': payWith.value,
        },
        parser: (d) => CheckoutStart.fromJson(J.asMap(d)),
      ))
          .data;

  Future<FanBoxReceived> fanboxReceived({int page = 1}) async => (await _api.get(
    '/store/me/fanbox',
    query: {'page': page, 'limit': 50},
    parser: (d) {
      final m = J.asMap(d);
      final totals = J.map(m, 'totals') ?? const <String, dynamic>{};
      return FanBoxReceived(
        items: J.list(m, 'fanbox', (j) => FanBoxItem.fromJson(j, received: true)),
        count: J.integer(totals, 'count'),
        gross: J.integer(totals, 'gross'),
        net: J.integer(totals, 'net'),
        supporters: J.integer(totals, 'supporters'),
      );
    },
  ))
      .data;

  // ---------- analytics ----------

  Future<StoreAnalytics> analytics(int days) async =>
      (await _api.get('/store/me/analytics', query: {'days': days}, parser: (d) => StoreAnalytics.fromJson(J.asMap(d)))).data;

  // ---------- Virtual Meet (existing Live Sessions + bookings) ----------

  Future<Set<String>> myBookedSessionIds() async => (await _api.get(
    '/bookings/me',
    parser: (d) {
      final ids = <String>{};
      if (d is List) {
        for (final b in d.whereType<Map<String, dynamic>>()) {
          final status = b['status']?.toString();
          final sessionId = J.refId(b, 'session');
          if (sessionId != null && (status == 'confirmed' || status == 'completed')) ids.add(sessionId);
        }
      }
      return ids;
    },
  ))
      .data;

  /// Books a meet. Free meets are confirmed at once; paid ones return a
  /// Razorpay order to pay and then [verifyMeetBooking].
  Future<({String bookingId, bool requiresPayment, String? orderId, int amount})> bookMeet(String sessionId) async => (await _api.post(
    '/bookings',
    data: {'sessionId': sessionId},
    parser: (d) {
      final m = J.asMap(d);
      final booking = J.map(m, 'booking') ?? const <String, dynamic>{};
      final order = J.map(m, 'order');
      return (
      bookingId: J.id(booking),
      requiresPayment: J.boolean(m, 'requiresPayment'),
      orderId: order == null ? null : J.strOrNull(order, 'id'),
      amount: order == null ? 0 : J.integer(order, 'amount'),
      );
    },
  ))
      .data;

  Future<void> verifyMeetBooking({required String bookingId, required String razorpayOrderId, required String paymentId, required String signature}) async {
    await _api.post(
      '/bookings/verify-payment',
      data: {'bookingId': bookingId, 'razorpayOrderId': razorpayOrderId, 'razorpayPaymentId': paymentId, 'razorpaySignature': signature},
      parser: (_) => null,
    );
  }

  /// Meets anyone can find. tab: live | upcoming | booked.
  Future<Paged<StoreMeet>> meets({String tab = 'upcoming', List<String>? ids, int page = 1}) async => (await _api.get(
    '/store/meets',
    query: {'tab': tab, 'page': page, if (ids != null && ids.isNotEmpty) 'ids': ids.join(',')},
    parser: (d) {
      final m = J.asMap(d);
      return Paged(items: J.list(m, 'meets', StoreMeet.fromJson), page: J.integer(m, 'page', 1), pages: J.integer(m, 'pages', 1), total: J.integer(m, 'total'));
    },
  ))
      .data;

  Future<MeetDetail> meet(String id) async => (await _api.get('/store/meets/$id', parser: (d) => MeetDetail.fromJson(J.asMap(d)))).data;

  /// In-app (LiveKit) connection. The host's join starts the meeting.
  Future<({LiveConnection connection, bool isHost, StoreMeet meet})> joinMeet(String id) async => (await _api.post(
    '/store/meets/$id/join',
    parser: (d) {
      final m = J.asMap(d);
      return (
      connection: LiveConnection.fromJson(J.map(m, 'connection')),
      isHost: J.str(m, 'role') == 'host',
      meet: StoreMeet.fromJson(J.map(m, 'meet') ?? const {}),
      );
    },
  ))
      .data;

  Future<void> endMeet(String id) async {
    await _api.post('/store/meets/$id/end', parser: (_) => null);
  }
}

/// One expert taking 1:1 calls.
class CallExpert {
  const CallExpert({required this.store, required this.calls, required this.category, required this.creator});

  final StoreInfo store;
  final CallInfo calls;

  /// The person you talk to (name, photo, title, bio…).
  final ExpertCreator creator;

  /// Category label from the expert's creator profile ('' when none).
  final String category;
}

/// A category that has experts taking calls (filter chip).
class ExpertCategory {
  const ExpertCategory({required this.id, required this.label, required this.count});

  final String id;
  final String label;
  final int count;
}

class CallExpertsPage {
  const CallExpertsPage({required this.items, required this.page, required this.pages, required this.total, required this.categories});

  final List<CallExpert> items;
  final int page;
  final int pages;
  final int total;

  /// Only filled on page 1.
  final List<ExpertCategory> categories;

  bool get hasMore => page < pages;
}

/// One of the host's lives + ticket info for the Stream Live screen.
class HostLive {
  const HostLive({required this.live, required this.ticketsToday, required this.recentBuyers, required this.missed, required this.cancelledReason});

  factory HostLive.fromJson(Map<String, dynamic> json) {
    final stats = J.map(json, 'stats') ?? const <String, dynamic>{};
    return HostLive(
      // Owner rows carry the full stats object; LiveStream reads it.
      live: LiveStream.fromJson({...json, 'stats': stats}),
      ticketsToday: J.integer(json, 'ticketsToday'),
      recentBuyers: J.list(json, 'recentBuyers', (j) => LiveBuyerLite(name: J.str(j, 'name', 'Fanitt user'), avatarUrl: J.str(j, 'avatarUrl'))),
      missed: J.boolean(json, 'missed'),
      cancelledReason: J.str(json, 'cancelledReason'),
    );
  }

  final LiveStream live;

  /// Tickets bought in the last 24 hours.
  final int ticketsToday;
  final List<LiveBuyerLite> recentBuyers;

  /// Scheduled but never started → cancelled and refunded automatically.
  final bool missed;
  final String cancelledReason;
}

class LiveBuyerLite {
  const LiveBuyerLite({required this.name, required this.avatarUrl});

  final String name;
  final String avatarUrl;
}

/// Host view: the live + everyone who bought a ticket.
class LiveTickets {
  const LiveTickets({required this.live, required this.tickets});

  final LiveStream live;
  final List<LiveTicket> tickets;

  List<LiveTicket> get paid => tickets.where((t) => !t.refunded).toList();
  int get earned => paid.fold(0, (a, t) => a + t.earning);
}

class LiveTicket {
  const LiveTicket({required this.name, required this.avatarUrl, required this.amount, required this.earning, required this.refunded, this.paidAt});

  factory LiveTicket.fromJson(Map<String, dynamic> json) {
    final buyer = J.map(json, 'buyer') ?? const <String, dynamic>{};
    final amount = J.integer(json, 'amount');
    return LiveTicket(
      name: J.str(buyer, 'name', 'Fanitt user'),
      avatarUrl: J.str(buyer, 'avatarUrl'),
      amount: amount,
      earning: J.integer(json, 'creatorEarning', amount),
      refunded: J.str(json, 'status') == 'refunded',
      paidAt: J.date(json, 'paidAt'),
    );
  }

  final String name;
  final String avatarUrl;

  /// Paise the buyer paid.
  final int amount;

  /// Paise the creator keeps after the platform fee.
  final int earning;
  final bool refunded;
  final DateTime? paidAt;

  bool get isNew => paidAt != null && DateTime.now().difference(paidAt!).inHours < 24;
}

/// The creator behind a store that takes calls — what fans see and call.
class ExpertCreator {
  const ExpertCreator({
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.slug,
    required this.title,
    required this.bio,
    required this.category,
    required this.languages,
    required this.rating,
    required this.reviews,
    required this.followers,
    required this.verified,
  });

  factory ExpertCreator.fromJson(Map<String, dynamic>? json, {Map<String, dynamic>? category}) {
    final j = json ?? const <String, dynamic>{};
    return ExpertCreator(
      userId: J.str(j, 'userId'),
      name: J.str(j, 'name'),
      avatarUrl: J.str(j, 'avatarUrl'),
      slug: J.str(j, 'slug'),
      title: J.str(j, 'title'),
      bio: J.str(j, 'bio'),
      category: category == null ? '' : J.str(category, 'label'),
      languages: J.strings(j, 'languages'),
      rating: J.dbl(j, 'rating'),
      reviews: J.integer(j, 'reviews'),
      followers: J.integer(j, 'followers'),
      verified: J.boolean(j, 'verified'),
    );
  }

  final String userId;
  final String name;
  final String avatarUrl;

  /// Creator profile slug ('' when the profile is missing).
  final String slug;

  /// Short headline, e.g. "Fitness coach · 8 yrs".
  final String title;
  final String bio;
  final String category;
  final List<String> languages;
  final double rating;
  final int reviews;
  final int followers;
  final bool verified;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

  /// One line about them: title, else bio, else category.
  String get headline {
    if (title.trim().isNotEmpty) return title.trim();
    if (bio.trim().isNotEmpty) return bio.trim().replaceAll(RegExp(r'\s+'), ' ');
    return category;
  }
}