import 'package:flutter/material.dart';

import '../models/bill.dart';
import '../models/category.dart';
import '../models/preferences.dart';
import 'category_picker.dart';

Future<BillFilters?> showFilterSheet(
        BuildContext context, BillFilters current, CategoryTree tree, String lang, List<String> cities) =>
    showModalBottomSheet<BillFilters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FilterSheet(current: current, tree: tree, lang: lang, cities: cities),
    );

class _FilterSheet extends StatefulWidget {
  final BillFilters current;
  final CategoryTree tree;
  final String lang;
  final List<String> cities;
  const _FilterSheet({required this.current, required this.tree, required this.lang, required this.cities});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  static const _maxAmount = 100000.0;
  late Set<String> _cats = {...widget.current.categoryIds};
  late RangeValues _range = RangeValues(widget.current.minAmount ?? 0, widget.current.maxAmount ?? _maxAmount);
  late String? _city = widget.current.city;
  late Set<Urgency> _urg = {...widget.current.urgencies};
  late bool _verifiedOnly = widget.current.verifiedOnly;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: Text('Filters', style: t.titleLarge)),
            TextButton(onPressed: () => Navigator.pop(context, const BillFilters()), child: const Text('Reset')),
          ]),
          const SizedBox(height: 12),
          Text('Category', style: t.titleSmall),
          Wrap(spacing: 6, runSpacing: 6, children: [
            ..._cats.map((id) => InputChip(
                  label: Text(widget.tree[id]?.displayName(widget.lang) ?? id),
                  onDeleted: () => setState(() => _cats.remove(id)),
                )),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
              onPressed: () async {
                final r = await pickCategories(context, widget.tree, widget.lang, _cats);
                if (r != null) setState(() => _cats = r);
              },
            ),
          ]),
          const SizedBox(height: 16),
          Text('Amount left to fund: ₹${_range.start.round()} – ₹${_range.end.round()}${_range.end >= _maxAmount ? '+' : ''}',
              style: t.titleSmall),
          RangeSlider(
            values: _range,
            max: _maxAmount,
            divisions: 100,
            onChanged: (v) => setState(() => _range = v),
          ),
          Text('Location', style: t.titleSmall),
          DropdownButton<String?>(
            isExpanded: true,
            value: _city,
            items: [
              const DropdownMenuItem(value: null, child: Text('Anywhere')),
              ...widget.cities.map((c) => DropdownMenuItem(value: c, child: Text(c))),
            ],
            onChanged: (v) => setState(() => _city = v),
          ),
          const SizedBox(height: 16),
          Text('Urgency', style: t.titleSmall),
          Wrap(
            spacing: 6,
            children: Urgency.values.reversed
                .map((u) => FilterChip(
                      label: Text(u.name[0].toUpperCase() + u.name.substring(1)),
                      selected: _urg.contains(u),
                      onSelected: (s) => setState(() => s ? _urg.add(u) : _urg.remove(u)),
                    ))
                .toList(),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Verified receipts only'),
            value: _verifiedOnly,
            onChanged: (v) => setState(() => _verifiedOnly = v),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(
                context,
                BillFilters(
                  categoryIds: _cats,
                  minAmount: _range.start > 0 ? _range.start : null,
                  maxAmount: _range.end < _maxAmount ? _range.end : null,
                  city: _city,
                  urgencies: _urg,
                  verifiedOnly: _verifiedOnly,
                ),
              ),
              child: const Text('Apply'),
            ),
          ),
        ]),
      ),
    );
  }
}
