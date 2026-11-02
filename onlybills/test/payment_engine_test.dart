import 'package:flutter_test/flutter_test.dart';
import 'package:onlybills/services/payment_engine.dart';

Map<String, dynamic> ev(String id, String method, num amount, String status, int at) =>
    {'paymentId': id, 'method': method, 'amount': amount, 'status': status, 'at': at};

// Same cases as functions/test/payments.test.js, so the two implementations agree.
void main() {
  test('latest final state per attempt', () {
    final a = PaymentEngine.finalAttempts([ev('1', 'upi', 100, 'created', 1), ev('1', 'upi', 100, 'failed', 2), ev('1', 'upi', 100, 'captured', 3)]);
    expect(a.single['status'], 'captured');
  });

  test('donor profile', () {
    final p = PaymentEngine.buildDonorProfile([
      ev('1', 'card', 1000, 'captured', 1), ev('2', 'upi', 500, 'captured', 2),
      ev('3', 'upi', 2000, 'captured', 3), ev('4', 'wallet', 300, 'abandoned', 4),
    ]);
    expect(p['totalDonations'], 3);
    expect(p['medianAmount'], 1000);
    expect(p['lastMethod'], 'upi');
  });

  test('new donor gets UPI; limits respected', () {
    final r = PaymentEngine.recommend(null, {}, 20000);
    expect(r.first['method'], 'upi');
    expect(r.any((m) => m['method'] == 'wallet'), isFalse);
    expect(PaymentEngine.recommend(null, {}, 150000).any((m) => m['method'] == 'upi'), isFalse);
  });

  test('failing UPI steers donor to their working card', () {
    final events = [
      for (var i = 0; i < 8; i++) ev('u$i', 'upi', 1500, 'failed', i),
      for (var i = 0; i < 6; i++) ev('c$i', 'card', 1500, 'captured', 10 + i),
    ];
    final r = PaymentEngine.recommend(PaymentEngine.buildDonorProfile(events), {}, 1500);
    expect(r.first['method'], 'card');
    expect((r.first['reasons'] as List).first, contains('last time'));
  });

  test('platform data moves ranking', () {
    final g = {
      'upi:l': {'attempts': 1000, 'captured': 550},
      'netbanking:l': {'attempts': 1000, 'captured': 960},
    };
    expect(PaymentEngine.recommend(null, g, 20000).first['method'], 'netbanking');
  });

  test('amount suggestions', () {
    final s = PaymentEngine.suggestAmounts({'medianAmount': 1000, 'p75Amount': 2000}, 1800);
    expect(s['amounts'], [500, 1000]);
    expect(s['defaultAmount'], 1000);
    expect(PaymentEngine.suggestAmounts(null, 5000)['amounts'], [250, 500, 1000]);
  });
}
