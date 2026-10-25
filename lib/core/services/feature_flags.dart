import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/api_client.dart';
import '../utils/json.dart';

/// Switches the admin panel can flip without an app update.
///
/// Right now: the Fanitt Store's physical products (merch shop) —
/// GET /api/features → store.enabled. Off hides the shop (home "Fanitt
/// Store" section, shop, cart, checkout, product pages); stores, digital
/// products, lives, calls and FanBox stay. The last value is cached, so the
/// app opens in the right state even offline, and it refreshes on launch
/// and whenever the app comes back to the foreground.
abstract final class FeatureFlags {
  static const _storeKey = 'feature_store_enabled';

  /// true = show the physical-products shop. Listen to rebuild on change.
  static final ValueNotifier<bool> store = ValueNotifier<bool>(true);

  static bool get storeOn => store.value;

  static ApiClient? _api;
  static SharedPreferences? _prefs;
  static DateTime? _lastFetch;
  static _ResumeWatcher? _watcher;

  /// Call once at startup (after dependency injection).
  static void init(ApiClient api, SharedPreferences prefs) {
    _api = api;
    _prefs = prefs;
    store.value = prefs.getBool(_storeKey) ?? true;
    debugPrint('[FeatureFlags] init — cached store=${store.value}');
    _watcher ??= _ResumeWatcher(() => refresh());
    WidgetsBinding.instance.addObserver(_watcher!);
    unawaited(refresh(force: true));
  }

  /// Fetches the latest switches (at most every 20 seconds unless [force]).
  static Future<void> refresh({bool force = false}) async {
    final api = _api;
    if (api == null) return;
    final last = _lastFetch;
    if (!force && last != null && DateTime.now().difference(last) < const Duration(seconds: 20)) return;
    _lastFetch = DateTime.now();
    try {
      final res = await api.get('/features', parser: (d) => J.asMap(d));
      debugPrint('[FeatureFlags] GET /features → ${res.data}');
      final storeMap = J.asMap(res.data['store']);
      final on = storeMap['enabled'] != false;
      if (store.value != on) store.value = on;
      debugPrint('[FeatureFlags] store is now ${on ? 'ON' : 'OFF'}');
      await _prefs?.setBool(_storeKey, on);
    } catch (e) {
      // Offline or an older backend without /features: keep the last value.
      debugPrint('[FeatureFlags] GET /features FAILED → $e (keeping store=${store.value})');
    }
  }

  /// Screens of the physical-products shop. Order pages (buyers' and
  /// sellers') stay reachable so existing orders can be tracked and shipped.
  static bool isShopLocation(String location) {
    if (location == '/app/shop') return true;
    const prefixes = [
      '/app/shop/p/', // a physical product
      '/app/shop/cart',
      '/app/shop/checkout',
      '/app/store/shop-product-editor', // sellers adding products
    ];
    return prefixes.any(location.startsWith);
  }
}

class _ResumeWatcher with WidgetsBindingObserver {
  _ResumeWatcher(this.onResume);

  final VoidCallback onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}

/// Shows [child] only while the Fanitt Store is on (otherwise [otherwise]).
class StoreOnly extends StatelessWidget {
  const StoreOnly({super.key, required this.child, this.otherwise = const SizedBox.shrink()});

  final Widget child;
  final Widget otherwise;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: FeatureFlags.store,
      builder: (context, on, _) => on ? child : otherwise,
    );
  }
}