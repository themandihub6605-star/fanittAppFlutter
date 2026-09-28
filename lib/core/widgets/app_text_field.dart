import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_icons.dart';
import '../theme/app_palette.dart';
import '../theme/app_spacing.dart';

class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.helperText,
    this.prefixIcon,
    this.isPassword = false,
    this.validator,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.onSubmitted,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.enabled = true,
    this.autofocus = false,
    this.minLines,
    this.maxLines = 1,
    this.maxLength,
    this.onChanged,
    this.suffixText,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? helperText;
  final IconData? prefixIcon;
  final bool isPassword;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final bool enabled;
  final bool autofocus;
  final int? minLines;
  final int? maxLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final String? suffixText;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.label, style: context.text.labelMedium?.copyWith(color: palette.textPrimary)),
        const SizedBox(height: AppSpacing.xs),
        TextFormField(
          controller: widget.controller,
          validator: widget.validator,
          enabled: widget.enabled,
          autofocus: widget.autofocus,
          obscureText: widget.isPassword && _obscured,
          enableSuggestions: !widget.isPassword,
          autocorrect: false,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          autofillHints: widget.autofillHints,
          onFieldSubmitted: widget.onSubmitted,
          textCapitalization: widget.textCapitalization,
          inputFormatters: widget.inputFormatters,
          minLines: widget.isPassword ? 1 : widget.minLines,
          maxLines: widget.isPassword ? 1 : widget.maxLines,
          maxLength: widget.maxLength,
          onChanged: widget.onChanged,
          keyboardAppearance: context.isDark ? Brightness.dark : Brightness.light,
          style: context.text.bodyLarge?.copyWith(fontSize: 15, color: palette.textPrimary),
          decoration: InputDecoration(
            hintText: widget.hint,
            helperText: widget.helperText,
            suffixText: widget.suffixText,
            alignLabelWithHint: true,
            prefixIcon: widget.prefixIcon == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(left: 14, right: 10),
                    child: Icon(widget.prefixIcon, size: 20),
                  ),
            prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            suffixIcon: widget.isPassword
                ? IconButton(
                    tooltip: _obscured ? 'Show password' : 'Hide password',
                    onPressed: () => setState(() => _obscured = !_obscured),
                    icon: AnimatedSwitcher(
                      duration: AppDurations.fast,
                      child: Icon(
                        _obscured ? AppIcons.eye : AppIcons.eyeOff,
                        key: ValueKey(_obscured),
                        size: 20,
                      ),
                    ),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}
