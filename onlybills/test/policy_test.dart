import 'package:flutter_test/flutter_test.dart';
import 'package:onlybills/models/bill.dart';
import 'package:onlybills/models/category.dart';
import 'package:onlybills/models/preferences.dart';
import 'package:onlybills/services/receipt_scanner.dart';
import 'package:onlybills/services/redaction.dart';

BillCategory cat(String id, Classification c, {String? parent}) =>
    BillCategory(categoryId: id, categoryName: id, parentCategoryId: parent, classification: c);

void main() {
  group('DonorPreferences', () {
    final school = cat('education.school_fees', Classification.essential, parent: 'education');
    final beer = cat('restricted_recreational.beer', Classification.restricted, parent: 'restricted_recreational');
    final cafe = cat('food.cafes', Classification.discretionary, parent: 'food');

    test('defaults show essentials only', () {
      const p = DonorPreferences();
      expect(p.allows(school), isTrue);
      expect(p.allows(beer), isFalse);
      expect(p.allows(cafe), isFalse);
    });

    test('excluding a main category hides its subcategories', () {
      expect(const DonorPreferences(excludedCategoryIds: {'education'}).allows(school), isFalse);
    });

    test('include list narrows the feed', () {
      const p = DonorPreferences(includedCategoryIds: {'healthcare'});
      expect(p.allows(school), isFalse);
    });
  });

  test('CategoryTree search matches subcategory and parent names', () {
    final tree = CategoryTree([
      cat('healthcare', Classification.essential),
      cat('healthcare.x_rays_mri_ct_scans', Classification.essential, parent: 'healthcare')
          .copyName('X-rays, MRI, CT Scans'),
    ]);
    expect(tree.search('mri', 'en').single.categoryId, 'healthcare.x_rays_mri_ct_scans');
  });

  test('filters', () {
    final b = Bill(
      billId: '1', userId: 'u', merchantName: 'm', categoryId: 'health', amount: 1000, remainingAmount: 400,
      verificationStatus: VerificationStatus.verified, city: 'Pune', urgency: Urgency.high, createdAt: DateTime(2026),
    );
    expect(const BillFilters(maxAmount: 500).matches(b, null), isTrue);
    expect(const BillFilters(minAmount: 500).matches(b, null), isFalse);
    expect(const BillFilters(city: 'pune').matches(b, null), isTrue);
    expect(const BillFilters(urgencies: {Urgency.critical}).matches(b, null), isFalse);
  });

  test('receipt parsing extracts merchant, total, date and suggests category', () {
    final s = ReceiptScanner.parse([
      'TAX INVOICE',
      'MedPlus Pharmacy',
      'Ph: 9876543210',
      'Date: 12/10/2026',
      'Insulin Glargine   1,850.00',
      'Test strips          550.00',
      'Grand Total ₹ 2,400.00',
    ]);
    expect(s.merchantName, 'MedPlus Pharmacy');
    expect(s.total, 2400);
    expect(s.date, DateTime(2026, 10, 12));
    expect(s.suggestedCategoryId, 'healthcare');
    expect(s.lineItemTotals, [1850, 550]);
    expect(s.redactedText.contains('9876543210'), isFalse);
  });

  test('whole-word keyword matching', () {
    expect(ReceiptScanner.suggestCategory('Sunrise Public School', '').categoryId, 'education');
    expect(ReceiptScanner.suggestCategory('City Wine & Liquor Store', '').categoryId, 'restricted_recreational');
  });

  test('redaction', () {
    final r = Redactor.redact('UHID: 445-221 PAN ABCDE1234F card 4111 1111 1111 1111');
    expect(r, isNot(contains('445-221')));
    expect(r, isNot(contains('ABCDE1234F')));
    expect(r, isNot(contains('4111')));
  });
}

extension on BillCategory {
  BillCategory copyName(String name) => BillCategory.fromMap({...toMap(), 'categoryName': name});
}
