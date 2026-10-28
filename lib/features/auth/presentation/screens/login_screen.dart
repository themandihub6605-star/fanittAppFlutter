// File: lib/features/auth/presentation/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../bloc/auth_bloc.dart';
import '../cubits/auth_form_state.dart';
import '../cubits/login_cubit.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/auth_switch_prompt.dart';
import '../widgets/or_divider.dart';
import '../widgets/social_sign_in.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _attempted = false;
  bool _appleBusy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    setState(() => _attempted = true);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    context.read<LoginCubit>().login(email: _email.text.trim(), password: _password.text);
  }

  Future<void> _continueWithApple() async {
    FocusScope.of(context).unfocus();
    setState(() => _appleBusy = true);
    final user = await runAppleSignIn(context);
    if (!mounted) return;
    setState(() => _appleBusy = false);
    if (user != null) context.read<AuthBloc>().add(AuthLoggedIn(user));
  }

  void _onStateChanged(BuildContext context, AuthFormState state) {
    if (state.user != null) {
      TextInput.finishAutofillContext();
      context.read<AuthBloc>().add(AuthLoggedIn(state.user!));
    } else if (state.errorMessage != null) {
      AppSnackbar.error(context, state.errorMessage!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<LoginCubit, AuthFormState>(
      listenWhen: (previous, current) => previous.tick != current.tick || previous.user != current.user,
      listener: _onStateChanged,
      builder: (context, state) {
        final busy = state.isBusy || _appleBusy;
        return AuthScaffold(
          title: 'Welcome back',
          subtitle: 'Log in to your Fanitt account.',
          footer: Column(
            children: [
              const OrDivider(),
              const SizedBox(height: AppSpacing.lg),
              SocialSignInRow(
                googleBusy: state.loading == AuthMethod.google,
                appleBusy: _appleBusy,
                onGoogle: busy ? null : context.read<LoginCubit>().continueWithGoogle,
                onApple: busy ? null : _continueWithApple,
              ),
              const SizedBox(height: AppSpacing.md),
              AuthSwitchPrompt(
                prompt: 'New to Fanitt?',
                action: 'Create account',
                onTap: () => context.pushReplacement(AppRoutes.register),
              ),
            ],
          ),
          child: AutofillGroup(
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
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    validator: Validators.email,
                    enabled: !busy,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppTextField(
                    label: 'Password',
                    hint: 'Your password',
                    controller: _password,
                    prefixIcon: AppIcons.lock,
                    isPassword: true,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    validator: Validators.password,
                    onSubmitted: (_) => _submit(),
                    enabled: !busy,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: busy ? null : () => context.push(AppRoutes.forgotPassword),
                      child: const Text('Forgot password?'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppButton(
                    label: 'Log in',
                    isLoading: state.loading == AuthMethod.email,
                    onPressed: busy ? null : _submit,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}