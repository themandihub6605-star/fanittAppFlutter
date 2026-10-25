// File: lib/core/network/integrity_interceptor.dart
import 'package:dio/dio.dart';

import '../services/play_integrity.dart';

/// Adds the Play Integrity token (header `X-Integrity-Token`) to sensitive
/// requests — the same list the backend checks
/// (src/middlewares/playIntegrity.middleware.js).
class IntegrityInterceptor extends Interceptor {
  static final _sensitive = <RegExp>[
    RegExp(r'^/?auth/(login|register|google)$'),
    RegExp(r'^/?payments(/|$)'),
    RegExp(r'^/?subscriptions/checkout'),
    RegExp(r'^/?wallet/withdraw'),
    RegExp(r'^/?(milestones|campaigns)/[^/]+/(fund|escrow|verify)'),
    RegExp(r'^/?(donations|bookings)(/|$)'),
    RegExp(r'^/?store/.*/checkout(/|$)'),
    RegExp(r'^/?store/shop/checkout'),
    RegExp(r'^/?store/stores/[^/]+/calls$'),
    RegExp(r'^/?store/lives/[^/]+/(checkout|join)$'),
    RegExp(r'^/?store/fanbox$'),
  ];

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (PlayIntegrity.enabled && options.method != 'GET') {
      final path = options.path.split('?').first;
      if (_sensitive.any((re) => re.hasMatch(path))) {
        final token = await PlayIntegrity.token();
        if (token != null) options.headers['X-Integrity-Token'] = token;
      }
    }
    handler.next(options);
  }
}