import '../models/bill.dart';
import '../models/category.dart';
import '../models/preferences.dart';

class SubmitBillRequest {
  final String merchantName;
  final String categoryId;
  final String? subcategoryId;
  final double amount;
  final String currency;
  final DateTime? billDate;
  final String fundingPurpose;
  final String? city;
  final Urgency urgency;
  final String localImagePath;
  final String? suggestedCategoryId;
  final Map<String, dynamic>? ocr;
  final Map<String, dynamic>? imageMetadata;

  const SubmitBillRequest({
    required this.merchantName,
    required this.categoryId,
    this.subcategoryId,
    required this.amount,
    this.currency = 'INR',
    this.billDate,
    required this.fundingPurpose,
    this.city,
    this.urgency = Urgency.medium,
    required this.localImagePath,
    this.suggestedCategoryId,
    this.ocr,
    this.imageMetadata,
  });
}

class SubmitResult {
  final String billId;
  final VerificationStatus verificationStatus;
  final FundingEligibility fundingEligibility;
  final List<String> flags;
  const SubmitResult(this.billId, this.verificationStatus, this.fundingEligibility, this.flags);
}

class CategoryAnalytics {
  final String categoryId;
  final int uploadedBills;
  final int fullyFundedBills;
  final double requestedAmount;
  final double fundedAmount;
  const CategoryAnalytics(
      this.categoryId, this.uploadedBills, this.fullyFundedBills, this.requestedAmount, this.fundedAmount);
  double get successRate => uploadedBills == 0 ? 0 : fullyFundedBills / uploadedBills;
}

/// Backend abstraction. [FirebaseRepository] talks to Firestore/Functions;
/// [DemoRepository] serves bundled sample data so the app runs without a project.
abstract class Repository {
  bool get isDemo;
  Stream<CategoryTree> watchCategories();
  Stream<List<Bill>> watchFeed();
  Future<DonorPreferences> loadPreferences();
  Future<void> savePreferences(DonorPreferences prefs);
  Future<SubmitResult> submitBill(SubmitBillRequest req);

  /// Returns the remaining amount after funding.
  Future<double> fundBill(String billId, double amount);
  Future<List<CategoryAnalytics>> loadAnalytics();

  // Admin
  Future<void> upsertCategory(BillCategory c);
  Future<void> reorderCategories(List<String> orderedIds);
  Future<void> mergeCategories(String fromId, String intoId);
}
