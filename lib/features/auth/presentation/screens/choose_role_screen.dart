import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bloc/request_state.dart';
import '../../../../core/enums/user_role.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../domain/entities/app_user.dart';
import '../bloc/auth_bloc.dart';
import '../cubits/choose_role_cubit.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/role_card.dart';

/// Shown to accounts created as "fan" (e.g. first-time Google sign-in from
/// the login screen). The app needs a creator, brand or agency account.
class ChooseRoleScreen extends StatefulWidget {
  const ChooseRoleScreen({super.key});

  @override
  State<ChooseRoleScreen> createState() => _ChooseRoleScreenState();
}

class _ChooseRoleScreenState extends State<ChooseRoleScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  UserRole? _role;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthBloc>().state;
    _name = TextEditingController(text: auth is AuthAuthenticated ? auth.user.name : '');
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    if (_role == null || !(_formKey.currentState?.validate() ?? false)) return;
    context.read<ChooseRoleCubit>().submit(role: _role!, name: _name.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ChooseRoleCubit, RequestState<AppUser>>(
      listenWhen: (previous, current) => previous.tick != current.tick || previous.status != current.status,
      listener: (context, state) {
        if (state.isSuccess && state.data != null) {
          context.read<AuthBloc>().add(AuthUserUpdated(state.data!));
        } else if (state.isFailure && state.errorMessage != null) {
          AppSnackbar.error(context, state.errorMessage!);
        }
      },
      builder: (context, state) {
        return AuthScaffold(
          title: 'Finish setting up',
          subtitle: 'The Fanitt app is for creators, brands and agencies. Choose your account type.',
          showBack: false,
          footer: Column(
            children: [
              AppButton(
                label: 'Continue',
                isLoading: state.isLoading,
                onPressed: _role == null || state.isLoading ? null : _submit,
              ),
              const SizedBox(height: AppSpacing.xs),
              TextButton(
                onPressed: state.isLoading ? null : () => context.read<AuthBloc>().add(const AuthLogoutRequested()),
                child: const Text('Log out'),
              ),
            ],
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, role) in UserRole.appRoles.indexed) ...[
                  RoleCard(
                    role: role,
                    selected: _role == role,
                    onTap: () => setState(() => _role = role),
                  ).animate(delay: (index * 70).ms).fadeIn(duration: 350.ms).slideY(begin: 0.08),
                  const SizedBox(height: AppSpacing.sm),
                ],
                AnimatedSize(
                  duration: AppDurations.normal,
                  curve: Curves.easeOutCubic,
                  child: _role == null
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.md),
                          child: AppTextField(
                            label: _role!.nameFieldLabel,
                            hint: _role!.nameFieldHint,
                            controller: _name,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.done,
                            validator: Validators.requiredText(_role!.nameFieldLabel),
                            onSubmitted: (_) => _submit(),
                            enabled: !state.isLoading,
                          ),
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
