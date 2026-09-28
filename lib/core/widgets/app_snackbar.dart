import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_palette.dart';
import '../theme/app_spacing.dart';

abstract final class AppSnackbar {
  static void error(BuildContext context, String message) =>
      _show(context, message, AppIcons.warning, AppColors.error);

  static void success(BuildContext context, String message) =>
      _show(context, message, AppIcons.checkCircle, AppColors.success);

  static void info(BuildContext context, String message) =>
      _show(context, message, AppIcons.info, AppColors.info);

  static void _show(BuildContext context, String message, IconData icon, Color color) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  style: context.text.bodyMedium?.copyWith(color: context.palette.textPrimary),
                ),
              ),
            ],
          ),
        ),
      );
  }
}
