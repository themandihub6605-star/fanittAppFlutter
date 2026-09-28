part of 'auth_bloc.dart';

sealed class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

/// Session not checked yet — the splash screen is showing.
final class AuthUnknown extends AuthState {
  const AuthUnknown();
}

/// A saved session exists but the server couldn't be reached to confirm it.
final class AuthUnreachable extends AuthState {
  const AuthUnreachable(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

final class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.user);

  final AppUser user;

  @override
  List<Object?> get props => [user];
}

final class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated({this.sessionExpired = false});

  final bool sessionExpired;

  @override
  List<Object?> get props => [sessionExpired];
}
