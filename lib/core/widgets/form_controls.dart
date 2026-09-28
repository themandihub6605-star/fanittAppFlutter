import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_palette.dart';
import '../theme/app_spacing.dart';

/// Label shown above custom form controls, matching AppTextField.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(text, style: context.text.labelMedium)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Horizontal single- or multi-select pills.
class ChoicePills<T> extends StatelessWidget {
  const ChoicePills({
    super.key,
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    this.scrollable = false,
  });

  final List<T> options;
  final Set<T> selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final pills = [
      for (final option in options) _Pill(label: labelOf(option), selected: selected.contains(option), onTap: () => onChanged(option)),
    ];
    if (scrollable) {
      return SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: AppSpacing.screen,
          itemCount: pills.length,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
          itemBuilder: (_, index) => pills[index],
        ),
      );
    }
    return Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: pills);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AnimatedContainer(
      duration: AppDurations.fast,
      decoration: BoxDecoration(
        color: selected ? AppColors.primary : palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: selected ? AppColors.primary : palette.border),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Text(
              label,
              style: context.text.labelMedium?.copyWith(color: selected ? Colors.white : palette.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}

/// Free-text list entry (skills, do's and don'ts, categories).
class TagInput extends StatefulWidget {
  const TagInput({
    super.key,
    required this.label,
    required this.values,
    required this.onChanged,
    this.hint = 'Type and press add',
    this.maxItems = 20,
  });

  final String label;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final String hint;
  final int maxItems;

  @override
  State<TagInput> createState() => _TagInputState();
}

class _TagInputState extends State<TagInput> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final value = _controller.text.trim();
    if (value.isEmpty || widget.values.contains(value) || widget.values.length >= widget.maxItems) return;
    widget.onChanged([...widget.values, value]);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(widget.label),
        TextField(
          controller: _controller,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _add(),
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: widget.hint,
            suffixIcon: IconButton(tooltip: 'Add', icon: const Icon(AppIcons.plus, color: AppColors.primary), onPressed: _add),
          ),
        ),
        if (widget.values.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final value in widget.values)
                Container(
                  padding: const EdgeInsets.only(left: 12, right: 4),
                  decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(child: Text(value, style: context.text.labelMedium)),
                      IconButton(
                        tooltip: 'Remove',
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        icon: Icon(AppIcons.close, color: palette.textSecondary),
                        onPressed: () => widget.onChanged(widget.values.where((v) => v != value).toList()),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// − value + control for small counts.
class CounterField extends StatelessWidget {
  const CounterField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 99,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget button(IconData icon, bool enabled, int next) => IconButton(
          onPressed: enabled
              ? () {
                  HapticFeedback.selectionClick();
                  onChanged(next);
                }
              : null,
          icon: Icon(icon, size: 18),
          style: IconButton.styleFrom(
            backgroundColor: palette.surfaceMuted,
            disabledBackgroundColor: palette.surfaceMuted.withValues(alpha: 0.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
          ),
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: context.text.titleSmall)),
          button(AppIcons.minus, value > min, value - 1),
          SizedBox(
            width: 40,
            child: Text('$value', textAlign: TextAlign.center, style: context.text.titleMedium),
          ),
          button(AppIcons.plus, value < max, value + 1),
        ],
      ),
    );
  }
}

/// Dropdown styled like AppTextField.
class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    super.key,
    required this.label,
    required this.items,
    required this.value,
    required this.labelOf,
    required this.onChanged,
    this.hint = 'Select',
    this.validator,
  });

  final String label;
  final List<T> items;
  final T? value;
  final String Function(T) labelOf;
  final ValueChanged<T?> onChanged;
  final String hint;
  final FormFieldValidator<T>? validator;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label),
        DropdownButtonFormField<T>(
          value: items.contains(value) ? value : null,
          isExpanded: true,
          validator: validator,
          hint: Text(hint),
          icon: const Icon(AppIcons.caretDown, size: 18),
          borderRadius: BorderRadius.circular(AppRadius.md),
          dropdownColor: context.palette.surface,
          items: [
            for (final item in items)
              DropdownMenuItem<T>(value: item, child: Text(labelOf(item), overflow: TextOverflow.ellipsis)),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}
