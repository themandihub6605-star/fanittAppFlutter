import 'package:dio/dio.dart';

/// Every failed request surfaces as an [ApiException] with a message that is
/// safe to show to the user. [errorCode] mirrors the backend's stable codes
/// (e.g. PROPOSAL_QUOTA_EXCEEDED) for flows that need to branch on them.
class ApiException implements Exception {
  const ApiException(
      this.message, {
        this.statusCode,
        this.errorCode,
        this.errors = const [],
      });

  factory ApiException.fromDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const ApiException.network('The connection timed out. Check your internet and try again.');
      case DioExceptionType.connectionError:
        return const ApiException.network('No internet connection. Check your network and try again.');
      case DioExceptionType.cancel:
        return const ApiException('The request was cancelled.');
      case DioExceptionType.badCertificate:
        return const ApiException('A secure connection could not be established.');
      case DioExceptionType.badResponse:
        return _fromResponse(error.response);
      case DioExceptionType.unknown:
        if (error.error is ApiException) return error.error! as ApiException;
        return const ApiException.network('Something went wrong. Please try again.');
    // Newer Dio versions add types (e.g. transformTimeout); treat them
    // as timeouts so the app works on any Dio 5.x.
    // ignore: unreachable_switch_default
      default:
        return const ApiException.network('The connection timed out. Check your internet and try again.');
    }
  }

  const factory ApiException.network(String message) = _NetworkApiException;

  static ApiException _fromResponse(Response<dynamic>? response) {
    final status = response?.statusCode;
    final body = response?.data;

    if (body is Map<String, dynamic>) {
      final message = _text(body['message']);
      return ApiException(
        message ?? _fallbackFor(status),
        statusCode: status,
        errorCode: _text(body['errorCode']),
        errors: _textList(body['errors']),
      );
    }
    return ApiException(_fallbackFor(status), statusCode: status);
  }

  /// Non-empty string, or null for anything else (null, [], numbers, maps).
  static String? _text(Object? value) => value is String && value.trim().isNotEmpty ? value.trim() : null;

  /// Accepts a list of anything, or a single string; ignores other shapes.
  static List<String> _textList(Object? value) {
    if (value is String && value.trim().isNotEmpty) return [value.trim()];
    if (value is! List) return const [];
    return value.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList(growable: false);
  }


  static String _fallbackFor(int? status) => switch (status) {
    400 => 'Please check the details and try again.',
    401 => 'Your session has expired. Please log in again.',
    403 => "You don't have access to this.",
    404 => 'We couldn’t find what you were looking for.',
    409 => 'This already exists.',
    429 => 'Too many attempts. Please wait a few minutes and try again.',
    _ => 'Something went wrong on our side. Please try again.',
  };

  final String message;
  final int? statusCode;
  final String? errorCode;
  final List<String> errors;

  bool get isNetwork => false;
  bool get isUnauthorized => statusCode == 401;

  /// Backend validation errors arrive as "field: message" — show the first
  /// field message instead of the generic "Validation failed".
  String get displayMessage {
    if (errors.isNotEmpty && message == 'Validation failed') {
      final first = errors.first;
      final index = first.indexOf(': ');
      return index == -1 ? first : first.substring(index + 2);
    }
    return message;
  }

  @override
  String toString() => 'ApiException($statusCode, $errorCode): $message';
}

class _NetworkApiException extends ApiException {
  const _NetworkApiException(super.message);

  @override
  bool get isNetwork => true;
}