import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/bloc/action_cubit.dart';
import '../../../core/bloc/load_cubit.dart';
import '../../../core/bloc/paged_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/action_scope.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/form_controls.dart';
import '../../../core/widgets/paged_list_view.dart';
import '../../../core/widgets/status_chip.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../data/wallet_repository.dart';

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key, this.title = 'Wallet'});

  final String title;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    final myId = auth is AuthAuthenticated ? auth.user.id : '';
    return BlocProvider(
      create: (_) => LoadCubit<WalletSummary>(() => sl<WalletRepository>().summary(myId)),
      child: _WalletView(title: title),
    );
  }
}

class _WalletView extends StatelessWidget {
  const _WalletView({required this.title});

  final String title;

  Future<void> _withdraw(BuildContext context, int balance) async {
    final message = await showAppSheet<String>(context, builder: (_) => SheetActionScope(child: _WithdrawSheet(balance: balance)));
    if (message != null && context.mounted) {
      AppSnackbar.success(context, message);
      context.read<LoadCubit<WalletSummary>>().refresh();
      context.read<AuthBloc>().add(const AuthRefreshRequested());
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<WalletSummary>>();
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: AsyncView<WalletSummary>(
        state: cubit.state,
        onRetry: cubit.load,
        builder: (wallet) => AppRefresh(
          onRefresh: cubit.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xxl),
            children: [
              _BalanceCard(wallet: wallet, onWithdraw: () => _withdraw(context, wallet.balance)),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(title: 'Recent activity', actionLabel: 'See all', onAction: () => context.push(AppRoutes.transactions)),
              if (wallet.recent.isEmpty)
                Text('Payments you receive show up here.', style: context.text.bodyMedium)
              else
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final (index, t) in wallet.recent.indexed) ...[
                        if (index > 0) const Divider(indent: 64),
                        TransactionTile(transaction: t),
                      ],
                    ],
                  ),
                ),
              if (wallet.withdrawals.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xl),
                const SectionHeader(title: 'Withdrawals'),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final (index, w) in wallet.withdrawals.indexed) ...[
                        if (index > 0) const Divider(indent: 64),
                        _WithdrawalTile(withdrawal: w),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.wallet, required this.onWithdraw});

  final WalletSummary wallet;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.navy, AppColors.navyRaised],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Available balance', style: context.text.bodyMedium?.copyWith(color: Colors.white70)),
          const SizedBox(height: AppSpacing.xs),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: wallet.balance.toDouble()),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => Text(
              Fmt.money(value.round()),
              style: context.text.displaySmall?.copyWith(color: Colors.white),
            ),
          ),
          if (wallet.pendingWithdrawals > 0) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              '${Fmt.money(wallet.pendingWithdrawals)} on its way to your account',
              style: context.text.bodySmall?.copyWith(color: AppColors.sunrise),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: 'Withdraw',
            icon: AppIcons.bank,
            onPressed: wallet.balance >= 100 ? onWithdraw : null,
          ),
        ],
      ),
    );
  }
}

class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.transaction});

  final WalletTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final t = transaction;
    final color = t.isCredit ? AppColors.success : palette.textPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: (t.isCredit ? AppColors.success : palette.textSecondary).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(t.isCredit ? AppIcons.arrowDownLeft : AppIcons.arrowUpRight, size: 18, color: t.isCredit ? AppColors.success : palette.textSecondary),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.title, style: context.text.titleSmall),
                Text(
                  '${Fmt.dateTime(t.createdAt)}${t.status == 'success' || t.status == 'released' ? '' : ' · ${Fmt.titleCase(t.status)}'}',
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
          Text('${t.isCredit ? '+' : '−'}${Fmt.money(t.displayAmount)}', style: context.text.titleSmall?.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _WithdrawalTile extends StatelessWidget {
  const _WithdrawalTile({required this.withdrawal});

  final Withdrawal withdrawal;

  @override
  Widget build(BuildContext context) {
    final w = withdrawal;
    final color = switch (w.status) {
      'completed' => AppColors.success,
      'rejected' => AppColors.error,
      _ => AppColors.warning,
    };
    final label = switch (w.status) {
      'completed' => 'Paid',
      'rejected' => 'Rejected',
      'processing' => 'Processing',
      _ => 'Requested',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(AppIcons.bank, size: 18, color: color),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('To ${w.payoutMethod == 'upi' ? 'UPI' : 'bank account'}', style: context.text.titleSmall),
                Text(
                  w.adminNote.isNotEmpty ? w.adminNote : '${Fmt.date(w.createdAt)} · fee ${Fmt.money(w.platformFee)}',
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(Fmt.money(w.netPayoutAmount), style: context.text.titleSmall),
              const SizedBox(height: 2),
              StatusChip(label: label, color: color),
            ],
          ),
        ],
      ),
    );
  }
}

class _WithdrawSheet extends StatefulWidget {
  const _WithdrawSheet({required this.balance});

  final int balance;

  @override
  State<_WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends State<_WithdrawSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _upi = TextEditingController();
  final _account = TextEditingController();
  final _ifsc = TextEditingController();
  final _holder = TextEditingController();
  String _method = 'upi';
  WithdrawalPreview? _preview;
  Timer? _debounce;

  @override
  void dispose() {
    for (final c in [_amount, _upi, _account, _ifsc, _holder]) {
      c.dispose();
    }
    _debounce?.cancel();
    super.dispose();
  }

  void _onAmountChanged(String value) {
    _debounce?.cancel();
    final paise = Fmt.rupeesToPaise(value);
    if (paise == null || paise <= 0 || paise > widget.balance) {
      setState(() => _preview = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final preview = await sl<WalletRepository>().preview(paise);
        if (mounted) setState(() => _preview = preview);
      } on ApiException {
        if (mounted) setState(() => _preview = null);
      }
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final details = _method == 'upi'
        ? _upi.text.trim()
        : 'Name: ${_holder.text.trim()}, Acc: ${_account.text.trim()}, IFSC: ${_ifsc.text.trim().toUpperCase()}';
    final message = await context.read<ActionCubit>().run(
          'withdraw',
          () => sl<WalletRepository>().withdraw(amount: Fmt.rupeesToPaise(_amount.text)!, method: _method, details: details),
        );
    if (message != null && mounted) Navigator.of(context).pop(message);
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<ActionCubit>().state.isBusy;
    return SheetBody(
      title: 'Withdraw money',
      subtitle: 'Available ${Fmt.money(widget.balance)}. Payouts reach you within 48 hours.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              label: 'Amount',
              controller: _amount,
              prefixIcon: AppIcons.rupee,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              onChanged: _onAmountChanged,
              validator: (v) {
                final paise = Fmt.rupeesToPaise(v ?? '');
                if (paise == null || paise < 100) return 'Enter at least ₹1';
                if (paise > widget.balance) return 'That’s more than your balance';
                return null;
              },
            ),
            AnimatedSize(
              duration: AppDurations.normal,
              child: _preview == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: AppCard(
                        color: context.palette.surfaceMuted,
                        borderColor: Colors.transparent,
                        child: Column(
                          children: [
                            KeyValueRow(label: 'Platform fee (${_preview!.feePercent.toStringAsFixed(_preview!.feePercent % 1 == 0 ? 0 : 1)}%)', value: '−${Fmt.money(_preview!.fee)}'),
                            KeyValueRow(label: 'You receive', value: Fmt.money(_preview!.net), emphasize: true),
                          ],
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const FieldLabel('Send to'),
            ChoicePills<String>(
              options: const ['upi', 'bank'],
              selected: {_method},
              labelOf: (m) => m == 'upi' ? 'UPI' : 'Bank account',
              onChanged: (m) => setState(() => _method = m),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_method == 'upi')
              AppTextField(
                label: 'UPI ID',
                hint: 'name@bank',
                controller: _upi,
                prefixIcon: AppIcons.at,
                keyboardType: TextInputType.emailAddress,
                validator: (v) => RegExp(r'^[\w.\-]{2,}@[a-zA-Z]{2,}$').hasMatch(v?.trim() ?? '') ? null : 'Enter a valid UPI ID',
              )
            else ...[
              AppTextField(
                label: 'Account holder name',
                controller: _holder,
                textCapitalization: TextCapitalization.words,
                validator: (v) => (v?.trim().isEmpty ?? true) ? 'Enter the account holder’s name' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Account number',
                controller: _account,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) => (v?.trim().length ?? 0) < 9 ? 'Enter a valid account number' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'IFSC',
                controller: _ifsc,
                textCapitalization: TextCapitalization.characters,
                validator: (v) => RegExp(r'^[A-Za-z]{4}0[A-Za-z0-9]{6}$').hasMatch(v?.trim() ?? '') ? null : 'Enter a valid IFSC',
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            const InlineActionError(),
            AppButton(label: 'Request withdrawal', isLoading: busy, onPressed: busy ? null : _submit),
          ],
        ),
      ),
    );
  }
}

class TransactionsScreen extends StatelessWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = sl<WalletRepository>();
    return BlocProvider(
      create: (_) => PagedCubit<WalletTransaction>((page) => repo.transactions(page: page)),
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('All activity')),
          body: PagedListView<WalletTransaction>(
            cubit: context.read<PagedCubit<WalletTransaction>>(),
            spacing: 0,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            empty: const MessageView(icon: AppIcons.wallet, title: 'No activity yet'),
            itemBuilder: (context, t) => TransactionTile(transaction: t),
          ),
        ),
      ),
    );
  }
}
