import 'dart:async';

import 'package:flutter/foundation.dart';

import 'data/repository.dart';
import 'models/bill.dart';
import 'models/category.dart';
import 'models/preferences.dart';

class AppState extends ChangeNotifier {
  final Repository repo;
  CategoryTree categories = CategoryTree(const []);
  List<Bill> _feed = const [];
  DonorPreferences prefs = const DonorPreferences();
  BillFilters filters = const BillFilters();
  final Set<String> _skipped = {};
  String languageCode = 'en';
  bool loading = true;
  final List<StreamSubscription> _subs = [];

  AppState(this.repo) {
    _subs.add(repo.watchCategories().listen((t) {
      categories = t;
      loading = false;
      notifyListeners();
    }));
    _subs.add(repo.watchFeed().listen((b) {
      _feed = b;
      notifyListeners();
    }));
    repo.loadPreferences().then((p) {
      prefs = p;
      notifyListeners();
    });
  }

  /// Bills for the swipe deck: server-eligible, allowed by donor preferences,
  /// matching the active filters, and not skipped this session.
  List<Bill> get deck => _feed.where((b) {
        final c = categories[b.effectiveCategoryId];
        return c != null && !_skipped.contains(b.billId) && prefs.allows(c) && filters.matches(b, c);
      }).toList()
        ..sort((a, b) => b.urgency.index.compareTo(a.urgency.index));

  List<String> get cities => {for (final b in _feed) if (b.city != null) b.city!}.toList()..sort();

  void skip(Bill b) {
    _skipped.add(b.billId);
    notifyListeners();
  }

  void resetSkipped() {
    _skipped.clear();
    notifyListeners();
  }

  void setFilters(BillFilters f) {
    filters = f;
    notifyListeners();
  }

  Future<void> setPrefs(DonorPreferences p) async {
    prefs = p;
    notifyListeners();
    await repo.savePreferences(p);
  }

  void setLanguage(String code) {
    languageCode = code;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
