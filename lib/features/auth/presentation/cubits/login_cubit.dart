import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/api_exception.dart';
import '../../domain/repositories/auth_repository.dart';
import 'auth_form_state.dart';

class LoginCubit extends Cubit<AuthFormState> {
  LoginCubit(this._repository) : super(const AuthFormState());

  final AuthRepository _repository;

  Future<void> login({required String email, required String password}) async {
    if (state.isBusy) return;
    emit(state.loadingWith(AuthMethod.email));
    try {
      final user = await _repository.login(email: email, password: password);
      emit(state.succeeded(user));
    } on ApiException catch (error) {
      emit(state.failed(error.displayMessage));
    }
  }

  Future<void> continueWithGoogle() async {
    if (state.isBusy) return;
    emit(state.loadingWith(AuthMethod.google));
    try {
      final user = await _repository.signInWithGoogle();
      emit(state.succeeded(user));
    } on GoogleSignInCancelled {
      emit(state.idle());
    } on ApiException catch (error) {
      emit(state.failed(error.displayMessage));
    }
  }
}
