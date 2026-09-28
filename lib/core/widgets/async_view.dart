import 'package:flutter/material.dart';

import '../bloc/request_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_palette.dart';
import '../theme/app_spacing.dart';
import 'app_button.dart';

/// Renders loading, error and data for a [RequestState]. Keeps showing
/// the last good data while a refresh is in flight or after it fails.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.state,
    required this.builder,
    required this.onRetry,
    this.loading,
  });

  final RequestState<T> state;
  final Widget Function(T data) builder;
  final VoidCallback onRetry;
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    final data = state.data;
    final Widget child;
    if (data != null) {
      child = KeyedSubtree(key: const ValueKey('data'), child: builder(data));
    } else if (state.isFailure) {
      child = ErrorView(key: const ValueKey('error'), message: state.errorMessage ?? '', onRetry: onRetry);
    } else {
      child = KeyedSubtree(key: const ValueKey('loading'), child: loading ?? const LoadingView());
    }
    return AnimatedSwitcher(duration: AppDurations.normal, child: child);
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4)),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MessageView(
      icon: AppIcons.wifiOff,
      title: 'Couldn’t load this',
      message: message,
      action: AppButton.secondary(label: 'Try again', icon: AppIcons.refresh, expand: false, onPressed: onRetry),
    );
  }
}

/// Centered icon + title + message, used for empty and error states.
class MessageView extends StatelessWidget {
  const MessageView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: iconColor == null ? palette.surfaceMuted : iconColor!.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Icon(icon, size: 28, color: iconColor ?? palette.textTertiary),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(title, textAlign: TextAlign.center, style: context.text.titleMedium),
            if (message != null && message!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text(message!, textAlign: TextAlign.center, style: context.text.bodyMedium),
            ],
            if (action != null) ...[const SizedBox(height: AppSpacing.lg), action!],
          ],
        ),
      ),
    );
  }
}

/// Empty state that still supports pull-to-refresh inside a RefreshIndicator.
class ScrollableMessage extends StatelessWidget {
  const ScrollableMessage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(height: constraints.maxHeight, child: child),
      ),
    );
  }
}

class AppRefresh extends StatelessWidget {
  const AppRefresh({super.key, required this.onRefresh, required this.child});

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator.adaptive(
      color: AppColors.primary,
      backgroundColor: context.palette.surface,
      onRefresh: onRefresh,
      child: child,
    );
  }
}
