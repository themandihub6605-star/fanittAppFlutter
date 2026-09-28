import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Page transitions used across the app.
abstract final class AppPages {
  /// Root-level swaps (splash → welcome → app). Nothing to go back to.
  static Page<void> fade(GoRouterState state, Widget child) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      name: state.name,
      child: child,
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  /// Screens pushed on top of another. Uses the native Cupertino page on
  /// iOS so the edge swipe-back gesture keeps working.
  static Page<void> push(GoRouterState state, Widget child) {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return CupertinoPage<void>(key: state.pageKey, name: state.name, child: child);
    }
    return CustomTransitionPage<void>(
      key: state.pageKey,
      name: state.name,
      child: child,
      transitionDuration: const Duration(milliseconds: 340),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final enter = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        final exit = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween(begin: const Offset(0.08, 0), end: Offset.zero).animate(enter),
          child: FadeTransition(
            opacity: enter,
            child: SlideTransition(
              position: Tween(begin: Offset.zero, end: const Offset(-0.04, 0)).animate(exit),
              child: child,
            ),
          ),
        );
      },
    );
  }

  /// Tab roots inside a shell — the shell handles the switch.
  static Page<void> tab(GoRouterState state, Widget child) {
    return NoTransitionPage<void>(key: state.pageKey, name: state.name, child: child);
  }
}
