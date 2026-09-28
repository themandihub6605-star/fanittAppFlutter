import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../bloc/action_cubit.dart';
import '../router/app_routes.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_palette.dart';
import '../theme/app_spacing.dart';
import 'app_button.dart';
import 'app_sheet.dart';
import 'app_snackbar.dart';

/// Backend error codes that mean "your plan doesn't allow this".
const _upgradeCodes = {'PROPOSAL_QUOTA_EXCEEDED', 'EXCLUSIVE_CAMPAIGN_LOCKED', 'PRO_FEATURE_LOCKED'};

/// Provides an [ActionCubit] to a screen and reports every action's
/// outcome — snackbars for success and errors, an upgrade prompt for
/// plan limits.
class ActionScope extends StatelessWidget {
  const ActionScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ActionCubit(),
      child: ActionListener(child: child),
    );
  }
}

class ActionListener extends StatelessWidget {
  const ActionListener({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocListener<ActionCubit, ActionState>(
      listenWhen: (previous, current) => previous.tick != current.tick,
      listener: (context, state) {
        if (state.errorMessage != null) {
          if (_upgradeCodes.contains(state.errorCode)) {
            showUpgradePrompt(context, state.errorMessage!);
          } else {
            AppSnackbar.error(context, state.errorMessage!);
          }
        } else if (state.successMessage != null) {
          AppSnackbar.success(context, state.successMessage!);
        }
      },
      child: child,
    );
  }
}

Future<void> showUpgradePrompt(BuildContext context, String message) {
  return showAppSheet<void>(
    context,
    builder: (sheetContext) => SheetBody(
      title: 'Upgrade your plan',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: sheetContext.palette.primarySoft,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                const Icon(AppIcons.crown, color: AppColors.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(message, style: sheetContext.text.bodyMedium?.copyWith(color: sheetContext.palette.textPrimary))),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: 'See plans',
            onPressed: () {
              Navigator.of(sheetContext).pop();
              context.push(AppRoutes.plans);
            },
          ),
        ],
      ),
    ),
  );
}

/// Action scope for bottom sheets. Snackbars would render behind the sheet,
/// so sheets show errors inline with [InlineActionError] and report success
/// by popping with a result.
class SheetActionScope extends StatelessWidget {
  const SheetActionScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => BlocProvider(create: (_) => ActionCubit(), child: child);
}

class InlineActionError extends StatelessWidget {
  const InlineActionError({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ActionCubit, ActionState>(
      builder: (context, state) {
        final message = state.errorMessage;
        return AnimatedSize(
          duration: AppDurations.normal,
          child: message == null
              ? const SizedBox(width: double.infinity)
              : Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(AppIcons.warning, size: 18, color: AppColors.error),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(message, style: context.text.bodyMedium?.copyWith(color: context.palette.textPrimary)),
                            if (_upgradeCodes.contains(state.errorCode))
                              TextButton(
                                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
                                onPressed: () {
                                  final router = GoRouter.of(context);
                                  Navigator.of(context).pop();
                                  router.push(AppRoutes.plans);
                                },
                                child: const Text('See plans'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}
