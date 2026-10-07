import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../data/store_repository.dart';
import '../widgets/store_checkout.dart';

/// Send a FanBox (tip) to a creator from anywhere: store page, live, profile.
Future<void> showFanBoxSheet(
  BuildContext context, {
  String? storeId,
  String? creatorId,
  required String creatorName,
  FanBoxConfig? config,
  String sentFrom = 'store',
}) async {
  final cfg = config ?? await _loadConfig(context);
  if (cfg == null || !context.mounted) return;
  final pick = await showAppSheet<({int amount, String message})>(context, builder: (_) => _FanBoxSheet(name: creatorName, config: cfg));
  if (pick == null || !context.mounted) return;

  final order = await payForStoreItem(
    context,
    amount: pick.amount,
    title: 'FanBox for $creatorName',
    start: (payWith) => sl<StoreRepository>().sendFanBox(
      storeId: storeId,
      creatorId: creatorId,
      amount: pick.amount,
      message: pick.message,
      context: sentFrom,
      payWith: payWith,
    ),
  );
  if (order == null || !context.mounted) return;
  HapticFeedback.heavyImpact();
  await showAppSheet<void>(
    context,
    builder: (ctx) => SheetBody(
      title: 'FanBox sent 🎁',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(AppIcons.gift, size: 72, color: AppColors.primary)
              .animate()
              .scale(begin: const Offset(0.2, 0.2), duration: 500.ms, curve: Curves.elasticOut)
              .then()
              .shake(hz: 3, duration: 400.ms),
          const SizedBox(height: AppSpacing.md),
          Text('${Fmt.money(pick.amount)} is on its way to $creatorName. Thank you for supporting creators!', textAlign: TextAlign.center, style: ctx.text.bodyMedium),
          const SizedBox(height: AppSpacing.lg),
          AppButton(label: 'Done', onPressed: () => Navigator.of(ctx).pop()),
        ],
      ),
    ),
  );
}

Future<FanBoxConfig?> _loadConfig(BuildContext context) async {
  try {
    return await sl<StoreRepository>().fanboxConfig();
  } catch (_) {
    if (context.mounted) AppSnackbar.error(context, 'Could not open FanBox — try again');
    return null;
  }
}

class _FanBoxSheet extends StatefulWidget {
  const _FanBoxSheet({required this.name, required this.config});

  final String name;
  final FanBoxConfig config;

  @override
  State<_FanBoxSheet> createState() => _FanBoxSheetState();
}

class _FanBoxSheetState extends State<_FanBoxSheet> {
  late int? _amount = widget.config.presets.length > 1 ? widget.config.presets[1] : widget.config.presets.first;
  final _custom = TextEditingController();
  final _message = TextEditingController();
  bool _useCustom = false;

  @override
  void dispose() {
    _custom.dispose();
    _message.dispose();
    super.dispose();
  }

  int? get _value => _useCustom ? Fmt.rupeesToPaise(_custom.text) : _amount;

  void _send() {
    final v = _value;
    final cfg = widget.config;
    if (v == null || v < cfg.minAmount || v > cfg.maxAmount) {
      AppSnackbar.error(context, 'Choose between ${Fmt.money(cfg.minAmount)} and ${Fmt.money(cfg.maxAmount)}');
      return;
    }
    Navigator.of(context).pop((amount: v, message: _message.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SheetBody(
      title: 'Send a FanBox',
      subtitle: 'Support ${widget.name} — no strings attached',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final p in widget.config.presets)
                ChoiceChip(
                  label: Text(Fmt.money(p)),
                  selected: !_useCustom && _amount == p,
                  selectedColor: AppColors.primary.withValues(alpha: 0.2),
                  onSelected: (_) => setState(() {
                    _useCustom = false;
                    _amount = p;
                  }),
                ),
              ChoiceChip(
                label: const Text('Custom'),
                selected: _useCustom,
                selectedColor: AppColors.primary.withValues(alpha: 0.2),
                onSelected: (_) => setState(() => _useCustom = true),
              ),
            ],
          ),
          if (_useCustom) ...[
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _custom,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: 'Amount in ₹', prefixIcon: Icon(AppIcons.rupee, size: 18)),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          TextField(controller: _message, maxLength: 200, maxLines: 2, decoration: const InputDecoration(hintText: 'Add a message (optional)')),
          const SizedBox(height: AppSpacing.xs),
          Text('Fanitt keeps ${widget.config.feePercent.toStringAsFixed(widget.config.feePercent % 1 == 0 ? 0 : 1)}% · the rest goes to ${widget.name}', style: context.text.bodySmall?.copyWith(color: palette.textTertiary)),
          const SizedBox(height: AppSpacing.md),
          AppButton(label: _value == null ? 'Send FanBox' : 'Send ${Fmt.money(_value!)}', icon: AppIcons.gift, onPressed: _send),
        ],
      ),
    );
  }
}
