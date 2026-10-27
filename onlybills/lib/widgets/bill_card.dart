import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/bill.dart';
import '../models/category.dart';
import 'category_icon.dart';

String formatMoney(double v, String currency) =>
    NumberFormat.simpleCurrency(name: currency, locale: 'en_IN', decimalDigits: 0).format(v);

/// Shows only what a donor needs to decide. Patient names, IDs, account numbers
/// and addresses never reach this widget; the server stores redacted text only.
class BillCard extends StatelessWidget {
  final Bill bill;
  final BillCategory? category;
  final BillCategory? parent;
  final String lang;

  const BillCard({super.key, required this.bill, this.category, this.parent, this.lang = 'en'});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final verified = bill.verificationStatus == VerificationStatus.verified;
    return Card(
      elevation: 6,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                backgroundColor: cs.primaryContainer,
                child: Icon(categoryIcon(parent?.icon ?? category?.icon), color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(parent?.displayName(lang) ?? '', style: theme.textTheme.labelMedium, overflow: TextOverflow.ellipsis),
                  Text(category?.displayName(lang) ?? 'Uncategorised',
                      style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis),
                ]),
              ),
              _UrgencyChip(bill.urgency),
            ]),
            const SizedBox(height: 16),
            Text(bill.merchantName, style: theme.textTheme.headlineSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
            if (bill.city != null || bill.billDate != null)
              Text(
                [if (bill.city != null) bill.city!, if (bill.billDate != null) DateFormat.yMMMd().format(bill.billDate!)]
                    .join(' · '),
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Text(bill.fundingPurpose, style: theme.textTheme.bodyLarge),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 4, children: [
              _Pill(
                icon: verified ? Icons.verified : Icons.hourglass_top,
                label: verified ? 'Receipt verified' : 'Verification pending',
                color: verified ? Colors.green.shade700 : Colors.orange.shade800,
              ),
              _Pill(
                icon: Icons.volunteer_activism,
                label: eligibilityLabel(bill.fundingEligibility),
                color: eligibilityColor(bill.fundingEligibility, cs),
              ),
              if (category != null && category!.classification != Classification.essential)
                _Pill(icon: Icons.info_outline, label: classificationLabel(category!.classification), color: cs.tertiary),
            ]),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: bill.progress, minHeight: 8, borderRadius: BorderRadius.circular(4)),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Requested ${formatMoney(bill.amount, bill.currency)}', style: theme.textTheme.bodyMedium),
              Text('${formatMoney(bill.remainingAmount, bill.currency)} left',
                  style: theme.textTheme.titleMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.bold)),
            ]),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Pill({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
}

class _UrgencyChip extends StatelessWidget {
  final Urgency urgency;
  const _UrgencyChip(this.urgency);

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (urgency) {
      Urgency.critical => ('Critical', Colors.red.shade700),
      Urgency.high => ('High', Colors.deepOrange),
      Urgency.medium => ('Medium', Colors.amber.shade800),
      Urgency.low => ('Low', Colors.blueGrey),
    };
    return _Pill(icon: Icons.schedule, label: label, color: color);
  }
}
