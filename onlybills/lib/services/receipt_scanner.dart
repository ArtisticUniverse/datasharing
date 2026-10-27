import 'dart:io';

import 'package:exif/exif.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'redaction.dart';

class ReceiptScan {
  final String? merchantName;
  final double? total;
  final DateTime? date;
  final String suggestedCategoryId;
  final double confidence;
  final String redactedText;
  final List<double> lineItemTotals;
  final Map<String, dynamic> imageMetadata;

  const ReceiptScan({
    this.merchantName,
    this.total,
    this.date,
    required this.suggestedCategoryId,
    required this.confidence,
    required this.redactedText,
    this.lineItemTotals = const [],
    this.imageMetadata = const {},
  });

  Map<String, dynamic> toOcrMap() => {
        'rawText': redactedText,
        'extractedTotal': total,
        'lineItemTotals': lineItemTotals,
        'suggestedCategoryId': suggestedCategoryId,
        'confidence': confidence,
      };
}

/// On-device OCR (ML Kit) plus heuristic extraction. Nothing leaves the device
/// until the user reviews and submits, and the text is redacted first.
/// Keyword lists mirror functions/rules.js MERCHANT_KEYWORDS, which makes the final call.
class ReceiptScanner {
  static const merchantKeywords = <String, List<String>>{
    'pets': ['veterinary', 'vet', 'pet', 'pets', 'animal'],
    'healthcare': ['hospital', 'hospitals', 'clinic', 'pharmacy', 'medical', 'diagnostic', 'diagnostics', 'pathology', 'apollo', 'medplus', 'dental', 'nursing', 'lab', 'labs', 'chemist'],
    'food': ['restaurant', 'cafe', 'kitchen', 'dhaba', 'swiggy', 'zomato', 'bakery', 'dmart', 'grocery', 'grocers', 'supermarket', 'bigbasket', 'foods', 'sweets'],
    'restricted_recreational': ['wine', 'wines', 'liquor', 'beer', 'bar', 'pub', 'spirits', 'tobacco', 'vape', 'hookah', 'cigar', 'cigars', 'paan'],
    'education': ['school', 'college', 'university', 'academy', 'coaching', 'institute', 'tuition', 'books', 'book', 'stationery'],
    'housing': ['electricity', 'power', 'water board', 'jal board', 'gas', 'bescom', 'rent', 'plumbing', 'plumber', 'pest'],
    'transport': ['railway', 'railways', 'irctc', 'metro', 'uber', 'ola', 'petrol', 'fuel', 'bus', 'redbus', 'motors', 'garage'],
    'technology': ['jio', 'airtel', 'vodafone', 'vi', 'bsnl', 'broadband', 'recharge', 'mobile'],
    'government': ['municipal', 'corporation', 'passport', 'government', 'nagar', 'registrar'],
  };

  static ({String categoryId, double confidence}) suggestCategory(String merchant, String text) {
    final hay = '$merchant $text'.toLowerCase();
    String? best;
    var bestScore = 0;
    merchantKeywords.forEach((cat, words) {
      final score = words.where((w) => RegExp('\\b${RegExp.escape(w)}\\b').hasMatch(hay)).length;
      if (score > bestScore) {
        best = cat;
        bestScore = score;
      }
    });
    return best == null
        ? (categoryId: 'other', confidence: 0.1)
        : (categoryId: best!, confidence: (0.5 + 0.15 * bestScore).clamp(0, 0.95).toDouble());
  }

  static final _totalLine = RegExp(r'(grand\s*total|net\s*amount|total\s*amount|amount\s*payable|total)\D{0,12}([\d,]+\.?\d{0,2})', caseSensitive: false);
  static final _money = RegExp(r'(?:₹|rs\.?|inr)?\s*([\d,]+\.\d{2})\s*$', caseSensitive: false);
  static final _date = RegExp(r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b');

  Future<ReceiptScan> scan(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(imagePath));
      final lines = result.blocks.expand((b) => b.lines).map((l) => l.text.trim()).where((l) => l.isNotEmpty).toList();
      return parse(lines, imageMetadata: await _metadata(imagePath));
    } finally {
      await recognizer.close();
    }
  }

  /// Pure parsing step, separated from ML Kit so it can be unit tested.
  static ReceiptScan parse(List<String> lines, {Map<String, dynamic> imageMetadata = const {}}) {
    final text = lines.join('\n');
    // Merchant is usually the first line that isn't a number, date or "Tax Invoice".
    final merchant = lines.firstWhere(
      (l) => RegExp(r'[A-Za-z]{3,}').hasMatch(l) && !RegExp(r'invoice|receipt|bill|gst', caseSensitive: false).hasMatch(l),
      orElse: () => '',
    );

    double? total;
    for (final m in _totalLine.allMatches(text)) {
      final v = double.tryParse(m.group(2)!.replaceAll(',', ''));
      if (v != null && (total == null || v > total)) total = v; // grand total is usually the largest "total"
    }
    final lineItems = <double>[];
    for (final l in lines) {
      if (RegExp(r'total|tax|gst|change|cash|paid', caseSensitive: false).hasMatch(l)) continue;
      final m = _money.firstMatch(l);
      if (m != null) lineItems.add(double.parse(m.group(1)!.replaceAll(',', '')));
    }

    DateTime? date;
    final dm = _date.firstMatch(text);
    if (dm != null) {
      var y = int.parse(dm.group(3)!);
      if (y < 100) y += 2000;
      final d = int.parse(dm.group(1)!), mo = int.parse(dm.group(2)!);
      if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31) date = DateTime(y, mo, d); // Indian DD/MM/YYYY
    }

    final s = suggestCategory(merchant, text);
    return ReceiptScan(
      merchantName: merchant.isEmpty ? null : merchant,
      total: total,
      date: date,
      suggestedCategoryId: s.categoryId,
      confidence: s.confidence,
      redactedText: Redactor.redact(text),
      lineItemTotals: lineItems,
      imageMetadata: imageMetadata,
    );
  }

  static Future<Map<String, dynamic>> _metadata(String path) async {
    try {
      final tags = await readExifFromBytes(await File(path).readAsBytes());
      return {
        if (tags['Image Software'] != null) 'software': tags['Image Software'].toString(),
        if (tags['Image DateTime'] != null) 'exifDateTime': tags['Image DateTime'].toString(),
        if (tags['Image Model'] != null) 'cameraModel': tags['Image Model'].toString(),
      };
    } catch (_) {
      return const {};
    }
  }
}
