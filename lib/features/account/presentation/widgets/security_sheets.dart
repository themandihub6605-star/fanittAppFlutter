import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bloc/action_cubit.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/action_scope.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../profile/data/profile_repository.dart';

Future<bool> showChangePasswordSheet(BuildContext context) async {
  final changed = await showAppSheet<bool>(context, builder: (_) => const SheetActionScope(child: _ChangePasswordSheet()));
  return changed ?? false;
}

/// Required by the App Store and Play Store: users can delete their account
/// from inside the app.
Future<void> showDeleteAccountSheet(BuildContext context) async {
  final deleted = await showAppSheet<bool>(context, builder: (_) => const SheetActionScope(child: _DeleteAccountSheet()));
  if ((deleted ?? false) && context.mounted) {
    context.read<AuthBloc>().add(const AuthLogoutRequested());
  }
}

class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet();

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final ok = await context.read<ActionCubit>().run('password', () async {
      await sl<ProfileRepository>().changePassword(current: _current.text, next: _next.text);
      return true;
    });
    if (ok != null && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<ActionCubit>().state.isBusy;
    return SheetBody(
      title: 'Change password',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(label: 'Current password', controller: _current, prefixIcon: AppIcons.lock, isPassword: true, validator: Validators.password),
            const SizedBox(height: AppSpacing.md),
            AppTextField(label: 'New password', controller: _next, prefixIcon: AppIcons.lock, isPassword: true, validator: Validators.newPassword),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Confirm new password',
              controller: _confirm,
              prefixIcon: AppIcons.lock,
              isPassword: true,
              validator: (v) => v != _next.text ? 'Passwords don’t match' : null,
            ),
            const SizedBox(height: AppSpacing.lg),
            const InlineActionError(),
            AppButton(label: 'Update password', isLoading: busy, onPressed: busy ? null : _submit),
          ],
        ),
      ),
    );
  }
}

class _DeleteAccountSheet extends StatefulWidget {
  const _DeleteAccountSheet();

  @override
  State<_DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends State<_DeleteAccountSheet> {
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final ok = await context.read<ActionCubit>().run('delete', () async {
      await sl<ProfileRepository>().deleteAccount();
      return true;
    });
    if (ok != null && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<ActionCubit>().state.isBusy;
    final ready = _confirm.text.trim().toUpperCase() == 'DELETE';
    return SheetBody(
      title: 'Delete your account',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            color: AppColors.error.withValues(alpha: 0.08),
            borderColor: Colors.transparent,
            child: Text(
              'Your request goes to the Fanitt team and your account is locked right away. '
                  'Once approved, your account is permanently deleted and you can sign up again with the same email. '
                  'Withdraw any wallet balance first — it can’t be recovered after deletion.',
              style: context.text.bodyMedium?.copyWith(color: context.palette.textPrimary),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            label: 'Type DELETE to confirm',
            controller: _confirm,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),
          const InlineActionError(),
          AppButton(
            label: 'Request deletion',
            variant: AppButtonVariant.danger,
            isLoading: busy,
            onPressed: busy || !ready ? null : _delete,
          ),
        ],
      ),
    );
  }
}