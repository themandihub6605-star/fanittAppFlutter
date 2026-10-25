import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/injection.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_sheet.dart';
import 'store_models.dart';
import 'store_repository.dart';

/// Where the creator's Fanitt Store stands. Go live, paid calls, digital
/// products, FanBox, affiliate, sales and analytics live inside the store,
/// so they only open once the store is live.
enum StoreGate {
  /// Not checked yet.
  unknown,

  /// No store yet, or still being set up.
  none,

  /// Sent for review.
  pending,

  /// Admin asked for changes.
  rejected,

  /// Store suspended.
  suspended,

  /// Live — every store tool is open.
  active;

  bool get isOpen => this == StoreGate.active;

  /// Known and not live (unknown counts as "don't block yet").
  bool get blocks => this != StoreGate.active && this != StoreGate.unknown;

  static StoreGate fromMyStore(MyStore data) {
    final store = data.store;
    if (store == null) return StoreGate.none;
    return switch (store.status) {
      StoreStatus.active => StoreGate.active,
      StoreStatus.pendingReview => StoreGate.pending,
      StoreStatus.rejected => StoreGate.rejected,
      StoreStatus.suspended => StoreGate.suspended,
      StoreStatus.draft => StoreGate.none,
    };
  }
}

abstract final class StoreAccess {
  /// Listen to rebuild (e.g. the lock on home quick actions).
  static final ValueNotifier<StoreGate> gate = ValueNotifier<StoreGate>(StoreGate.unknown);

  static String _userId = '';
  static Future<StoreGate>? _inFlight;

  /// Store-tool screens: everything under /app/store/ (the /app/store page
  /// itself is the way in, so it always opens).
  static bool isToolLocation(String location) => location.startsWith('${AppRoutes.store}/');

  /// True when [userId]'s store is known and not live.
  static bool blocksFor(String userId) => userId.isNotEmpty && userId == _userId && gate.value.blocks;

  /// Loads the creator's store status (one request at a time).
  static Future<StoreGate> refresh(String userId) {
    if (userId.isEmpty) return Future.value(StoreGate.unknown);
    if (userId != _userId) {
      _userId = userId;
      gate.value = StoreGate.unknown;
    }
    return _inFlight ??= () async {
      try {
        final data = await sl<StoreRepository>().myStore();
        _set(userId, StoreGate.fromMyStore(data));
      } catch (_) {
        // Offline: keep what we knew.
      } finally {
        _inFlight = null;
      }
      return gate.value;
    }();
  }

  /// Store page loaded fresh data — keep everyone in sync (for the creator
  /// whose status we're tracking).
  static void apply(MyStore data) {
    final userId = _userId;
    if (userId.isEmpty) return;
    final next = StoreGate.fromMyStore(data);
    // Called from build: update after the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _set(userId, next));
  }

  static void _set(String userId, StoreGate next) {
    if (userId != _userId) _userId = userId;
    if (gate.value != next) gate.value = next;
  }

  /// Opens a store tool, or explains first that the store has to be live.
  /// Always re-checks before blocking, so a just-approved store opens.
  static Future<void> open(BuildContext context, String route, {required String userId}) async {
    var status = gate.value;
    if (!status.isOpen) status = await refresh(userId);
    if (!context.mounted) return;
    if (status.isOpen || status == StoreGate.unknown) {
      unawaited(context.push(route));
      return;
    }
    await showStoreRequiredSheet(context, status);
  }
}

/// "Open your Fanitt Store first" — explains why, with a button to the store.
Future<void> showStoreRequiredSheet(BuildContext context, StoreGate status) {
  final (title, message, button) = switch (status) {
    StoreGate.pending => (
    'Your store is under review',
    'Go live, paid calls, digital products, FanBox and affiliate links unlock as soon as your Fanitt Store is approved. We\'ll notify you.',
    'View store status',
    ),
    StoreGate.rejected => (
    'Your store needs a few changes',
    'Update your Fanitt Store details and send it again. These tools unlock once it\'s approved.',
    'Fix store details',
    ),
    StoreGate.suspended => (
    'Your store is suspended',
    'Store tools are paused while your Fanitt Store is suspended. Open your store to see why.',
    'View details',
    ),
    _ => (
    'Open your Fanitt Store first',
    'Go live, paid calls, digital products, FanBox and affiliate links all live inside your Fanitt Store. Set it up in a few steps to start earning.',
    'Open Fanitt Store',
    ),
  };
  return showAppSheet<void>(
    context,
    builder: (sheet) {
      final palette = sheet.palette;
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]),
                  boxShadow: [BoxShadow(color: const Color(0xFFF4511E).withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8))],
                ),
                child: Icon(status == StoreGate.pending ? AppIcons.hourglass : AppIcons.storeFilled, color: Colors.white, size: 30),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(title, textAlign: TextAlign.center, style: sheet.text.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(message, textAlign: TextAlign.center, style: sheet.text.bodyMedium?.copyWith(color: palette.textSecondary, height: 1.45)),
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: button,
                icon: AppIcons.storeFilled,
                onPressed: () {
                  Navigator.of(sheet).pop();
                  context.push(AppRoutes.store);
                },
              ),
              const SizedBox(height: AppSpacing.xs),
              TextButton(onPressed: () => Navigator.of(sheet).pop(), child: const Text('Not now')),
            ],
          ),
        ),
      );
    },
  );
}