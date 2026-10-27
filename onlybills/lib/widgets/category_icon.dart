import 'package:flutter/material.dart';

import '../models/category.dart';

/// Backend stores icon names so admins can change them; unknown names fall back.
const _icons = <String, IconData>{
  'local_hospital': Icons.local_hospital,
  'restaurant': Icons.restaurant,
  'no_drinks': Icons.no_drinks,
  'local_drink': Icons.local_drink,
  'school': Icons.school,
  'home': Icons.home,
  'directions_bus': Icons.directions_bus,
  'family_restroom': Icons.family_restroom,
  'work': Icons.work,
  'account_balance': Icons.account_balance,
  'smartphone': Icons.smartphone,
  'sports_soccer': Icons.sports_soccer,
  'celebration': Icons.celebration,
  'volunteer_activism': Icons.volunteer_activism,
  'gavel': Icons.gavel,
  'pets': Icons.pets,
  'hotel': Icons.hotel,
  'shopping_bag': Icons.shopping_bag,
  'more_horiz': Icons.more_horiz,
};

IconData categoryIcon(String? name) => _icons[name] ?? Icons.receipt_long;

Color eligibilityColor(FundingEligibility e, ColorScheme cs) => switch (e) {
      FundingEligibility.eligible => Colors.green.shade700,
      FundingEligibility.review => Colors.orange.shade800,
      FundingEligibility.restricted => cs.error,
    };

String eligibilityLabel(FundingEligibility e) => switch (e) {
      FundingEligibility.eligible => 'Eligible',
      FundingEligibility.review => 'Awaiting review',
      FundingEligibility.restricted => 'Restricted',
    };

String classificationLabel(Classification c) => switch (c) {
      Classification.essential => 'Essential',
      Classification.discretionary => 'Discretionary',
      Classification.luxury => 'Luxury',
      Classification.restricted => 'Age-restricted',
      Classification.debt => 'Consumer debt',
      Classification.tax => 'Tax',
    };
