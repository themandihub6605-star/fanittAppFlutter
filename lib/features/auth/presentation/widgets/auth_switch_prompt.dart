import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_palette.dart';

/// "New to Fanitt? Create account" style prompt.
class AuthSwitchPrompt extends StatelessWidget {
  const AuthSwitchPrompt({super.key, required this.prompt, required this.action, required this.onTap});

  final String prompt;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(prompt, style: context.text.bodyMedium),
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6)),
          child: Text(action, style: context.text.labelLarge?.copyWith(color: AppColors.primary)),
        ),
      ],
    );
  }
}
