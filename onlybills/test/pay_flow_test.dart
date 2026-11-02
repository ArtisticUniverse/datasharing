import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onlybills/data/demo_repository.dart';
import 'package:onlybills/main.dart';

void main() {
  testWidgets('one-tap payment in demo mode', (tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = DemoRepository();

    Future<void> settle() => tester.runAsync(() async {
          for (var i = 0; i < 15; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            await tester.pump();
          }
        });

    await tester.pumpWidget(OnlyBillsApp(repo: repo));
    await settle();
    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pump();
    await settle();
    await tester.pump(const Duration(milliseconds: 400)); // sheet animation

    // Demo donor usually gives ~₹875 by UPI → UPI pre-selected and marked as best.
    expect(find.text('Best for you'), findsOneWidget);
    expect(find.textContaining('You used this last time'), findsOneWidget);
    final payButton = find.textContaining(RegExp(r'^Pay ₹.* with UPI$'));
    expect(payButton, findsOneWidget);

    await tester.tap(payButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000)); // simulated gateway delay (fake clock)
    await settle();
    expect(
      find.text('Thank you!').evaluate().isNotEmpty || find.textContaining("didn't go through").evaluate().isNotEmpty,
      isTrue,
    );

    // The payment was logged and the profile rebuilt from it.
    final profile = await tester.runAsync(repo.loadPaymentProfile);
    expect((profile!['methodStats'] as Map)['upi']['attempts'], 7); // 6 in the seeded history + this one
  });
}
