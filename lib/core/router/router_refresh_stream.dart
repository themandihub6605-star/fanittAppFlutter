import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Re-runs GoRouter redirects whenever the given stream emits.
///
/// Notifications are held until the current frame has finished and several
/// quick emits (e.g. login → profile refresh right after) become ONE redirect.
/// Re-running redirects in the middle of a frame, while the bottom-bar shell
/// was still being built, made Flutter mount the shell twice and crash with
/// "Duplicate GlobalKey … StatefulNavigationShellState".
class RouterRefreshStream extends ChangeNotifier {
  RouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.asBroadcastStream().listen((_) => _schedule());
  }

  late final StreamSubscription<dynamic> _subscription;
  bool _scheduled = false;
  bool _disposed = false;

  void _schedule() {
    if (_scheduled || _disposed) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!_disposed) notifyListeners();
    });
    // Make sure a frame comes even if nothing else is drawing.
    SchedulerBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription.cancel();
    super.dispose();
  }
}