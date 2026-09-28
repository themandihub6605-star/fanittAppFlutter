import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/app_spacing.dart';

enum AppButtonVariant { primary, secondary, ghost, danger }

class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.iconWidget,
    this.isLoading = false,
    this.expand = true,
    this.onDark = false,
    this.height = 54,
  });

  const AppButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.iconWidget,
    this.isLoading = false,
    this.expand = true,
    this.onDark = false,
    this.height = 54,
  }) : variant = AppButtonVariant.secondary;

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;

  /// Custom leading widget (e.g. a brand logo image). Takes priority over [icon] when set.
  final Widget? iconWidget;
  final bool isLoading;
  final bool expand;

  /// Use on navy brand backgrounds regardless of the active theme.
  final bool onDark;
  final double height;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.isLoading;

  void _setPressed(bool value) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  _ButtonSpec _spec(AppPalette palette) {
    switch (widget.variant) {
      case AppButtonVariant.primary:
        return const _ButtonSpec(background: AppColors.primary, foreground: Colors.white);
      case AppButtonVariant.secondary:
        return widget.onDark
            ? _ButtonSpec(
          background: Colors.white.withValues(alpha: 0.06),
          foreground: Colors.white,
          border: Colors.white.withValues(alpha: 0.2),
        )
            : _ButtonSpec(background: palette.surface, foreground: palette.textPrimary, border: palette.border);
      case AppButtonVariant.ghost:
        return const _ButtonSpec(background: Colors.transparent, foreground: AppColors.primary);
      case AppButtonVariant.danger:
        return _ButtonSpec(background: AppColors.error.withValues(alpha: 0.08), foreground: AppColors.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = _spec(context.palette);
    final radius = BorderRadius.circular(AppRadius.md);
    final isPrimary = widget.variant == AppButtonVariant.primary;

    final leading = widget.iconWidget ?? (widget.icon != null ? Icon(widget.icon, size: 20, color: spec.foreground) : null);

    final content = AnimatedSwitcher(
      duration: AppDurations.fast,
      child: widget.isLoading
          ? SizedBox(
        key: const ValueKey('loading'),
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          valueColor: AlwaysStoppedAnimation<Color>(spec.foreground),
        ),
      )
          : Row(
        key: const ValueKey('content'),
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            SizedBox(width: 20, height: 20, child: leading),
            const SizedBox(width: AppSpacing.xs + 2),
          ],
          Flexible(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelLarge?.copyWith(color: spec.foreground),
            ),
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      excludeSemantics: true,
      child: Listener(
        onPointerDown: (_) {
          if (_enabled) _setPressed(true);
        },
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: AnimatedScale(
          scale: _pressed ? 0.975 : 1,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: widget.onPressed == null && !widget.isLoading ? 0.45 : 1,
            duration: AppDurations.normal,
            child: SizedBox(
              height: widget.height,
              width: widget.expand ? double.infinity : null,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _pressed && isPrimary ? AppColors.primaryPressed : spec.background,
                  borderRadius: radius,
                  border: spec.border == null ? null : Border.all(color: spec.border!),
                  boxShadow: isPrimary && _enabled
                      ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.24),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                      : null,
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: radius,
                    splashColor: spec.foreground.withValues(alpha: 0.08),
                    onTap: _enabled
                        ? () {
                      HapticFeedback.lightImpact();
                      widget.onPressed!();
                    }
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      child: Center(child: content),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ButtonSpec {
  const _ButtonSpec({required this.background, required this.foreground, this.border});

  final Color background;
  final Color foreground;
  final Color? border;
}