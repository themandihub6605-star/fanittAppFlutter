import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/bloc/request_state.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../cubits/forgot_password_cubit.dart';
import '../widgets/auth_scaffold.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _attempted = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    setState(() => _attempted = true);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    context.read<ForgotPasswordCubit>().sendResetLink(_email.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ForgotPasswordCubit, RequestState<String>>(
      listenWhen: (previous, current) => previous.tick != current.tick,
      listener: (context, state) {
        if (state.errorMessage != null) AppSnackbar.error(context, state.errorMessage!);
      },
      builder: (context, state) {
        if (state.isSuccess) {
          return AuthScaffold(
            title: 'Check your email',
            subtitle: 'If an account exists for ${_email.text.trim()}, we’ve sent a link to reset '
                'your password. The link expires in 15 minutes.',
            footer: Column(
              children: [
                AppButton(label: 'I have the reset link', onPressed: () => context.push(AppRoutes.resetPassword)),
                const SizedBox(height: AppSpacing.sm),
                AppButton.secondary(label: 'Back to log in', onPressed: () => context.pop()),
              ],
            ),
            child: Center(
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(color: context.palette.primarySoft, shape: BoxShape.circle),
                child: const Icon(AppIcons.envelopeOpen, size: 38, color: AppColors.primary),
              ).animate().scale(begin: const Offset(0.6, 0.6), duration: 500.ms, curve: Curves.easeOutBack),
            ),
          );
        }

        return AuthScaffold(
          title: 'Reset your password',
          subtitle: 'Enter the email you signed up with and we’ll send you a reset link.',
          child: Form(
            key: _formKey,
            autovalidateMode: _attempted ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTextField(
                  label: 'Email',
                  hint: 'you@example.com',
                  controller: _email,
                  prefixIcon: AppIcons.mail,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.email],
                  validator: Validators.email,
                  onSubmitted: (_) => _submit(),
                  enabled: !state.isLoading,
                ),
                const SizedBox(height: AppSpacing.xl),
                AppButton(
                  label: 'Send reset link',
                  isLoading: state.isLoading,
                  onPressed: state.isLoading ? null : _submit,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
