// File: lib/features/billing/presentation/billing_sheets.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../data/billing_repository.dart';

/// Who is agreeing.
enum AgreementParty { creator, brand }

/// Shows the Fanitt agreement for [party] with a tick box.
///
/// Returns true when the user ticked it and tapped continue — or straight
/// away when the admin has agreements turned off. [otherSide] (what the
/// other party already agreed to) is shown above, so each side sees the other's.
Future<bool> confirmAgreement(
  BuildContext context, {
  required AgreementParty party,
  required String actionLabel,
  Agreement? otherSide,
  String? otherSideLabel,
}) async {
  BillingConfig config;
  try {
    config = await BillingRepository.instance().config();
  } on ApiException catch (e) {
    if (context.mounted) AppSnackbar.error(context, e.message);
    return false;
  }
  if (!config.agreementsEnabled) return true;
  final text = party == AgreementParty.creator ? config.creatorAgreement : config.brandAgreement;
  if (text.trim().isEmpty || !context.mounted) return true;
  final ok = await showAppSheet<bool>(
    context,
    builder: (_) => _AgreementSheet(
      party: party,
      text: text,
      actionLabel: actionLabel,
      otherSide: otherSide,
      otherSideLabel: otherSideLabel,
    ),
  );
  return ok ?? false;
}

class _AgreementSheet extends StatefulWidget {
  const _AgreementSheet({required this.party, required this.text, required this.actionLabel, this.otherSide, this.otherSideLabel});

  final AgreementParty party;
  final String text;
  final String actionLabel;
  final Agreement? otherSide;
  final String? otherSideLabel;

  @override
  State<_AgreementSheet> createState() => _AgreementSheetState();
}

class _AgreementSheetState extends State<_AgreementSheet> {
  bool _agreed = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isCreator = widget.party == AgreementParty.creator;
    return SheetBody(
      title: isCreator ? 'Creator agreement' : 'Brand agreement',
      subtitle: 'Please read and accept before you continue. The other side can see what you agreed to.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.otherSide != null) ...[
            Text(widget.otherSideLabel ?? (isCreator ? 'The brand agreed to' : 'The creator agreed to'), style: context.text.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            _AgreementText(text: widget.otherSide!.text, muted: true),
            const SizedBox(height: AppSpacing.lg),
            Text('You agree to', style: context.text.labelLarge),
            const SizedBox(height: AppSpacing.xs),
          ],
          _AgreementText(text: widget.text),
          const SizedBox(height: AppSpacing.md),
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _agreed = !_agreed);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _agreed,
                      activeColor: AppColors.primary,
                      onChanged: (v) => setState(() => _agreed = v ?? false),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'I have read this agreement and I agree to it.',
                      style: context.text.bodyMedium?.copyWith(color: palette.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(label: widget.actionLabel, onPressed: _agreed ? () => Navigator.of(context).pop(true) : null),
        ],
      ),
    );
  }
}

class _AgreementText extends StatelessWidget {
  const _AgreementText({required this.text, this.muted = false});

  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.border),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(
          text,
          style: context.text.bodyMedium?.copyWith(height: 1.5, color: muted ? palette.textSecondary : palette.textPrimary),
        ),
      ),
    );
  }
}

/// Small "✓ Agreed to Fanitt terms · date" row; tap to read the text.
class AgreementNote extends StatelessWidget {
  const AgreementNote({super.key, required this.agreement, required this.label});

  final Agreement agreement;

  /// e.g. "Creator accepted the agreement".
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final when = agreement.acceptedAt == null ? '' : ' · ${Fmt.date(agreement.acceptedAt!)}';
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: () => showAppSheet<void>(
        context,
        builder: (_) => SheetBody(
          title: label,
          subtitle: agreement.acceptedAt == null ? null : 'Accepted on ${Fmt.date(agreement.acceptedAt!)}',
          child: _AgreementText(text: agreement.text),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          children: [
            const Icon(AppIcons.sealCheck, size: 16, color: AppColors.success),
            const SizedBox(width: 6),
            Expanded(
              child: Text('$label$when', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelMedium?.copyWith(color: palette.textSecondary)),
            ),
            Text('View', style: context.text.labelMedium?.copyWith(color: palette.textPrimary, decoration: TextDecoration.underline)),
          ],
        ),
      ),
    );
  }
}

/// Before a brand pays: amount + GST = total. Returns true to continue.
/// Skipped (returns true) when there's no GST on the payment.
Future<bool> confirmGstPayment(
  BuildContext context, {
  required String title,
  required int base,
  required int gstAmount,
  required double gstPercent,
}) async {
  if (gstAmount <= 0) return true;
  final ok = await showAppSheet<bool>(
    context,
    builder: (sheetContext) => SheetBody(
      title: title,
      subtitle: 'GST is added on top. The creator still gets the full amount, and your tax invoice is emailed and saved in Wallet → Invoices.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            color: sheetContext.palette.surfaceMuted,
            borderColor: Colors.transparent,
            child: Column(
              children: [
                KeyValueRow(label: 'Amount', value: Fmt.money(base)),
                KeyValueRow(label: 'GST (${_pct(gstPercent)}%)', value: '+${Fmt.money(gstAmount)}'),
                const Divider(),
                KeyValueRow(label: 'You pay', value: Fmt.money(base + gstAmount), emphasize: true),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(label: 'Pay ${Fmt.money(base + gstAmount)}', onPressed: () => Navigator.of(sheetContext).pop(true)),
        ],
      ),
    ),
  );
  return ok ?? false;
}

String _pct(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 1);
