import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/bloc/action_cubit.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/action_scope.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../domain/repositories/auth_repository.dart';
import '../widgets/auth_scaffold.dart';

/// Sets a new password. Opened from a deep link with `?token=`, or the user
/// pastes the link from the reset email.
class ResetPasswordScreen extends StatelessWidget {
  const ResetPasswordScreen({super.key, this.token});

  final String? token;

  @override
  Widget build(BuildContext context) => SheetActionScope(child: _ResetView(token: token));
}

class _ResetView extends StatefulWidget {
  const _ResetView({this.token});

  final String? token;

  @override
  State<_ResetView> createState() => _ResetViewState();
}

class _ResetViewState extends State<_ResetView> {
  final _formKey = GlobalKey<FormState>();
  late final _link = TextEditingController(text: widget.token ?? '');
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _link.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  /// Accepts the full link from the email or just the token.
  String _extractToken(String input) {
    final value = input.trim();
    final uri = Uri.tryParse(value);
    return uri?.queryParameters['token'] ?? value;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final message = await context.read<ActionCubit>().run(
          'reset',
          () => sl<AuthRepository>().resetPassword(token: _extractToken(_link.text), newPassword: _password.text),
        );
    if (message != null && mounted) {
      AppSnackbar.success(context, 'Password updated. Log in with your new password.');
      context.go(AppRoutes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<ActionCubit>().state.isBusy;
    return AuthScaffold(
      title: 'Set a new password',
      subtitle: widget.token == null ? 'Paste the reset link from your email, then choose a new password.' : 'Choose a new password.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.token == null) ...[
              AppTextField(
                label: 'Reset link',
                hint: 'https://fanitt.com/reset-password?token=…',
                controller: _link,
                prefixIcon: AppIcons.link,
                keyboardType: TextInputType.url,
                validator: (v) => _extractToken(v ?? '').length < 20 ? 'Paste the full link from the email' : null,
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            AppTextField(
              label: 'New password',
              controller: _password,
              prefixIcon: AppIcons.lock,
              isPassword: true,
              autofillHints: const [AutofillHints.newPassword],
              validator: Validators.newPassword,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              label: 'Confirm password',
              controller: _confirm,
              prefixIcon: AppIcons.lock,
              isPassword: true,
              validator: (v) => v != _password.text ? 'Passwords don’t match' : null,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpacing.xl),
            const InlineActionError(),
            AppButton(label: 'Update password', isLoading: busy, onPressed: busy ? null : _submit),
          ],
        ),
      ),
    );
  }
}
