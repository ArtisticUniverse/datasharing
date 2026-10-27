import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/repository.dart';
import '../models/bill.dart';
import '../models/category.dart';
import '../services/receipt_scanner.dart';
import '../widgets/category_icon.dart';
import '../widgets/category_picker.dart';

class UploadBillScreen extends StatefulWidget {
  const UploadBillScreen({super.key});

  @override
  State<UploadBillScreen> createState() => _UploadBillScreenState();
}

class _UploadBillScreenState extends State<UploadBillScreen> {
  final _form = GlobalKey<FormState>();
  final _merchant = TextEditingController();
  final _amount = TextEditingController();
  final _purpose = TextEditingController();
  final _city = TextEditingController();
  String? _imagePath;
  ReceiptScan? _scan;
  BillCategory? _category;
  DateTime? _date;
  Urgency _urgency = Urgency.medium;
  bool _scanning = false;
  bool _submitting = false;

  Future<void> _pick(ImageSource src) async {
    final img = await ImagePicker().pickImage(source: src, maxWidth: 2400, imageQuality: 90);
    if (img == null) return;
    setState(() {
      _imagePath = img.path;
      _scanning = true;
    });
    final tree = context.read<AppState>().categories;
    try {
      final scan = await ReceiptScanner().scan(img.path);
      setState(() {
        _scan = scan;
        if (scan.merchantName != null) _merchant.text = scan.merchantName!;
        if (scan.total != null) _amount.text = scan.total!.toStringAsFixed(2);
        _date = scan.date ?? _date;
        _category = tree[scan.suggestedCategoryId];
      });
    } catch (_) {
      // OCR is a convenience; manual entry always works.
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not read the receipt. Please fill in the details.')));
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _category == null) {
      if (_category == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose a category')));
      }
      return;
    }
    if (_imagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Attach a receipt photo')));
      return;
    }
    final s = context.read<AppState>();
    final c = _category!;
    setState(() => _submitting = true);
    try {
      final r = await s.repo.submitBill(SubmitBillRequest(
        merchantName: _merchant.text.trim(),
        categoryId: c.rootId,
        subcategoryId: c.isRoot ? null : c.categoryId,
        amount: double.parse(_amount.text),
        billDate: _date,
        fundingPurpose: _purpose.text.trim(),
        city: _city.text.trim().isEmpty ? null : _city.text.trim(),
        urgency: _urgency,
        localImagePath: _imagePath!,
        suggestedCategoryId: _scan?.suggestedCategoryId,
        ocr: _scan?.toOcrMap(),
        imageMetadata: _scan?.imageMetadata,
      ));
      if (!mounted) return;
      await showDialog(context: context, builder: (_) => _ResultDialog(result: r));
      _reset();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _reset() {
    _form.currentState?.reset();
    for (final c in [_merchant, _amount, _purpose, _city]) {
      c.clear();
    }
    setState(() {
      _imagePath = null;
      _scan = null;
      _category = null;
      _date = null;
      _urgency = Urgency.medium;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final lang = s.languageCode;
    final cs = Theme.of(context).colorScheme;
    final parent = s.categories[_category?.parentCategoryId];
    final userChanged = _scan != null && _category != null && _category!.rootId != _scan!.suggestedCategoryId;

    return Scaffold(
      appBar: AppBar(title: const Text('Upload a bill')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Form(
            key: _form,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              _ReceiptBox(
                path: _imagePath,
                scanning: _scanning,
                onCamera: () => _pick(ImageSource.camera),
                onGallery: () => _pick(ImageSource.gallery),
              ),
              if (_scan != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'We read the receipt on your device and filled in what we could. '
                    'Personal details (IDs, phone numbers, account numbers) are redacted before upload. '
                    'Please check everything.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 16),
              ListTile(
                shape:
                    RoundedRectangleBorder(side: BorderSide(color: cs.outline), borderRadius: BorderRadius.circular(4)),
                leading: Icon(categoryIcon(parent?.icon ?? _category?.icon)),
                title: Text(_category?.displayName(lang) ?? 'Choose category *'),
                subtitle: _category == null
                    ? null
                    : Text([
                        if (parent != null) parent.displayName(lang),
                        if (_scan != null && !userChanged)
                          'Suggested (${(_scan!.confidence * 100).round()}% confident)',
                      ].join(' · ')),
                trailing: const Icon(Icons.edit),
                onTap: () async {
                  final c = await pickCategory(context, s.categories, lang, initialId: _category?.categoryId);
                  if (c != null) setState(() => _category = c);
                },
              ),
              if (_category != null && _category!.fundingEligibility != FundingEligibility.eligible)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _category!.fundingEligibility == FundingEligibility.restricted
                        ? 'Bills in this category are restricted and will not be shown to donors.'
                        : 'Bills in this category are reviewed by a moderator before donors can see them.',
                    style: TextStyle(color: eligibilityColor(_category!.fundingEligibility, cs)),
                  ),
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _merchant,
                decoration: const InputDecoration(labelText: 'Merchant / provider *', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().length < 2) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Amount (₹) *', border: OutlineInputBorder()),
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      if (n == null || n <= 0) return 'Enter a valid amount';
                      if (n > 500000) return 'Max ₹5,00,000 per bill';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                    icon: const Icon(Icons.event),
                    label: Text(_date == null ? 'Bill date' : DateFormat.yMMMd().format(_date!)),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _date ?? DateTime.now(),
                        firstDate: DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now(),
                      );
                      if (d != null) setState(() => _date = d);
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextFormField(
                controller: _city,
                decoration: const InputDecoration(labelText: 'City', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _purpose,
                maxLines: 4,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Why do you need help? *',
                  helperText: "Don't include names, phone numbers, ID or account numbers.",
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().length < 15) ? 'Please add a short explanation' : null,
              ),
              const SizedBox(height: 12),
              Text('Urgency', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              SegmentedButton<Urgency>(
                segments: Urgency.values
                    .map((u) => ButtonSegment(value: u, label: Text(u.name[0].toUpperCase() + u.name.substring(1))))
                    .toList(),
                selected: {_urgency},
                onSelectionChanged: (v) => setState(() => _urgency = v.first),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload),
                label: const Text('Submit for verification'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ReceiptBox extends StatelessWidget {
  final String? path;
  final bool scanning;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  const _ReceiptBox({this.path, required this.scanning, required this.onCamera, required this.onGallery});

  @override
  Widget build(BuildContext context) => Container(
        height: 200,
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(fit: StackFit.expand, children: [
          if (path != null) Image.file(File(path!), fit: BoxFit.cover),
          if (scanning)
            Container(
              color: Colors.black45,
              child: const Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 8),
                  Text('Reading receipt…', style: TextStyle(color: Colors.white)),
                ]),
              ),
            ),
          if (path == null)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              FilledButton.tonalIcon(
                  onPressed: onCamera, icon: const Icon(Icons.photo_camera), label: const Text('Camera')),
              const SizedBox(width: 12),
              OutlinedButton.icon(onPressed: onGallery, icon: const Icon(Icons.photo), label: const Text('Gallery')),
            ])
          else if (!scanning)
            Positioned(
              right: 8,
              bottom: 8,
              child: FilledButton.tonalIcon(
                  onPressed: onGallery, icon: const Icon(Icons.refresh), label: const Text('Replace')),
            ),
        ]),
      );
}

class _ResultDialog extends StatelessWidget {
  final SubmitResult result;
  const _ResultDialog({required this.result});

  static const _flagText = {
    'duplicate_receipt': 'This receipt has already been uploaded.',
    'suspicious_total': 'The amount is unusually high for this category.',
    'amount_mismatch_with_receipt': 'The amount differs from the total printed on the receipt.',
    'line_items_do_not_add_up': "The line items don't add up to the total.",
    'possible_edited_image': 'The image appears to have been edited.',
    'merchant_category_mismatch': "The merchant doesn't look like it matches the category.",
    'possible_restricted_item_miscategorised': 'The merchant may sell restricted products.',
    'future_dated': 'The bill date is in the future.',
  };

  @override
  Widget build(BuildContext context) {
    final (title, body) = switch (result.verificationStatus) {
      VerificationStatus.verified => ('Bill submitted', 'Your receipt passed automatic checks.'),
      VerificationStatus.pendingReview => (
          'Submitted for review',
          'A moderator will check this bill before donors see it.'
        ),
      VerificationStatus.rejected => ('Bill not accepted', 'This bill could not be accepted.'),
    };
    return AlertDialog(
      title: Text(title),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(body),
        const SizedBox(height: 8),
        Text('Funding: ${eligibilityLabel(result.fundingEligibility)}'),
        ...result.flags.map((f) => Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.flag_outlined, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text(_flagText[f] ?? f)),
              ]),
            )),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
    );
  }
}
