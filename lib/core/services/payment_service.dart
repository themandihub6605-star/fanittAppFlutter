import 'dart:async';

import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../config/app_config.dart';
import '../network/api_exception.dart';

class PaymentCancelled implements Exception {
  const PaymentCancelled();
}

class PaymentResult {
  const PaymentResult({required this.paymentId, required this.signature, this.orderId, this.subscriptionId});

  final String paymentId;
  final String signature;
  final String? orderId;
  final String? subscriptionId;
}

class CheckoutPrefill {
  const CheckoutPrefill({this.name, this.email, this.contact});

  final String? name;
  final String? email;
  final String? contact;
}

/// Opens Razorpay Checkout for an order or a subscription and completes
/// with the ids the backend needs to verify the payment.
class PaymentService {
  Future<PaymentResult> checkout({
    String? orderId,
    String? subscriptionId,
    int? amount,
    required String description,
    CheckoutPrefill prefill = const CheckoutPrefill(),
    String? keyId,
  }) {
    assert(orderId != null || subscriptionId != null, 'An order or subscription id is required');
    final key = (keyId?.isNotEmpty ?? false) ? keyId! : AppConfig.razorpayKeyId;
    if (key.isEmpty) {
      return Future.error(const ApiException('Payments are not configured in this build.'));
    }

    final completer = Completer<PaymentResult>();
    final razorpay = Razorpay();

    void finish() => razorpay.clear();

    razorpay
      ..on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse response) {
        if (!completer.isCompleted) {
          completer.complete(
            PaymentResult(
              paymentId: response.paymentId ?? '',
              signature: response.signature ?? '',
              orderId: response.orderId,
              subscriptionId: response.data?['razorpay_subscription_id'] as String? ?? subscriptionId,
            ),
          );
        }
        finish();
      })
      ..on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse response) {
        if (!completer.isCompleted) {
          if (response.code == Razorpay.PAYMENT_CANCELLED) {
            completer.completeError(const PaymentCancelled());
          } else {
            completer.completeError(ApiException(response.message ?? 'Payment failed. No money was taken.'));
          }
        }
        finish();
      })
      ..on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse response) {});

    razorpay.open({
      'key': key,
      if (orderId != null) 'order_id': orderId,
      if (subscriptionId != null) 'subscription_id': subscriptionId,
      if (amount != null) 'amount': amount,
      'currency': 'INR',
      'name': 'Fanitt',
      'description': description,
      'prefill': {
        if (prefill.name != null) 'name': prefill.name,
        if (prefill.email != null) 'email': prefill.email,
        if (prefill.contact != null) 'contact': prefill.contact,
      },
      'theme': {'color': '#F4511E'},
    });

    return completer.future;
  }
}
