/// A ranked payment option for one donor and one amount (from getCheckout / PaymentEngine).
class PaymentOption {
  final String method;
  final String label;
  final double expectedSuccess;
  final int fee;
  final List<String> reasons;
  final bool recommended;

  const PaymentOption({
    required this.method,
    required this.label,
    required this.expectedSuccess,
    required this.fee,
    required this.reasons,
    this.recommended = false,
  });

  factory PaymentOption.fromMap(Map<String, dynamic> m) => PaymentOption(
        method: m['method'] as String,
        label: m['label'] as String,
        expectedSuccess: (m['expectedSuccess'] as num).toDouble(),
        fee: (m['fee'] as num).round(),
        reasons: List<String>.from(m['reasons'] ?? const []),
        recommended: (m['recommended'] ?? false) as bool,
      );
}

class CheckoutPlan {
  final List<int> amounts;
  final double payRemaining;
  final double defaultAmount;
  final List<PaymentOption> methods;

  const CheckoutPlan({
    required this.amounts,
    required this.payRemaining,
    required this.defaultAmount,
    required this.methods,
  });

  factory CheckoutPlan.fromMap(Map<String, dynamic> m) {
    final a = Map<String, dynamic>.from(m['amounts'] as Map);
    return CheckoutPlan(
      amounts: (a['amounts'] as List).map((e) => (e as num).round()).toList(),
      payRemaining: (a['payRemaining'] as num).toDouble(),
      defaultAmount: (a['defaultAmount'] as num).toDouble(),
      methods: (m['methods'] as List).map((e) => PaymentOption.fromMap(Map<String, dynamic>.from(e as Map))).toList(),
    );
  }
}

enum PaymentStatus { captured, failed, cancelled }

class PaymentResult {
  final PaymentStatus status;
  final double applied;
  final double refundDue;
  final double remainingAmount;
  final String? message;

  const PaymentResult(this.status, {this.applied = 0, this.refundDue = 0, this.remainingAmount = 0, this.message});
}
