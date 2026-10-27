import 'bill.dart';
import 'category.dart';

/// Stored at donors/{uid}.preferences. Mirrors the server's visibleInFeed().
class DonorPreferences {
  final Set<String> includedCategoryIds;
  final Set<String> excludedCategoryIds;
  final bool showDiscretionary;
  final bool showDebtAndTax;
  final bool allowRestrictedCategories;

  const DonorPreferences({
    this.includedCategoryIds = const {},
    this.excludedCategoryIds = const {},
    this.showDiscretionary = false,
    this.showDebtAndTax = false,
    this.allowRestrictedCategories = false,
  });

  DonorPreferences copyWith({
    Set<String>? includedCategoryIds,
    Set<String>? excludedCategoryIds,
    bool? showDiscretionary,
    bool? showDebtAndTax,
    bool? allowRestrictedCategories,
  }) =>
      DonorPreferences(
        includedCategoryIds: includedCategoryIds ?? this.includedCategoryIds,
        excludedCategoryIds: excludedCategoryIds ?? this.excludedCategoryIds,
        showDiscretionary: showDiscretionary ?? this.showDiscretionary,
        showDebtAndTax: showDebtAndTax ?? this.showDebtAndTax,
        allowRestrictedCategories: allowRestrictedCategories ?? this.allowRestrictedCategories,
      );

  bool allows(BillCategory c) {
    final ids = {c.categoryId, c.rootId};
    if (excludedCategoryIds.any(ids.contains)) return false;
    if (includedCategoryIds.isNotEmpty && !includedCategoryIds.any(ids.contains)) return false;
    return switch (c.classification) {
      Classification.restricted => allowRestrictedCategories,
      Classification.discretionary || Classification.luxury => showDiscretionary,
      Classification.debt || Classification.tax => showDebtAndTax,
      Classification.essential => true,
    };
  }

  factory DonorPreferences.fromMap(Map<String, dynamic>? m) => m == null
      ? const DonorPreferences()
      : DonorPreferences(
          includedCategoryIds: Set<String>.from(m['includedCategoryIds'] ?? const []),
          excludedCategoryIds: Set<String>.from(m['excludedCategoryIds'] ?? const []),
          showDiscretionary: (m['showDiscretionary'] ?? false) as bool,
          showDebtAndTax: (m['showDebtAndTax'] ?? false) as bool,
          allowRestrictedCategories: (m['allowRestrictedCategories'] ?? false) as bool,
        );

  Map<String, dynamic> toMap() => {
        'includedCategoryIds': includedCategoryIds.toList(),
        'excludedCategoryIds': excludedCategoryIds.toList(),
        'showDiscretionary': showDiscretionary,
        'showDebtAndTax': showDebtAndTax,
        'allowRestrictedCategories': allowRestrictedCategories,
      };
}

/// Transient swipe-feed filters (not persisted).
class BillFilters {
  final Set<String> categoryIds;
  final double? minAmount;
  final double? maxAmount;
  final String? city;
  final Set<Urgency> urgencies;
  final bool verifiedOnly;

  const BillFilters({
    this.categoryIds = const {},
    this.minAmount,
    this.maxAmount,
    this.city,
    this.urgencies = const {},
    this.verifiedOnly = true,
  });

  int get activeCount =>
      (categoryIds.isNotEmpty ? 1 : 0) +
      (minAmount != null || maxAmount != null ? 1 : 0) +
      (city != null ? 1 : 0) +
      (urgencies.isNotEmpty ? 1 : 0) +
      (verifiedOnly ? 0 : 1);

  bool matches(Bill b, BillCategory? c) {
    if (categoryIds.isNotEmpty && !categoryIds.contains(b.categoryId) && !categoryIds.contains(b.subcategoryId))
      return false;
    if (minAmount != null && b.remainingAmount < minAmount!) return false;
    if (maxAmount != null && b.remainingAmount > maxAmount!) return false;
    if (city != null && city!.isNotEmpty && b.city?.toLowerCase() != city!.toLowerCase()) return false;
    if (urgencies.isNotEmpty && !urgencies.contains(b.urgency)) return false;
    if (verifiedOnly && b.verificationStatus != VerificationStatus.verified) return false;
    return true;
  }
}
