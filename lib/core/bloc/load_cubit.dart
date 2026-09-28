import '../network/api_exception.dart';
import 'request_state.dart';
import 'safe_cubit.dart';

/// Loads one piece of data for a screen, with pull-to-refresh and local
/// updates after an action (e.g. marking something read).
class LoadCubit<T> extends SafeCubit<RequestState<T>> {
  LoadCubit(this._loader, {bool autoLoad = true}) : super(RequestState<T>()) {
    if (autoLoad) load();
  }

  final Future<T> Function() _loader;

  Future<void> load() async {
    safeEmit(state.loading());
    await _fetch();
  }

  /// Reloads without showing the full-screen loader.
  Future<void> refresh() => _fetch();

  void replace(T data) => safeEmit(state.success(data));

  Future<void> _fetch() async {
    try {
      safeEmit(state.success(await _loader()));
    } on ApiException catch (error) {
      safeEmit(state.failure(error.displayMessage));
    }
  }
}
