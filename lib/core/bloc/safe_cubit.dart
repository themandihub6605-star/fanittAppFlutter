import 'package:flutter_bloc/flutter_bloc.dart';

/// Ignores emits after the screen that owned the cubit has closed it.
abstract class SafeCubit<S> extends Cubit<S> {
  SafeCubit(super.initialState);

  void safeEmit(S state) {
    if (!isClosed) emit(state);
  }
}
