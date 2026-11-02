import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/bill.dart';
import '../models/preferences.dart';
import '../widgets/bill_card.dart';
import '../widgets/category_icon.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/pay_sheet.dart';

class SwipeFeedScreen extends StatelessWidget {
  const SwipeFeedScreen({super.key});

  Future<void> _fund(BuildContext context, AppState s, Bill bill) async {
    final r = await showPaySheet(context, s.repo, bill);
    if (r != null) s.paymentsChanged();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final deck = s.deck;
    final roots = s.categories.roots.where((c) => s.prefs.allows(c)).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('OnlyBills'),
        actions: [
          if (s.repo.isDemo) const Padding(padding: EdgeInsets.only(right: 8), child: Chip(label: Text('DEMO'))),
          IconButton(
            tooltip: 'Filters',
            icon: Badge(
              isLabelVisible: s.filters.activeCount > 0,
              label: Text('${s.filters.activeCount}'),
              child: const Icon(Icons.tune),
            ),
            onPressed: () async {
              final f = await showFilterSheet(context, s.filters, s.categories, s.languageCode, s.cities);
              if (f != null) s.setFilters(f);
            },
          ),
        ],
      ),
      body: s.loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              // Quick category filter: horizontally scrollable so it works on any width.
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: const Text('All'),
                        selected: s.filters.categoryIds.isEmpty,
                        onSelected: (_) => s.setFilters(_withCategories(s.filters, {})),
                      ),
                    ),
                    ...roots.map((c) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            avatar: Icon(categoryIcon(c.icon), size: 16),
                            label: Text(c.displayName(s.languageCode)),
                            selected: s.filters.categoryIds.contains(c.categoryId),
                            onSelected: (sel) {
                              final ids = {...s.filters.categoryIds};
                              sel ? ids.add(c.categoryId) : ids.remove(c.categoryId);
                              s.setFilters(_withCategories(s.filters, ids));
                            },
                          ),
                        )),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(builder: (context, box) {
                  // Keep cards phone-shaped on tablets / landscape.
                  final w = math.min(box.maxWidth - 32, 480.0);
                  // Leave room for the action buttons (large FAB 96px + spacing).
                  final h = math.max(0.0, math.min(box.maxHeight - 136, w * 1.45));
                  if (deck.isEmpty) return _Empty(onReset: s.resetSkipped);
                  return Column(children: [
                    const SizedBox(height: 8),
                    SizedBox(
                      width: w,
                      height: h,
                      child: Stack(children: [
                        for (final (i, b) in deck.take(3).toList().reversed.indexed)
                          _positioned(context, s, b, isTop: i == math.min(deck.length, 3) - 1),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      FloatingActionButton(
                        heroTag: 'skip',
                        backgroundColor: Colors.grey.shade200,
                        onPressed: () => s.skip(deck.first),
                        child: const Icon(Icons.close, color: Colors.black54),
                      ),
                      const SizedBox(width: 40),
                      FloatingActionButton.large(
                        heroTag: 'fund',
                        onPressed: () => _fund(context, s, deck.first),
                        child: const Icon(Icons.favorite),
                      ),
                    ]),
                  ]);
                }),
              ),
            ]),
    );
  }

  Widget _positioned(BuildContext context, AppState s, Bill b, {required bool isTop}) {
    final cat = s.categories[b.effectiveCategoryId];
    final card = BillCard(bill: b, category: cat, parent: s.categories[cat?.parentCategoryId], lang: s.languageCode);
    if (!isTop) return Positioned.fill(top: 12, child: IgnorePointer(child: Opacity(opacity: 0.6, child: card)));
    return Positioned.fill(
      child: _SwipeableCard(
        key: ValueKey(b.billId),
        onSwipeLeft: () => s.skip(b),
        onSwipeRight: () => _fund(context, s, b),
        child: card,
      ),
    );
  }

  static BillFilters _withCategories(BillFilters f, Set<String> ids) => BillFilters(
      categoryIds: ids,
      minAmount: f.minAmount,
      maxAmount: f.maxAmount,
      city: f.city,
      urgencies: f.urgencies,
      verifiedOnly: f.verifiedOnly);
}

class _SwipeableCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onSwipeLeft;
  final VoidCallback onSwipeRight;
  const _SwipeableCard({super.key, required this.child, required this.onSwipeLeft, required this.onSwipeRight});

  @override
  State<_SwipeableCard> createState() => _SwipeableCardState();
}

class _SwipeableCardState extends State<_SwipeableCard> {
  Offset _drag = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final dx = _drag.dx;
    return GestureDetector(
      onPanUpdate: (d) => setState(() => _drag += d.delta),
      onPanEnd: (d) {
        final threshold = width * 0.25;
        final fling = d.velocity.pixelsPerSecond.dx;
        if (dx > threshold || fling > 1200) {
          widget.onSwipeRight();
        } else if (dx < -threshold || fling < -1200) {
          widget.onSwipeLeft();
        }
        setState(() => _drag = Offset.zero); // right swipe opens the dialog; card returns until funded
      },
      child: Transform.translate(
        offset: _drag,
        child: Transform.rotate(
          angle: dx / width * 0.4,
          child: Stack(children: [
            widget.child,
            if (dx.abs() > 20)
              Positioned(
                top: 24,
                left: dx > 0 ? 24 : null,
                right: dx < 0 ? 24 : null,
                child: Transform.rotate(
                  angle: dx > 0 ? -0.3 : 0.3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border.all(color: dx > 0 ? Colors.green : Colors.red, width: 3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(dx > 0 ? 'FUND' : 'SKIP',
                        style: TextStyle(
                            color: dx > 0 ? Colors.green : Colors.red, fontSize: 28, fontWeight: FontWeight.w900)),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final VoidCallback onReset;
  const _Empty({required this.onReset});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.inbox_outlined, size: 64),
            const SizedBox(height: 12),
            const Text('No more bills match your filters and preferences.', textAlign: TextAlign.center),
            TextButton(onPressed: onReset, child: const Text('Show skipped bills again')),
          ]),
        ),
      );
}
