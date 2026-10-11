import '../../../core/utils/json.dart';

// Physical products: product, cart, address, checkout and orders.
// Backend: /api/store/shop/... — all money is in paise.

const shopCategories = <String, String>{
  'fashion': 'Fashion',
  'accessories': 'Accessories',
  'beauty': 'Beauty',
  'home': 'Home & living',
  'electronics': 'Electronics',
  'books': 'Books',
  'art': 'Art',
  'fitness': 'Fitness',
  'food': 'Food',
  'merch': 'Merch',
  'other': 'Other',
};

String shopCategoryLabel(String key) => shopCategories[key] ?? 'Other';

class ShopConfig {
  const ShopConfig({required this.enabled, required this.categories, required this.codEnabled, required this.onlineEnabled, required this.codMaxAmount});

  factory ShopConfig.fromJson(Map<String, dynamic> json) => ShopConfig(
    enabled: J.boolean(json, 'enabled', true),
    categories: J.strings(json, 'categories'),
    codEnabled: J.boolean(json, 'codEnabled', true),
    onlineEnabled: J.boolean(json, 'onlineEnabled', true),
    codMaxAmount: J.integer(json, 'codMaxAmount'),
  );

  final bool enabled;
  final List<String> categories;
  final bool codEnabled;
  final bool onlineEnabled;
  final int codMaxAmount;
}

class ShopStoreRef {
  const ShopStoreRef({required this.id, required this.name, required this.slug, required this.logoUrl, this.tagline = '', this.userId});

  factory ShopStoreRef.fromJson(Map<String, dynamic> json) => ShopStoreRef(
    id: J.id(json),
    name: J.str(json, 'name'),
    slug: J.str(json, 'slug'),
    logoUrl: J.str(json, 'logoUrl'),
    tagline: J.str(json, 'tagline'),
    userId: J.refId(json, 'user'),
  );

  static const empty = ShopStoreRef(id: '', name: '', slug: '', logoUrl: '');

  final String id;
  final String name;
  final String slug;
  final String logoUrl;
  final String tagline;
  final String? userId;
}

class ShopVariant {
  const ShopVariant({required this.id, required this.label, this.stock, this.inStock = true});

  factory ShopVariant.fromJson(Map<String, dynamic> json) => ShopVariant(
    id: J.id(json),
    label: J.str(json, 'label'),
    stock: J.integerOrNull(json, 'stock'),
    inStock: J.boolean(json, 'inStock', true),
  );

  final String id;
  final String label;

  /// Exact number for the seller; for buyers only when 10 or fewer are left.
  final int? stock;
  final bool inStock;
}

class ShopProduct {
  const ShopProduct({
    required this.id,
    required this.title,
    required this.description,
    required this.highlights,
    required this.category,
    required this.images,
    required this.mrp,
    required this.price,
    required this.discountPercent,
    required this.variantName,
    required this.variants,
    required this.inStock,
    required this.totalStock,
    required this.deliveryCharge,
    required this.deliveryDays,
    required this.codAvailable,
    required this.returnPolicy,
    required this.salesCount,
    required this.store,
    required this.status,
    required this.removedReason,
    required this.views,
    this.stock = 0,
  });

  factory ShopProduct.fromJson(Map<String, dynamic> json) {
    final storeMap = J.map(json, 'store');
    return ShopProduct(
      id: J.id(json),
      title: J.str(json, 'title'),
      description: J.str(json, 'description'),
      highlights: J.strings(json, 'highlights'),
      category: J.str(json, 'category', 'other'),
      images: J.strings(json, 'images'),
      mrp: J.integer(json, 'mrp'),
      price: J.integer(json, 'price'),
      discountPercent: J.integer(json, 'discountPercent'),
      variantName: J.str(json, 'variantName'),
      variants: J.list(json, 'variants', ShopVariant.fromJson),
      inStock: J.boolean(json, 'inStock', true),
      totalStock: J.integerOrNull(json, 'totalStock'),
      deliveryCharge: J.integer(json, 'deliveryCharge'),
      deliveryDays: J.str(json, 'deliveryDays'),
      codAvailable: J.boolean(json, 'codAvailable', true),
      returnPolicy: J.str(json, 'returnPolicy'),
      salesCount: J.integer(json, 'salesCount'),
      store: storeMap == null ? ShopStoreRef(id: J.refId(json, 'store') ?? '', name: '', slug: '', logoUrl: '') : ShopStoreRef.fromJson(storeMap),
      status: J.str(json, 'status', 'published'),
      removedReason: J.str(json, 'removedReason'),
      views: J.integer(json, 'views'),
      stock: J.integer(json, 'totalStock'),
    );
  }

  final String id;
  final String title;
  final String description;
  final List<String> highlights;
  final String category;
  final List<String> images;
  final int mrp;
  final int price;
  final int discountPercent;
  final String variantName;
  final List<ShopVariant> variants;
  final bool inStock;
  final int? totalStock;
  final int deliveryCharge;
  final String deliveryDays;
  final bool codAvailable;
  final String returnPolicy;
  final int salesCount;
  final ShopStoreRef store;
  final String status;
  final String removedReason;
  final int views;

  /// Seller view: units in stock when the product has no options.
  final int stock;

  String get imageUrl => images.isEmpty ? '' : images.first;
  bool get hasVariants => variants.isNotEmpty;
  bool get isPublished => status == 'published';
  bool get isDraft => status == 'draft';
  bool get isRemoved => status == 'removed';
  bool get hasDiscount => mrp > price;
  String get categoryLabel => shopCategoryLabel(category);

  /// "Only 3 left" when stock is low (buyers only see small numbers).
  String? get lowStockLabel {
    final left = totalStock;
    if (!inStock) return 'Out of stock';
    if (left != null && left > 0 && left <= 5) return 'Only $left left';
    return null;
  }
}

/// Product page = product + the store + more from the same store.
class ShopProductPage {
  const ShopProductPage({required this.product, required this.isOwner, required this.moreFromStore});

  factory ShopProductPage.fromJson(Map<String, dynamic> json) => ShopProductPage(
    product: ShopProduct.fromJson(json),
    isOwner: J.boolean(json, 'isOwner'),
    moreFromStore: J.list(json, 'moreFromStore', ShopProduct.fromJson),
  );

  final ShopProduct product;
  final bool isOwner;
  final List<ShopProduct> moreFromStore;
}

// ---------- cart ----------

class CartLine {
  const CartLine({
    required this.id,
    required this.productId,
    required this.variantId,
    required this.qty,
    required this.available,
    required this.problem,
    required this.title,
    required this.imageUrl,
    required this.variantLabel,
    required this.variantName,
    required this.price,
    required this.mrp,
    required this.lineTotal,
    required this.store,
    this.stock,
  });

  factory CartLine.fromJson(Map<String, dynamic> json) {
    final store = J.map(json, 'store');
    return CartLine(
      id: J.id(json),
      productId: J.str(json, 'productId'),
      variantId: J.strOrNull(json, 'variantId'),
      qty: J.integer(json, 'qty', 1),
      available: J.boolean(json, 'available'),
      problem: J.str(json, 'problem'),
      title: J.str(json, 'title'),
      imageUrl: J.str(json, 'imageUrl'),
      variantLabel: J.str(json, 'variantLabel'),
      variantName: J.str(json, 'variantName'),
      price: J.integer(json, 'price'),
      mrp: J.integer(json, 'mrp'),
      lineTotal: J.integer(json, 'lineTotal'),
      store: store == null ? ShopStoreRef.empty : ShopStoreRef.fromJson(store),
      stock: J.integerOrNull(json, 'stock'),
    );
  }

  final String id;
  final String productId;
  final String? variantId;
  final int qty;
  final bool available;
  final String problem;
  final String title;
  final String imageUrl;
  final String variantLabel;
  final String variantName;
  final int price;
  final int mrp;
  final int lineTotal;
  final ShopStoreRef store;
  final int? stock;

  String get optionText => variantLabel.isEmpty ? '' : '${variantName.isEmpty ? 'Option' : variantName}: $variantLabel';
}

/// Items of one seller — they ship as one parcel.
class SellerGroup {
  const SellerGroup({required this.store, required this.itemsTotal, required this.deliveryCharge, required this.total, required this.codAvailable, required this.lines});

  factory SellerGroup.fromJson(Map<String, dynamic> json) => SellerGroup(
    store: ShopStoreRef.fromJson(J.map(json, 'store') ?? const {}),
    itemsTotal: J.integer(json, 'itemsTotal'),
    deliveryCharge: J.integer(json, 'deliveryCharge'),
    total: J.integer(json, 'total'),
    codAvailable: J.boolean(json, 'codAvailable', true),
    lines: J.list(json, 'lines', CartLine.fromJson),
  );

  final ShopStoreRef store;
  final int itemsTotal;
  final int deliveryCharge;
  final int total;
  final bool codAvailable;
  final List<CartLine> lines;
}

class CheckoutSummary {
  const CheckoutSummary({
    required this.sellers,
    required this.itemCount,
    required this.mrpTotal,
    required this.itemsTotal,
    required this.savings,
    required this.deliveryCharge,
    required this.total,
    required this.codAvailable,
    required this.codNote,
    required this.onlineAvailable,
    this.unavailable = const [],
  });

  factory CheckoutSummary.fromJson(Map<String, dynamic> json) => CheckoutSummary(
    sellers: J.list(json, 'sellers', SellerGroup.fromJson),
    itemCount: J.integer(json, 'itemCount'),
    mrpTotal: J.integer(json, 'mrpTotal'),
    itemsTotal: J.integer(json, 'itemsTotal'),
    savings: J.integer(json, 'savings'),
    deliveryCharge: J.integer(json, 'deliveryCharge'),
    total: J.integer(json, 'total'),
    codAvailable: J.boolean(json, 'codAvailable'),
    codNote: J.str(json, 'codNote'),
    onlineAvailable: J.boolean(json, 'onlineAvailable', true),
    unavailable: J.list(json, 'unavailable', CartLine.fromJson),
  );

  final List<SellerGroup> sellers;
  final int itemCount;
  final int mrpTotal;
  final int itemsTotal;
  final int savings;
  final int deliveryCharge;
  final int total;
  final bool codAvailable;
  final String codNote;
  final bool onlineAvailable;
  final List<CartLine> unavailable;
}

class Cart {
  const Cart({required this.items, required this.count, required this.summary});

  factory Cart.fromJson(Map<String, dynamic> json) => Cart(
    items: J.list(json, 'items', CartLine.fromJson),
    count: J.integer(json, 'count'),
    summary: CheckoutSummary.fromJson(J.map(json, 'summary') ?? const {}),
  );

  final List<CartLine> items;
  final int count;
  final CheckoutSummary summary;

  bool get isEmpty => items.isEmpty;
  List<CartLine> get unavailable => items.where((l) => !l.available).toList();
}

// ---------- address ----------

class ShopAddress {
  const ShopAddress({
    required this.id,
    required this.name,
    required this.phone,
    required this.line1,
    required this.line2,
    required this.landmark,
    required this.city,
    required this.state,
    required this.pincode,
    required this.label,
    required this.isDefault,
  });

  factory ShopAddress.fromJson(Map<String, dynamic> json) => ShopAddress(
    id: J.id(json),
    name: J.str(json, 'name'),
    phone: J.str(json, 'phone'),
    line1: J.str(json, 'line1'),
    line2: J.str(json, 'line2'),
    landmark: J.str(json, 'landmark'),
    city: J.str(json, 'city'),
    state: J.str(json, 'state'),
    pincode: J.str(json, 'pincode'),
    label: J.str(json, 'label', 'home'),
    isDefault: J.boolean(json, 'isDefault'),
  );

  final String id;
  final String name;
  final String phone;
  final String line1;
  final String line2;
  final String landmark;
  final String city;
  final String state;
  final String pincode;
  final String label;
  final bool isDefault;

  String get singleLine => [line1, line2, if (landmark.isNotEmpty) 'Near $landmark', city, '$state - $pincode'].where((s) => s.trim().isNotEmpty).join(', ');
  String get labelText => switch (label) { 'work' => 'Work', 'other' => 'Other', _ => 'Home' };
}

// ---------- orders ----------

class ShopOrderItem {
  const ShopOrderItem({required this.productId, required this.title, required this.imageUrl, required this.variantLabel, required this.variantName, required this.price, required this.mrp, required this.qty});

  factory ShopOrderItem.fromJson(Map<String, dynamic> json) => ShopOrderItem(
    productId: J.refId(json, 'product') ?? '',
    title: J.str(json, 'title'),
    imageUrl: J.str(json, 'imageUrl'),
    variantLabel: J.str(json, 'variantLabel'),
    variantName: J.str(json, 'variantName'),
    price: J.integer(json, 'price'),
    mrp: J.integer(json, 'mrp'),
    qty: J.integer(json, 'qty', 1),
  );

  final String productId;
  final String title;
  final String imageUrl;
  final String variantLabel;
  final String variantName;
  final int price;
  final int mrp;
  final int qty;

  String get optionText => variantLabel.isEmpty ? '' : '${variantName.isEmpty ? 'Option' : variantName}: $variantLabel';
}

class OrderEvent {
  const OrderEvent({required this.status, required this.at, required this.note, required this.by});

  factory OrderEvent.fromJson(Map<String, dynamic> json) => OrderEvent(
    status: J.str(json, 'status'),
    at: J.date(json, 'at') ?? DateTime.now(),
    note: J.str(json, 'note'),
    by: J.str(json, 'by'),
  );

  final String status;
  final DateTime at;
  final String note;
  final String by;
}

class OrderBuyer {
  const OrderBuyer({required this.id, required this.name, required this.avatar});

  final String id;
  final String name;
  final String avatar;
}

class ShopOrder {
  const ShopOrder({
    required this.id,
    required this.orderNumber,
    required this.checkoutId,
    required this.status,
    required this.items,
    required this.itemCount,
    required this.itemsTotal,
    required this.deliveryCharge,
    required this.total,
    required this.address,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.courier,
    required this.trackingId,
    required this.trackingUrl,
    required this.sellerNote,
    required this.cancelReason,
    required this.cancelledBy,
    required this.timeline,
    required this.createdAt,
    required this.store,
    required this.canCancel,
    required this.canMarkReceived,
    required this.feeAmount,
    required this.feePercent,
    required this.creatorEarning,
    required this.nextActions,
    this.placedAt,
    this.deliveredAt,
    this.buyer,
  });

  factory ShopOrder.fromJson(Map<String, dynamic> json) {
    final storeMap = J.map(json, 'store');
    final buyerMap = J.map(json, 'buyer');
    final address = J.map(json, 'address') ?? const <String, dynamic>{};
    return ShopOrder(
      id: J.id(json),
      orderNumber: J.str(json, 'orderNumber'),
      checkoutId: J.str(json, 'checkoutId'),
      status: J.str(json, 'status'),
      items: J.list(json, 'items', ShopOrderItem.fromJson),
      itemCount: J.integer(json, 'itemCount', 1),
      itemsTotal: J.integer(json, 'itemsTotal'),
      deliveryCharge: J.integer(json, 'deliveryCharge'),
      total: J.integer(json, 'total'),
      address: ShopAddress.fromJson(address),
      paymentMethod: J.str(json, 'paymentMethod', 'cod'),
      paymentStatus: J.str(json, 'paymentStatus', 'pending'),
      courier: J.str(json, 'courier'),
      trackingId: J.str(json, 'trackingId'),
      trackingUrl: J.str(json, 'trackingUrl'),
      sellerNote: J.str(json, 'sellerNote'),
      cancelReason: J.str(json, 'cancelReason'),
      cancelledBy: J.str(json, 'cancelledBy'),
      timeline: J.list(json, 'timeline', OrderEvent.fromJson),
      createdAt: J.date(json, 'createdAt') ?? DateTime.now(),
      placedAt: J.date(json, 'placedAt'),
      deliveredAt: J.date(json, 'deliveredAt'),
      store: storeMap == null ? ShopStoreRef(id: J.refId(json, 'store') ?? '', name: '', slug: '', logoUrl: '') : ShopStoreRef.fromJson(storeMap),
      buyer: buyerMap == null ? null : OrderBuyer(id: J.id(buyerMap), name: J.str(buyerMap, 'name'), avatar: J.str(buyerMap, 'avatar')),
      canCancel: J.boolean(json, 'canCancel'),
      canMarkReceived: J.boolean(json, 'canMarkReceived'),
      feeAmount: J.integer(json, 'feeAmount'),
      feePercent: J.dbl(json, 'feePercent'),
      creatorEarning: J.integer(json, 'creatorEarning'),
      nextActions: J.strings(json, 'nextActions'),
    );
  }

  final String id;
  final String orderNumber;
  final String checkoutId;
  final String status;
  final List<ShopOrderItem> items;
  final int itemCount;
  final int itemsTotal;
  final int deliveryCharge;
  final int total;
  final ShopAddress address;
  final String paymentMethod;
  final String paymentStatus;
  final String courier;
  final String trackingId;
  final String trackingUrl;
  final String sellerNote;
  final String cancelReason;
  final String cancelledBy;
  final List<OrderEvent> timeline;
  final DateTime createdAt;
  final DateTime? placedAt;
  final DateTime? deliveredAt;
  final ShopStoreRef store;
  final OrderBuyer? buyer;
  final bool canCancel;
  final bool canMarkReceived;

  // Seller only
  final int feeAmount;
  final double feePercent;
  final int creatorEarning;
  final List<String> nextActions;

  bool get isCod => paymentMethod == 'cod';
  bool get isCancelled => status == 'cancelled';
  bool get isDelivered => status == 'delivered';
  bool get isShipped => status == 'shipped';
  String get statusLabel => orderStatusLabel(status);
  String get firstImage => items.isEmpty ? '' : items.first.imageUrl;
  String get title => items.isEmpty ? 'Order' : (items.length == 1 ? items.first.title : '${items.first.title} + ${items.length - 1} more');

  String get paymentLabel {
    if (isCod) return paymentStatus == 'paid' ? 'Cash on Delivery · Paid' : 'Cash on Delivery';
    return switch (paymentStatus) { 'refunded' => 'Paid online · Refunded', 'paid' => 'Paid online', _ => 'Online payment pending' };
  }
}

String orderStatusLabel(String status) => switch (status) {
  'awaiting_payment' => 'Payment pending',
  'placed' => 'Order placed',
  'confirmed' => 'Confirmed',
  'shipped' => 'Shipped',
  'delivered' => 'Delivered',
  'cancelled' => 'Cancelled',
  'payment_failed' => 'Payment failed',
  _ => status,
};

/// Result of placing an order. `razorpay` is set when it still needs paying online.
class CheckoutResult {
  const CheckoutResult({required this.checkoutId, required this.placed, required this.orders, required this.total, this.razorpay});

  factory CheckoutResult.fromJson(Map<String, dynamic> json) {
    final rzp = J.map(json, 'razorpay');
    return CheckoutResult(
      checkoutId: J.str(json, 'checkoutId'),
      placed: J.boolean(json, 'placed'),
      orders: J.list(json, 'orders', ShopOrder.fromJson),
      total: J.integer(json, 'total'),
      razorpay: rzp == null ? null : ShopRazorpay.fromJson(rzp),
    );
  }

  final String checkoutId;
  final bool placed;
  final List<ShopOrder> orders;
  final int total;
  final ShopRazorpay? razorpay;
}

class ShopRazorpay {
  const ShopRazorpay({required this.keyId, required this.orderId, required this.amount, required this.description, required this.name, required this.email, required this.contact});

  factory ShopRazorpay.fromJson(Map<String, dynamic> json) {
    final prefill = J.map(json, 'prefill') ?? const <String, dynamic>{};
    return ShopRazorpay(
      keyId: J.str(json, 'keyId'),
      orderId: J.str(json, 'orderId'),
      amount: J.integer(json, 'amount'),
      description: J.str(json, 'description', 'Fanitt Store order'),
      name: J.str(prefill, 'name'),
      email: J.str(prefill, 'email'),
      contact: J.str(prefill, 'contact'),
    );
  }

  final String keyId;
  final String orderId;
  final int amount;
  final String description;
  final String name;
  final String email;
  final String contact;
}

// ---------- seller ----------

class SellerShopSummary {
  const SellerShopSummary({
    required this.productsTotal,
    required this.productsLive,
    required this.productsDraft,
    required this.newOrders,
    required this.toShip,
    required this.shipped,
    required this.delivered,
    required this.cancelled,
    required this.sales,
    required this.fees,
    required this.earnings,
  });

  factory SellerShopSummary.fromJson(Map<String, dynamic> json) {
    final p = J.map(json, 'products') ?? const <String, dynamic>{};
    final o = J.map(json, 'orders') ?? const <String, dynamic>{};
    return SellerShopSummary(
      productsTotal: J.integer(p, 'total'),
      productsLive: J.integer(p, 'published'),
      productsDraft: J.integer(p, 'draft'),
      newOrders: J.integer(o, 'new'),
      toShip: J.integer(o, 'toShip'),
      shipped: J.integer(o, 'shipped'),
      delivered: J.integer(o, 'delivered'),
      cancelled: J.integer(o, 'cancelled'),
      sales: J.integer(json, 'sales'),
      fees: J.integer(json, 'fees'),
      earnings: J.integer(json, 'earnings'),
    );
  }

  final int productsTotal;
  final int productsLive;
  final int productsDraft;
  final int newOrders;
  final int toShip;
  final int shipped;
  final int delivered;
  final int cancelled;
  final int sales;
  final int fees;
  final int earnings;

  int get needsAction => newOrders + toShip;
}

class SellerOrdersPage {
  const SellerOrdersPage({required this.orders, required this.page, required this.pages, required this.total, required this.tabCounts});

  factory SellerOrdersPage.fromJson(Map<String, dynamic> json) {
    final counts = J.map(json, 'tabCounts') ?? const <String, dynamic>{};
    return SellerOrdersPage(
      orders: J.list(json, 'orders', ShopOrder.fromJson),
      page: J.integer(json, 'page', 1),
      pages: J.integer(json, 'pages', 1),
      total: J.integer(json, 'total'),
      tabCounts: {for (final e in counts.entries) e.key: e.value is num ? (e.value as num).toInt() : 0},
    );
  }

  final List<ShopOrder> orders;
  final int page;
  final int pages;
  final int total;
  final Map<String, int> tabCounts;
}

/// What the seller fills in on the product editor.
class ShopProductInput {
  const ShopProductInput({
    required this.title,
    required this.description,
    required this.highlights,
    required this.category,
    required this.price,
    required this.mrp,
    required this.stock,
    required this.variantName,
    required this.variants,
    required this.deliveryCharge,
    required this.deliveryDays,
    required this.codAvailable,
    required this.returnPolicy,
  });

  final String title;
  final String description;
  final List<String> highlights;
  final String category;
  final int price;
  final int mrp;
  final int stock;
  final String variantName;

  /// (id or null for new, label, stock)
  final List<({String? id, String label, int stock})> variants;
  final int deliveryCharge;
  final String deliveryDays;
  final bool codAvailable;
  final String returnPolicy;

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'highlights': highlights,
    'category': category,
    'price': price,
    'mrp': mrp,
    'stock': stock,
    'variantName': variants.isEmpty ? '' : variantName,
    'variants': [
      for (final v in variants) {if (v.id != null) '_id': v.id, 'label': v.label, 'stock': v.stock},
    ],
    'deliveryCharge': deliveryCharge,
    'deliveryDays': deliveryDays,
    'codAvailable': codAvailable,
    'returnPolicy': returnPolicy,
  };
}