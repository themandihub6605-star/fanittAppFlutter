// File: lib/features/auth/presentation/screens/forgot_password_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
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
import '../widgets/auth_scaffold.dart';

enum _Step { email, code, password }

/// Forgot password, fully inside the app:
///   1. enter email → a 6-digit code is emailed
///   2. enter the code → verified
///   3. choose a new password → back to log in
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailForm = GlobalKey<FormState>();
  final _passwordForm = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  _Step _step = _Step.email;
  bool _busy = false;
  String _sentTo = '';
  String _resetToken = '';
  int _resendIn = 0;
  Timer? _timer;
  String? _codeError;

  AuthRepository get _repo => sl<AuthRepository>();

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in [_email, _code, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  void _startTimer(int seconds) {
    _timer?.cancel();
    setState(() => _resendIn = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn = _resendIn > 0 ? _resendIn - 1 : 0);
      if (_resendIn == 0) t.cancel();
    });
  }

  // --- step 1: send the code -------------------------------------------------------

  Future<void> _sendCode({bool resend = false}) async {
    FocusScope.of(context).unfocus();
    if (!resend && !(_emailForm.currentState?.validate() ?? false)) return;
    final email = resend ? _sentTo : _email.text.trim().toLowerCase();
    // Same email and the timer is still running → just go back to the code.
    if (!resend && email == _sentTo && _resendIn > 0) {
      setState(() => _step = _Step.code);
      return;
    }
    setState(() => _busy = true);
    try {
      final wait = await _repo.requestResetCode(email);
      if (!mounted) return;
      if (email != _sentTo) _code.clear();
      setState(() {
        _sentTo = email;
        _step = _Step.code;
        _codeError = null;
      });
      _startTimer(wait);
      if (resend) AppSnackbar.success(context, 'New code sent to $email');
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.displayMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // --- step 2: verify the code ------------------------------------------------------

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _codeError = 'Enter the 6-digit code');
      return;
    }
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _codeError = null;
    });
    try {
      final token = await _repo.verifyResetCode(email: _sentTo, otp: code);
      if (!mounted) return;
      HapticFeedback.lightImpact();
      setState(() {
        _resetToken = token;
        _step = _Step.password;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      _code.clear();
      setState(() => _codeError = e.displayMessage);
      // Too many wrong tries → they need a fresh code.
      if (e.errorCode == 'RESET_OTP_LOCKED') setState(() => _resendIn = 0);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // --- step 3: new password ------------------------------------------------------------

  Future<void> _savePassword() async {
    FocusScope.of(context).unfocus();
    if (!(_passwordForm.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await _repo.resetPassword(token: _resetToken, newPassword: _password.text);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      AppSnackbar.success(context, 'Password updated. Log in with your new password.');
      context.go(AppRoutes.login);
    } on ApiException catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, e.displayMessage);
      // The one-time token expired → start again from the code.
      if (e.errorCode == 'RESET_TOKEN_INVALID') {
        setState(() {
          _resetToken = '';
          _code.clear();
          _resendIn = 0;
          _step = _Step.code;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _back() {
    if (_busy) return;
    switch (_step) {
      case _Step.email:
        context.pop();
      case _Step.code:
        setState(() => _step = _Step.email);
      case _Step.password:
        setState(() => _step = _Step.code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (title, subtitle) = switch (_step) {
      _Step.email => ('Forgot password?', 'Enter the email you signed up with. We’ll send you a 6-digit code.'),
      _Step.code => ('Enter the code', 'We sent a 6-digit code to $_sentTo'),
      _Step.password => ('Set a new password', 'Use at least 8 characters. You’ll log in with this from now on.'),
    };
    return PopScope(
      canPop: _step == _Step.email && !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: AuthScaffold(
        title: title,
        subtitle: subtitle,
        onBack: _back,
        footer: _step == _Step.code ? _codeFooter() : null,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: switch (_step) {
            _Step.email => _emailStep(),
            _Step.code => _codeStep(),
            _Step.password => _passwordStep(),
          },
        ),
      ),
    );
  }

  Widget _emailStep() {
    return Form(
      key: _emailForm,
      child: Column(
        key: const ValueKey('email'),
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
            onSubmitted: (_) => _sendCode(),
            enabled: !_busy,
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton(label: 'Send code', isLoading: _busy, onPressed: _busy ? null : _sendCode),
        ],
      ),
    );
  }

  Widget _codeStep() {
    final palette = context.palette;
    return Column(
      key: const ValueKey('code'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primary.withValues(alpha: 0.12)),
            child: const Icon(AppIcons.envelopeOpen, color: AppColors.primary, size: 30),
          ).animate().scale(begin: const Offset(0.7, 0.7), duration: 400.ms, curve: Curves.easeOutBack),
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _code,
          autofocus: true,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          style: context.text.headlineSmall?.copyWith(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 12, color: palette.textPrimary),
          decoration: InputDecoration(hintText: '••••••', counterText: '', errorText: _codeError, errorMaxLines: 3),
          onChanged: (v) {
            if (_codeError != null) setState(() => _codeError = null);
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
        AppButton(label: 'Verify code', isLoading: _busy, onPressed: _busy ? null : _verify),
      ],
    );
  }

  Widget _codeFooter() {
    final palette = context.palette;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Didn’t receive the code? ', style: context.text.bodyMedium?.copyWith(color: palette.textSecondary)),
            if (_resendIn > 0)
              Text('Resend in ${_resendIn}s', style: context.text.bodyMedium?.copyWith(color: palette.textTertiary, fontWeight: FontWeight.w600))
            else
              GestureDetector(
                onTap: _busy ? null : () => _sendCode(resend: true),
                child: Text('Resend code', style: context.text.bodyMedium?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton.icon(
          onPressed: _busy ? null : () => setState(() => _step = _Step.email),
          icon: const Icon(AppIcons.pencil, size: 16),
          label: const Text('Change email'),
        ),
      ],
    );
  }

  Widget _passwordStep() {
    return Form(
      key: _passwordForm,
      child: Column(
        key: const ValueKey('password'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            label: 'New password',
            controller: _password,
            prefixIcon: AppIcons.lock,
            isPassword: true,
            autofocus: true,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.next,
            validator: Validators.newPassword,
            enabled: !_busy,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            label: 'Confirm new password',
            controller: _confirm,
            prefixIcon: AppIcons.lock,
            isPassword: true,
            textInputAction: TextInputAction.done,
            validator: (v) => v != _password.text ? 'Passwords don’t match' : null,
            onSubmitted: (_) => _savePassword(),
            enabled: !_busy,
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton(label: 'Update password', isLoading: _busy, onPressed: _busy ? null : _savePassword),
        ],
      ),
    );
  }
}
