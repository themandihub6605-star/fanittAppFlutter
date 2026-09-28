/// Build-time configuration. Values can still be overridden with --dart-define, e.g.
/// flutter run --dart-define=API_BASE_URL=http://10.146.186.235:5000/api
abstract final class AppConfig {
  /// Live backend on the VPS (nginx → pm2 fanitt-api).
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
   // defaultValue: 'http://10.56.97.235:5000/api',   // local testing
     defaultValue: 'https://api.fanitt.com/api',  // live — switch back before building for Play Store
  );

  /// Razorpay public key id (rzp_live_… / rzp_test_…). Safe to ship in the app.
  static const String razorpayKeyId = String.fromEnvironment(
    'RAZORPAY_KEY_ID',
    defaultValue: 'rzp_live_TWGZOWs5hQ1iac',
  );

  /// Socket.IO lives on the API host without the /api suffix.
  static String get socketUrl => apiBaseUrl.replaceFirst(RegExp(r'/api/?$'), '');

  /// Public contact details (match the Privacy Policy).
  static const String supportEmail = 'info@fanitt.com';
  static const String supportPhone = '+91 92014 69274';

  static const Duration connectTimeout = Duration(seconds: 20);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration sendTimeout = Duration(seconds: 60);
}