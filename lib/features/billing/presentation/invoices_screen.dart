// File: lib/features/billing/presentation/invoices_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/bloc/paged_cubit.dart';
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
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/paged_list_view.dart';
import '../../../core/widgets/status_chip.dart';
import '../data/billing_repository.dart';

/// Wallet → Invoices: every tax invoice Fanitt issued to me — brand payments
/// (campaign / milestone + GST) and the fee on creator withdrawals.
class InvoicesScreen extends StatelessWidget {
  const InvoicesScreen({super.key});

  /// Opened with a plain push, so no router change is needed.
  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const InvoicesScreen()));

  @override
  Widget build(BuildContext context) {
    final repo = BillingRepository.instance();
    return BlocProvider(
      create: (_) => PagedCubit<Invoice>((page) => repo.invoices(page: page)),
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Invoices')),
          body: PagedListView<Invoice>(
            cubit: context.read<PagedCubit<Invoice>>(),
            empty: const MessageView(
              icon: AppIcons.receipt,
              title: 'No invoices yet',
              message: 'Invoices for campaign payments and withdrawal fees show up here.',
            ),
            itemBuilder: (context, invoice) => _InvoiceTile(invoice: invoice),
          ),
        ),
      ),
    );
  }
}

class _InvoiceTile extends StatelessWidget {
  const _InvoiceTile({required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final i = invoice;
    return AppCard(
      onTap: () => showAppSheet<void>(context, builder: (_) => InvoiceSheet(invoice: i)),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.sm)),
            child: Icon(AppIcons.receipt, size: 20, color: palette.textSecondary),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall),
                const SizedBox(height: 2),
                Text('${i.number} · ${Fmt.date(i.createdAt)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(Fmt.money(i.total), style: context.text.titleSmall),
              if (i.isCancelled) ...[const SizedBox(height: 2), const StatusChip(label: 'Cancelled', color: AppColors.error)],
            ],
          ),
        ],
      ),
    );
  }
}

/// Full invoice with an "Email me this invoice" button.
class InvoiceSheet extends StatefulWidget {
  const InvoiceSheet({super.key, required this.invoice});

  final Invoice invoice;

  @override
  State<InvoiceSheet> createState() => _InvoiceSheetState();
}

class _InvoiceSheetState extends State<InvoiceSheet> {
  bool _sending = false;

  Future<void> _email() async {
    setState(() => _sending = true);
    try {
      final message = await BillingRepository.instance().emailInvoice(widget.invoice.id);
      if (mounted) AppSnackbar.success(context, message);
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final i = widget.invoice;
    String pct(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 1);
    return SheetBody(
      title: 'Tax invoice',
      subtitle: '${i.number} · ${Fmt.date(i.createdAt)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i.sellerName, style: context.text.titleMedium),
                if (i.sellerAddress.isNotEmpty) Text(i.sellerAddress, style: context.text.bodySmall),
                if (i.sellerGstin.isNotEmpty) Text('GSTIN: ${i.sellerGstin}', style: context.text.bodySmall),
                const SizedBox(height: AppSpacing.md),
                Text('Billed to', style: context.text.bodySmall),
                Text(i.billedToName, style: context.text.titleSmall),
                if (i.billedToEmail.isNotEmpty) Text(i.billedToEmail, style: context.text.bodySmall),
                const SizedBox(height: AppSpacing.md),
                Text(i.title, style: context.text.titleSmall),
                const Divider(height: AppSpacing.lg),
                for (final line in i.lines) KeyValueRow(label: line.label, value: Fmt.money(line.amount)),
                if (i.gstAmount > 0) KeyValueRow(label: 'GST @ ${pct(i.gstPercent)}%', value: Fmt.money(i.gstAmount)),
                const Divider(),
                KeyValueRow(label: 'Total', value: Fmt.money(i.total), emphasize: true),
                if (i.isWithdrawalFee && i.withdrawalAmount != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Withdrawn ${Fmt.money(i.withdrawalAmount!)} · paid to you ${Fmt.money(i.payoutAmount ?? 0)}',
                    style: context.text.bodySmall?.copyWith(color: palette.textSecondary),
                  ),
                ],
                if (i.paymentId.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text('Payment ID: ${i.paymentId}', style: context.text.bodySmall),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton.secondary(
            label: 'Email me this invoice',
            icon: AppIcons.mail,
            isLoading: _sending,
            onPressed: _sending ? null : _email,
          ),
        ],
      ),
    );
  }
}
