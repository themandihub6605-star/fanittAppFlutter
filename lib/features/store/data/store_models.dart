import 'package:equatable/equatable.dart';

import '../../../core/utils/json.dart';
import 'live_call_models.dart';
import 'store_extra_models.dart';

export 'live_call_models.dart';
export 'store_extra_models.dart';

// Fanitt Store data models (backend: src/FanittStore). Money is in paise.

enum StoreStatus {
  draft('draft', 'Setting up'),
  pendingReview('pending_review', 'Under review'),
  active('active', 'Live'),
  rejected('rejected', 'Needs changes'),
  suspended('suspended', 'Suspended');

  const StoreStatus(this.value, this.label);
  final String value;
  final String label;

  static StoreStatus from(String? v) => StoreStatus.values.firstWhere((s) => s.value == v, orElse: () => StoreStatus.draft);
}

enum KycStatus {
  notSubmitted('not_submitted'),
  pending('pending'),
  verified('verified'),
  rejected('rejected');

  const KycStatus(this.value);
  final String value;

  static KycStatus from(String? v) => KycStatus.values.firstWhere((s) => s.value == v, orElse: () => KycStatus.notSubmitted);
}

class StoreStats extends Equatable {
  const StoreStats({required this.views, required this.orders, required this.grossSales, required this.feesPaid, required this.netEarnings, required this.refunds});

  factory StoreStats.fromJson(Map<String, dynamic>? json) {
    final j = json ?? const <String, dynamic>{};
    return StoreStats(
      views: J.integer(j, 'views'),
      orders: J.integer(j, 'orders'),
      grossSales: J.integer(j, 'grossSales'),
      feesPaid: J.integer(j, 'feesPaid'),
      netEarnings: J.integer(j, 'netEarnings'),
      refunds: J.integer(j, 'refunds'),
    );
  }

  final int views;
  final int orders;
  final int grossSales;
  final int feesPaid;
  final int netEarnings;
  final int refunds;

  @override
  List<Object?> get props => [views, orders, grossSales, feesPaid, netEarnings, refunds];
}

class StorePayout extends Equatable {
  const StorePayout({required this.method, this.upiId, this.accountHolderName, this.accountNumberMasked, this.ifsc, this.bankName});

  factory StorePayout.fromJson(Map<String, dynamic> json) => StorePayout(
    method: J.str(json, 'method'),
    upiId: J.strOrNull(json, 'upiId'),
    accountHolderName: J.strOrNull(json, 'accountHolderName'),
    accountNumberMasked: J.strOrNull(json, 'accountNumberMasked'),
    ifsc: J.strOrNull(json, 'ifsc'),
    bankName: J.strOrNull(json, 'bankName'),
  );

  final String method; // upi | bank
  final String? upiId;
  final String? accountHolderName;
  final String? accountNumberMasked;
  final String? ifsc;
  final String? bankName;

  bool get isUpi => method == 'upi';

  @override
  List<Object?> get props => [method, upiId, accountNumberMasked, ifsc];
}

/// A store as its owner sees it (also used for public pages, where the
/// private parts are simply empty).
class StoreInfo extends Equatable {
  const StoreInfo({
    required this.id,
    required this.slug,
    required this.name,
    required this.tagline,
    required this.about,
    required this.logoUrl,
    required this.bannerUrl,
    required this.isOpen,
    required this.status,
    required this.statusReason,
    required this.kycStatus,
    required this.kycRejectionReason,
    required this.hasPayout,
    required this.stats,
    this.payout,
  });

  factory StoreInfo.fromJson(Map<String, dynamic> json) {
    final payout = J.map(json, 'payout');
    final kyc = J.map(json, 'kyc');
    return StoreInfo(
      id: J.id(json),
      slug: J.str(json, 'slug'),
      name: J.str(json, 'name'),
      tagline: J.str(json, 'tagline'),
      about: J.str(json, 'about'),
      logoUrl: J.str(json, 'logoUrl'),
      bannerUrl: J.str(json, 'bannerUrl'),
      isOpen: J.boolean(json, 'isOpen', true),
      status: StoreStatus.from(J.strOrNull(json, 'status')),
      statusReason: J.str(json, 'statusReason'),
      kycStatus: KycStatus.from(J.strOrNull(json, 'kycStatus')),
      kycRejectionReason: kyc == null ? '' : J.str(kyc, 'rejectionReason'),
      hasPayout: J.boolean(json, 'hasPayout'),
      stats: StoreStats.fromJson(J.map(json, 'stats')),
      payout: payout == null ? null : StorePayout.fromJson(payout),
    );
  }

  final String id;
  final String slug;
  final String name;
  final String tagline;
  final String about;
  final String logoUrl;
  final String bannerUrl;
  final bool isOpen;
  final StoreStatus status;
  final String statusReason;
  final KycStatus kycStatus;
  final String kycRejectionReason;
  final bool hasPayout;
  final StoreStats stats;
  final StorePayout? payout;

  bool get isActive => status == StoreStatus.active;

  @override
  List<Object?> get props => [id, name, tagline, about, logoUrl, bannerUrl, isOpen, status, kycStatus, hasPayout, stats, payout];
}

class SetupSteps extends Equatable {
  const SetupSteps({required this.profile, required this.payout, required this.kyc, required this.terms, required this.complete});

  factory SetupSteps.fromJson(Map<String, dynamic>? json) {
    final j = json ?? const <String, dynamic>{};
    return SetupSteps(
      profile: J.boolean(j, 'profile'),
      payout: J.boolean(j, 'payout'),
      kyc: J.boolean(j, 'kyc'),
      terms: J.boolean(j, 'terms'),
      complete: J.boolean(j, 'complete'),
    );
  }

  final bool profile;
  final bool payout;
  final bool kyc;
  final bool terms;
  final bool complete;

  /// First step that still needs doing (0–3), or 4 when all are done.
  int get nextStep => !profile ? 0 : !payout ? 1 : !kyc ? 2 : !terms ? 3 : 4;

  @override
  List<Object?> get props => [profile, payout, kyc, terms, complete];
}

/// Response of GET/POST /store/me and every setup step.
class MyStore extends Equatable {
  const MyStore({
    required this.store,
    required this.steps,
    required this.termsVersion,
    required this.termsText,
    required this.storeFeePercent,
    this.subscriptionRequired = false,
    this.hasSubscription = false,
    this.planName = '',
  });

  factory MyStore.fromJson(Map<String, dynamic> json) {
    final store = J.map(json, 'store');
    final terms = J.map(json, 'terms') ?? const <String, dynamic>{};
    final fees = J.map(json, 'fees') ?? const <String, dynamic>{};
    final access = J.map(json, 'access') ?? const <String, dynamic>{};
    return MyStore(
      store: store == null ? null : StoreInfo.fromJson(store),
      steps: SetupSteps.fromJson(J.map(json, 'steps')),
      termsVersion: J.str(terms, 'version'),
      termsText: J.str(terms, 'text'),
      storeFeePercent: (fees['storeFeePercent'] as num?)?.toDouble() ?? 0,
      subscriptionRequired: J.boolean(access, 'subscriptionRequired'),
      hasSubscription: J.boolean(access, 'hasSubscription'),
      planName: J.str(access, 'planName'),
    );
  }

  final StoreInfo? store;
  final SetupSteps steps;
  final String termsVersion;
  final String termsText;
  final double storeFeePercent;

  /// Admin switch: a paid plan is needed to open a new store.
  final bool subscriptionRequired;
  final bool hasSubscription;
  final String planName;

  /// No store yet, plan required, and the creator isn't on a paid plan.
  bool get needsPlan => store == null && subscriptionRequired && !hasSubscription;

  @override
  List<Object?> get props => [store, steps, termsVersion, subscriptionRequired, hasSubscription];
}

class ToolCard extends Equatable {
  const ToolCard({required this.key, required this.title, required this.description, required this.imageUrl, required this.order});

  factory ToolCard.fromJson(Map<String, dynamic> json) => ToolCard(
    key: J.str(json, 'key'),
    title: J.str(json, 'title'),
    description: J.str(json, 'description'),
    imageUrl: J.str(json, 'imageUrl'),
    order: J.integer(json, 'order'),
  );

  final String key;
  final String title;
  final String description;
  final String imageUrl;
  final int order;

  @override
  List<Object?> get props => [key, title, description, imageUrl, order];
}

class StoreConfig extends Equatable {
  const StoreConfig({required this.toolCards, required this.storeFeePercent, required this.fanboxFeePercent});

  factory StoreConfig.fromJson(Map<String, dynamic> json) => StoreConfig(
    toolCards: J.list(json, 'toolCards', ToolCard.fromJson)..sort((a, b) => a.order.compareTo(b.order)),
    storeFeePercent: (json['storeFeePercent'] as num?)?.toDouble() ?? 0,
    fanboxFeePercent: (json['fanboxFeePercent'] as num?)?.toDouble() ?? 0,
  );

  final List<ToolCard> toolCards;
  final double storeFeePercent;
  final double fanboxFeePercent;

  @override
  List<Object?> get props => [toolCards, storeFeePercent, fanboxFeePercent];
}

enum ProductStatus {
  draft('draft', 'Draft'),
  published('published', 'Live'),
  unpublished('unpublished', 'Hidden'),
  removed('removed', 'Removed by Fanitt');

  const ProductStatus(this.value, this.label);
  final String value;
  final String label;

  static ProductStatus from(String? v) => ProductStatus.values.firstWhere((s) => s.value == v, orElse: () => ProductStatus.draft);
}

const productCategories = <String, String>{
  'course': 'Course',
  'ebook': 'eBook',
  'template': 'Template',
  'video': 'Video',
  'audio': 'Audio',
  'guide': 'Guide',
  'other': 'Other',
};

class ProductFile extends Equatable {
  const ProductFile({required this.id, required this.name, required this.size, required this.mimeType});

  factory ProductFile.fromJson(Map<String, dynamic> json) =>
      ProductFile(id: J.id(json), name: J.str(json, 'name'), size: J.integer(json, 'size'), mimeType: J.str(json, 'mimeType'));

  final String id;
  final String name;
  final int size;
  final String mimeType;

  @override
  List<Object?> get props => [id, name, size];
}

class DigitalProduct extends Equatable {
  const DigitalProduct({
    required this.id,
    required this.storeId,
    required this.title,
    required this.description,
    required this.category,
    required this.coverUrl,
    required this.price,
    required this.files,
    required this.fileCount,
    required this.totalSize,
    required this.status,
    required this.salesCount,
    required this.revenue,
    required this.views,
    required this.owned,
    required this.removedReason,
    this.storeName = '',
    this.storeSlug = '',
    this.storeLogoUrl = '',
  });

  factory DigitalProduct.fromJson(Map<String, dynamic> json) {
    final store = J.map(json, 'store');
    return DigitalProduct(
      id: J.id(json),
      storeId: J.refId(json, 'store') ?? '',
      title: J.str(json, 'title'),
      description: J.str(json, 'description'),
      category: J.str(json, 'category', 'other'),
      coverUrl: J.str(json, 'coverUrl'),
      price: J.integer(json, 'price'),
      files: J.list(json, 'files', ProductFile.fromJson),
      fileCount: J.integer(json, 'fileCount'),
      totalSize: J.integer(json, 'totalSize'),
      status: ProductStatus.from(J.strOrNull(json, 'status')),
      salesCount: J.integer(json, 'salesCount'),
      revenue: J.integer(json, 'revenue'),
      views: J.integer(json, 'views'),
      owned: J.boolean(json, 'owned'),
      removedReason: J.str(json, 'removedReason'),
      storeName: store == null ? '' : J.str(store, 'name'),
      storeSlug: store == null ? '' : J.str(store, 'slug'),
      storeLogoUrl: store == null ? '' : J.str(store, 'logoUrl'),
    );
  }

  final String id;
  final String storeId;

  /// Filled on the marketplace list (which store sells it).
  final String storeName;
  final String storeSlug;
  final String storeLogoUrl;
  final String title;
  final String description;
  final String category;
  final String coverUrl;
  final int price;
  final List<ProductFile> files;
  final int fileCount;
  final int totalSize;
  final ProductStatus status;
  final int salesCount;
  final int revenue;
  final int views;
  final bool owned;
  final String removedReason;

  bool get isFree => price == 0;
  String get categoryLabel => productCategories[category] ?? 'Other';

  @override
  List<Object?> get props => [id, title, description, category, coverUrl, price, files, status, salesCount, owned];
}

class StoreOrder extends Equatable {
  const StoreOrder({
    required this.id,
    required this.itemType,
    required this.itemId,
    required this.itemTitle,
    required this.itemCoverUrl,
    required this.amount,
    required this.feeAmount,
    required this.creatorEarning,
    required this.status,
    required this.invoiceNumber,
    required this.paidWith,
    this.paidAt,
    this.buyerName,
    this.buyerAvatarUrl,
  });

  factory StoreOrder.fromJson(Map<String, dynamic> json) {
    final buyer = J.map(json, 'buyer');
    return StoreOrder(
      id: J.id(json),
      itemType: J.str(json, 'itemType'),
      itemId: J.refId(json, 'itemId') ?? '',
      itemTitle: J.str(json, 'itemTitle'),
      itemCoverUrl: J.str(json, 'itemCoverUrl'),
      amount: J.integer(json, 'amount'),
      feeAmount: J.integer(json, 'feeAmount'),
      creatorEarning: J.integer(json, 'creatorEarning'),
      status: J.str(json, 'status'),
      invoiceNumber: J.str(json, 'invoiceNumber'),
      paidWith: J.str(json, 'paidWith'),
      paidAt: J.date(json, 'paidAt'),
      buyerName: buyer == null ? null : J.strOrNull(buyer, 'name'),
      buyerAvatarUrl: buyer == null ? null : J.strOrNull(buyer, 'avatarUrl'),
    );
  }

  final String id;
  final String itemType;
  final String itemId;
  final String itemTitle;
  final String itemCoverUrl;
  final int amount;
  final int feeAmount;
  final int creatorEarning;
  final String status; // pending | paid | failed | refunded
  final String invoiceNumber;
  final String paidWith;
  final DateTime? paidAt;
  final String? buyerName;
  final String? buyerAvatarUrl;

  bool get isPaid => status == 'paid';

  @override
  List<Object?> get props => [id, status, amount];
}

/// What the app needs to open Razorpay for a store payment.
class RazorpayCheckout {
  const RazorpayCheckout({required this.orderId, required this.amount, required this.keyId, required this.name, required this.description, this.prefillName, this.prefillEmail, this.prefillContact});

  factory RazorpayCheckout.fromJson(Map<String, dynamic> json) {
    final prefill = J.map(json, 'prefill') ?? const <String, dynamic>{};
    return RazorpayCheckout(
      orderId: J.str(json, 'orderId'),
      amount: J.integer(json, 'amount'),
      keyId: J.str(json, 'keyId'),
      name: J.str(json, 'name'),
      description: J.str(json, 'description'),
      prefillName: J.strOrNull(prefill, 'name'),
      prefillEmail: J.strOrNull(prefill, 'email'),
      prefillContact: J.strOrNull(prefill, 'contact'),
    );
  }

  final String orderId;
  final int amount;
  final String keyId;
  final String name;
  final String description;
  final String? prefillName;
  final String? prefillEmail;
  final String? prefillContact;
}

/// Result of starting any store checkout.
class CheckoutStart {
  const CheckoutStart({required this.order, required this.paid, this.razorpay});

  factory CheckoutStart.fromJson(Map<String, dynamic> json) {
    final rzp = J.map(json, 'razorpay');
    return CheckoutStart(
      order: StoreOrder.fromJson(J.map(json, 'order') ?? const {}),
      paid: J.boolean(json, 'paid') || J.boolean(json, 'free'),
      razorpay: rzp == null ? null : RazorpayCheckout.fromJson(rzp),
    );
  }

  final StoreOrder order;
  final bool paid;
  final RazorpayCheckout? razorpay;
}

class StoreSummary extends Equatable {
  const StoreSummary({required this.stats, required this.last30Days, required this.topProducts});

  factory StoreSummary.fromJson(Map<String, dynamic> json) => StoreSummary(
    stats: StoreStats.fromJson(J.map(json, 'stats')),
    last30Days: J.list(json, 'last30Days', (d) => (date: J.str(d, 'date'), gross: J.integer(d, 'gross'), net: J.integer(d, 'net'), orders: J.integer(d, 'orders'))),
    topProducts: J.list(json, 'topProducts', DigitalProduct.fromJson),
  );

  final StoreStats stats;
  final List<({String date, int gross, int net, int orders})> last30Days;
  final List<DigitalProduct> topProducts;

  @override
  List<Object?> get props => [stats, last30Days.length, topProducts];
}

/// A public store page.
class StorePage extends Equatable {
  const StorePage({
    required this.store,
    required this.isOwner,
    required this.products,
    required this.lives,
    required this.calls,
    required this.meets,
    required this.affiliate,
    required this.fanbox,
  });

  factory StorePage.fromJson(Map<String, dynamic> json) => StorePage(
    store: StoreInfo.fromJson(J.map(json, 'store') ?? const {}),
    isOwner: J.boolean(json, 'isOwner'),
    products: J.list(json, 'products', DigitalProduct.fromJson),
    lives: J.list(json, 'lives', LiveStream.fromJson),
    calls: CallInfo.fromJson(J.map(json, 'calls')),
    meets: J.list(json, 'meets', StoreMeet.fromJson),
    affiliate: AffiliateStorefront.fromJson(J.map(json, 'affiliate')),
    fanbox: FanBoxConfig.fromJson(J.map(json, 'fanbox')),
  );

  final StoreInfo store;
  final bool isOwner;
  final List<DigitalProduct> products;
  final List<LiveStream> lives;
  final CallInfo calls;
  final List<StoreMeet> meets;
  final AffiliateStorefront affiliate;
  final FanBoxConfig fanbox;

  @override
  List<Object?> get props => [store, isOwner, products, lives, calls, meets, affiliate];
}

class ProductPage extends Equatable {
  const ProductPage({required this.product, required this.store, required this.owned, required this.isOwner});

  factory ProductPage.fromJson(Map<String, dynamic> json) => ProductPage(
    product: DigitalProduct.fromJson(J.map(json, 'product') ?? const {}),
    store: StoreInfo.fromJson(J.map(json, 'store') ?? const {}),
    owned: J.boolean(json, 'owned'),
    isOwner: J.boolean(json, 'isOwner'),
  );

  final DigitalProduct product;
  final StoreInfo store;
  final bool owned;
  final bool isOwner;

  ProductPage copyWith({bool? owned}) => ProductPage(product: product, store: store, owned: owned ?? this.owned, isOwner: isOwner);

  @override
  List<Object?> get props => [product, store, owned, isOwner];
}

class LibraryItem extends Equatable {
  const LibraryItem({required this.orderId, required this.purchasedAt, required this.invoiceNumber, required this.storeName, required this.storeSlug, required this.product, required this.available});

  factory LibraryItem.fromJson(Map<String, dynamic> json) {
    final store = J.map(json, 'store') ?? const <String, dynamic>{};
    return LibraryItem(
      orderId: J.str(json, 'orderId'),
      purchasedAt: J.date(json, 'purchasedAt'),
      invoiceNumber: J.str(json, 'invoiceNumber'),
      storeName: J.str(store, 'name'),
      storeSlug: J.str(store, 'slug'),
      product: DigitalProduct.fromJson(J.map(json, 'product') ?? const {}),
      available: J.boolean(json, 'available'),
    );
  }

  final String orderId;
  final DateTime? purchasedAt;
  final String invoiceNumber;
  final String storeName;
  final String storeSlug;
  final DigitalProduct product;
  final bool available;

  @override
  List<Object?> get props => [orderId, product];
}

class Invoice {
  const Invoice({required this.invoiceNumber, required this.date, required this.status, required this.sellerName, required this.buyerName, required this.buyerEmail, required this.itemTitle, required this.amount, required this.paymentId});

  factory Invoice.fromJson(Map<String, dynamic> json) {
    final seller = J.map(json, 'seller') ?? const <String, dynamic>{};
    final buyer = J.map(json, 'buyer') ?? const <String, dynamic>{};
    final item = J.map(json, 'item') ?? const <String, dynamic>{};
    return Invoice(
      invoiceNumber: J.str(json, 'invoiceNumber'),
      date: J.date(json, 'date'),
      status: J.str(json, 'status'),
      sellerName: J.str(seller, 'name'),
      buyerName: J.str(buyer, 'name'),
      buyerEmail: J.str(buyer, 'email'),
      itemTitle: J.str(item, 'title'),
      amount: J.integer(json, 'amount'),
      paymentId: J.str(json, 'paymentId'),
    );
  }

  final String invoiceNumber;
  final DateTime? date;
  final String status;
  final String sellerName;
  final String buyerName;
  final String buyerEmail;
  final String itemTitle;
  final int amount;
  final String paymentId;
}