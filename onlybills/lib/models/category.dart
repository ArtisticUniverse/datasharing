enum FundingEligibility { eligible, review, restricted }

enum Classification { essential, discretionary, luxury, restricted, debt, tax }

T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) =>
    values.firstWhere((v) => v.name == name, orElse: () => fallback);

class BillCategory {
  final String categoryId;
  final String categoryName;
  final Map<String, String> localizedNames;
  final String? parentCategoryId;
  final String description;
  final String icon;
  final bool isActive;
  final bool requiresAgeVerification;
  final bool requiresManualReview;
  final FundingEligibility fundingEligibility;
  final Classification classification;
  final int displayOrder;

  const BillCategory({
    required this.categoryId,
    required this.categoryName,
    this.localizedNames = const {},
    this.parentCategoryId,
    this.description = '',
    this.icon = 'more_horiz',
    this.isActive = true,
    this.requiresAgeVerification = false,
    this.requiresManualReview = false,
    this.fundingEligibility = FundingEligibility.eligible,
    this.classification = Classification.essential,
    this.displayOrder = 0,
  });

  bool get isRoot => parentCategoryId == null;
  String get rootId => parentCategoryId ?? categoryId;

  /// Falls back to English, then to the canonical name, so new languages
  /// (hi, ta, bn, ...) can be added in Firestore without an app release.
  String displayName(String languageCode) => localizedNames[languageCode] ?? localizedNames['en'] ?? categoryName;

  factory BillCategory.fromMap(Map<String, dynamic> m) => BillCategory(
        categoryId: m['categoryId'] as String,
        categoryName: m['categoryName'] as String,
        localizedNames: Map<String, String>.from(m['localizedNames'] ?? const {}),
        parentCategoryId: m['parentCategoryId'] as String?,
        description: (m['description'] ?? '') as String,
        icon: (m['icon'] ?? 'more_horiz') as String,
        isActive: (m['isActive'] ?? true) as bool,
        requiresAgeVerification: (m['requiresAgeVerification'] ?? false) as bool,
        requiresManualReview: (m['requiresManualReview'] ?? false) as bool,
        fundingEligibility:
            _enumByName(FundingEligibility.values, m['fundingEligibility'] as String?, FundingEligibility.review),
        classification: _enumByName(Classification.values, m['classification'] as String?, Classification.essential),
        displayOrder: (m['displayOrder'] ?? 0) as int,
      );

  Map<String, dynamic> toMap() => {
        'categoryId': categoryId,
        'categoryName': categoryName,
        'localizedNames': localizedNames,
        'parentCategoryId': parentCategoryId,
        'description': description,
        'icon': icon,
        'isActive': isActive,
        'requiresAgeVerification': requiresAgeVerification,
        'requiresManualReview': requiresManualReview,
        'fundingEligibility': fundingEligibility.name,
        'classification': classification.name,
        'displayOrder': displayOrder,
      };
}

/// In-memory index over the backend category list.
class CategoryTree {
  final Map<String, BillCategory> byId;
  CategoryTree(Iterable<BillCategory> all) : byId = {for (final c in all) c.categoryId: c};

  List<BillCategory> get roots => _sorted(byId.values.where((c) => c.isRoot && c.isActive));
  List<BillCategory> childrenOf(String id) => _sorted(byId.values.where((c) => c.parentCategoryId == id && c.isActive));
  BillCategory? operator [](String? id) => id == null ? null : byId[id];

  List<BillCategory> search(String query, String lang) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return roots;
    return byId.values.where((c) {
      if (!c.isActive) return false;
      final parent = byId[c.parentCategoryId];
      return c.displayName(lang).toLowerCase().contains(q) ||
          c.categoryName.toLowerCase().contains(q) ||
          (parent?.displayName(lang).toLowerCase().contains(q) ?? false);
    }).toList()
      ..sort((a, b) => a.displayName(lang).compareTo(b.displayName(lang)));
  }

  static List<BillCategory> _sorted(Iterable<BillCategory> it) =>
      it.toList()..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
}
