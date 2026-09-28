import 'package:equatable/equatable.dart';

enum RequestStatus { idle, loading, success, failure }

/// State for a single async action (submit, check, send…).
/// [tick] changes on every failure so the same error message still
/// triggers listeners.
class RequestState<T> extends Equatable {
  const RequestState({
    this.status = RequestStatus.idle,
    this.data,
    this.errorMessage,
    this.tick = 0,
  });

  final RequestStatus status;
  final T? data;
  final String? errorMessage;
  final int tick;

  bool get isLoading => status == RequestStatus.loading;
  bool get isSuccess => status == RequestStatus.success;
  bool get isFailure => status == RequestStatus.failure;

  RequestState<T> loading() => RequestState<T>(status: RequestStatus.loading, data: data, tick: tick);

  RequestState<T> success(T data) => RequestState<T>(status: RequestStatus.success, data: data, tick: tick);

  RequestState<T> failure(String message) => RequestState<T>(
        status: RequestStatus.failure,
        data: data,
        errorMessage: message,
        tick: tick + 1,
      );

  @override
  List<Object?> get props => [status, data, errorMessage, tick];
}
