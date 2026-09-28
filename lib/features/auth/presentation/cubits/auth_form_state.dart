import 'package:equatable/equatable.dart';

import '../../domain/entities/app_user.dart';

enum AuthMethod { email, google }

/// Shared by the login and register forms, which each have two ways to
/// submit (email and Google) that show their own loading state.
class AuthFormState extends Equatable {
  const AuthFormState({this.loading, this.errorMessage, this.user, this.tick = 0});

  final AuthMethod? loading;
  final String? errorMessage;
  final AppUser? user;
  final int tick;

  bool get isBusy => loading != null;

  AuthFormState loadingWith(AuthMethod method) => AuthFormState(loading: method, tick: tick);

  AuthFormState failed(String message) => AuthFormState(errorMessage: message, tick: tick + 1);

  AuthFormState succeeded(AppUser user) => AuthFormState(user: user, tick: tick);

  AuthFormState idle() => AuthFormState(tick: tick);

  @override
  List<Object?> get props => [loading, errorMessage, user, tick];
}
