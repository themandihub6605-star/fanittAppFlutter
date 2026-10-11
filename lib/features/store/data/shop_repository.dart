import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/di/injection.dart';
import '../../../core/models/common_models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/multipart.dart';
import '../../../core/services/media_picker.dart';
import '../../../core/utils/json.dart';
import 'shop_models.dart';

export 'shop_models.dart';

/// Fanitt Store — physical products (backend: /api/store/shop).
/// Cart, addresses, checkout and orders for buyers; products and orders
/// for sellers.
class ShopRepository {
  ShopRepository._(this._api);

  static ShopRepository? _instance;

  /// One shared instance (uses the app's API client).
  static ShopRepository get i => _instance ??= ShopRepository._(sl<ApiClient>());

  final ApiClient _api;

  /// Items in the cart — the cart icon badge listens to this.
  final ValueNotifier<int> cartCount = ValueNotifier<int>(0);

  static const _base = '/store/shop';

  static ShopProduct _product(dynamic d) => ShopProduct.fromJson(J.asMap(d));
  static ShopOrder _order(dynamic d) => ShopOrder.fromJson(J.asMap(d));

  Cart _cart(dynamic d) {
    final cart = Cart.fromJson(J.asMap(d));
    cartCount.value = cart.count;
    return cart;
  }

  Paged<T> _paged<T>(dynamic d, String key, T Function(Map<String, dynamic>) parse) {
    final m = J.asMap(d);
    return Paged(items: J.list(m, key, parse), page: J.integer(m, 'page', 1), pages: J.integer(m, 'pages', 1), total: J.integer(m, 'total'));
  }

  // ---------- browsing ----------

  Future<ShopConfig> config() async => (await _api.get('$_base/config', parser: (d) => ShopConfig.fromJson(J.asMap(d)))).data;

  /// sort: new | popular | price_low | price_high
  Future<Paged<ShopProduct>> products({int page = 1, int limit = 20, String? category, String? search, String sort = 'new', String? storeId, String? exclude}) async => (await _api.get(
    '$_base/products',
    query: {
      'page': page,
      'limit': limit,
      'sort': sort,
      if (category != null && category.isNotEmpty) 'category': category,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (storeId != null && storeId.isNotEmpty) 'store': storeId,
      if (exclude != null) 'exclude': exclude,
    },
    parser: (d) => _paged(d, 'products', ShopProduct.fromJson),
  ))
      .data;

  Future<ShopProductPage> productPage(String id) async =>
      (await _api.get('$_base/products/$id', parser: (d) => ShopProductPage.fromJson(J.asMap(d)))).data;

  // ---------- cart ----------

  Future<Cart> cart() async => (await _api.get('$_base/cart', parser: _cart)).data;

  /// Keeps the cart badge right (call on app start / when a screen opens).
  Future<void> refreshCartCount() async {
    try {
      cartCount.value = (await _api.get('$_base/cart/count', parser: (d) => J.integer(J.asMap(d), 'count'))).data;
    } catch (_) {
      // Badge only — never block a screen on it.
    }
  }

  Future<Cart> addToCart(String productId, {String? variantId, int qty = 1}) async => (await _api.post(
    '$_base/cart/items',
    data: {'productId': productId, if (variantId != null) 'variantId': variantId, 'qty': qty},
    parser: _cart,
  ))
      .data;

  Future<Cart> setQty(String lineId, int qty) async => (await _api.patch('$_base/cart/items/$lineId', data: {'qty': qty}, parser: _cart)).data;

  Future<Cart> removeLine(String lineId) async => (await _api.delete('$_base/cart/items/$lineId', parser: _cart)).data;

  // ---------- addresses ----------

  Future<List<ShopAddress>> addresses() async => (await _api.get('$_base/addresses', parser: (d) => J.listOf(d, ShopAddress.fromJson))).data;

  Future<ShopAddress> saveAddress(Map<String, dynamic> data, {String? id}) async {
    final parser = (dynamic d) => ShopAddress.fromJson(J.asMap(d));
    return id == null
        ? (await _api.post('$_base/addresses', data: data, parser: parser)).data
        : (await _api.patch('$_base/addresses/$id', data: data, parser: parser)).data;
  }

  Future<void> deleteAddress(String id) async => _api.delete('$_base/addresses/$id', parser: (_) => null);

  // ---------- checkout ----------

  /// Whole cart (productId == null) or "Buy now" for one product.
  Map<String, dynamic> _lines({String? productId, String? variantId, int qty = 1}) => productId == null
      ? {'source': 'cart'}
      : {'source': 'buy_now', 'productId': productId, if (variantId != null) 'variantId': variantId, 'qty': qty};

  Future<CheckoutSummary> previewCheckout({String? productId, String? variantId, int qty = 1}) async => (await _api.post(
    '$_base/checkout/preview',
    data: _lines(productId: productId, variantId: variantId, qty: qty),
    parser: (d) => CheckoutSummary.fromJson(J.asMap(d)),
  ))
      .data;

  Future<CheckoutResult> checkout({required String addressId, required String paymentMethod, String? productId, String? variantId, int qty = 1}) async => (await _api.post(
    '$_base/checkout',
    data: {..._lines(productId: productId, variantId: variantId, qty: qty), 'addressId': addressId, 'paymentMethod': paymentMethod},
    parser: (d) => CheckoutResult.fromJson(J.asMap(d)),
  ))
      .data;

  Future<List<ShopOrder>> verifyCheckout(String checkoutId, {required String razorpayOrderId, required String paymentId, required String signature}) async => (await _api.post(
    '$_base/checkout/$checkoutId/verify',
    data: {'razorpayOrderId': razorpayOrderId, 'razorpayPaymentId': paymentId, 'razorpaySignature': signature},
    parser: (d) => J.list(J.asMap(d), 'orders', ShopOrder.fromJson),
  ))
      .data;

  // ---------- my orders (buyer) ----------

  /// status: active | delivered | cancelled | null (all)
  Future<Paged<ShopOrder>> myOrders({int page = 1, String? status}) async => (await _api.get(
    '$_base/orders',
    query: {'page': page, if (status != null) 'status': status},
    parser: (d) => _paged(d, 'orders', ShopOrder.fromJson),
  ))
      .data;

  Future<ShopOrder> myOrder(String id) async => (await _api.get('$_base/orders/$id', parser: _order)).data;

  Future<ShopOrder> cancelMyOrder(String id, String reason) async => (await _api.post('$_base/orders/$id/cancel', data: {'reason': reason}, parser: _order)).data;

  Future<ShopOrder> markReceived(String id) async => (await _api.post('$_base/orders/$id/received', parser: _order)).data;

  // ---------- seller: products ----------

  Future<SellerShopSummary> sellerSummary() async => (await _api.get('$_base/me/summary', parser: (d) => SellerShopSummary.fromJson(J.asMap(d)))).data;

  Future<List<ShopProduct>> myProducts({String? status}) async =>
      (await _api.get('$_base/me/products', query: {if (status != null) 'status': status}, parser: (d) => J.listOf(d, ShopProduct.fromJson))).data;

  Future<ShopProduct> myProduct(String id) async => (await _api.get('$_base/me/products/$id', parser: _product)).data;

  Future<ShopProduct> createProduct(ShopProductInput input) async => (await _api.post('$_base/me/products', data: input.toJson(), parser: _product)).data;

  Future<ShopProduct> updateProduct(String id, ShopProductInput input) async => (await _api.patch('$_base/me/products/$id', data: input.toJson(), parser: _product)).data;

  /// Deletes the product — or only hides it when it has past orders.
  /// Returns the server's message so the app can say which happened.
  Future<String> deleteProduct(String id) async => (await _api.delete('$_base/me/products/$id', parser: (_) => null)).message;

  Future<ShopProduct> uploadImages(String id, List<PickedMedia> images) async {
    final form = FormData();
    for (final image in images) {
      form.files.add(MapEntry('images', await multipartFrom(image)));
    }
    return (await _api.post('$_base/me/products/$id/images', data: form, parser: _product)).data;
  }

  Future<ShopProduct> reorderImages(String id, List<String> urls) async => (await _api.put('$_base/me/products/$id/images', data: {'images': urls}, parser: _product)).data;

  Future<ShopProduct> removeImage(String id, String url) async => (await _api.delete('$_base/me/products/$id/images', data: {'url': url}, parser: _product)).data;

  Future<ShopProduct> publish(String id) async => (await _api.post('$_base/me/products/$id/publish', parser: _product)).data;

  Future<ShopProduct> unpublish(String id) async => (await _api.post('$_base/me/products/$id/unpublish', parser: _product)).data;

  // ---------- seller: orders ----------

  /// tab: new | to_ship | shipped | delivered | cancelled
  Future<SellerOrdersPage> sellerOrders({required String tab, int page = 1}) async => (await _api.get(
    '$_base/me/orders',
    query: {'tab': tab, 'page': page},
    parser: (d) => SellerOrdersPage.fromJson(J.asMap(d)),
  ))
      .data;

  Future<ShopOrder> sellerOrder(String id) async => (await _api.get('$_base/me/orders/$id', parser: _order)).data;

  Future<ShopOrder> confirmOrder(String id) async => (await _api.post('$_base/me/orders/$id/confirm', parser: _order)).data;

  Future<ShopOrder> shipOrder(String id, {String courier = '', String trackingId = '', String trackingUrl = '', String note = ''}) async => (await _api.post(
    '$_base/me/orders/$id/ship',
    data: {'courier': courier, 'trackingId': trackingId, 'trackingUrl': trackingUrl, 'note': note},
    parser: _order,
  ))
      .data;

  Future<ShopOrder> deliverOrder(String id) async => (await _api.post('$_base/me/orders/$id/deliver', parser: _order)).data;

  Future<ShopOrder> sellerCancel(String id, String reason) async => (await _api.post('$_base/me/orders/$id/cancel', data: {'reason': reason}, parser: _order)).data;
}