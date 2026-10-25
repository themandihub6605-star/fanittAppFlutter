import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../di/injection.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_palette.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_button.dart';
import '../widgets/app_sheet.dart';

/// "Rate Fanitt on Google Play".
///
/// * On Home (any role), after the app has been opened a few times, a small
///   sheet asks the user to rate Fanitt on Google Play.
/// * "Rate on Google Play" opens Google's own rating popup inside the app
///   (stars + review go straight to Google Play / Play Console). After that
///   we never ask again.
/// * "Not now" or closing the sheet → ask again after 7 days.
///
/// Google's rules: the stars and the review are only ever chosen by the user
/// in Google's popup (the app can't fill them in), we don't ask how they
/// like the app first, and everyone gets the same button whatever they think.
/// Google also decides if its popup appears — when it can't, the Play Store
/// page opens instead.
abstract final class AppRating {
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
      await _ask(context);
    } catch (e) {
      debugPrint('[AppRating] $e');
    }
  }

  /// "Rate Fanitt" from the Account screen — straight to Google's popup.
  static Future<void> rateNow() async {
    await _prefs.setBool(_doneKey, true);
    await _openGoogle();
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

  static Future<void> _openGoogle() async {
    final review = InAppReview.instance;
    try {
      if (await review.isAvailable()) {
        await review.requestReview();
      } else {
        await review.openStoreListing();
      }
    } catch (_) {
      try {
        await review.openStoreListing();
      } catch (e) {
        debugPrint('[AppRating] could not open Play Store: $e');
      }
    }
  }
}

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
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]),
                boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8))],
              ),
              child: const Icon(AppIcons.starFilled, color: Colors.white, size: 34),
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
            Text('Rate Fanitt on Google Play', textAlign: TextAlign.center, style: context.text.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Your rating helps more creators, brands and fans find Fanitt. It only takes a few seconds.',
              textAlign: TextAlign.center,
              style: context.text.bodyMedium?.copyWith(color: palette.textSecondary, height: 1.45),
            ),
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: 'Rate on Google Play',
              icon: AppIcons.starFilled,
              onPressed: () {
                HapticFeedback.selectionClick();
                Navigator.of(context).pop(true);
              },
            ),
            const SizedBox(height: AppSpacing.xs),
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Not now')),
          ],
        ),
      ),
    );
  }
}