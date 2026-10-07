import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../storage/token_storage.dart';
import 'api_exception.dart';
import 'auth_interceptor.dart';
import 'session_events.dart';

typedef JsonParser<T> = T Function(dynamic data);

/// The backend wraps every success in `{ success, message, data }`.
class ApiResponse<T> {
  const ApiResponse(this.data, this.message);

  final T data;
  final String message;
}

class ApiClient {
  ApiClient({required TokenStorage storage, required SessionEvents sessionEvents}) {
    final options = BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      sendTimeout: AppConfig.sendTimeout,
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
      headers: const {'Accept': 'application/json'},
    );

    _dio = Dio(options);
    final plainDio = Dio(options);

    _dio.interceptors.add(
      AuthInterceptor(storage: storage, plainDio: plainDio, sessionEvents: sessionEvents),
    );
    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(requestBody: true, responseBody: true, logPrint: (object) => debugPrint(object.toString())));
    }
  }

  late final Dio _dio;

  Future<ApiResponse<T>> get<T>(
      String path, {
        Map<String, dynamic>? query,
        required JsonParser<T> parser,
        CancelToken? cancelToken,
      }) {
    return _send(
          () => _dio.get<dynamic>(path, queryParameters: query, cancelToken: cancelToken),
      parser,
    );
  }

  Future<ApiResponse<T>> post<T>(
      String path, {
        Object? data,
        required JsonParser<T> parser,
        bool skipAuth = false,
        ProgressCallback? onSendProgress,
      }) {
    return _send(
          () => _dio.post<dynamic>(
        path,
        data: data,
        options: Options(extra: {AuthInterceptor.skipAuthKey: skipAuth}),
        onSendProgress: onSendProgress,
      ),
      parser,
    );
  }

  Future<ApiResponse<T>> patch<T>(
      String path, {
        Object? data,
        required JsonParser<T> parser,
        ProgressCallback? onSendProgress,
      }) {
    return _send(
          () => _dio.patch<dynamic>(path, data: data, onSendProgress: onSendProgress),
      parser,
    );
  }

  Future<ApiResponse<T>> put<T>(String path, {Object? data, required JsonParser<T> parser}) {
    return _send(() => _dio.put<dynamic>(path, data: data), parser);
  }

  Future<ApiResponse<T>> delete<T>(String path, {Object? data, required JsonParser<T> parser}) {
    return _send(() => _dio.delete<dynamic>(path, data: data), parser);
  }

  Future<ApiResponse<T>> _send<T>(
      Future<Response<dynamic>> Function() request,
      JsonParser<T> parser,
      ) async {
    try {
      final response = await request();
      final body = response.data;
      if (body is Map<String, dynamic>) {
        return ApiResponse(parser(body['data']), body['message'] as String? ?? '');
      }
      return ApiResponse(parser(body), '');
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    } on ApiException {
      rethrow;
    } catch (error, stack) {
      debugPrint('ApiClient parse error: $error\n$stack');
      throw const ApiException('We received an unexpected response. Please try again.');
    }
  }
}