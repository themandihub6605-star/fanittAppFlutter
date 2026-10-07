import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/enums/user_role.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
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

/// Three steps: choose a role, enter account details, then confirm the
/// email with the 6-digit code we send to it. The account is created only
/// after the code is confirmed.
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
  final _otp = TextEditingController();

  UserRole? _role;
  bool _onDetails = false;
  bool _onOtp = false;
  bool _attempted = false;

  // Email code
  bool _sending = false;
  String _otpEmail = '';
  int _resendIn = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _referral.dispose();
    _otp.dispose();
    _resendTimer?.cancel();
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

  void _backToDetails() {
    FocusScope.of(context).unfocus();
    setState(() => _onOtp = false);
  }

  void _startResendTimer(int seconds) {
    _resendTimer?.cancel();
    setState(() => _resendIn = seconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _resendIn = _resendIn > 0 ? _resendIn - 1 : 0);
      if (_resendIn == 0) t.cancel();
    });
  }

  /// Step 2 → 3: check the form, then email the 6-digit code.
  void _submit() {
    FocusScope.of(context).unfocus();
    setState(() => _attempted = true);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final email = _email.text.trim().toLowerCase();
    // Same email and the last code is still fresh → just reopen the code step.
    if (email == _otpEmail && _resendIn > 0) {
      setState(() => _onOtp = true);
      return;
    }
    _sendCode();
  }

  Future<void> _sendCode() async {
    final email = _email.text.trim().toLowerCase();
    setState(() => _sending = true);
    try {
      final res = await sl<ApiClient>().post<Map<String, dynamic>>(
        '/auth/register/send-otp',
        data: {'email': email, 'name': _name.text.trim()},
        skipAuth: true,
        parser: (d) => d is Map<String, dynamic> ? d : const <String, dynamic>{},
      );
      if (!mounted) return;
      if (email != _otpEmail) _otp.clear();
      setState(() {
        _otpEmail = email;
        _onOtp = true;
      });
      _startResendTimer((res.data['resendInSeconds'] as num?)?.toInt() ?? 60);
      AppSnackbar.success(context, res.message.isEmpty ? 'Code sent to $email' : res.message);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.errorCode == 'OTP_RESEND_WAIT' && email == _otpEmail) {
        // A code was just sent — let them enter it.
        setState(() => _onOtp = true);
      }
      AppSnackbar.error(context, e.displayMessage);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Step 3: confirm the code — this creates the account.
  void _verify() {
    if (context.read<RegisterCubit>().state.isBusy) return;
    FocusScope.of(context).unfocus();
    final code = _otp.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      AppSnackbar.error(context, 'Enter the 6-digit code from your email');
      return;
    }
    final phone = Validators.normalizeMobile(_phone.text);
    context.read<RegisterCubit>().register(
      RegisterInput(
        role: _role!,
        name: _name.text.trim(),
        email: _otpEmail,
        password: _password.text,
        phone: phone.isEmpty ? null : phone,
        referralCode: _referralCode,
        otp: code,
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
    if (_onOtp) return 'Verify your email';
    return switch (_role) {
      UserRole.brand => 'Set up your brand',
      UserRole.agency => 'Register your agency',
      UserRole.fan => 'Create your account',
      _ => 'Create your creator account',
    };
  }

  String get _subtitle {
    if (_onOtp) return 'Enter the 6-digit code we sent to $_otpEmail';
    return _onDetails
        ? 'Your profile is reviewed by our team before it goes live.'
        : 'Pick the account type that fits you. You can add another later.';
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<RegisterCubit, AuthFormState>(
      listenWhen: (previous, current) => previous.tick != current.tick || previous.user != current.user,
      listener: _onStateChanged,
      builder: (context, state) {
        return PopScope(
          canPop: !_onDetails,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop || state.isBusy || _sending) return;
            _onOtp ? _backToDetails() : _backToRoles();
          },
          child: AuthScaffold(
            title: _title,
            subtitle: _subtitle,
            onBack: _onDetails ? (state.isBusy || _sending ? () {} : (_onOtp ? _backToDetails : _backToRoles)) : null,
            footer: _onOtp ? _otpFooter(state) : (_onDetails ? _detailsFooter(state) : _rolesFooter()),
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
              child: _onOtp ? _otpStep(state) : (_onDetails ? _details(state) : _roles()),
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
    final busy = state.isBusy || _sending;

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
              prefixIcon: role == UserRole.creator || role == UserRole.fan ? AppIcons.user : role.icon,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: role == UserRole.creator || role == UserRole.fan ? const [AutofillHints.name] : const [AutofillHints.organizationName],
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
              label: 'Continue',
              isLoading: _sending,
              onPressed: busy ? null : _submit,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'We’ll send a 6-digit code to your email to confirm it’s yours.',
              textAlign: TextAlign.center,
              style: context.text.bodySmall?.copyWith(color: context.palette.textTertiary),
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
          iconWidget: Image.asset('assets/images/google.png'),
          isLoading: state.loading == AuthMethod.google,
          onPressed: state.isBusy || _sending ? null : _continueWithGoogle,
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

  // Step 3 --------------------------------------------------------------------

  Widget _otpStep(AuthFormState state) {
    final palette = context.palette;
    final busy = state.isBusy;
    return Column(
      key: const ValueKey('otp'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primary.withValues(alpha: 0.12)),
            child: const Icon(AppIcons.mail, color: AppColors.primary, size: 30),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _otp,
          autofocus: true,
          enabled: !busy,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          style: context.text.headlineSmall?.copyWith(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 12, color: palette.textPrimary),
          decoration: const InputDecoration(hintText: '••••••', counterText: ''),
          onChanged: (v) {
            if (v.length == 6) _verify();
          },
          onSubmitted: (_) => _verify(),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Didn’t get it? Check your spam folder. The code works for 10 minutes.',
          textAlign: TextAlign.center,
          style: context.text.bodySmall?.copyWith(color: palette.textTertiary),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: 'Verify & create account',
          isLoading: state.loading == AuthMethod.email,
          onPressed: busy ? null : _verify,
        ),
      ],
    );
  }

  Widget _otpFooter(AuthFormState state) {
    final palette = context.palette;
    final busy = state.isBusy || _sending;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Didn’t receive the code? ', style: context.text.bodyMedium?.copyWith(color: palette.textSecondary)),
            if (_sending)
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            else if (_resendIn > 0)
              Text('Resend in ${_resendIn}s', style: context.text.bodyMedium?.copyWith(color: palette.textTertiary, fontWeight: FontWeight.w600))
            else
              GestureDetector(
                onTap: busy ? null : _sendCode,
                child: Text('Resend code', style: context.text.bodyMedium?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton.icon(
          onPressed: busy ? null : _backToDetails,
          icon: const Icon(AppIcons.pencil, size: 16),
          label: const Text('Change email'),
        ),
      ],
    );
  }
}