import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/category.dart';
import '../widgets/category_icon.dart';
import '../widgets/category_picker.dart';

/// Create, edit, disable, merge and reorder categories. All writes go through
/// admin-only Cloud Functions; the app picks changes up live from Firestore.
class AdminCategoriesScreen extends StatelessWidget {
  final String? parentId;
  const AdminCategoriesScreen({super.key, this.parentId});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final tree = s.categories;
    final parent = tree[parentId];
    // Show inactive ones too so admins can re-enable them.
    final items = tree.byId.values.where((c) => c.parentCategoryId == parentId).toList()
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

    Future<void> run(Future<void> Function() op, String done) async {
      final m = ScaffoldMessenger.of(context);
      try {
        await op();
        m.showSnackBar(SnackBar(content: Text(done)));
      } catch (e) {
        m.showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(parent == null ? 'Categories' : parent.categoryName)),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New'),
        onPressed: () async {
          final c = await showDialog<BillCategory>(
              context: context, builder: (_) => _EditDialog(parentId: parentId, nextOrder: (items.length + 1) * 10));
          if (c != null) await run(() => s.repo.upsertCategory(c), 'Created ${c.categoryName}');
        },
      ),
      body: ReorderableListView.builder(
        itemCount: items.length,
        onReorderItem: (from, to) {
          final ids = items.map((c) => c.categoryId).toList();
          ids.insert(to, ids.removeAt(from));
          run(() => s.repo.reorderCategories(ids), 'Order saved');
        },
        itemBuilder: (context, i) {
          final c = items[i];
          return ListTile(
            key: ValueKey(c.categoryId),
            leading: Icon(categoryIcon(c.icon), color: c.isActive ? null : Theme.of(context).disabledColor),
            title: Text(c.categoryName,
                style: c.isActive ? null : const TextStyle(decoration: TextDecoration.lineThrough)),
            subtitle: Text(
              '${classificationLabel(c.classification)} · ${eligibilityLabel(c.fundingEligibility)}'
              '${c.requiresAgeVerification ? ' · 18+' : ''}${c.requiresManualReview ? ' · manual review' : ''}',
              style: TextStyle(color: eligibilityColor(c.fundingEligibility, Theme.of(context).colorScheme)),
            ),
            onTap: c.isRoot
                ? () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => AdminCategoriesScreen(parentId: c.categoryId)))
                : null,
            trailing: PopupMenuButton<String>(
              onSelected: (action) async {
                switch (action) {
                  case 'edit':
                    final e =
                        await showDialog<BillCategory>(context: context, builder: (_) => _EditDialog(existing: c));
                    if (e != null) await run(() => s.repo.upsertCategory(e), 'Saved');
                  case 'toggle':
                    await run(
                        () => s.repo.upsertCategory(BillCategory.fromMap({...c.toMap(), 'isActive': !c.isActive})),
                        c.isActive ? 'Disabled' : 'Enabled');
                  case 'merge':
                    final into = await pickCategory(context, tree, s.languageCode);
                    if (into == null || into.categoryId == c.categoryId || !context.mounted) return;
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Merge categories?'),
                        content: Text('All bills in "${c.categoryName}" move to "${into.categoryName}", '
                            'and "${c.categoryName}" is disabled. This cannot be undone automatically.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Merge')),
                        ],
                      ),
                    );
                    if (ok == true) await run(() => s.repo.mergeCategories(c.categoryId, into.categoryId), 'Merged');
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'toggle', child: Text(c.isActive ? 'Disable' : 'Enable')),
                const PopupMenuItem(value: 'merge', child: Text('Merge into…')),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EditDialog extends StatefulWidget {
  final BillCategory? existing;
  final String? parentId;
  final int nextOrder;
  const _EditDialog({this.existing, this.parentId, this.nextOrder = 0});

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final BillCategory? e = widget.existing;
  late final _name = TextEditingController(text: e?.categoryName);
  late final _hindi = TextEditingController(text: e?.localizedNames['hi']);
  late final _desc = TextEditingController(text: e?.description);
  late FundingEligibility _elig = e?.fundingEligibility ?? FundingEligibility.review;
  late Classification _class = e?.classification ?? Classification.essential;
  late bool _age = e?.requiresAgeVerification ?? false;
  late bool _review = e?.requiresManualReview ?? true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(e == null ? 'New category' : 'Edit category'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name (English)')),
          TextField(controller: _hindi, decoration: const InputDecoration(labelText: 'Name (Hindi, optional)')),
          TextField(controller: _desc, decoration: const InputDecoration(labelText: 'Description')),
          const SizedBox(height: 12),
          DropdownButtonFormField<Classification>(
            initialValue: _class,
            decoration: const InputDecoration(labelText: 'Classification'),
            items: Classification.values
                .map((c) => DropdownMenuItem(value: c, child: Text(classificationLabel(c))))
                .toList(),
            onChanged: (v) => setState(() => _class = v!),
          ),
          DropdownButtonFormField<FundingEligibility>(
            initialValue: _elig,
            decoration: const InputDecoration(labelText: 'Funding eligibility'),
            items: FundingEligibility.values
                .map((f) => DropdownMenuItem(value: f, child: Text(eligibilityLabel(f))))
                .toList(),
            onChanged: (v) => setState(() => _elig = v!),
          ),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Requires age verification'),
              value: _age,
              onChanged: (v) => setState(() => _age = v)),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Requires manual review'),
              value: _review,
              onChanged: (v) => setState(() => _review = v)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            final slug = name.toLowerCase().replaceAll('&', 'and').replaceAll(RegExp(r'[^a-z0-9]+'), '_');
            final parent = e?.parentCategoryId ?? widget.parentId;
            Navigator.pop(
              context,
              BillCategory(
                categoryId: e?.categoryId ?? (parent == null ? slug : '$parent.$slug'),
                categoryName: name,
                localizedNames: {
                  ...?e?.localizedNames,
                  'en': name,
                  if (_hindi.text.trim().isNotEmpty) 'hi': _hindi.text.trim(),
                },
                parentCategoryId: parent,
                description: _desc.text.trim(),
                icon: e?.icon ?? 'more_horiz',
                isActive: e?.isActive ?? true,
                requiresAgeVerification: _age,
                requiresManualReview: _review,
                fundingEligibility: _elig,
                classification: _class,
                displayOrder: e?.displayOrder ?? widget.nextOrder,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
