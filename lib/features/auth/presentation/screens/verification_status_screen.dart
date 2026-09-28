import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bloc/request_state.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/enums/user_role.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../domain/entities/app_user.dart';
import '../bloc/auth_bloc.dart';
import '../cubits/status_check_cubit.dart';

/// Shown while an admin reviews the profile, or after it was not approved.
class VerificationStatusScreen extends StatelessWidget {
  const VerificationStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final user = auth is AuthAuthenticated ? auth.user : null;
    final rejected = user?.profileStatus == VerificationStatus.rejected;
    final palette = context.palette;

    final accent = rejected ? AppColors.error : AppColors.warning;
    final title = rejected ? 'Your profile wasn’t approved' : 'Your profile is under review';
    final body = rejected
        ? 'Our team couldn’t verify your ${user?.role.label.toLowerCase() ?? ''} profile. '
            'Email ${AppConfig.supportEmail} and we’ll help you fix it.'
        : 'We verify every ${user?.role.label.toLowerCase() ?? 'account'} to keep Fanitt trusted. '
            'You’ll get full access as soon as your profile is approved.';

    return BlocListener<StatusCheckCubit, RequestState<AppUser>>(
      listenWhen: (previous, current) => previous.tick != current.tick || previous.status != current.status,
      listener: (context, state) {
        if (state.isSuccess && state.data != null) {
          final updated = state.data!;
          if (updated.profileStatus?.blocksAccess ?? false) {
            AppSnackbar.info(context, 'Still under review. We’ll let you in as soon as it’s approved.');
          }
          context.read<AuthBloc>().add(AuthUserUpdated(updated));
        } else if (state.isFailure && state.errorMessage != null) {
          AppSnackbar.error(context, state.errorMessage!);
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Center(
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: context.isDark ? 0.16 : 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(rejected ? AppIcons.xCircle : AppIcons.hourglass, size: 42, color: accent),
                  ).animate().scale(begin: const Offset(0.7, 0.7), duration: 500.ms, curve: Curves.easeOutBack),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(title, textAlign: TextAlign.center, style: context.text.headlineSmall)
                    .animate(delay: 120.ms)
                    .fadeIn(duration: 400.ms),
                const SizedBox(height: AppSpacing.sm),
                Text(body, textAlign: TextAlign.center, style: context.text.bodyMedium?.copyWith(fontSize: 15))
                    .animate(delay: 200.ms)
                    .fadeIn(duration: 400.ms),
                if (user != null) ...[
                  const SizedBox(height: AppSpacing.xl),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: palette.border),
                    ),
                    child: Row(
                      children: [
                        Icon(AppIcons.mail, size: 20, color: palette.textSecondary),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            user.email,
                            style: context.text.titleSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ).animate(delay: 280.ms).fadeIn(duration: 400.ms),
                ],
                const Spacer(),
                BlocBuilder<StatusCheckCubit, RequestState<AppUser>>(
                  builder: (context, state) => AppButton(
                    label: 'Check status',
                    icon: AppIcons.refresh,
                    isLoading: state.isLoading,
                    onPressed: state.isLoading ? null : context.read<StatusCheckCubit>().check,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                TextButton(
                  onPressed: () => context.read<AuthBloc>().add(const AuthLogoutRequested()),
                  child: const Text('Log out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
