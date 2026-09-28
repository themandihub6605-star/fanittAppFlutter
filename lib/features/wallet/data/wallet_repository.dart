import 'package:equatable/equatable.dart';

import '../../../core/models/common_models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json.dart';

class WalletTransaction extends Equatable {
  const WalletTransaction({
    required this.id,
    required this.type,
    required this.status,
    required this.amount,
    required this.netAmount,
    required this.isCredit,
    required this.createdAt,
    required this.notes,
  });

  factory WalletTransaction.fromJson(Map<String, dynamic> json, {String? myUserId}) {
    final direction = J.strOrNull(json, 'direction');
    final toId = J.refId(json, 'to');
    return WalletTransaction(
      id: J.id(json),
      type: J.str(json, 'type'),
      status: J.str(json, 'status'),
      amount: J.integer(json, 'amount'),
      netAmount: J.integer(json, 'netAmount'),
      isCredit: direction != null ? direction == 'credit' : (myUserId != null && toId == myUserId),
      createdAt: J.date(json, 'createdAt') ?? DateTime.now(),
      notes: J.str(json, 'notes'),
    );
  }

  final String id;
  final String type;
  final String status;
  final int amount;
  final int netAmount;
  final bool isCredit;
  final DateTime createdAt;
  final String notes;

  /// What the user actually received or paid.
  int get displayAmount => isCredit && netAmount > 0 ? netAmount : amount;

  String get title => switch (type) {
        'session_payment' => 'Session booking',
        'donation' => 'Live session tip',
        'gift' => 'FanBox gift',
        'campaign_escrow_deposit' => 'Milestone funded',
        'campaign_payout' => 'Campaign payment',
        'referral_commission' => 'Referral commission',
        'subscription_payment' => 'Plan subscription',
        'extra_proposal_fee' => 'Extra proposal',
        'refund' => 'Refund',
        _ => Fmt.titleCase(type),
      };

  @override
  List<Object?> get props => [id, status];
}

class Withdrawal extends Equatable {
  const Withdrawal({
    required this.id,
    required this.amount,
    required this.platformFee,
    required this.netPayoutAmount,
    required this.payoutMethod,
    required this.status,
    required this.createdAt,
    required this.adminNote,
  });

  factory Withdrawal.fromJson(Map<String, dynamic> json) => Withdrawal(
        id: J.id(json),
        amount: J.integer(json, 'amount'),
        platformFee: J.integer(json, 'platformFee'),
        netPayoutAmount: J.integer(json, 'netPayoutAmount'),
        payoutMethod: J.str(json, 'payoutMethod'),
        status: J.str(json, 'status'),
        createdAt: J.date(json, 'createdAt') ?? DateTime.now(),
        adminNote: J.str(json, 'adminNote'),
      );

  final String id;
  final int amount;
  final int platformFee;
  final int netPayoutAmount;
  final String payoutMethod;
  final String status;
  final DateTime createdAt;
  final String adminNote;

  @override
  List<Object?> get props => [id, status];
}

class WithdrawalPreview {
  const WithdrawalPreview({required this.amount, required this.feePercent, required this.fee, required this.net});

  factory WithdrawalPreview.fromJson(Map<String, dynamic> json) => WithdrawalPreview(
        amount: J.integer(json, 'amount'),
        feePercent: J.dbl(json, 'platformFeePercent'),
        fee: J.integer(json, 'platformFee'),
        net: J.integer(json, 'netPayoutAmount'),
      );

  final int amount;
  final double feePercent;
  final int fee;
  final int net;
}

class WalletSummary {
  const WalletSummary({required this.balance, required this.recent, required this.withdrawals});

  final int balance;
  final List<WalletTransaction> recent;
  final List<Withdrawal> withdrawals;

  int get pendingWithdrawals => withdrawals
      .where((w) => w.status == 'initiated' || w.status == 'processing')
      .fold(0, (sum, w) => sum + w.amount);
}

class WalletRepository {
  const WalletRepository(this._api);

  final ApiClient _api;

  Future<WalletSummary> summary(String myUserId) async {
    final results = await Future.wait([
      _api.get('/wallet/me', parser: (d) => J.asMap(d)),
      _api.get('/wallet/withdrawals', parser: (d) => J.listOf(d, Withdrawal.fromJson)),
    ]);
    final wallet = results[0].data as Map<String, dynamic>;
    return WalletSummary(
      balance: J.integer(wallet, 'balance'),
      recent: J.list(wallet, 'recentTransactions', (t) => WalletTransaction.fromJson(t, myUserId: myUserId)),
      withdrawals: results[1].data as List<Withdrawal>,
    );
  }

  Future<Paged<WalletTransaction>> transactions({int page = 1}) async =>
      (await _api.get('/wallet/transactions', query: {'page': page, 'limit': 20}, parser: (d) {
        final m = J.asMap(d);
        return Paged(
          items: J.list(m, 'transactions', WalletTransaction.fromJson),
          page: J.integer(m, 'page', 1),
          pages: J.integer(m, 'pages', 1),
          total: J.integer(m, 'total'),
        );
      }))
          .data;

  Future<WithdrawalPreview> preview(int amount) async => (await _api.get(
        '/wallet/withdraw/preview',
        query: {'amount': amount},
        parser: (d) => WithdrawalPreview.fromJson(J.asMap(d)),
      ))
          .data;

  Future<String> withdraw({required int amount, required String method, required String details}) async =>
      (await _api.post(
        '/wallet/withdraw',
        data: {'amount': amount, 'payoutMethod': method, 'payoutDetails': details},
        parser: (_) => null,
      ))
          .message;
}
