import 'category.dart';

enum VerificationStatus { verified, pendingReview, rejected }

enum Urgency { low, medium, high, critical }

VerificationStatus _verification(String? s) => switch (s) {
      'verified' => VerificationStatus.verified,
      'rejected' => VerificationStatus.rejected,
      _ => VerificationStatus.pendingReview,
    };

class Bill {
  final String billId;
  final String userId;
  final String merchantName;
  final String categoryId;
  final String? subcategoryId;
  final double amount;
  final String currency;
  final DateTime? billDate;
  final String receiptImageUrl;
  final VerificationStatus verificationStatus;
  final List<String> verificationFlags;
  final String fundingStatus;
  final FundingEligibility fundingEligibility;
  final List<String> eligibilityReasons;
  final double fundedAmount;
  final double remainingAmount;
  final String fundingPurpose;
  final String? city;
  final Urgency urgency;
  final DateTime createdAt;

  const Bill({
    required this.billId,
    required this.userId,
    required this.merchantName,
    required this.categoryId,
    this.subcategoryId,
    required this.amount,
    this.currency = 'INR',
    this.billDate,
    this.receiptImageUrl = '',
    this.verificationStatus = VerificationStatus.pendingReview,
    this.verificationFlags = const [],
    this.fundingStatus = 'open',
    this.fundingEligibility = FundingEligibility.review,
    this.eligibilityReasons = const [],
    this.fundedAmount = 0,
    required this.remainingAmount,
    this.fundingPurpose = '',
    this.city,
    this.urgency = Urgency.medium,
    required this.createdAt,
  });

  String get effectiveCategoryId => subcategoryId ?? categoryId;
  double get progress => amount <= 0 ? 0 : (fundedAmount / amount).clamp(0, 1);

  factory Bill.fromMap(Map<String, dynamic> m) {
    DateTime? date(dynamic v) => switch (v) {
          null => null,
          String s => DateTime.tryParse(s),
          // Firestore Timestamp, without importing cloud_firestore into the model layer.
          _ => (v as dynamic).toDate() as DateTime,
        };
    return Bill(
      billId: m['billId'] as String,
      userId: m['userId'] as String,
      merchantName: (m['merchantName'] ?? '') as String,
      categoryId: m['categoryId'] as String,
      subcategoryId: m['subcategoryId'] as String?,
      amount: (m['amount'] as num).toDouble(),
      currency: (m['currency'] ?? 'INR') as String,
      billDate: date(m['billDate']),
      receiptImageUrl: (m['receiptImageUrl'] ?? '') as String,
      verificationStatus: _verification(m['verificationStatus'] as String?),
      verificationFlags: List<String>.from(m['verificationFlags'] ?? const []),
      fundingStatus: (m['fundingStatus'] ?? 'open') as String,
      fundingEligibility: FundingEligibility.values.firstWhere(
          (e) => e.name == m['fundingEligibility'],
          orElse: () => FundingEligibility.review),
      eligibilityReasons: List<String>.from(m['eligibilityReasons'] ?? const []),
      fundedAmount: ((m['fundedAmount'] ?? 0) as num).toDouble(),
      remainingAmount: ((m['remainingAmount'] ?? m['amount']) as num).toDouble(),
      fundingPurpose: (m['fundingPurpose'] ?? '') as String,
      city: m['city'] as String?,
      urgency: Urgency.values.firstWhere((u) => u.name == m['urgency'], orElse: () => Urgency.medium),
      createdAt: date(m['createdAt']) ?? DateTime.now(),
    );
  }
}
