import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/guards/profile_gate.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/services/payment_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../data/store_repository.dart';

/// Pays for any store item (products now; live tickets, calls and FanBox
/// later). Free items skip straight to `start`. For paid items the buyer
/// picks UPI/card (Razorpay) or their Fanitt wallet.
///
/// Returns the paid order, or null if the buyer backed out.
Future<StoreOrder?> payForStoreItem(
    BuildContext context, {
      required int amount,
      required String title,
      required Future<CheckoutStart> Function(PayWith payWith) start,
    }) async {
  // Creators, brands and agencies need a complete profile to buy.
  if (!await ensureProfileComplete(context)) return null;
  if (!context.mounted) return null;

  PayWith payWith = PayWith.razorpay;
  if (amount > 0) {
    final picked = await showAppSheet<PayWith>(context, builder: (_) => _PayMethodSheet(amount: amount, title: title));
    if (picked == null) return null;
    payWith = picked;
  }
  if (!context.mounted) return null;

  final repo = sl<StoreRepository>();
  try {
    final started = await start(payWith);
    if (started.paid) {
      if (context.mounted) _afterPayment(context);
      return started.order;
    }
    final rzp = started.razorpay;
    if (rzp == null) throw const ApiException('Could not start the payment — please try again');

    final result = await sl<PaymentService>().checkout(
      orderId: rzp.orderId,
      amount: rzp.amount,
      description: rzp.description,
      keyId: rzp.keyId,
      prefill: CheckoutPrefill(name: rzp.prefillName, email: rzp.prefillEmail, contact: rzp.prefillContact),
    );
    final order = await repo.verifyPayment(
      started.order.id,
      razorpayOrderId: result.orderId ?? rzp.orderId,
      paymentId: result.paymentId,
      signature: result.signature,
    );
    if (context.mounted) _afterPayment(context);
    return order;
  } on PaymentCancelled {
    return null;
  } on ApiException catch (error) {
    if (context.mounted) AppSnackbar.error(context, error.displayMessage);
    return null;
  }
}

void _afterPayment(BuildContext context) {
  HapticFeedback.mediumImpact();
  // Wallet balance may have changed.
  context.read<AuthBloc>().add(const AuthRefreshRequested());
}

class _PayMethodSheet extends StatelessWidget {
  const _PayMethodSheet({required this.amount, required this.title});

  final int amount;
  final String title;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final balance = auth is AuthAuthenticated ? auth.user.walletBalance : 0;
    final walletOk = balance >= amount;

    return SheetBody(
      title: 'Pay ${Fmt.money(amount)}',
      subtitle: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MethodTile(
            icon: AppIcons.lightning,
            title: 'UPI, card or netbanking',
            subtitle: 'Secure checkout by Razorpay',
            onTap: () => Navigator.of(context).pop(PayWith.razorpay),
          ),
          const SizedBox(height: AppSpacing.sm),
          _MethodTile(
            icon: AppIcons.wallet,
            title: 'Fanitt wallet',
            subtitle: walletOk ? 'Balance ${Fmt.money(balance)}' : 'Balance ${Fmt.money(balance)} — not enough',
            enabled: walletOk,
            onTap: () => Navigator.of(context).pop(PayWith.wallet),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton.secondary(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({required this.icon, required this.title, required this.subtitle, required this.onTap, this.enabled = true});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(AppRadius.sm)),
                  child: Icon(icon, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.text.titleSmall),
                      Text(subtitle, style: context.text.bodySmall),
                    ],
                  ),
                ),
                Icon(AppIcons.chevronRight, size: 18, color: palette.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}