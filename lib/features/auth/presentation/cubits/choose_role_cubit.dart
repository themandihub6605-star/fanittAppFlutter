import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bloc/request_state.dart';
import '../../../../core/enums/user_role.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';

/// Turns an existing fan account into a creator, brand or agency account.
class ChooseRoleCubit extends Cubit<RequestState<AppUser>> {
  ChooseRoleCubit(this._repository) : super(const RequestState<AppUser>());

  final AuthRepository _repository;

  Future<void> submit({required UserRole role, required String name}) async {
    if (state.isLoading) return;
    emit(state.loading());
    try {
      emit(state.success(await _repository.upgradeRole(role, name: name)));
    } on ApiException catch (error) {
      emit(state.failure(error.displayMessage));
    }
  }
}
