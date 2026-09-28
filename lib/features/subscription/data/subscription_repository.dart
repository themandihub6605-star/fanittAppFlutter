import 'package:equatable/equatable.dart';

import '../../../core/network/api_client.dart';
import '../../../core/services/payment_service.dart';
import '../../../core/utils/json.dart';

class SubscriptionPlan extends Equatable {
  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.appliesTo,
    required this.price,
    required this.isYearly,
    required this.groupSlug,
    required this.isDefault,
    required this.description,
    required this.perks,
    required this.platformFeePercent,
    this.proposalLimit,
    this.campaignPostLimit,
  });

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) => SubscriptionPlan(
        id: J.id(json),
        name: J.str(json, 'name'),
        appliesTo: J.str(json, 'appliesTo'),
        price: J.integer(json, 'price'),
        isYearly: J.str(json, 'billingCycle') == 'yearly',
        groupSlug: J.strOrNull(json, 'billingGroupSlug') ?? J.str(json, 'slug'),
        isDefault: J.boolean(json, 'isDefault'),
        description: J.str(json, 'description'),
        perks: J.strings(json, 'perks'),
        platformFeePercent: J.dbl(json, 'platformFeePercent'),
        proposalLimit: J.integerOrNull(json, 'proposalLimit'),
        campaignPostLimit: J.integerOrNull(json, 'campaignPostLimit'),
      );

  final String id;
  final String name;
  final String appliesTo;
  final int price;
  final bool isYearly;
  final String groupSlug;
  final bool isDefault;
  final String description;
  final List<String> perks;
  final double platformFeePercent;
  final int? proposalLimit;
  final int? campaignPostLimit;

  bool get isFree => price <= 0;

  @override
  List<Object?> get props => [id];
}

class UserSubscription extends Equatable {
  const UserSubscription({
    required this.plan,
    required this.status,
    required this.cancelAtPeriodEnd,
    required this.proposalsUsed,
    required this.campaignsPosted,
    this.periodEnd,
  });

  factory UserSubscription.fromJson(Map<String, dynamic> json) => UserSubscription(
        plan: SubscriptionPlan.fromJson(J.map(json, 'plan') ?? const {}),
        status: J.str(json, 'status'),
        cancelAtPeriodEnd: J.boolean(json, 'cancelAtPeriodEnd'),
        proposalsUsed: J.integer(json, 'proposalsUsedThisCycle'),
        campaignsPosted: J.integer(json, 'campaignsPostedThisCycle'),
        periodEnd: J.date(json, 'currentPeriodEnd'),
      );

  final SubscriptionPlan plan;
  final String status;
  final bool cancelAtPeriodEnd;
  final int proposalsUsed;
  final int campaignsPosted;
  final DateTime? periodEnd;

  @override
  List<Object?> get props => [plan, status, cancelAtPeriodEnd, proposalsUsed, campaignsPosted];
}

class SubscriptionRepository {
  const SubscriptionRepository(this._api, this._payments);

  final ApiClient _api;
  final PaymentService _payments;

  Future<List<SubscriptionPlan>> plans(String appliesTo) async => (await _api.get(
        '/subscriptions/plans',
        query: {'appliesTo': appliesTo},
        parser: (d) => J.listOf(d, SubscriptionPlan.fromJson),
      ))
          .data;

  Future<UserSubscription> mine() async =>
      (await _api.get('/subscriptions/me', parser: (d) => UserSubscription.fromJson(J.asMap(d)))).data;

  /// Creates the Razorpay subscription, opens checkout and activates the plan.
  Future<UserSubscription> subscribe(SubscriptionPlan plan, {CheckoutPrefill prefill = const CheckoutPrefill()}) async {
    final checkout = (await _api.post('/subscriptions/checkout', data: {'planId': plan.id}, parser: (d) => J.asMap(d))).data;
    final subscriptionId = J.str(checkout, 'razorpaySubscriptionId');

    final payment = await _payments.checkout(
      subscriptionId: subscriptionId,
      description: 'Fanitt ${plan.name}',
      keyId: J.strOrNull(checkout, 'razorpayKeyId'),
      prefill: prefill,
    );

    final response = await _api.post(
      '/subscriptions/verify',
      data: {
        'razorpaySubscriptionId': payment.subscriptionId ?? subscriptionId,
        'razorpayPaymentId': payment.paymentId,
        'razorpaySignature': payment.signature,
        'planId': plan.id,
      },
      parser: (d) => UserSubscription.fromJson(J.asMap(d)),
    );
    return response.data;
  }

  Future<UserSubscription> cancel() async =>
      (await _api.post('/subscriptions/cancel', parser: (d) => UserSubscription.fromJson(J.asMap(d)))).data;
}
