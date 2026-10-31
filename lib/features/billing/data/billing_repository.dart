// File: lib/features/billing/data/billing_repository.dart
import 'package:equatable/equatable.dart';

import '../../../core/di/injection.dart';
import '../../../core/models/common_models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';

/// Admin-controlled money rules + agreement texts (GET /billing/config).
class BillingConfig {
  const BillingConfig({
    required this.gstPercent,
    required this.gstOnBrandPayments,
    required this.gstOnWithdrawalFee,
    required this.creatorMinWithdrawal,
    required this.myWithdrawalFeePercent,
    required this.agreementsEnabled,
    required this.creatorAgreement,
    required this.brandAgreement,
  });

  factory BillingConfig.fromJson(Map<String, dynamic> json) => BillingConfig(
        gstPercent: J.dbl(json, 'gstPercent'),
        gstOnBrandPayments: J.boolean(json, 'gstOnBrandPayments'),
        gstOnWithdrawalFee: J.boolean(json, 'gstOnWithdrawalFee'),
        creatorMinWithdrawal: J.integer(json, 'creatorMinWithdrawal', 100000),
        myWithdrawalFeePercent: J.dbl(json, 'myWithdrawalFeePercent'),
        agreementsEnabled: J.boolean(json, 'agreementsEnabled', true),
        creatorAgreement: J.str(json, 'creatorAgreement'),
        brandAgreement: J.str(json, 'brandAgreement'),
      );

  final double gstPercent;
  final bool gstOnBrandPayments;
  final bool gstOnWithdrawalFee;
  final int creatorMinWithdrawal; // paise
  final double myWithdrawalFeePercent;
  final bool agreementsEnabled;
  final String creatorAgreement;
  final String brandAgreement;
}

/// What one side agreed to — the exact text, frozen when they ticked the box.
class Agreement extends Equatable {
  const Agreement({required this.text, required this.version, this.acceptedAt});

  static Agreement? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final text = J.str(json, 'text');
    if (text.isEmpty) return null;
    return Agreement(text: text, version: J.integer(json, 'version'), acceptedAt: J.date(json, 'acceptedAt'));
  }

  final String text;
  final int version;
  final DateTime? acceptedAt;

  @override
  List<Object?> get props => [text, version, acceptedAt];
}

class InvoiceLine {
  const InvoiceLine({required this.label, required this.amount});

  factory InvoiceLine.fromJson(Map<String, dynamic> json) => InvoiceLine(label: J.str(json, 'label'), amount: J.integer(json, 'amount'));

  final String label;
  final int amount;
}

/// A Fanitt tax invoice: a brand payment, or the fee on a creator withdrawal.
class Invoice extends Equatable {
  const Invoice({
    required this.id,
    required this.number,
    required this.kind,
    required this.title,
    required this.billedToName,
    required this.billedToEmail,
    required this.sellerName,
    required this.sellerGstin,
    required this.sellerAddress,
    required this.lines,
    required this.subtotal,
    required this.gstPercent,
    required this.gstAmount,
    required this.total,
    required this.status,
    required this.createdAt,
    this.withdrawalAmount,
    this.payoutAmount,
    this.paymentId = '',
  });

  factory Invoice.fromJson(Map<String, dynamic> json) {
    final billedTo = J.map(json, 'billedTo') ?? const <String, dynamic>{};
    final seller = J.map(json, 'seller') ?? const <String, dynamic>{};
    return Invoice(
      id: J.id(json),
      number: J.str(json, 'number'),
      kind: J.str(json, 'kind'),
      title: J.str(json, 'title'),
      billedToName: J.str(billedTo, 'name'),
      billedToEmail: J.str(billedTo, 'email'),
      sellerName: J.str(seller, 'name', 'Fanitt'),
      sellerGstin: J.str(seller, 'gstin'),
      sellerAddress: J.str(seller, 'address'),
      lines: J.list(json, 'lines', InvoiceLine.fromJson),
      subtotal: J.integer(json, 'subtotal'),
      gstPercent: J.dbl(json, 'gstPercent'),
      gstAmount: J.integer(json, 'gstAmount'),
      total: J.integer(json, 'total'),
      withdrawalAmount: J.integerOrNull(json, 'withdrawalAmount'),
      payoutAmount: J.integerOrNull(json, 'payoutAmount'),
      status: J.str(json, 'status', 'issued'),
      paymentId: J.str(json, 'razorpayPaymentId'),
      createdAt: J.date(json, 'createdAt') ?? DateTime.now(),
    );
  }

  final String id;
  final String number;
  final String kind; // brand_payment | withdrawal_fee
  final String title;
  final String billedToName;
  final String billedToEmail;
  final String sellerName;
  final String sellerGstin;
  final String sellerAddress;
  final List<InvoiceLine> lines;
  final int subtotal;
  final double gstPercent;
  final int gstAmount;
  final int total;
  final int? withdrawalAmount;
  final int? payoutAmount;
  final String status;
  final String paymentId;
  final DateTime createdAt;

  bool get isWithdrawalFee => kind == 'withdrawal_fee';
  bool get isCancelled => status == 'cancelled';

  @override
  List<Object?> get props => [id, status];
}

class BillingRepository {
  const BillingRepository(this._api);

  /// No DI registration needed — uses the app's shared ApiClient.
  factory BillingRepository.instance() => BillingRepository(sl<ApiClient>());

  final ApiClient _api;

  static BillingConfig? _cached;
  static DateTime? _cachedAt;

  /// Cached for a minute so sheets open instantly.
  Future<BillingConfig> config({bool fresh = false}) async {
    final at = _cachedAt;
    if (!fresh && _cached != null && at != null && DateTime.now().difference(at) < const Duration(minutes: 1)) return _cached!;
    final config = (await _api.get('/billing/config', parser: (d) => BillingConfig.fromJson(J.asMap(d)))).data;
    _cached = config;
    _cachedAt = DateTime.now();
    return config;
  }

  Future<Paged<Invoice>> invoices({int page = 1}) async => (await _api.get('/billing/invoices', query: {'page': page, 'limit': 20}, parser: (d) {
        final m = J.asMap(d);
        return Paged(
          items: J.list(m, 'invoices', Invoice.fromJson),
          page: J.integer(m, 'page', 1),
          pages: J.integer(m, 'pages', 1),
          total: J.integer(m, 'total'),
        );
      }))
          .data;

  Future<Invoice> invoice(String id) async => (await _api.get('/billing/invoices/$id', parser: (d) => Invoice.fromJson(J.asMap(d)))).data;

  /// Emails the invoice again; returns the server's message.
  Future<String> emailInvoice(String id) async => (await _api.post('/billing/invoices/$id/email', parser: (_) => null)).message;
}
