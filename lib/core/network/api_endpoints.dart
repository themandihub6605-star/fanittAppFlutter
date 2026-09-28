/// Paths relative to [AppConfig.apiBaseUrl] (which already ends in /api).
abstract final class ApiEndpoints {
  // Auth
  static const String login = '/auth/login';
  static const String register = '/auth/register';
  static const String google = '/auth/google';
  static const String refresh = '/auth/refresh';
  static const String logout = '/auth/logout';
  static const String me = '/auth/me';
  static const String forgotPassword = '/auth/forgot-password';
  static const String resetPassword = '/auth/reset-password';
  static const String upgradeRole = '/auth/upgrade-role';
  static const String completeOnboarding = '/auth/complete-onboarding';
}
