import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bloc/request_state.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/repositories/auth_repository.dart';

class ForgotPasswordCubit extends Cubit<RequestState<String>> {
  ForgotPasswordCubit(this._repository) : super(const RequestState<String>());

  final AuthRepository _repository;

  Future<void> sendResetLink(String email) async {
    if (state.isLoading) return;
    emit(state.loading());
    try {
      emit(state.success(await _repository.forgotPassword(email)));
    } on ApiException catch (error) {
      emit(state.failure(error.displayMessage));
    }
  }
}
