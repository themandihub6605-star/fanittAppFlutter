import 'package:equatable/equatable.dart';

import '../../../core/utils/json.dart';

// Affiliate, FanBox, analytics and Virtual Meet models. Money in paise.

class AffiliateProduct extends Equatable {
  const AffiliateProduct({
    required this.id,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.price,
    required this.merchant,
    required this.category,
    required this.goPath,
    required this.url,
    required this.status,
    required this.clicks,
    required this.removedReason,
  });

  factory AffiliateProduct.fromJson(Map<String, dynamic> json) => AffiliateProduct(
    id: J.id(json),
    title: J.str(json, 'title'),
    description: J.str(json, 'description'),
    imageUrl: J.str(json, 'imageUrl'),
    price: J.integerOrNull(json, 'price'),
    merchant: J.str(json, 'merchant'),
    category: J.str(json, 'category'),
    goPath: J.str(json, 'goPath'),
    url: J.str(json, 'url'),
    status: J.str(json, 'status', 'active'),
    clicks: J.integer(json, 'clicks'),
    removedReason: J.str(json, 'removedReason'),
  );

  final String id;
  final String title;
  final String description;
  final String imageUrl;
  final int? price;
  final String merchant;
  final String category;
  final String goPath; // /api/store/go/<id> — counts the click, then redirects
  final String url; // owner only
  final String status; // active | hidden | removed
  final int clicks;
  final String removedReason;

  bool get isHidden => status == 'hidden';
  bool get isRemoved => status == 'removed';

  @override
  List<Object?> get props => [id, title, imageUrl, price, merchant, url, status, clicks];
}

class AffiliateCollection extends Equatable {
  const AffiliateCollection({required this.id, required this.title, required this.description, required this.productIds, required this.products, required this.isPublic});

  factory AffiliateCollection.fromJson(Map<String, dynamic> json) {
    final raw = json['products'];
    final ids = <String>[];
    final products = <AffiliateProduct>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is String) ids.add(item);
        if (item is Map<String, dynamic>) {
          final p = AffiliateProduct.fromJson(item);
          products.add(p);
          ids.add(p.id);
        }
      }
    }
    return AffiliateCollection(
      id: J.id(json),
      title: J.str(json, 'title'),
      description: J.str(json, 'description'),
      productIds: ids,
      products: products,
      isPublic: J.boolean(json, 'isPublic', true),
    );
  }

  final String id;
  final String title;
  final String description;
  final List<String> productIds;
  final List<AffiliateProduct> products; // filled on public store pages
  final bool isPublic;

  @override
  List<Object?> get props => [id, title, productIds, isPublic];
}

class AffiliateStorefront extends Equatable {
  const AffiliateStorefront({required this.products, required this.collections});

  factory AffiliateStorefront.fromJson(Map<String, dynamic>? json) {
    final j = json ?? const <String, dynamic>{};
    return AffiliateStorefront(products: J.list(j, 'products', AffiliateProduct.fromJson), collections: J.list(j, 'collections', AffiliateCollection.fromJson));
  }

  final List<AffiliateProduct> products;
  final List<AffiliateCollection> collections;

  bool get isEmpty => products.isEmpty;

  @override
  List<Object?> get props => [products, collections];
}

class AffiliateEarning extends Equatable {
  const AffiliateEarning({required this.id, required this.amount, required this.merchant, required this.status, required this.orders, required this.note, this.earnedAt, this.productTitle});

  factory AffiliateEarning.fromJson(Map<String, dynamic> json) {
    final product = J.map(json, 'product');
    return AffiliateEarning(
      id: J.id(json),
      amount: J.integer(json, 'amount'),
      merchant: J.str(json, 'merchant'),
      status: J.str(json, 'status', 'pending'),
      orders: J.integer(json, 'orders', 1),
      note: J.str(json, 'note'),
      earnedAt: J.date(json, 'earnedAt'),
      productTitle: product == null ? null : J.strOrNull(product, 'title'),
    );
  }

  final String id;
  final int amount;
  final String merchant;
  final String status; // pending | confirmed | reversed
  final int orders;
  final String note;
  final DateTime? earnedAt;
  final String? productTitle;

  @override
  List<Object?> get props => [id, amount, status];
}

class AffiliateEarnings extends Equatable {
  const AffiliateEarnings({required this.items, required this.pending, required this.confirmed, required this.reversed, required this.byMerchant});

  factory AffiliateEarnings.fromJson(Map<String, dynamic> json) {
    final totals = J.map(json, 'totals') ?? const <String, dynamic>{};
    final merchants = J.map(json, 'byMerchant') ?? const <String, dynamic>{};
    return AffiliateEarnings(
      items: J.list(json, 'earnings', AffiliateEarning.fromJson),
      pending: J.integer(totals, 'pending'),
      confirmed: J.integer(totals, 'confirmed'),
      reversed: J.integer(totals, 'reversed'),
      byMerchant: {for (final e in merchants.entries) e.key: (e.value as num?)?.toInt() ?? 0},
    );
  }

  final List<AffiliateEarning> items;
  final int pending;
  final int confirmed;
  final int reversed;
  final Map<String, int> byMerchant;

  @override
  List<Object?> get props => [items, pending, confirmed, reversed];
}

/// Link details read from a product page (pre-fills the form).
class LinkPreview {
  const LinkPreview({required this.url, required this.title, required this.description, required this.imageUrl, required this.price, required this.merchant, required this.found});

  factory LinkPreview.fromJson(Map<String, dynamic> json) => LinkPreview(
    url: J.str(json, 'url'),
    title: J.str(json, 'title'),
    description: J.str(json, 'description'),
    imageUrl: J.str(json, 'imageUrl'),
    price: J.integerOrNull(json, 'price'),
    merchant: J.str(json, 'merchant'),
    found: J.boolean(json, 'found'),
  );

  final String url;
  final String title;
  final String description;
  final String imageUrl;
  final int? price;
  final String merchant;
  final bool found;
}

class FanBoxConfig {
  const FanBoxConfig({required this.presets, required this.minAmount, required this.maxAmount, required this.feePercent});

  factory FanBoxConfig.fromJson(Map<String, dynamic>? json) {
    final j = json ?? const <String, dynamic>{};
    final presets = (j['presets'] is List ? j['presets'] as List : const [])
        .whereType<num>()
        .map((n) => n.toInt())
        .toList();
    return FanBoxConfig(
      presets: presets.isEmpty ? const [5000, 10000, 50000, 100000] : presets,
      minAmount: J.integer(j, 'minAmount', 1000),
      maxAmount: J.integer(j, 'maxAmount', 10000000),
      feePercent: (j['feePercent'] as num?)?.toDouble() ?? 3,
    );
  }

  final List<int> presets;
  final int minAmount;
  final int maxAmount;
  final double feePercent;
}

class FanBoxItem extends Equatable {
  const FanBoxItem({required this.id, required this.amount, required this.creatorEarning, required this.message, required this.name, this.avatarUrl, this.paidAt});

  factory FanBoxItem.fromJson(Map<String, dynamic> json, {required bool received}) {
    final person = J.map(json, received ? 'buyer' : 'seller') ?? const <String, dynamic>{};
    return FanBoxItem(
      id: J.id(json),
      amount: J.integer(json, 'amount'),
      creatorEarning: J.integer(json, 'creatorEarning'),
      message: J.str(json, 'message'),
      name: J.str(person, 'name', 'Fan'),
      avatarUrl: J.strOrNull(person, 'avatarUrl'),
      paidAt: J.date(json, 'paidAt'),
    );
  }

  final String id;
  final int amount;
  final int creatorEarning;
  final String message;
  final String name;
  final String? avatarUrl;
  final DateTime? paidAt;

  @override
  List<Object?> get props => [id];
}

class FanBoxReceived {
  const FanBoxReceived({required this.items, required this.count, required this.gross, required this.net, required this.supporters});

  final List<FanBoxItem> items;
  final int count;
  final int gross;
  final int net;
  final int supporters;
}

class SourceTotals {
  const SourceTotals({required this.orders, required this.gross, required this.fees, required this.net});

  factory SourceTotals.fromJson(Map<String, dynamic>? json) {
    final j = json ?? const <String, dynamic>{};
    return SourceTotals(orders: J.integer(j, 'orders'), gross: J.integer(j, 'gross'), fees: J.integer(j, 'fees'), net: J.integer(j, 'net'));
  }

  final int orders;
  final int gross;
  final int fees;
  final int net;
}

class DayPoint {
  const DayPoint({required this.date, required this.gross, required this.net, required this.orders, required this.views, required this.visitors});

  factory DayPoint.fromJson(Map<String, dynamic> json) => DayPoint(
    date: J.str(json, 'date'),
    gross: J.integer(json, 'gross'),
    net: J.integer(json, 'net'),
    orders: J.integer(json, 'orders'),
    views: J.integer(json, 'views'),
    visitors: J.integer(json, 'visitors'),
  );

  final String date; // YYYY-MM-DD
  final int gross;
  final int net;
  final int orders;
  final int views;
  final int visitors;
}

class StoreAnalytics {
  const StoreAnalytics({
    required this.days,
    required this.totals,
    required this.views,
    required this.uniqueVisitors,
    required this.customers,
    required this.conversionRate,
    required this.bySource,
    required this.daily,
    required this.topItems,
    required this.liveCount,
    required this.livePeak,
    required this.liveJoins,
    required this.liveTickets,
    required this.callsCompleted,
    required this.callMinutes,
    required this.callEarnings,
    required this.fanboxCount,
    required this.fanboxGross,
    required this.fanboxSupporters,
    required this.affiliateClicks,
    required this.affiliatePending,
    required this.affiliateConfirmed,
  });

  factory StoreAnalytics.fromJson(Map<String, dynamic> json) {
    final totals = J.map(json, 'totals') ?? const <String, dynamic>{};
    final by = J.map(json, 'bySource') ?? const <String, dynamic>{};
    final lives = J.map(json, 'lives') ?? const <String, dynamic>{};
    final calls = J.map(json, 'calls') ?? const <String, dynamic>{};
    final fanbox = J.map(json, 'fanbox') ?? const <String, dynamic>{};
    final affiliate = J.map(json, 'affiliate') ?? const <String, dynamic>{};
    final range = J.map(json, 'range') ?? const <String, dynamic>{};
    return StoreAnalytics(
      days: J.integer(range, 'days', 30),
      totals: SourceTotals.fromJson(totals),
      views: J.integer(totals, 'views'),
      uniqueVisitors: J.integer(totals, 'uniqueVisitors'),
      customers: J.integer(totals, 'customers'),
      conversionRate: (totals['conversionRate'] as num?)?.toDouble() ?? 0,
      bySource: {for (final key in const ['digital_product', 'live_stream', 'call', 'fanbox']) key: SourceTotals.fromJson(J.map(by, key))},
      daily: J.list(json, 'daily', DayPoint.fromJson),
      topItems: J.list(json, 'topItems', (m) => (title: J.str(m, 'title'), orders: J.integer(m, 'orders'), gross: J.integer(m, 'gross'))),
      liveCount: J.integer(lives, 'count'),
      livePeak: J.integer(lives, 'peakViewers'),
      liveJoins: J.integer(lives, 'totalJoins'),
      liveTickets: J.integer(lives, 'ticketsSold'),
      callsCompleted: J.integer(calls, 'completed'),
      callMinutes: J.integer(calls, 'minutes'),
      callEarnings: J.integer(calls, 'earnings'),
      fanboxCount: J.integer(fanbox, 'count'),
      fanboxGross: J.integer(fanbox, 'gross'),
      fanboxSupporters: J.integer(fanbox, 'supporters'),
      affiliateClicks: J.integer(affiliate, 'clicks'),
      affiliatePending: J.integer(affiliate, 'pending'),
      affiliateConfirmed: J.integer(affiliate, 'confirmed'),
    );
  }

  final int days;
  final SourceTotals totals;
  final int views;
  final int uniqueVisitors;
  final int customers;
  final double conversionRate;
  final Map<String, SourceTotals> bySource;
  final List<DayPoint> daily;
  final List<({String title, int orders, int gross})> topItems;
  final int liveCount;
  final int livePeak;
  final int liveJoins;
  final int liveTickets;
  final int callsCompleted;
  final int callMinutes;
  final int callEarnings;
  final int fanboxCount;
  final int fanboxGross;
  final int fanboxSupporters;
  final int affiliateClicks;
  final int affiliatePending;
  final int affiliateConfirmed;
}

/// A Virtual Meet (existing Live Session) shown in a store.
class StoreMeet extends Equatable {
  const StoreMeet({
    required this.id,
    required this.title,
    required this.description,
    required this.coverUrl,
    required this.price,
    required this.durationMinutes,
    required this.spotsLeft,
    required this.isLive,
    this.scheduledAt,
    this.endsAt,
    this.hostName = '',
    this.hostAvatarUrl = '',
    this.hostSlug = '',
    this.booked = false,
    this.isHost = false,
  });

  factory StoreMeet.fromJson(Map<String, dynamic> json) {
    final max = J.integer(json, 'maxParticipants');
    final host = J.map(json, 'host') ?? const <String, dynamic>{};
    return StoreMeet(
      id: J.id(json),
      title: J.str(json, 'title'),
      description: J.str(json, 'description'),
      coverUrl: J.str(json, 'coverImageUrl'),
      price: J.integer(json, 'price'),
      durationMinutes: J.integer(json, 'durationMinutes'),
      spotsLeft: max == 0 ? null : (max - J.integer(json, 'bookedCount')),
      isLive: J.boolean(json, 'isLive'),
      scheduledAt: J.date(json, 'scheduledAt'),
      endsAt: J.date(json, 'endsAt'),
      hostName: J.str(host, 'name'),
      hostAvatarUrl: J.str(host, 'avatarUrl'),
      hostSlug: J.str(host, 'slug'),
      booked: J.boolean(json, 'booked'),
      isHost: J.boolean(json, 'isHost'),
    );
  }

  final DateTime? endsAt;
  final String hostName;
  final String hostAvatarUrl;
  final String hostSlug;
  final bool booked;
  final bool isHost;

  final String id;
  final String title;
  final String description;
  final String coverUrl;
  final int price;
  final int durationMinutes;
  final int? spotsLeft;
  final bool isLive;
  final DateTime? scheduledAt;

  bool get isFree => price == 0;

  @override
  List<Object?> get props => [id, title, isLive, spotsLeft];
}

/// What the current user can do with a meet.
class MeetAccess extends Equatable {
  const MeetAccess({required this.isHost, required this.booked, required this.canJoin, this.reason});

  factory MeetAccess.fromJson(Map<String, dynamic>? json) {
    final j = json ?? const <String, dynamic>{};
    return MeetAccess(isHost: J.boolean(j, 'isHost'), booked: J.boolean(j, 'booked'), canJoin: J.boolean(j, 'canJoin'), reason: J.strOrNull(j, 'reason'));
  }

  final bool isHost;
  final bool booked;
  final bool canJoin;
  final String? reason; // cancelled | ended | login_required | too_early | not_booked | not_started

  @override
  List<Object?> get props => [isHost, booked, canJoin, reason];
}

class MeetDetail extends Equatable {
  const MeetDetail({required this.meet, required this.access});

  factory MeetDetail.fromJson(Map<String, dynamic> json) =>
      MeetDetail(meet: StoreMeet.fromJson(J.map(json, 'meet') ?? const {}), access: MeetAccess.fromJson(J.map(json, 'access')));

  final StoreMeet meet;
  final MeetAccess access;

  @override
  List<Object?> get props => [meet, access];
}