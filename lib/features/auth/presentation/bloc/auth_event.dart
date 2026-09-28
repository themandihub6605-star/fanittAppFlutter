part of 'auth_bloc.dart';

sealed class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

/// App launch (and "Try again" when the server was unreachable).
final class AuthStarted extends AuthEvent {
  const AuthStarted();
}

final class AuthLoggedIn extends AuthEvent {
  const AuthLoggedIn(this.user);

  final AppUser user;

  @override
  List<Object?> get props => [user];
}

/// The current user's data changed (role upgrade, status check, profile edit).
final class AuthUserUpdated extends AuthEvent {
  const AuthUserUpdated(this.user);

  final AppUser user;

  @override
  List<Object?> get props => [user];
}

/// Re-fetches the user quietly (wallet balance, avatar, verification).
final class AuthRefreshRequested extends AuthEvent {
  const AuthRefreshRequested();
}

final class AuthLogoutRequested extends AuthEvent {
  const AuthLogoutRequested();
}

final class _AuthSessionExpired extends AuthEvent {
  const _AuthSessionExpired();
}
