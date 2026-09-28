import 'package:equatable/equatable.dart';

import '../../features/auth/domain/repositories/auth_repository.dart';
import '../network/api_exception.dart';
import '../services/payment_service.dart';
import 'safe_cubit.dart';

class ActionState extends Equatable {
  const ActionState({this.busyKey, this.errorMessage, this.errorCode, this.successMessage, this.tick = 0});

  /// Identifies which button is busy, so only that one shows a spinner.
  final String? busyKey;
  final String? errorMessage;
  final String? errorCode;
  final String? successMessage;
  final int tick;

  bool get isBusy => busyKey != null;
  bool isBusyWith(String key) => busyKey == key;

  @override
  List<Object?> get props => [busyKey, errorMessage, errorCode, successMessage, tick];
}

/// Runs one-off actions (apply, fund, approve, save…) for a screen and
/// reports the outcome through [ActionState]. Returns the result, or null
/// when the action failed or was cancelled.
class ActionCubit extends SafeCubit<ActionState> {
  ActionCubit() : super(const ActionState());

  Future<T?> run<T>(String key, Future<T> Function() task, {String? success}) async {
    if (state.isBusy) return null;
    safeEmit(ActionState(busyKey: key, tick: state.tick));
    try {
      final result = await task();
      safeEmit(ActionState(successMessage: success, tick: state.tick + 1));
      return result;
    } on PaymentCancelled {
      safeEmit(ActionState(tick: state.tick));
    } on GoogleSignInCancelled {
      safeEmit(ActionState(tick: state.tick));
    } on ApiException catch (error) {
      safeEmit(ActionState(errorMessage: error.displayMessage, errorCode: error.errorCode, tick: state.tick + 1));
    }
    return null;
  }
}
