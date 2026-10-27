import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/bill.dart';
import '../models/category.dart';
import '../models/preferences.dart';
import '../services/receipt_scanner.dart';
import 'repository.dart';

/// Runs fully offline from assets/demo/*.json (generated from the same taxonomy
/// and server rules as production). Submitted and funded bills live in memory.
class DemoRepository implements Repository {
  final _categories = StreamController<CategoryTree>.broadcast();
  final _feed = StreamController<List<Bill>>.broadcast();
  late CategoryTree _tree;
  late List<Map<String, dynamic>> _bills;
  DonorPreferences _prefs = const DonorPreferences();
  final _fingerprints = <String>{};
  bool _loaded = false;

  @override
  bool get isDemo => true;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final cats = jsonDecode(await rootBundle.loadString('assets/demo/categories.json')) as List;
    _tree = CategoryTree(cats.map((m) => BillCategory.fromMap(m as Map<String, dynamic>)));
    _bills = (jsonDecode(await rootBundle.loadString('assets/demo/bills.json')) as List)
        .cast<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();
    for (final b in _bills) {
      _fingerprints.add(_fingerprint(b['merchantName'], b['amount'], b['billDate']));
    }
    _loaded = true;
  }

  String _fingerprint(dynamic merchant, dynamic amount, dynamic date) =>
      '${merchant.toString().trim().toLowerCase()}|${(amount as num).toDouble()}|${date ?? ''}';

  void _emit() {
    _categories.add(_tree);
    _feed.add(_visibleBills());
  }

  List<Bill> _visibleBills() => _bills
      .map(Bill.fromMap)
      .where((b) =>
          b.verificationStatus == VerificationStatus.verified &&
          b.fundingEligibility == FundingEligibility.eligible &&
          b.remainingAmount > 0)
      .toList();

  @override
  Stream<CategoryTree> watchCategories() async* {
    await _ensureLoaded();
    yield _tree;
    yield* _categories.stream;
  }

  @override
  Stream<List<Bill>> watchFeed() async* {
    await _ensureLoaded();
    yield _visibleBills();
    yield* _feed.stream;
  }

  @override
  Future<DonorPreferences> loadPreferences() async => _prefs;

  @override
  Future<void> savePreferences(DonorPreferences prefs) async => _prefs = prefs;

  /// Simplified port of functions/index.js submitBill for offline demos.
  @override
  Future<SubmitResult> submitBill(SubmitBillRequest req) async {
    await _ensureLoaded();
    final cat = _tree[req.subcategoryId ?? req.categoryId]!;
    final flags = <String>[];
    final date = req.billDate?.toIso8601String();
    if (!_fingerprints.add(_fingerprint(req.merchantName, req.amount, date))) flags.add('duplicate_receipt');
    final total = req.ocr?['extractedTotal'] as num?;
    if (total != null && (total - req.amount).abs() > (req.amount * 0.02).clamp(1, double.infinity)) {
      flags.add('amount_mismatch_with_receipt');
    }
    final sw = (req.imageMetadata?['software'] ?? '').toString().toLowerCase();
    if (RegExp('photoshop|gimp|picsart|snapseed|canva|lightroom').hasMatch(sw)) flags.add('possible_edited_image');
    final suggested = ReceiptScanner.suggestCategory(req.merchantName, '').categoryId;
    if (suggested != 'other' && suggested != cat.rootId) flags.add('merchant_category_mismatch');

    final status = flags.contains('duplicate_receipt')
        ? VerificationStatus.rejected
        : (flags.isNotEmpty || cat.requiresManualReview
            ? VerificationStatus.pendingReview
            : VerificationStatus.verified);
    final elig = cat.fundingEligibility == FundingEligibility.restricted || status == VerificationStatus.rejected
        ? FundingEligibility.restricted
        : (status == VerificationStatus.verified && cat.fundingEligibility == FundingEligibility.eligible
            ? FundingEligibility.eligible
            : FundingEligibility.review);
    final id = 'demo_new_${_bills.length + 1}';
    _bills.insert(0, {
      'billId': id,
      'userId': 'demo_me',
      'merchantName': req.merchantName,
      'categoryId': cat.rootId,
      'subcategoryId': cat.isRoot ? null : cat.categoryId,
      'amount': req.amount,
      'currency': req.currency,
      'billDate': date,
      'verificationStatus': switch (status) {
        VerificationStatus.verified => 'verified',
        VerificationStatus.rejected => 'rejected',
        VerificationStatus.pendingReview => 'pending_review',
      },
      'verificationFlags': flags,
      'fundingEligibility': elig.name,
      'fundedAmount': 0,
      'remainingAmount': req.amount,
      'fundingPurpose': req.fundingPurpose,
      'city': req.city,
      'urgency': req.urgency.name,
      'createdAt': DateTime.now().toIso8601String(),
    });
    _emit();
    return SubmitResult(id, status, elig, flags);
  }

  @override
  Future<double> fundBill(String billId, double amount) async {
    final b = _bills.firstWhere((b) => b['billId'] == billId);
    final remaining = (b['remainingAmount'] as num).toDouble();
    final applied = amount.clamp(0, remaining).toDouble();
    b['fundedAmount'] = (b['fundedAmount'] as num).toDouble() + applied;
    b['remainingAmount'] = remaining - applied;
    b['fundingStatus'] = remaining - applied <= 0 ? 'funded' : 'partially_funded';
    _emit();
    return remaining - applied;
  }

  @override
  Future<List<CategoryAnalytics>> loadAnalytics() async {
    await _ensureLoaded();
    final byRoot = <String, List<Map<String, dynamic>>>{};
    for (final b in _bills) {
      byRoot.putIfAbsent(b['categoryId'] as String, () => []).add(b);
    }
    return byRoot.entries
        .map((e) => CategoryAnalytics(
              e.key,
              e.value.length,
              e.value.where((b) => b['fundingStatus'] == 'funded').length,
              e.value.fold(0.0, (s, b) => s + (b['amount'] as num)),
              e.value.fold(0.0, (s, b) => s + (b['fundedAmount'] as num)),
            ))
        .toList();
  }

  BillCategory _replace(BillCategory c, {int? displayOrder, String? parentCategoryId, bool? isActive}) =>
      BillCategory.fromMap({
        ...c.toMap(),
        if (displayOrder != null) 'displayOrder': displayOrder,
        if (parentCategoryId != null) 'parentCategoryId': parentCategoryId,
        if (isActive != null) 'isActive': isActive,
      });

  @override
  Future<void> upsertCategory(BillCategory c) async {
    _tree = CategoryTree([..._tree.byId.values.where((x) => x.categoryId != c.categoryId), c]);
    _emit();
  }

  @override
  Future<void> reorderCategories(List<String> orderedIds) async {
    final all = Map.of(_tree.byId);
    for (var i = 0; i < orderedIds.length; i++) {
      all[orderedIds[i]] = _replace(all[orderedIds[i]]!, displayOrder: (i + 1) * 10);
    }
    _tree = CategoryTree(all.values);
    _emit();
  }

  @override
  Future<void> mergeCategories(String fromId, String intoId) async {
    final into = _tree[intoId]!;
    for (final b in _bills) {
      if (b['categoryId'] == fromId || b['subcategoryId'] == fromId) {
        b['categoryId'] = into.rootId;
        b['subcategoryId'] = into.isRoot ? null : intoId;
      }
    }
    _tree = CategoryTree(_tree.byId.values.map((c) => c.categoryId == fromId
        ? _replace(c, isActive: false)
        : c.parentCategoryId == fromId
            ? _replace(c, parentCategoryId: intoId)
            : c));
    _emit();
  }
}
