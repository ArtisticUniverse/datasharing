import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../widgets/category_icon.dart';
import 'admin_categories_screen.dart';

class PreferencesScreen extends StatelessWidget {
  const PreferencesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = s.prefs;
    final lang = s.languageCode;
    return Scaffold(
      appBar: AppBar(title: const Text('Donor preferences')),
      body: ListView(children: [
        const ListTile(
          title: Text('What you see in your swipe feed'),
          subtitle: Text('By default you only see verified essential bills.'),
        ),
        SwitchListTile(
          title: const Text('Show discretionary bills'),
          subtitle: const Text('Restaurants, entertainment, gym, celebrations, non-essential shopping'),
          value: p.showDiscretionary,
          onChanged: (v) => s.setPrefs(p.copyWith(showDiscretionary: v)),
        ),
        SwitchListTile(
          title: const Text('Show consumer debt'),
          subtitle: const Text('Credit cards, loan repayments, bank charges (always moderator-reviewed)'),
          value: p.showDebtAndTax,
          onChanged: (v) => s.setPrefs(p.copyWith(showDebtAndTax: v)),
        ),
        SwitchListTile(
          title: const Text('Allow age-restricted categories'),
          subtitle: const Text(
              'Alcohol, tobacco, nicotine and similar. Off by platform policy: funding also requires age verification, '
              'local legality and payment-provider approval, all checked on the server.'),
          value: p.allowRestrictedCategories,
          onChanged: (v) => s.setPrefs(p.copyWith(allowRestrictedCategories: v)),
        ),
        const Divider(),
        const ListTile(
          title: Text('Categories'),
          subtitle: Text('Tap to cycle: show → only these → hide'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: s.categories.roots.map((c) {
              final included = p.includedCategoryIds.contains(c.categoryId);
              final excluded = p.excludedCategoryIds.contains(c.categoryId);
              return FilterChip(
                avatar: Icon(excluded ? Icons.block : categoryIcon(c.icon), size: 16),
                label: Text(c.displayName(lang),
                    style: excluded ? const TextStyle(decoration: TextDecoration.lineThrough) : null),
                selected: included,
                onSelected: (_) {
                  final inc = {...p.includedCategoryIds}..remove(c.categoryId);
                  final exc = {...p.excludedCategoryIds}..remove(c.categoryId);
                  if (!included && !excluded) {
                    inc.add(c.categoryId);
                  } else if (included) {
                    exc.add(c.categoryId);
                  }
                  s.setPrefs(p.copyWith(includedCategoryIds: inc, excludedCategoryIds: exc));
                },
              );
            }).toList(),
          ),
        ),
        const Divider(height: 32),
        ListTile(
          leading: const Icon(Icons.translate),
          title: const Text('Language'),
          trailing: DropdownButton<String>(
            value: lang,
            items: const [
              DropdownMenuItem(value: 'en', child: Text('English')),
              // Category names fall back to English until translations are added in Firestore.
              DropdownMenuItem(value: 'hi', child: Text('हिन्दी (beta)')),
            ],
            onChanged: (v) => s.setLanguage(v!),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.admin_panel_settings),
          title: const Text('Manage categories (admin)'),
          subtitle: Text(s.repo.isDemo ? 'Demo: changes are kept in memory' : 'Requires admin claim'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminCategoriesScreen())),
        ),
      ]),
    );
  }
}
