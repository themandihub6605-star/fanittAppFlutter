import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_routes.dart';

/// Back never closes the app from an inner screen.
///
/// Whatever screen you're on, Back first goes back normally. When there's
/// nothing left to go back to (a screen opened from a notification, a link,
/// or anything else that left it alone on the stack), Back takes you to your
/// Home instead of closing the app. Only Home (and the sign-in screens)
/// close the app.
///
/// Two parts, both wired in `app.dart`:
/// * [HomeFirstBack.config] — the router config with a back-button
///   dispatcher that goes Home instead of exiting.
/// * [HomeFirstBackScope] — tells Android (predictive back) that the app
///   still handles Back while you're not on Home, so the system doesn't
///   close the app on its own.
abstract final class HomeFirstBack {
  /// Places where Back is allowed to close the app.
  static const Set<String> _exitPaths = {
    AppRoutes.creatorHome,
    AppRoutes.brandHome,
    AppRoutes.fanHome,
    AppRoutes.agencyHome,
    AppRoutes.splash,
    AppRoutes.onboarding,
    AppRoutes.welcome,
    AppRoutes.chooseRole,
    AppRoutes.verification,
  };

  static String _path(GoRouter router) {
    try {
      return router.routerDelegate.currentConfiguration.uri.path;
    } catch (_) {
      return AppRoutes.splash;
    }
  }

  static bool canExitAt(GoRouter router) => _exitPaths.contains(_path(router));

  /// Use instead of passing the router straight to `MaterialApp.router`.
  static RouterConfig<Object> config(GoRouter router) => RouterConfig<Object>(
    routerDelegate: router.routerDelegate,
    routeInformationParser: router.routeInformationParser,
    routeInformationProvider: router.routeInformationProvider,
    backButtonDispatcher: _HomeFirstBackDispatcher(router),
  );

  /// Nothing left to pop: go Home (the splash redirect picks the right Home
  /// for the role). Returns false only where the app may close.
  static bool _goHome(GoRouter router) {
    if (canExitAt(router)) return false;
    router.go(AppRoutes.splash);
    return true;
  }
}

class _HomeFirstBackDispatcher extends RootBackButtonDispatcher {
  _HomeFirstBackDispatcher(this._router);

  final GoRouter _router;

  @override
  Future<bool> didPopRoute() async {
    // Normal back first (pop a screen, switch to the first tab, close a sheet…).
    if (await super.didPopRoute()) return true;
    return HomeFirstBack._goHome(_router);
  }
}

/// Put around the app (MaterialApp.router `builder`). While you're not on
/// Home, it keeps Android from closing the app on Back.
class HomeFirstBackScope extends StatelessWidget {
  const HomeFirstBackScope({super.key, required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<NavigationNotification>(
      onNotification: (notification) {
        if (notification.canHandlePop || HomeFirstBack.canExitAt(router)) return false;
        // Not on Home yet: the app still handles Back (it goes Home).
        const NavigationNotification(canHandlePop: true).dispatch(context);
        return true;
      },
      child: child,
    );
  }
}