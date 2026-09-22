import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../data/models.dart';

/// Turns AI output (or, offline, raw OCR text) into an [Expense] draft.
/// Everything here is defensive: the model may return strings for numbers,
/// unknown categories, missing totals, or a hallucinated future date.
class ReceiptParser {
  static Expense fromGemini(
    Map<String, dynamic> json, {
    required String rawOcr,
    String? imagePath,
    DateTime? now,
  }) {
    final today = dayOnly(now ?? DateTime.now());
    final items = <ExpenseItem>[];
    final rawItems = json['items'];
    if (rawItems is List) {
      for (final i in rawItems.whereType<Map>()) {
        final name = '${i['name'] ?? ''}'.trim();
        if (name.isEmpty) continue;
        final qty = _num(i['quantity']);
        items.add(ExpenseItem(name: name, price: _num(i['price']), quantity: qty <= 0 ? 1 : qty));
      }
    }
    final itemsSum = round2(items.fold(0.0, (s, i) => s + i.lineTotal));
    final tax = _num(json['tax']);
    var subtotal = _num(json['subtotal']);
    if (subtotal <= 0) subtotal = itemsSum;
    var total = _num(json['total']);
    if (total <= 0) total = subtotal > 0 ? subtotal + tax : itemsSum;

    var date = DateTime.tryParse('${json['date'] ?? ''}') ?? today;
    // A bill dated in the future is an OCR/AI misread.
    if (date.isAfter(today.add(const Duration(days: 1)))) date = today;

    final merchant = '${json['merchant'] ?? ''}'.trim();
    return Expense(
      merchant: merchant.isEmpty ? 'Unknown merchant' : merchant,
      date: dayOnly(date),
      category: normalizeCategory(json['category']),
      subtotal: round2(subtotal),
      tax: round2(tax),
      total: round2(total),
      paymentMethod: normalizePayment(json['payment_method']),
      imagePath: imagePath,
      rawOcr: rawOcr,
      confidence: _num(json['confidence']).clamp(0.0, 1.0).toDouble(),
      createdAt: DateTime.now(),
      items: items,
    );
  }

  /// Offline / AI-failure fallback: a few cheap heuristics so the manual
  /// entry form isn't blank. Confidence 0 marks it as "please verify".
  static Expense fromOcrFallback(String rawOcr, {String? imagePath, DateTime? now}) {
    final today = dayOnly(now ?? DateTime.now());
    final lines = rawOcr.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    // Merchant: first line with at least 3 letters (shop name is usually on top).
    final merchant = lines.firstWhere(
      (l) => RegExp(r'[A-Za-z]').allMatches(l).length >= 3,
      orElse: () => '',
    );

    // Total: last amount on (or, since ML Kit often splits label and value
    // into separate blocks, just after) the last line mentioning a total.
    final amountRe = RegExp(r'\d{1,3}(?:,\d{2,3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?');
    double? lastAmount(String line) {
      final m = amountRe.allMatches(line).toList();
      return m.isEmpty ? null : double.tryParse(m.last.group(0)!.replaceAll(',', ''));
    }

    double? total;
    for (var i = lines.length - 1; i >= 0 && total == null; i--) {
      final lower = lines[i].toLowerCase();
      if ((lower.contains('total') && !lower.contains('sub')) ||
          lower.contains('amount payable') ||
          lower.contains('net amount')) {
        total = lastAmount(lines[i]) ?? (i + 1 < lines.length ? lastAmount(lines[i + 1]) : null);
      }
    }
    // Else the biggest money-looking amount. Prefer ones with paise ("1,272.60")
    // so bill numbers, phone numbers and PIN codes don't win.
    if (total == null) {
      final all = amountRe.allMatches(rawOcr).map((m) => m.group(0)!).toList();
      final withPaise = all.where((s) => RegExp(r'\.\d{2}$').hasMatch(s)).toList();
      final values = (withPaise.isNotEmpty ? withPaise : all)
          .map((s) => double.tryParse(s.replaceAll(',', '')) ?? 0)
          .where((v) => v > 0 && v < 200000);
      if (values.isNotEmpty) total = values.reduce((a, b) => a > b ? a : b);
    }

    // Date: Indian dd/mm/yyyy (or dd-mm-yy).
    var date = today;
    final dm = RegExp(r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b').firstMatch(rawOcr);
    if (dm != null) {
      final d = int.parse(dm.group(1)!), mo = int.parse(dm.group(2)!);
      var y = int.parse(dm.group(3)!);
      if (y < 100) y += 2000;
      if (d >= 1 && d <= 31 && mo >= 1 && mo <= 12) {
        final parsed = DateTime(y, mo, d);
        if (!parsed.isAfter(today)) date = parsed;
      }
    }

    return Expense(
      merchant: merchant.length > 40 ? merchant.substring(0, 40) : merchant,
      date: date,
      category: 'Other',
      total: total ?? 0,
      subtotal: total ?? 0,
      paymentMethod: normalizePayment(rawOcr),
      imagePath: imagePath,
      rawOcr: rawOcr,
      confidence: 0,
      createdAt: DateTime.now(),
    );
  }

  static String normalizeCategory(Object? v) {
    final s = '${v ?? ''}'.trim().toLowerCase();
    for (final c in kCategories) {
      if (s == c.name.toLowerCase()) return c.name;
    }
    for (final c in kCategories) {
      if (s.contains(c.name.toLowerCase())) return c.name;
    }
    return 'Other';
  }

  static String normalizePayment(Object? v) {
    final s = '${v ?? ''}'.toLowerCase();
    if (RegExp(r'upi|gpay|google pay|phonepe|paytm|bhim').hasMatch(s)) return 'UPI';
    if (RegExp(r'card|visa|mastercard|rupay|debit|credit').hasMatch(s)) return 'Card';
    if (s.contains('cash')) return 'Cash';
    return 'Unknown';
  }

  static double _num(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? ''}'.replaceAll(RegExp(r'[^0-9.\-]'), '')) ?? 0;
  }
}
