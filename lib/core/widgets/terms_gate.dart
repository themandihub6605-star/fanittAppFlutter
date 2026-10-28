// File: lib/core/widgets/terms_gate.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../di/injection.dart';
import '../network/api_client.dart';
import '../router/app_routes.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/app_spacing.dart';
import '../utils/json.dart';
import 'app_button.dart';

/// Makes sure every signed-in user has agreed to the Terms of Use
/// (Apple / Google rule for apps with user posts and chat).
///
/// - Sign-up: the user ticks the box → [markAgreed] → saved silently on the
///   first app open.
/// - Everyone else (old accounts, Google sign-in from Login, new Terms
///   version): a one-time "Agree to continue" popup.
class TermsGate {
  TermsGate._();

  static bool _agreedAtSignup = false;
  static bool _checking = false;
  static String? _okForUser;

  /// Call when the user ticks "I agree" on sign-up.
  static void markAgreed() => _agreedAtSignup = true;

  /// Call once the app's main screen is on (safe to call often).
  static Future<void> check(BuildContext context) async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) return;
    final userId = auth.user.id;
    if (_checking || _okForUser == userId) return;
    _checking = true;
    try {
      final accepted = (await sl<ApiClient>().get('/terms/status', parser: (d) => J.boolean(J.asMap(d), 'accepted'))).data;
      if (accepted) {
        _okForUser = userId;
        return;
      }
      if (_agreedAtSignup) {
        await _accept();
        _agreedAtSignup = false;
        _okForUser = userId;
        return;
      }
      if (!context.mounted) return;
      final agreed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (_) => const _TermsDialog(),
      );
      if (agreed == true) _okForUser = userId;
    } catch (_) {
      // Offline / server issue — ask again next time.
    } finally {
      _checking = false;
    }
  }

  static Future<void> _accept() => sl<ApiClient>().post(
    '/terms/accept',
    data: {'platform': kIsWeb ? 'web' : defaultTargetPlatform.name},
    parser: (_) => null,
  );
}

class _TermsDialog extends StatefulWidget {
  const _TermsDialog();

  @override
  State<_TermsDialog> createState() => _TermsDialogState();
}

class _TermsDialogState extends State<_TermsDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _agree() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await TermsGate._accept();
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _error = 'Couldn’t save. Check your internet and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final link = TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, decoration: TextDecoration.underline, decorationColor: AppColors.primary.withValues(alpha: 0.5));
    return PopScope(
      canPop: false,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Before you continue', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                style: context.text.bodyMedium?.copyWith(color: palette.textSecondary, height: 1.45),
                children: [
                  const TextSpan(text: 'Please agree to Fanitt’s '),
                  TextSpan(text: 'Terms of Use', style: link, recognizer: TapGestureRecognizer()..onTap = () => context.push(AppRoutes.legal('terms-of-use'))),
                  const TextSpan(text: ' and '),
                  TextSpan(text: 'Privacy Policy', style: link, recognizer: TapGestureRecognizer()..onTap = () => context.push(AppRoutes.legal('privacy-policy'))),
                  const TextSpan(text: '.\n\n'),
                  const TextSpan(
                    text: 'Fanitt has zero tolerance for abusive, sexual, hateful, violent or illegal content. Accounts that post it are removed.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppButton(label: 'I agree', isLoading: _busy, onPressed: _busy ? null : _agree),
              const SizedBox(height: 4),
              TextButton(
                onPressed: _busy
                    ? null
                    : () {
                  Navigator.of(context).pop(false);
                  context.read<AuthBloc>().add(const AuthLogoutRequested());
                },
                child: Text('Log out', style: TextStyle(color: palette.textSecondary, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "☐ I agree to the Terms of Use and Privacy Policy…" for sign-up.
class TermsCheckbox extends StatelessWidget {
  const TermsCheckbox({super.key, required this.value, required this.onChanged, this.showError = false, this.enabled = true});

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool showError;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final link = TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700);
    final error = showError && !value;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: enabled ? () => onChanged(!value) : null,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: error ? Border.all(color: AppColors.error.withValues(alpha: 0.6)) : null,
          color: error ? AppColors.error.withValues(alpha: 0.05) : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 36,
              height: 28,
              child: Checkbox(
                value: value,
                onChanged: enabled ? (v) => onChanged(v ?? false) : null,
                activeColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                side: BorderSide(color: error ? AppColors.error : palette.borderStrong, width: 1.6),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text.rich(
                  TextSpan(
                    style: context.text.bodySmall?.copyWith(color: palette.textSecondary, height: 1.45, fontSize: 12.5),
                    children: [
                      const TextSpan(text: 'I agree to the '),
                      TextSpan(text: 'Terms of Use', style: link, recognizer: TapGestureRecognizer()..onTap = () => context.push(AppRoutes.legal('terms-of-use'))),
                      const TextSpan(text: ' and '),
                      TextSpan(text: 'Privacy Policy', style: link, recognizer: TapGestureRecognizer()..onTap = () => context.push(AppRoutes.legal('privacy-policy'))),
                      const TextSpan(text: '. I won’t post abusive, sexual, hateful or illegal content.'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}