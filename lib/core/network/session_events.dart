import 'dart:async';

/// Lets the network layer tell the app that the session can no longer be
/// refreshed, without depending on the AuthBloc directly.
class SessionEvents {
  final StreamController<void> _expired = StreamController<void>.broadcast();

  Stream<void> get expired => _expired.stream;

  void notifyExpired() {
    if (!_expired.isClosed) _expired.add(null);
  }

  Future<void> dispose() => _expired.close();
}
