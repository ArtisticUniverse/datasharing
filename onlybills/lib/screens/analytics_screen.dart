import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/repository.dart';
import '../widgets/bill_card.dart';
import '../widgets/category_icon.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  late Future<List<CategoryAnalytics>> _future = context.read<AppState>().repo.loadAnalytics();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Impact'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _future = s.repo.loadAnalytics()),
          ),
        ],
      ),
      body: FutureBuilder<List<CategoryAnalytics>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final rows = snap.data!..sort((a, b) => b.fundedAmount.compareTo(a.fundedAmount));
          final uploaded = rows.fold(0, (s, r) => s + r.uploadedBills);
          final funded = rows.fold(0, (s, r) => s + r.fullyFundedBills);
          final requested = rows.fold(0.0, (s, r) => s + r.requestedAmount);
          final raised = rows.fold(0.0, (s, r) => s + r.fundedAmount);
          final maxRaised = rows.isEmpty ? 1.0 : rows.first.fundedAmount.clamp(1.0, double.infinity);
          return LayoutBuilder(builder: (context, box) {
            final cols = box.maxWidth > 700 ? 4 : 2;
            return ListView(padding: const EdgeInsets.all(16), children: [
              GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.8,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: [
                  _Stat('Bills uploaded', '$uploaded'),
                  _Stat('Amount raised', formatMoney(raised, 'INR')),
                  _Stat('Fully funded', uploaded == 0 ? '0%' : '${(funded / uploaded * 100).round()}%'),
                  _Stat('Of requested', requested == 0 ? '0%' : '${(raised / requested * 100).round()}%'),
                ],
              ),
              const SizedBox(height: 24),
              Text('Donations by category', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...rows.map((r) {
                final c = s.categories[r.categoryId];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Icon(categoryIcon(c?.icon), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c?.displayName(s.languageCode) ?? r.categoryId, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(value: r.fundedAmount / maxRaised, minHeight: 6),
                      ]),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 96,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(formatMoney(r.fundedAmount, 'INR'), style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('${r.uploadedBills} bills', style: Theme.of(context).textTheme.bodySmall),
                      ]),
                    ),
                  ]),
                );
              }),
            ]);
          });
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat(this.label, this.value);

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(child: Text(value, style: Theme.of(context).textTheme.headlineSmall)),
                Text(label, style: Theme.of(context).textTheme.bodySmall),
              ]),
        ),
      );
}
