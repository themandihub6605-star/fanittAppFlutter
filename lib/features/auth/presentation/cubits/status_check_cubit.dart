import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bloc/request_state.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';

/// Re-fetches the user so a newly approved profile unlocks the app.
class StatusCheckCubit extends Cubit<RequestState<AppUser>> {
  StatusCheckCubit(this._repository) : super(const RequestState<AppUser>());

  final AuthRepository _repository;

  Future<void> check() async {
    if (state.isLoading) return;
    emit(state.loading());
    try {
      emit(state.success(await _repository.fetchCurrentUser()));
    } on ApiException catch (error) {
      emit(state.failure(error.displayMessage));
    }
  }
}
