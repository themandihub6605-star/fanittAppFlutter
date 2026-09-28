import 'package:shared_preferences/shared_preferences.dart';

import '../di/injection.dart';

/// Remembers whether the intro screens were shown on this install.
abstract final class OnboardingStore {
  static const _key = 'fanitt.onboardingSeen';

  static SharedPreferences get _prefs => sl<SharedPreferences>();

  static bool get seen => _prefs.getBool(_key) ?? false;

  static Future<void> markSeen() => _prefs.setBool(_key, true);
}