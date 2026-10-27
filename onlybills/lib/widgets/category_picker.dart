import 'package:flutter/material.dart';

import '../models/category.dart';
import 'category_icon.dart';

/// Searchable two-level category picker. Returns the chosen category (root or sub).
/// [multi] mode returns a set of ids instead (used by filters and donor preferences).
Future<BillCategory?> pickCategory(BuildContext context, CategoryTree tree, String lang, {String? initialId}) =>
    showModalBottomSheet<BillCategory>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CategoryPickerSheet(tree: tree, lang: lang, initialId: initialId),
    );

Future<Set<String>?> pickCategories(BuildContext context, CategoryTree tree, String lang, Set<String> selected,
        {String title = 'Categories'}) =>
    showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CategoryPickerSheet(tree: tree, lang: lang, multiSelected: {...selected}, title: title),
    );

class _CategoryPickerSheet extends StatefulWidget {
  final CategoryTree tree;
  final String lang;
  final String? initialId;
  final Set<String>? multiSelected;
  final String title;
  const _CategoryPickerSheet(
      {required this.tree, required this.lang, this.initialId, this.multiSelected, this.title = 'Choose a category'});

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  String _query = '';
  String? _expanded;

  bool get _multi => widget.multiSelected != null;

  @override
  void initState() {
    super.initState();
    _expanded = widget.tree[widget.initialId]?.rootId;
  }

  void _tap(BillCategory c) {
    if (_multi) {
      setState(() => widget.multiSelected!.contains(c.categoryId)
          ? widget.multiSelected!.remove(c.categoryId)
          : widget.multiSelected!.add(c.categoryId));
    } else {
      Navigator.pop(context, c);
    }
  }

  Widget _tile(BillCategory c, {bool indent = false}) {
    final parent = widget.tree[c.parentCategoryId];
    final restricted = c.fundingEligibility != FundingEligibility.eligible;
    return ListTile(
      contentPadding: EdgeInsets.only(left: indent ? 56 : 16, right: 16),
      leading: indent ? null : Icon(categoryIcon(c.icon)),
      title: Text(c.displayName(widget.lang)),
      subtitle: _query.isNotEmpty && parent != null
          ? Text(parent.displayName(widget.lang))
          : (restricted
              ? Text(c.fundingEligibility == FundingEligibility.restricted ? 'Restricted from funding' : 'Reviewed before funding',
                  style: TextStyle(color: eligibilityColor(c.fundingEligibility, Theme.of(context).colorScheme)))
              : null),
      selected: widget.initialId == c.categoryId,
      trailing: _multi
          ? Checkbox(value: widget.multiSelected!.contains(c.categoryId), onChanged: (_) => _tap(c))
          : (c.requiresAgeVerification ? const Icon(Icons.eighteen_up_rating_outlined) : null),
      onTap: () => _tap(c),
    );
  }

  @override
  Widget build(BuildContext context) {
    final results = widget.tree.search(_query, widget.lang);
    final children = <Widget>[];
    if (_query.isEmpty) {
      for (final root in results) {
        final open = _expanded == root.categoryId;
        children.add(ListTile(
          leading: Icon(categoryIcon(root.icon)),
          title: Text(root.displayName(widget.lang)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (_multi) Checkbox(value: widget.multiSelected!.contains(root.categoryId), onChanged: (_) => _tap(root)),
            Icon(open ? Icons.expand_less : Icons.expand_more),
          ]),
          onTap: () => setState(() => _expanded = open ? null : root.categoryId),
        ));
        if (open) {
          if (!_multi) children.add(_tile(root, indent: true)); // allow choosing the main category itself
          children.addAll(widget.tree.childrenOf(root.categoryId).map((c) => _tile(c, indent: true)));
        }
      }
    } else {
      children.addAll(results.map(_tile));
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(children: [
            Expanded(child: Text(widget.title, style: Theme.of(context).textTheme.titleLarge)),
            if (_multi)
              FilledButton(onPressed: () => Navigator.pop(context, widget.multiSelected), child: const Text('Done')),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            autofocus: !_multi,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search e.g. "MRI", "rent", "school fees"',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: children.isEmpty
              ? const Center(child: Text('No matching categories'))
              : ListView(controller: scroll, children: children),
        ),
      ]),
    );
  }
}
