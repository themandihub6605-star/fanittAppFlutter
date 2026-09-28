import 'package:dio/dio.dart';

import '../storage/token_storage.dart';
import 'api_endpoints.dart';
import 'session_events.dart';

/// Attaches the access token and transparently refreshes it on a 401.
///
/// Runs as a [QueuedInterceptor], so parallel requests that fail with 401
/// wait for a single refresh instead of each refreshing on their own.
/// Retries go through [_plainDio] (no interceptors) to avoid re-entering
/// this queue.
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({
    required TokenStorage storage,
    required Dio plainDio,
    required SessionEvents sessionEvents,
  })  : _storage = storage,
        _plainDio = plainDio,
        _sessionEvents = sessionEvents;

  final TokenStorage _storage;
  final Dio _plainDio;
  final SessionEvents _sessionEvents;

  static const skipAuthKey = 'skipAuth';
  static const _retriedKey = 'retried';

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.extra[skipAuthKey] != true) {
      final token = await _storage.accessToken;
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    final isUnauthorized = err.response?.statusCode == 401;

    if (!isUnauthorized || options.extra[skipAuthKey] == true || options.extra[_retriedKey] == true) {
      return handler.next(err);
    }

    // Another queued request may already have refreshed the token.
    final currentToken = await _storage.accessToken;
    final sentToken = (options.headers['Authorization'] as String?)?.replaceFirst('Bearer ', '');
    if (currentToken != null && currentToken != sentToken) {
      return _retry(options, currentToken, handler, err);
    }

    final refreshToken = await _storage.refreshToken;
    if (refreshToken == null) {
      await _expireSession();
      return handler.next(err);
    }

    try {
      final response = await _plainDio.post<Map<String, dynamic>>(
        ApiEndpoints.refresh,
        data: {'refreshToken': refreshToken},
      );
      final data = response.data?['data'] as Map<String, dynamic>?;
      final newAccess = data?['accessToken'] as String?;
      if (newAccess == null) throw StateError('Refresh response had no access token');

      await _storage.save(
        accessToken: newAccess,
        refreshToken: data?['refreshToken'] as String?,
      );
      return _retry(options, newAccess, handler, err);
    } catch (_) {
      await _expireSession();
      return handler.next(err);
    }
  }

  Future<void> _retry(
    RequestOptions options,
    String token,
    ErrorInterceptorHandler handler,
    DioException original,
  ) async {
    options.headers['Authorization'] = 'Bearer $token';
    options.extra[_retriedKey] = true;
    try {
      final response = await _plainDio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    } catch (_) {
      handler.next(original);
    }
  }

  Future<void> _expireSession() async {
    await _storage.clear();
    _sessionEvents.notifyExpired();
  }
}
