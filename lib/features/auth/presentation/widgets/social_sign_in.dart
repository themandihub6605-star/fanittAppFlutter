// File: lib/features/auth/presentation/widgets/social_sign_in.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/enums/user_role.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';

/// Apple sign-in works on iPhone / iPad. On Android the button only shows.
bool get appleSignInAvailable => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// [ Google ] [ Apple ] side by side, used on Login and Sign up.
class SocialSignInRow extends StatelessWidget {
  const SocialSignInRow({
    super.key,
    required this.onGoogle,
    required this.onApple,
    this.googleBusy = false,
    this.appleBusy = false,
  });

  final VoidCallback? onGoogle;
  final VoidCallback? onApple;
  final bool googleBusy;
  final bool appleBusy;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: AppButton.secondary(
            label: 'Google',
            iconWidget: Image.asset('assets/images/google.png'),
            isLoading: googleBusy,
            onPressed: onGoogle,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: AppButton.secondary(
            label: 'Apple',
            // Put the logo at assets/images/apple.png (and list it in pubspec.yaml).
            iconWidget: Image.asset(
              'assets/images/apple.png',
              errorBuilder: (context, _, _) => const Icon(Icons.apple, size: 22),
            ),
            isLoading: appleBusy,
            onPressed: onApple,
          ),
        ),
      ],
    );
  }
}

/// Runs Sign in with Apple. Returns the signed-in user, or null when it was
/// cancelled, failed (a message is shown) or isn't available on this phone.
Future<AppUser?> runAppleSignIn(BuildContext context, {UserRole? role, String? referralCode}) async {
  if (!appleSignInAvailable) {
    AppSnackbar.info(context, 'Apple sign-in works on iPhone. Use Google or email here.');
    return null;
  }
  try {
    return await sl<AuthRepository>().signInWithApple(role: role, referralCode: referralCode);
  } on AppleSignInCancelled {
    return null;
  } on ApiException catch (error) {
    if (context.mounted) AppSnackbar.error(context, error.displayMessage);
    return null;
  } catch (_) {
    if (context.mounted) AppSnackbar.error(context, 'Apple sign-in failed. Please try again.');
    return null;
  }
}