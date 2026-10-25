// File: lib/core/services/play_integrity.dart
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Google Play Integrity token for sensitive requests (login, payments,
/// withdrawals, calls…). The backend asks Google to check it — that's how
/// it knows a request comes from the real Fanitt app from Play Store, on a
/// genuine phone.
///
/// Needs the Google Cloud project NUMBER (Firebase console → Project
/// settings → General → "Project number"). Build with:
///   flutter build appbundle --release --dart-define=GCP_PROJECT_NUMBER=123456789012
/// Without it (or in debug builds) no token is sent and nothing breaks.
class PlayIntegrity {
  PlayIntegrity._();

  static const _channel = MethodChannel('fanitt/device_security');
  static const _projectNumber = String.fromEnvironment('GCP_PROJECT_NUMBER');

  /// Tokens are reused for a few minutes (Google limits how many we can ask for).
  static const _reuseFor = Duration(minutes: 4);

  static String? _token;
  static DateTime? _at;
  static Future<String?>? _inFlight;

  static bool get enabled => kReleaseMode && !kIsWeb && Platform.isAndroid && _projectNumber.isNotEmpty;

  /// A fresh-enough token, or null when not available (never throws).
  static Future<String?> token() {
    if (!enabled) return Future.value(null);
    final at = _at;
    if (_token != null && at != null && DateTime.now().difference(at) < _reuseFor) return Future.value(_token);
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  static Future<String?> _fetch() async {
    try {
      final t = await _channel
          .invokeMethod<String>('integrityToken', {'nonce': _nonce(), 'cloudProjectNumber': _projectNumber})
          .timeout(const Duration(seconds: 8));
      if (t != null && t.isNotEmpty) {
        _token = t;
        _at = DateTime.now();
      }
      return t;
    } catch (e) {
      debugPrint('[PlayIntegrity] token failed: $e');
      return null;
    }
  }

  /// Random, URL-safe base64, no padding (what the Play API expects).
  static String _nonce() {
    final r = Random.secure();
    final bytes = List<int>.generate(24, (_) => r.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}