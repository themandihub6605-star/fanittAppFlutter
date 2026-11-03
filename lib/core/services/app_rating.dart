// File: lib/core/services/app_rating.dart
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../di/injection.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_palette.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_button.dart';
import '../widgets/app_sheet.dart';
import 'link_opener.dart';

/// "Rate Fanitt on Google Play".
///
/// * On Home (any role), after the app has been opened a few times, a small
///   sheet asks the user to rate Fanitt.
/// * "Rate on Google Play" (and "Rate Fanitt" in Settings & more) first try
///   Google's **in-app review popup** (stars + review without leaving the
///   app). Google shows that popup only a few times per user and never says
///   if it appeared, so we watch whether the app was covered by it; if not,
///   Fanitt's **Play Store page** opens instead.
///
/// Note: on the Play Store page Google hides "Write a review" for accounts
/// that are testers of the app or have already reviewed it (they see their
/// old review instead) — that's Play's rule, not the app's.
abstract final class AppRating {
  /// The store the app came from — iPhone must never say "Google Play".
  static String get storeName => Platform.isIOS ? 'the App Store' : 'Google Play';

  /// iPhone: the app's App Store ID (the number in its App Store link, e.g.
  /// apps.apple.com/app/id1234567890 → '1234567890'). Empty until the app is
  /// live on the App Store — till then iPhone has no "Rate Fanitt" button.
  static const String appStoreId = '';

  /// False on iPhone until [appStoreId] is set (the store page doesn't exist yet).
  static bool get canOpenStore => !Platform.isIOS || appStoreId.isNotEmpty;

  static const _doneKey = 'app_rating_done';
  static const _nextKey = 'app_rating_next_at';
  static const _opensKey = 'app_rating_opens';

  /// Ask only after this many app opens.
  static const _minOpens = 3;

  /// "Not now" / closed → ask again after this long.
  static const _snooze = Duration(days: 7);

  static bool _countedThisRun = false;
  static bool _showing = false;

  static SharedPreferences get _prefs => sl<SharedPreferences>();

  /// Call when Home is on screen. Shows the sheet at most once per app run,
  /// and only when it's due.
  static Future<void> maybeAsk(BuildContext context) async {
    try {
      final prefs = _prefs;
      if (!_countedThisRun) {
        _countedThisRun = true;
        await prefs.setInt(_opensKey, (prefs.getInt(_opensKey) ?? 0) + 1);
      } else {
        return; // already handled this run
      }
      if (prefs.getBool(_doneKey) ?? false) return;
      if ((prefs.getInt(_opensKey) ?? 0) < _minOpens) return;
      final next = prefs.getInt(_nextKey);
      if (next != null && DateTime.now().millisecondsSinceEpoch < next) return;
      // Let Home settle first.
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!context.mounted || _showing) return;
      if (Platform.isIOS) {
        // Apple allows only its own review popup (no custom sheet before it).
        // iOS itself decides whether to show it (max 3 times a year).
        await prefs.setInt(_nextKey, DateTime.now().add(_snooze).millisecondsSinceEpoch);
        await _tryInAppPopup();
        return;
      }
      await _ask(context);
    } catch (e) {
      debugPrint('[AppRating] $e');
    }
  }

  /// "Rate Fanitt" — in-app popup first, the Play Store page if it didn't show.
  static Future<void> rateNow() async {
    HapticFeedback.selectionClick();
    try {
      await _prefs.setBool(_doneKey, true);
    } catch (_) {}
    if (Platform.isIOS) {
      // App Store page (with "Write a review") once the app is live;
      // before that only Apple's own popup — never a blank store page.
      if (appStoreId.isNotEmpty) {
        try {
          await InAppReview.instance.openStoreListing(appStoreId: appStoreId);
          return;
        } catch (e) {
          debugPrint('[AppRating] App Store page did not open: $e');
        }
      }
      await _tryInAppPopup();
      return;
    }
    if (await _tryInAppPopup()) return;
    await _openStorePage();
  }

  /// Google's review popup. True when it actually appeared (the popup covers
  /// the app, which makes the app inactive for a moment).
  static Future<bool> _tryInAppPopup() async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    final review = InAppReview.instance;
    try {
      if (!await review.isAvailable()) return false;
    } catch (_) {
      return false;
    }
    var covered = false;
    final listener = AppLifecycleListener(onInactive: () => covered = true, onHide: () => covered = true, onPause: () => covered = true);
    try {
      await review.requestReview();
      // The popup may take a moment to come up.
      await Future<void>.delayed(const Duration(milliseconds: 1600));
    } catch (e) {
      debugPrint('[AppRating] in-app review failed: $e');
    } finally {
      listener.dispose();
    }
    return covered;
  }

  static Future<void> _ask(BuildContext context) async {
    _showing = true;
    final rated = await showAppSheet<bool>(context, builder: (sheet) => const _RateSheet());
    _showing = false;
    if (rated == true) {
      await rateNow();
    } else {
      // "Not now" or closed → again in 7 days.
      await _prefs.setInt(_nextKey, DateTime.now().add(_snooze).millisecondsSinceEpoch);
    }
  }

  /// Play Store app first; if that can't open, the Play Store website.
  static Future<void> _openStorePage() async {
    try {
      await InAppReview.instance.openStoreListing();
      return;
    } catch (e) {
      debugPrint('[AppRating] store app did not open: $e');
    }
    try {
      final info = await PackageInfo.fromPlatform();
      final url = Platform.isIOS
          ? 'https://apps.apple.com/app/id$appStoreId'
          : 'https://play.google.com/store/apps/details?id=${info.packageName}';
      await LinkOpener.open(url);
    } catch (e) {
      debugPrint('[AppRating] could not open the store page: $e');
    }
  }
}

/// Calm white sheet: star badge, five stars, one orange button.
class _RateSheet extends StatelessWidget {
  const _RateSheet();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(22)),
              child: const Icon(AppIcons.starFilled, color: Color(0xFFFFB400), size: 34),
            ),
            const SizedBox(height: AppSpacing.md),
            // Five stars — just a picture, the user picks theirs on Google Play.
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 5; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(AppIcons.starFilled, size: 22, color: const Color(0xFFFFB400).withValues(alpha: 0.9)),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(Platform.isIOS ? 'Rate Fanitt on the App Store' : 'Rate Fanitt on Google Play', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.4, color: palette.textPrimary)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Your rating helps more creators, brands and fans find Fanitt. It only takes a few seconds.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.45, color: palette.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: Platform.isIOS ? 'Rate on the App Store' : 'Rate on Google Play',
              icon: AppIcons.starFilled,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: AppSpacing.xs),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(foregroundColor: palette.textSecondary),
              child: const Text('Not now', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}