import 'dart:math' as math;

/// Dart port of functions/payments.js, used by demo mode so personalisation works
/// offline. In live mode the server computes the same thing (getCheckout).
/// Keep the two in sync; test/payment_engine_test.dart mirrors the Node tests.
class PaymentEngine {
  static const methods = <String, ({String label, double maxAmount, double feePct})>{
    'upi': (label: 'UPI', maxAmount: 100000, feePct: 0),
    'card': (label: 'Debit / credit card', maxAmount: 500000, feePct: 2.0),
    'netbanking': (label: 'Net banking', maxAmount: 500000, feePct: 1.9),
    'wallet': (label: 'Wallet', maxAmount: 10000, feePct: 1.9),
  };
  static const _prior = {'upi': 0.9, 'card': 0.82, 'netbanking': 0.8, 'wallet': 0.85};
  static const _priorWeight = 10;
  static const _final = {'captured', 'failed', 'abandoned'};

  static String bucketOf(num amount) => amount < 500
      ? 'xs'
      : amount < 2000
          ? 's'
          : amount < 10000
              ? 'm'
              : amount < 50000
                  ? 'l'
                  : 'xl';

  static int fee(String method, num amount) => (amount * methods[method]!.feePct / 100).round();

  static List<Map<String, dynamic>> finalAttempts(List<Map<String, dynamic>> events) {
    final byId = <String, Map<String, dynamic>>{};
    for (final e in events) {
      if (!_final.contains(e['status']) || !methods.containsKey(e['method'])) continue;
      final prev = byId[e['paymentId']];
      if (prev == null || (e['at'] as num) >= (prev['at'] as num)) byId[e['paymentId'] as String] = e;
    }
    return byId.values.toList();
  }

  static Map<String, Map<String, int>> buildStats(List<Map<String, dynamic>> events) {
    final stats = <String, Map<String, int>>{};
    for (final e in finalAttempts(events)) {
      final s = stats.putIfAbsent('${e['method']}:${bucketOf(e['amount'] as num)}', () => {'attempts': 0, 'captured': 0});
      s['attempts'] = s['attempts']! + 1;
      if (e['status'] == 'captured') s['captured'] = s['captured']! + 1;
    }
    return stats;
  }

  static double? _quantile(List<num> sorted, double q) {
    if (sorted.isEmpty) return null;
    final pos = (sorted.length - 1) * q;
    final lo = pos.floor(), hi = pos.ceil();
    return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
  }

  static Map<String, dynamic> buildDonorProfile(List<Map<String, dynamic>> events) {
    final attempts = finalAttempts(events)..sort((a, b) => (a['at'] as num).compareTo(b['at'] as num));
    final captured = attempts.where((e) => e['status'] == 'captured').toList();
    final amounts = captured.map((e) => e['amount'] as num).toList()..sort();
    final methodStats = <String, Map<String, int>>{};
    for (final e in attempts) {
      final m = methodStats.putIfAbsent(e['method'] as String, () => {'attempts': 0, 'captured': 0});
      m['attempts'] = m['attempts']! + 1;
      if (e['status'] == 'captured') m['captured'] = m['captured']! + 1;
    }
    return {
      'totalDonations': captured.length,
      'totalAmount': amounts.fold<num>(0, (a, b) => a + b),
      'medianAmount': _quantile(amounts, 0.5),
      'p75Amount': _quantile(amounts, 0.75),
      'lastMethod': captured.isEmpty ? null : captured.last['method'],
      'methodStats': methodStats,
      'bucketStats': buildStats(attempts),
    };
  }

  static List<Map<String, dynamic>> recommend(Map<String, dynamic>? profile, Map<String, dynamic> global, num amount) {
    final bucket = bucketOf(amount);
    final ranked = <Map<String, dynamic>>[];
    methods.forEach((method, m) {
      if (amount > m.maxAmount) return;
      final g = global['$method:$bucket'] as Map?;
      final platform = ((g?['captured'] ?? 0) + _prior[method]! * _priorWeight) / ((g?['attempts'] ?? 0) + _priorWeight);
      final own = (profile?['bucketStats'] as Map?)?['$method:$bucket'] as Map?;
      final expected =
          own == null ? platform : (own['captured'] + platform * _priorWeight) / (own['attempts'] + _priorWeight);
      final ms = (profile?['methodStats'] as Map?)?[method] as Map?;
      final familiar = ms != null && (ms['captured'] as num) > 0;
      final isLast = profile?['lastMethod'] == method;
      final f = fee(method, amount);
      final score = expected * (1 + (familiar ? 0.05 : 0) + (isLast ? 0.05 : 0)) - f / math.max(amount, 1);
      ranked.add({
        'method': method,
        'label': m.label,
        'score': score,
        'expectedSuccess': expected,
        'fee': f,
        'reasons': [
          if (isLast) 'You used this last time' else if (familiar) "You've paid this way ${ms['captured']}×",
          f == 0 ? 'No fee' : '₹$f fee',
          '${(expected * 100).round()}% success for amounts like this',
        ],
      });
    });
    ranked.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
    if (ranked.isNotEmpty) ranked.first['recommended'] = true;
    return ranked;
  }

  static const _nice = [50, 100, 200, 250, 500, 1000, 1500, 2000, 2500, 5000, 10000, 25000, 50000];
  static int roundNice(num v) => _nice.reduce((best, n) => (n - v).abs() < (best - v).abs() ? n : best);

  static Map<String, dynamic> suggestAmounts(Map<String, dynamic>? profile, num remaining) {
    final num base = (profile?['medianAmount'] as num?) ?? 500;
    final num high = (profile?['p75Amount'] as num?) ?? base * 2;
    final picks = {roundNice(base / 2), roundNice(base), roundNice(math.max(high, base * 1.5))}
        .where((v) => v < remaining)
        .toList()
      ..sort();
    final def = picks.contains(roundNice(base)) ? roundNice(base) : (picks.isEmpty ? remaining : picks.last);
    return {'amounts': picks, 'payRemaining': remaining, 'defaultAmount': def};
  }
}
