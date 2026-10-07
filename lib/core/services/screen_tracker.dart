import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/api_client.dart';

/// Measures which screens people use and for how long, for the admin panel's
/// App Analytics page. Only screen names and times are sent — never content.
///
/// - Listens to the router: every route change closes the current screen
///   visit and opens a new one.
/// - App in background → the visit stops (time away isn't counted).
/// - Visits are queued and sent in batches every 30 s, when 40 are waiting,
///   or when the app goes to the background. Unsent ones survive restarts.
class ScreenTracker with WidgetsBindingObserver {
  ScreenTracker(this._api, this._prefs);

  final ApiClient _api;
  final SharedPreferences _prefs;

  static const _queueKey = 'analytics_queue_v1';
  static const _installKey = 'analytics_install_id';
  static const _sessionGap = Duration(minutes: 30); // away longer = new session
  static const _maxQueue = 1000;

  GoRouter? _router;
  Timer? _timer;
  bool _sending = false;

  String _installId = '';
  String _sessionId = '';
  String _appVersion = '';
  DateTime? _pausedAt;

  String? _screen; // current screen name
  DateTime? _since; // when the current visit started
  final List<Map<String, dynamic>> _queue = [];

  // ---------- setup ----------

  void attach(GoRouter router) {
    if (_router != null) return;
    _router = router;
    _installId = _prefs.getString(_installKey) ?? _newId();
    _prefs.setString(_installKey, _installId);
    _sessionId = _newId();
    _restoreQueue();
    PackageInfo.fromPlatform().then((info) => _appVersion = info.version).catchError((_) => _appVersion);

    router.routerDelegate.addListener(_onRouteChanged);
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => flush());
    // First screen after launch.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onRouteChanged());
  }

  void detach() {
    _router?.routerDelegate.removeListener(_onRouteChanged);
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _closeVisit();
    _saveQueue();
    _router = null;
  }

  // ---------- router + lifecycle ----------

  void _onRouteChanged() {
    final router = _router;
    if (router == null) return;
    final name = _screenName(router);
    if (name == _screen) return;
    _closeVisit();
    if (name != null) {
      _screen = name;
      _since = DateTime.now();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        final pausedAt = _pausedAt;
        if (pausedAt != null && DateTime.now().difference(pausedAt) > _sessionGap) {
          _sessionId = _newId();
        }
        _pausedAt = null;
        // Same screen, new visit (time in background isn't counted).
        if (_screen != null) _since = DateTime.now();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        if (_pausedAt != null) return;
        final current = _screen;
        _closeVisit();
        _pausedAt = DateTime.now();
        _screen = current; // keep the name so resume continues on it
        _saveQueue();
        flush();
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _closeVisit() {
    final screen = _screen;
    final since = _since;
    _screen = null;
    _since = null;
    if (screen == null || since == null || _pausedAt != null) return;
    final ms = DateTime.now().difference(since).inMilliseconds;
    if (ms < 300) return; // redirect hop
    _queue.add({'screen': screen, 'durationMs': ms, 'startedAt': since.millisecondsSinceEpoch});
    if (_queue.length > _maxQueue) _queue.removeRange(0, _queue.length - _maxQueue);
    if (_queue.length >= 40) flush();
  }

  // ---------- sending ----------

  Future<void> flush() async {
    if (_sending || _queue.isEmpty) return;
    _sending = true;
    final batch = List<Map<String, dynamic>>.from(_queue.take(200));
    try {
      await _api.post<void>(
        '/analytics/events',
        data: {
          'installId': _installId,
          'sessionId': _sessionId,
          'platform': defaultTargetPlatform.name,
          'appVersion': _appVersion,
          'events': batch,
        },
        parser: (_) {},
      );
      _queue.removeRange(0, batch.length);
      _saveQueue();
    } catch (error) {
      // Offline or server busy — keep them for the next try.
      if (kDebugMode) debugPrint('Analytics flush failed: $error');
    } finally {
      _sending = false;
    }
  }

  void _saveQueue() {
    _prefs.setString(_queueKey, jsonEncode(_queue)).ignore();
  }

  void _restoreQueue() {
    final raw = _prefs.getString(_queueKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw);
      if (list is List) {
        _queue.addAll(list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
      }
    } catch (_) {
      _prefs.remove(_queueKey).ignore();
    }
  }

  static String _newId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  // ---------- screen names ----------

  /// Route template of the top screen, e.g. "/app/campaigns/:id".
  static String? _template(GoRouter router) {
    final config = router.routerDelegate.currentConfiguration;
    if (config.isEmpty) return null;
    final last = config.last;
    if (last is ImperativeRouteMatch) return last.matches.fullPath;
    return config.fullPath;
  }

  static String? _screenName(GoRouter router) {
    final path = _template(router);
    if (path == null || path.isEmpty || path == '/' || path.startsWith('/open/')) return null;

    // Bottom tabs: "/creator/home" → "Home" (role is stored separately).
    final tab = RegExp(r'^/(creator|brand|fan|agency)/([a-z-]+)$').firstMatch(path);
    if (tab != null) return _tabNames[tab.group(2)] ?? _titleCase(tab.group(2)!);

    return _names[path] ?? _fallback(path);
  }

  static const _tabNames = {
    'home': 'Home',
    'feed': 'Feed',
    'campaigns': 'Campaigns',
    'messages': 'Messages',
    'account': 'Account',
    'creators': 'Find creators',
    'library': 'Library',
    'network': 'Agency network',
    'earnings': 'Agency earnings',
  };

  static const _names = {
    '/onboarding': 'Onboarding',
    '/welcome': 'Welcome',
    '/login': 'Login',
    '/register': 'Sign up',
    '/forgot-password': 'Forgot password',
    '/reset-password': 'Reset password',
    '/choose-role': 'Choose role',
    '/verification': 'Verification status',
    '/app/notifications': 'Notifications',
    '/app/plans': 'Plans',
    '/app/profile/edit': 'Edit profile',
    '/app/wallet': 'Wallet',
    '/app/transactions': 'Transactions',
    '/app/referrals': 'Refer & earn',
    '/app/posts': 'My posts',
    '/app/sessions': 'My sessions',
    '/app/campaign-editor': 'Campaign editor',
    '/app/campaigns/:id': 'Campaign detail',
    '/app/manage/:id': 'Manage campaign',
    '/app/chat/:id': 'Chat',
    '/app/creators/:slug': 'Creator profile',
    '/app/brands/:slug': 'Brand profile',
    '/app/brands': 'Brands',
    '/app/creators': 'Creators',
    '/app/communities': 'Communities',
    '/app/c/:slug': 'Community',
    '/app/c-post/:postId': 'Community post',
    '/app/community-form': 'Create community',
    '/app/community-chat': 'Community chat',
    '/app/community-members': 'Community members',
    '/app/feed': 'Feed',
    '/app/following': 'Following',
    '/app/gifts': 'Gifts',
    '/app/privacy-policy': 'Privacy policy',
    '/app/terms': 'Terms of use',
    '/legal/:slug': 'Legal page',
    '/app/complete-profile': 'Complete profile',
    '/app/store': 'My store',
    '/app/store/products': 'Store products',
    '/app/store/product-editor': 'Product editor',
    '/app/store/sales': 'Store sales',
    '/app/s/:slug': 'Store page',
    '/app/sp/:id': 'Product page',
    '/app/library': 'Library',
    '/app/stores': 'Stores',
    '/app/store/lives': 'My lives',
    '/app/store/lives/new': 'New live',
    '/app/store/calls': 'My calls',
    '/app/live/:id': 'Live detail',
    '/app/live-room': 'Live room',
    '/app/call/:id': 'Call',
    '/app/store/affiliate': 'Affiliate',
    '/app/store/fanbox': 'FanBox',
    '/app/store/analytics': 'Store analytics',
    '/app/meets': 'Live sessions',
    '/app/meet/:id': 'Meet detail',
    '/app/meet-room': 'Meet room',
    '/app/search': 'Search',
    '/app/saved': 'Saved posts',
    '/app/post/:id': 'Post detail',
    '/app/products': 'Marketplace',
  };

  /// Unknown route → readable name from its path ("/app/foo-bar/:id" → "Foo bar").
  static String _fallback(String path) {
    final parts = path.split('/').where((p) => p.isNotEmpty && p != 'app' && !p.startsWith(':')).toList();
    if (parts.isEmpty) return path;
    return _titleCase(parts.join(' '));
  }

  static String _titleCase(String s) {
    final t = s.replaceAll(RegExp(r'[-_]+'), ' ').trim();
    return t.isEmpty ? s : '${t[0].toUpperCase()}${t.substring(1)}';
  }
}