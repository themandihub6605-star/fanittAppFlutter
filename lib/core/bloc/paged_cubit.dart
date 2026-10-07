import 'package:equatable/equatable.dart';

import '../models/common_models.dart';
import '../network/api_exception.dart';
import 'safe_cubit.dart';

class PagedState<T> extends Equatable {
  const PagedState({
    this.items = const [],
    this.page = 0,
    this.hasMore = true,
    this.isLoading = false,
    this.errorMessage,
  });

  final List<T> items;
  final int page;
  final bool hasMore;
  final bool isLoading;
  final String? errorMessage;

  bool get isFirstLoad => isLoading && items.isEmpty;
  bool get hasLoaded => page > 0;

  PagedState<T> copyWith({List<T>? items, int? page, bool? hasMore, bool? isLoading, String? errorMessage}) => PagedState<T>(
    items: items ?? this.items,
    page: page ?? this.page,
    hasMore: hasMore ?? this.hasMore,
    isLoading: isLoading ?? this.isLoading,
    errorMessage: errorMessage,
  );

  @override
  List<Object?> get props => [items, page, hasMore, isLoading, errorMessage];
}

/// Infinite-scroll list backed by a page-based endpoint.
class PagedCubit<T> extends SafeCubit<PagedState<T>> {
  PagedCubit(this._fetch) : super(PagedState<T>()) {
    refresh();
  }

  Future<Paged<T>> Function(int page) _fetch;

  /// Swap the query (search text, filters) and reload from page 1.
  void updateQuery(Future<Paged<T>> Function(int page) fetch) {
    _fetch = fetch;
    safeEmit(PagedState<T>());
    refresh();
  }

  Future<void> refresh() => _load(1, reset: true);

  /// [force] retries after a failed page (scrolling alone won't).
  Future<void> loadMore({bool force = false}) async {
    if (state.isLoading || !state.hasMore) return;
    if (state.errorMessage != null && !force) return;
    await _load(state.page + 1);
  }

  /// Local edit after an action (e.g. follow toggled on one item).
  void updateItem(bool Function(T item) test, T Function(T item) update) {
    safeEmit(state.copyWith(items: [for (final item in state.items) test(item) ? update(item) : item]));
  }

  /// Local removal (e.g. a deleted post or a removed member).
  void removeItem(bool Function(T item) test) {
    safeEmit(state.copyWith(items: [for (final item in state.items) if (!test(item)) item]));
  }

  /// Adds an item at the top (e.g. a post the user just published).
  void prependItem(T item) {
    safeEmit(state.copyWith(items: [item, ...state.items]));
  }

  Future<void> _load(int page, {bool reset = false}) async {
    safeEmit(state.copyWith(isLoading: true));
    try {
      final result = await _fetch(page);
      safeEmit(PagedState<T>(
        items: reset ? result.items : [...state.items, ...result.items],
        page: result.page,
        hasMore: result.hasMore,
      ));
    } on ApiException catch (error) {
      safeEmit(state.copyWith(isLoading: false, errorMessage: error.displayMessage));
    }
  }
}