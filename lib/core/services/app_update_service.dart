import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'link_opener.dart';

/// Checks Google Play for a newer build and installs it in-app.
///
/// Works for anyone who installed Fanitt from Play — production and the
/// closed/internal testing tracks. Debug builds and APKs installed by hand
/// aren't Play installs, so no update is ever reported for them.
class AppUpdateService with WidgetsBindingObserver {
  AppUpdateService() {
    WidgetsBinding.instance.addObserver(this);
  }

  /// True while a newer version is waiting on Play.
  final ValueNotifier<bool> updateAvailable = ValueNotifier<bool>(false);

  /// The user tapped "Later" — hide the banner until the app restarts.
  final ValueNotifier<bool> dismissed = ValueNotifier<bool>(false);

  AppUpdateInfo? _info;
  DateTime? _lastCheck;
  bool _checking = false;

  static const _minInterval = Duration(minutes: 30);

  bool get _supported => !kIsWeb && Platform.isAndroid && !kDebugMode;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check when the user comes back to the app.
    if (state == AppLifecycleState.resumed) check();
  }

  Future<void> check({bool force = false}) async {
    if (!_supported || _checking) return;
    final last = _lastCheck;
    if (!force && last != null && DateTime.now().difference(last) < _minInterval) return;
    _checking = true;
    try {
      final info = await InAppUpdate.checkForUpdate();
      _info = info;
      _lastCheck = DateTime.now();
      updateAvailable.value = info.updateAvailability == UpdateAvailability.updateAvailable ||
          info.installStatus == InstallStatus.downloaded;
    } catch (error) {
      // Not installed from Play, no Play Store, offline… nothing to show.
      debugPrint('Update check skipped: $error');
      updateAvailable.value = false;
    } finally {
      _checking = false;
    }
  }

  /// Starts the Play update. Falls back to the store page if Play can't
  /// update in-app.
  Future<void> update() async {
    try {
      final info = _info;
      if (info != null && info.installStatus == InstallStatus.downloaded) {
        await InAppUpdate.completeFlexibleUpdate();
        return;
      }
      if (info != null && info.immediateUpdateAllowed) {
        // Full-screen Play update; the app restarts on the new version.
        final result = await InAppUpdate.performImmediateUpdate();
        if (result == AppUpdateResult.success) updateAvailable.value = false;
        return;
      }
      if (info != null && info.flexibleUpdateAllowed) {
        final result = await InAppUpdate.startFlexibleUpdate();
        if (result == AppUpdateResult.success) await InAppUpdate.completeFlexibleUpdate();
        return;
      }
    } catch (error) {
      debugPrint('In-app update failed: $error');
    }
    await openStore();
  }

  Future<void> openStore() async {
    final package = (await PackageInfo.fromPlatform()).packageName;
    await LinkOpener.open('https://play.google.com/store/apps/details?id=$package');
  }

  void dismiss() => dismissed.value = true;
}