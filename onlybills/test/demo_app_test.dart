import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onlybills/data/demo_repository.dart';
import 'package:onlybills/main.dart';

void main() {
  for (final (name, size) in [('landscape 800x600', const Size(800, 600)), ('phone 360x780', const Size(360, 780))]) {
    testWidgets('demo mode shows essential bills and hides restricted ones ($name)', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await tester.pumpWidget(OnlyBillsApp(repo: DemoRepository()));
        for (var i = 0; i < 20 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
        }
      });
      await tester.pump();
      expect(find.text('DEMO'), findsOneWidget);
      expect(find.text('Apollo Hospitals, Chennai'), findsOneWidget); // most urgent first
      expect(find.text('City Wine & Liquor Store'), findsNothing);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(find.text('Apollo Hospitals, Chennai'), findsNothing);
    });
  }
}
