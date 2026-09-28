import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/network/session_events.dart';
import '../../../../core/services/push_service.dart';
import '../../../../core/services/socket_service.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';

part 'auth_event.dart';
part 'auth_state.dart';

/// App-wide session state. The router listens to this to decide where the
/// user belongs.
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({
    required AuthRepository repository,
    required SessionEvents sessionEvents,
    SocketService? socket,
    PushService? push,
  })  : _repository = repository,
        _socket = socket,
        _push = push,
        super(const AuthUnknown()) {
    on<AuthStarted>(_onStarted);
    on<AuthLoggedIn>((event, emit) => emit(AuthAuthenticated(event.user)));
    on<AuthUserUpdated>(_onUserUpdated);
    on<AuthRefreshRequested>(_onRefreshRequested);
    on<AuthLogoutRequested>(_onLogoutRequested);
    on<_AuthSessionExpired>(_onSessionExpired);

    _expiredSubscription = sessionEvents.expired.listen((_) => add(const _AuthSessionExpired()));
  }

  final AuthRepository _repository;
  final SocketService? _socket;
  final PushService? _push;
  late final StreamSubscription<void> _expiredSubscription;

  static const _minimumSplash = Duration(milliseconds: 2100);

  Future<void> _onStarted(AuthStarted event, Emitter<AuthState> emit) async {
    emit(const AuthUnknown());
    try {
      final results = await Future.wait<Object?>([
        _repository.restoreSession(),
        Future<void>.delayed(_minimumSplash),
      ]);
      final user = results.first as AppUser?;
      emit(user == null ? const AuthUnauthenticated() : AuthAuthenticated(user));
    } on ApiException catch (error) {
      emit(AuthUnreachable(error.displayMessage));
    }
  }

  void _onUserUpdated(AuthUserUpdated event, Emitter<AuthState> emit) {
    if (state is AuthAuthenticated) emit(AuthAuthenticated(event.user));
  }

  Future<void> _onRefreshRequested(AuthRefreshRequested event, Emitter<AuthState> emit) async {
    if (state is! AuthAuthenticated) return;
    try {
      emit(AuthAuthenticated(await _repository.fetchCurrentUser()));
    } on ApiException {
      // Keep the current user; the next screen load will retry.
    }
  }

  Future<void> _onLogoutRequested(AuthLogoutRequested event, Emitter<AuthState> emit) async {
    _socket?.disconnect();
    await _push?.unregister();
    await _repository.logout();
    emit(const AuthUnauthenticated());
  }

  void _onSessionExpired(_AuthSessionExpired event, Emitter<AuthState> emit) {
    _socket?.disconnect();
    if (state is AuthAuthenticated) emit(const AuthUnauthenticated(sessionExpired: true));
  }

  @override
  Future<void> close() async {
    await _expiredSubscription.cancel();
    return super.close();
  }
}
