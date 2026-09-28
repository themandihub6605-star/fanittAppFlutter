import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/enums/user_role.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../domain/repositories/auth_repository.dart';
import '../bloc/auth_bloc.dart';
import '../cubits/auth_form_state.dart';
import '../cubits/register_cubit.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/auth_switch_prompt.dart';
import '../widgets/or_divider.dart';
import '../widgets/role_card.dart';

/// Two steps: choose a role, then enter account details.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _referral = TextEditingController();

  UserRole? _role;
  bool _onDetails = false;
  bool _attempted = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _referral.dispose();
    super.dispose();
  }

  String? get _referralCode {
    final code = _referral.text.trim().toUpperCase();
    return code.isEmpty ? null : code;
  }

  void _goToDetails() {
    if (_role == null) return;
    setState(() => _onDetails = true);
  }

  void _backToRoles() {
    FocusScope.of(context).unfocus();
    setState(() => _onDetails = false);
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    setState(() => _attempted = true);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final phone = Validators.normalizeMobile(_phone.text);
    context.read<RegisterCubit>().register(
      RegisterInput(
        role: _role!,
        name: _name.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
        phone: phone.isEmpty ? null : phone,
        referralCode: _referralCode,
      ),
    );
  }

  void _continueWithGoogle() {
    FocusScope.of(context).unfocus();
    // Only the referral code matters for Google sign-up — check just that.
    final referralError = Validators.optionalReferralCode(_referral.text);
    if (referralError != null) {
      setState(() => _attempted = true);
      _formKey.currentState?.validate();
      AppSnackbar.error(context, referralError);
      return;
    }
    context.read<RegisterCubit>().continueWithGoogle(role: _role!, referralCode: _referralCode);
  }

  void _onStateChanged(BuildContext context, AuthFormState state) {
    if (state.user != null) {
      TextInput.finishAutofillContext();
      context.read<AuthBloc>().add(AuthLoggedIn(state.user!));
    } else if (state.errorMessage != null) {
      AppSnackbar.error(context, state.errorMessage!);
    }
  }

  String get _title {
    if (!_onDetails) return 'How will you use Fanitt?';
    return switch (_role) {
      UserRole.brand => 'Set up your brand',
      UserRole.agency => 'Register your agency',
      _ => 'Create your creator account',
    };
  }

  String get _subtitle => _onDetails
      ? 'Your profile is reviewed by our team before it goes live.'
      : 'Pick the account type that fits you. You can add another later.';

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<RegisterCubit, AuthFormState>(
      listenWhen: (previous, current) => previous.tick != current.tick || previous.user != current.user,
      listener: _onStateChanged,
      builder: (context, state) {
        return PopScope(
          canPop: !_onDetails,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && !state.isBusy) _backToRoles();
          },
          child: AuthScaffold(
            title: _title,
            subtitle: _subtitle,
            onBack: _onDetails ? (state.isBusy ? () {} : _backToRoles) : null,
            footer: _onDetails ? _detailsFooter(state) : _rolesFooter(),
            child: AnimatedSwitcher(
              duration: AppDurations.slow,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(animation),
                  child: child,
                ),
              ),
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topCenter,
                children: [...previous, if (current != null) current],
              ),
              child: _onDetails ? _details(state) : _roles(),
            ),
          ),
        );
      },
    );
  }

  // Step 1 --------------------------------------------------------------------

  Widget _roles() {
    return Column(
      key: const ValueKey('roles'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, role) in UserRole.appRoles.indexed) ...[
          RoleCard(
            role: role,
            selected: _role == role,
            onTap: () => setState(() => _role = role),
          ).animate(delay: (index * 70).ms).fadeIn(duration: 350.ms).slideY(begin: 0.08, curve: Curves.easeOutCubic),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }

  Widget _rolesFooter() {
    return Column(
      children: [
        AppButton(label: 'Continue', onPressed: _role == null ? null : _goToDetails),
        const SizedBox(height: AppSpacing.md),
        AuthSwitchPrompt(
          prompt: 'Already have an account?',
          action: 'Log in',
          onTap: () => context.pushReplacement(AppRoutes.login),
        ),
      ],
    );
  }

  // Step 2 --------------------------------------------------------------------

  Widget _details(AuthFormState state) {
    final role = _role!;
    final busy = state.isBusy;

    return AutofillGroup(
      key: const ValueKey('details'),
      child: Form(
        key: _formKey,
        autovalidateMode: _attempted ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              label: role.nameFieldLabel,
              hint: role.nameFieldHint,
              controller: _name,
              prefixIcon: role == UserRole.creator ? AppIcons.user : role.icon,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: role == UserRole.creator ? const [AutofillHints.name] : const [AutofillHints.organizationName],
              validator: Validators.requiredText(role.nameFieldLabel),
              enabled: !busy,
            ),
            const SizedBox(height: AppSpacing.lg),
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
              label: 'Mobile number (optional)',
              hint: '10-digit mobile number',
              controller: _phone,
              prefixIcon: AppIcons.phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.telephoneNumber],
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')), LengthLimitingTextInputFormatter(14)],
              validator: Validators.optionalMobile,
              enabled: !busy,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              label: 'Password',
              hint: 'At least 8 characters',
              controller: _password,
              prefixIcon: AppIcons.lock,
              isPassword: true,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              validator: Validators.newPassword,
              enabled: !busy,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              label: 'Referral code (optional)',
              hint: '8 characters, e.g. CRK7F3QX',
              controller: _referral,
              prefixIcon: AppIcons.gift,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              inputFormatters: Validators.referralCodeFormatters,
              validator: Validators.optionalReferralCode,
              onSubmitted: (_) => _submit(),
              enabled: !busy,
            ),
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: 'Create account',
              isLoading: state.loading == AuthMethod.email,
              onPressed: busy ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailsFooter(AuthFormState state) {
    return Column(
      children: [
        const OrDivider(),
        const SizedBox(height: AppSpacing.lg),
        AppButton.secondary(
          label: 'Sign up with Google',
          icon: AppIcons.google,
          isLoading: state.loading == AuthMethod.google,
          onPressed: state.isBusy ? null : _continueWithGoogle,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'By creating an account you agree to Fanitt’s Terms of Service and Privacy Policy.',
          textAlign: TextAlign.center,
          style: context.text.bodySmall?.copyWith(color: context.palette.textTertiary),
        ),
      ],
    );
  }
}