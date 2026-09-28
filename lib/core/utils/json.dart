/// Defensive readers for backend JSON. Mongo refs arrive either as an id
/// string or as a populated object, so [refId] handles both.
abstract final class J {
  static String id(Map<String, dynamic> json) => (json['_id'] ?? json['id'] ?? '').toString();

  static String str(Map<String, dynamic> json, String key, [String fallback = '']) {
    final value = json[key];
    if (value == null) return fallback;
    return value is String ? value : value.toString();
  }

  static String? strOrNull(Map<String, dynamic> json, String key) {
    final value = json[key];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  static int integer(Map<String, dynamic> json, String key, [int fallback = 0]) {
    final value = json[key];
    return value is num ? value.toInt() : fallback;
  }

  static int? integerOrNull(Map<String, dynamic> json, String key) {
    final value = json[key];
    return value is num ? value.toInt() : null;
  }

  static double dbl(Map<String, dynamic> json, String key, [double fallback = 0]) {
    final value = json[key];
    return value is num ? value.toDouble() : fallback;
  }

  static bool boolean(Map<String, dynamic> json, String key, [bool fallback = false]) {
    final value = json[key];
    return value is bool ? value : fallback;
  }

  static DateTime? date(Map<String, dynamic> json, String key) {
    final value = json[key];
    return value is String ? DateTime.tryParse(value)?.toLocal() : null;
  }

  static List<String> strings(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! List) return const [];
    return value.whereType<String>().where((s) => s.trim().isNotEmpty).toList(growable: false);
  }

  static Map<String, dynamic>? map(Map<String, dynamic> json, String key) {
    final value = json[key];
    return value is Map<String, dynamic> ? value : null;
  }

  static List<T> list<T>(Map<String, dynamic> json, String key, T Function(Map<String, dynamic>) parse) {
    final value = json[key];
    if (value is! List) return const [];
    return value.whereType<Map<String, dynamic>>().map(parse).toList(growable: false);
  }

  static List<T> listOf<T>(dynamic data, T Function(Map<String, dynamic>) parse) {
    if (data is! List) return const [];
    return data.whereType<Map<String, dynamic>>().map(parse).toList(growable: false);
  }

  static String? refId(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String) return value;
    if (value is Map<String, dynamic>) return value['_id']?.toString();
    return null;
  }

  static Map<String, dynamic> asMap(dynamic data) =>
      data is Map<String, dynamic> ? data : const <String, dynamic>{};
}
