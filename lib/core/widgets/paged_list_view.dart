import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/paged_cubit.dart';
import '../theme/app_icons.dart';
import '../theme/app_spacing.dart';
import 'async_view.dart';

/// Scrollable list for a [PagedCubit] with pull-to-refresh, load-more and
/// first-load / empty / error states.
class PagedListView<T> extends StatelessWidget {
  const PagedListView({
    super.key,
    required this.cubit,
    required this.itemBuilder,
    required this.empty,
    this.padding = const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xxl),
    this.spacing = AppSpacing.sm,
  });

  final PagedCubit<T> cubit;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final Widget empty;
  final EdgeInsetsGeometry padding;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PagedCubit<T>, PagedState<T>>(
      bloc: cubit,
      builder: (context, state) {
        if (!state.hasLoaded && state.errorMessage == null) return const LoadingView();
        if (state.items.isEmpty && state.errorMessage != null) {
          return ErrorView(message: state.errorMessage!, onRetry: cubit.refresh);
        }
        return AppRefresh(
          onRefresh: cubit.refresh,
          child: state.items.isEmpty
              ? ScrollableMessage(child: empty)
              : NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification.metrics.extentAfter < 400) cubit.loadMore();
                    return false;
                  },
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: padding,
                    itemCount: state.items.length + 1,
                    separatorBuilder: (_, _) => SizedBox(height: spacing),
                    itemBuilder: (context, index) {
                      if (index == state.items.length) return _Footer(state: state, onRetry: () => cubit.loadMore(force: true));
                      return itemBuilder(context, state.items[index]);
                    },
                  ),
                ),
        );
      },
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.state, required this.onRetry});

  final PagedState<dynamic> state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (state.errorMessage != null) {
      return Center(
        child: TextButton.icon(onPressed: onRetry, icon: const Icon(AppIcons.refresh, size: 18), label: const Text('Load more')),
      );
    }
    if (state.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    return const SizedBox(height: AppSpacing.md);
  }
}
