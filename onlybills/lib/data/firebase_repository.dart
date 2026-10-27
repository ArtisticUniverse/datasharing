import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/bill.dart';
import '../models/category.dart';
import '../models/preferences.dart';
import 'repository.dart';

class FirebaseRepository implements Repository {
  final _db = FirebaseFirestore.instance;
  final _fn = FirebaseFunctions.instanceFor(region: 'us-central1');
  final _auth = FirebaseAuth.instance;
  final _storage = FirebaseStorage.instance;

  String get _uid => _auth.currentUser!.uid;

  @override
  bool get isDemo => false;

  @override
  Stream<CategoryTree> watchCategories() => _db
      .collection('categories')
      .snapshots()
      .map((s) => CategoryTree(s.docs.map((d) => BillCategory.fromMap(d.data()))));

  // Server-side filters only cover what Firestore can index; donor preferences and
  // swipe filters are applied client-side on top, and re-checked by fundBill.
  @override
  Stream<List<Bill>> watchFeed() => _db
      .collection('bills')
      .where('verificationStatus', isEqualTo: 'verified')
      .where('fundingEligibility', isEqualTo: 'eligible')
      .orderBy('createdAt', descending: true)
      .limit(200)
      .snapshots()
      .map((s) => s.docs
          .map((d) => Bill.fromMap(d.data()))
          .where((b) => b.userId != _uid && b.remainingAmount > 0)
          .toList());

  @override
  Future<DonorPreferences> loadPreferences() async {
    final d = await _db.doc('donors/$_uid').get();
    return DonorPreferences.fromMap(d.data()?['preferences'] as Map<String, dynamic>?);
  }

  @override
  Future<void> savePreferences(DonorPreferences prefs) =>
      _db.doc('donors/$_uid').set({'preferences': prefs.toMap()}, SetOptions(merge: true));

  @override
  Future<SubmitResult> submitBill(SubmitBillRequest req) async {
    final file = File(req.localImagePath);
    final path = 'receipts/$_uid/${DateTime.now().millisecondsSinceEpoch}_${file.uri.pathSegments.last}';
    await _storage.ref(path).putFile(file);
    final res = await _fn.httpsCallable('submitBill').call<Map<String, dynamic>>({
      'merchantName': req.merchantName,
      'categoryId': req.categoryId,
      'subcategoryId': req.subcategoryId,
      'amount': req.amount,
      'currency': req.currency,
      'billDate': req.billDate?.toIso8601String(),
      'fundingPurpose': req.fundingPurpose,
      'city': req.city,
      'urgency': req.urgency.name,
      'receiptImagePath': path,
      'suggestedCategoryId': req.suggestedCategoryId,
      'ocr': req.ocr,
      'imageMetadata': req.imageMetadata,
    });
    final d = res.data;
    return SubmitResult(
      d['billId'] as String,
      Bill.fromMap({'billId': '', 'userId': '', 'categoryId': '', 'amount': 0, ...d}).verificationStatus,
      FundingEligibility.values.byName(d['fundingEligibility'] as String),
      List<String>.from(d['flags'] ?? const []),
    );
  }

  @override
  Future<double> fundBill(String billId, double amount) async {
    // TODO(payments): capture via the payment provider SDK (e.g. Razorpay) first; its
    // server webhook writes payments/{paymentId} with status 'captured'.
    throw UnimplementedError('Integrate a payment provider before enabling live funding.');
  }

  @override
  Future<List<CategoryAnalytics>> loadAnalytics() async {
    final s = await _db.collection('analytics').where('categoryId', isNull: false).get();
    return s.docs.map((d) {
      final m = d.data();
      return CategoryAnalytics(
        m['categoryId'] as String,
        (m['uploadedBills'] ?? 0) as int,
        (m['fullyFundedBills'] ?? 0) as int,
        ((m['requestedAmount'] ?? 0) as num).toDouble(),
        ((m['fundedAmount'] ?? 0) as num).toDouble(),
      );
    }).toList();
  }

  @override
  Future<void> upsertCategory(BillCategory c) => _fn.httpsCallable('upsertCategory').call(c.toMap());

  @override
  Future<void> reorderCategories(List<String> orderedIds) =>
      _fn.httpsCallable('reorderCategories').call({'orderedIds': orderedIds});

  @override
  Future<void> mergeCategories(String fromId, String intoId) =>
      _fn.httpsCallable('mergeCategories').call({'fromId': fromId, 'intoId': intoId});
}
