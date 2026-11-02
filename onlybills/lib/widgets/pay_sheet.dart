import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../models/bill.dart';
import '../models/payment.dart';
import 'bill_card.dart';

/// One-tap payment sheet. Amount and method are pre-selected from the donor's own
/// history (see functions/payments.js); the donor can change either before paying.
Future<PaymentResult?> showPaySheet(BuildContext context, Repository repo, Bill bill) =>
    showModalBottomSheet<PaymentResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _PaySheet(repo: repo, bill: bill),
    );

const _methodIcons = {
  'upi': Icons.qr_code_2,
  'card': Icons.credit_card,
  'netbanking': Icons.account_balance,
  'wallet': Icons.account_balance_wallet,
};

enum _Stage { loading, choose, paying, done }

class _PaySheet extends StatefulWidget {
  final Repository repo;
  final Bill bill;
  const _PaySheet({required this.repo, required this.bill});

  @override
  State<_PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends State<_PaySheet> {
  _Stage _stage = _Stage.loading;
  CheckoutPlan? _plan;
  double _amount = 0;
  String? _method;
  PaymentResult? _result;
  String? _error;
  final _custom = TextEditingController();
  final Set<String> _failedMethods = {};

  Bill get bill => widget.bill;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({double? amount}) async {
    try {
      final plan = await widget.repo.getCheckout(bill.billId, amount: amount);
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _amount = amount ?? plan.defaultAmount;
        // Keep the donor's manual choice if it is still allowed for this amount.
        final allowed = plan.methods.map((m) => m.method).toSet();
        final firstWorking = plan.methods.firstWhere((m) => !_failedMethods.contains(m.method),
            orElse: () => plan.methods.first);
        if (_method == null || !allowed.contains(_method) || _failedMethods.contains(_method)) {
          _method = firstWorking.method;
        }
        _stage = _Stage.choose;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _setAmount(double v) {
    _custom.clear();
    setState(() => _amount = v);
    _load(amount: v); // ranking depends on amount (UPI limits, large-payment success rates)
  }

  Future<void> _pay() async {
    setState(() => _stage = _Stage.paying);
    try {
      final r = await widget.repo.pay(bill.billId, _amount, _method!);
      if (!mounted) return;
      if (r.status == PaymentStatus.captured) {
        setState(() {
          _result = r;
          _stage = _Stage.done;
        });
      } else {
        if (r.status == PaymentStatus.failed) _failedMethods.add(_method!);
        final failedLabel = _option(_method!)?.label ?? _method!;
        setState(() => _error = r.status == PaymentStatus.cancelled
            ? null
            : '$failedLabel payment didn\'t go through. ${r.message ?? 'No money was taken.'}');
        await _load(amount: _amount); // re-rank with the failure counted
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _stage = _Stage.choose;
        });
      }
    }
  }

  PaymentOption? _option(String method) {
    for (final m in _plan?.methods ?? const <PaymentOption>[]) {
      if (m.method == method) return m;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    String money(double v) => formatMoney(v, bill.currency);

    Widget body;
    switch (_stage) {
      case _Stage.loading:
        body = SizedBox(
          height: 240,
          child: Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!)),
        );
      case _Stage.paying:
        body = SizedBox(
          height: 240,
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('Paying ${money(_amount)} with ${_option(_method!)?.label ?? _method}…'),
            ]),
          ),
        );
      case _Stage.done:
        final r = _result!;
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle, color: Colors.green.shade700, size: 64),
          const SizedBox(height: 12),
          Text('Thank you!', style: t.headlineSmall),
          const SizedBox(height: 8),
          Text(
            r.message ??
                (r.remainingAmount <= 0
                    ? 'You paid ${money(r.applied)}. This bill is now fully funded.'
                    : 'You paid ${money(r.applied)}. ${money(r.remainingAmount)} still needed.'),
            textAlign: TextAlign.center,
          ),
          if (r.refundDue > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('${money(r.refundDue)} was more than needed and will be refunded to you.',
                  textAlign: TextAlign.center, style: t.bodySmall),
            ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: () => Navigator.pop(context, r), child: const Text('Done')),
          ),
        ]);
      case _Stage.choose:
        final plan = _plan!;
        final selected = _option(_method!);
        body = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('Fund ${bill.merchantName}', style: t.titleLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
          Text('${money(bill.remainingAmount)} still needed', style: t.bodyMedium),
          const SizedBox(height: 16),
          Text('Amount', style: t.titleSmall),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final a in plan.amounts)
              ChoiceChip(
                label: Text(money(a.toDouble())),
                selected: _amount == a && _custom.text.isEmpty,
                onSelected: (_) => _setAmount(a.toDouble()),
              ),
            ChoiceChip(
              label: Text('All ${money(plan.payRemaining)}'),
              selected: _amount == plan.payRemaining && _custom.text.isEmpty,
              onSelected: (_) => _setAmount(plan.payRemaining),
            ),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _custom,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(prefixText: '₹ ', hintText: 'Other amount', isDense: true),
            onSubmitted: (v) {
              final n = double.tryParse(v);
              if (n != null && n > 0 && n <= plan.payRemaining) {
                setState(() => _amount = n);
                _load(amount: n);
              }
            },
          ),
          const SizedBox(height: 16),
          Text('Pay with', style: t.titleSmall),
          const SizedBox(height: 4),
          RadioGroup<String>(
            groupValue: _method,
            onChanged: (v) => setState(() => _method = v),
            child: Column(children: [
              for (final m in plan.methods)
                RadioListTile<String>(
                  value: m.method,
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(_methodIcons[m.method] ?? Icons.payment),
                  title: Row(children: [
                    Flexible(child: Text(m.label, overflow: TextOverflow.ellipsis)),
                    if (m.recommended) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
                        child: Text('Best for you',
                            style: TextStyle(fontSize: 11, color: cs.onPrimaryContainer, fontWeight: FontWeight.w600)),
                      ),
                    ],
                    if (_failedMethods.contains(m.method)) ...[
                      const SizedBox(width: 8),
                      Text('failed just now', style: TextStyle(fontSize: 11, color: cs.error)),
                    ],
                  ]),
                  subtitle: Text(m.reasons.join(' · '), style: t.bodySmall),
                ),
            ]),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: cs.error)),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              icon: Icon(_methodIcons[_method] ?? Icons.lock),
              onPressed: _amount > 0 ? _pay : null,
              label: Text('Pay ${money(_amount)} with ${selected?.label ?? ''}'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Money goes to the merchant or verified beneficiary, not to the person who uploaded the bill.'
            '${(selected?.fee ?? 0) > 0 ? ' The payment provider deducts a ₹${selected!.fee} fee.' : ''}',
            style: t.bodySmall,
          ),
        ]);
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(child: body),
    );
  }
}
