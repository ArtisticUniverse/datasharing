import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../models/payment.dart';

/// Opens the provider's checkout UI and reports what the donor did there.
/// The result is only a hint for the UI; the server settles payments from the signed webhook.
abstract class PaymentGateway {
  Future<PaymentStatus> open({
    required String keyId,
    required String orderId,
    required int amountPaise,
    required String method,
    String? email,
  });
}

class RazorpayGateway implements PaymentGateway {
  @override
  Future<PaymentStatus> open({
    required String keyId,
    required String orderId,
    required int amountPaise,
    required String method,
    String? email,
  }) {
    if (kIsWeb) {
      // razorpay_flutter is Android/iOS only. A web build would load Razorpay's checkout.js instead.
      throw UnsupportedError('Live payments are available in the Android app.');
    }
    final rp = Razorpay();
    final done = Completer<PaymentStatus>();
    void finish(PaymentStatus s) {
      if (!done.isCompleted) done.complete(s);
      rp.clear();
    }

    rp.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse _) => finish(PaymentStatus.captured));
    rp.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) =>
        finish(r.code == Razorpay.PAYMENT_CANCELLED ? PaymentStatus.cancelled : PaymentStatus.failed));
    rp.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse _) => finish(PaymentStatus.captured));
    rp.open({
      'key': keyId,
      'order_id': orderId,
      'amount': amountPaise,
      'name': 'OnlyBills',
      'description': 'Bill funding',
      // Opens checkout on the method the donor picked in our sheet; they can still switch.
      'method': method,
      'prefill': {if (email != null) 'email': email, 'method': method},
      'theme': {'color': '#00897B'},
    });
    return done.future;
  }
}

/// Demo-mode gateway: succeeds with the method's expected success rate, so the
/// data pipeline has realistic outcomes to learn from.
class SimulatedGateway {
  final double Function() random;
  SimulatedGateway(this.random);

  Future<PaymentStatus> charge(double expectedSuccess) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    return random() < expectedSuccess ? PaymentStatus.captured : PaymentStatus.failed;
  }
}
