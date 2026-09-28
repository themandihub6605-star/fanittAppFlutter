import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/enums/user_role.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/repositories/auth_repository.dart';
import 'auth_form_state.dart';

class RegisterCubit extends Cubit<AuthFormState> {
  RegisterCubit(this._repository) : super(const AuthFormState());

  final AuthRepository _repository;

  Future<void> register(RegisterInput input) async {
    if (state.isBusy) return;
    emit(state.loadingWith(AuthMethod.email));
    try {
      final user = await _repository.register(input);
      emit(state.succeeded(user));
    } on ApiException catch (error) {
      emit(state.failed(error.displayMessage));
    }
  }

  Future<void> continueWithGoogle({required UserRole role, String? referralCode}) async {
    if (state.isBusy) return;
    emit(state.loadingWith(AuthMethod.google));
    try {
      final user = await _repository.signInWithGoogle(role: role, referralCode: referralCode);
      emit(state.succeeded(user));
    } on GoogleSignInCancelled {
      emit(state.idle());
    } on ApiException catch (error) {
      emit(state.failed(error.displayMessage));
    }
  }
}
