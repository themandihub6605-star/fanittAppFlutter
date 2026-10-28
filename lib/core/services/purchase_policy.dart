// File: lib/core/services/purchase_policy.dart
import 'package:flutter/foundation.dart';

/// Apple doesn't allow digital things (plans, paid communities, digital
/// products, live tickets, paid live sessions, FanBox) to be bought in an
/// iPhone app without Apple's own In-App Purchase. So on iPhone the app hides
/// those buy buttons — people buy on fanitt.com and it unlocks in the app.
///
/// Android and everything physical / 1:1 (shop products, paid calls,
/// campaigns) work the same everywhere.
///
/// Important: on iPhone never show a price-to-pay, a "buy on the website"
/// message or a link to the website for these — Apple rejects that too.
abstract final class PurchasePolicy {
  /// false on iPhone / iPad.
  static bool get canBuyDigital => kIsWeb || defaultTargetPlatform != TargetPlatform.iOS;
}