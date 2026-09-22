import 'package:flutter_test/flutter_test.dart';
import 'package:rupiya_iq/data/models.dart';
import 'package:rupiya_iq/data/repositories/expense_repository.dart';
import 'package:rupiya_iq/data/services/gemini_service.dart';
import 'package:rupiya_iq/features/insights/anomaly_engine.dart';
import 'package:rupiya_iq/features/scan/receipt_parser.dart';

Expense _e(int id, String cat, double total, DateTime date, {String merchant = 'Shop'}) =>
    Expense(id: id, merchant: merchant, date: date, category: cat, total: total, createdAt: date);

void main() {
  final today = DateTime(2026, 9, 22);

  test('anomaly engine flags only the outlier', () {
    final list = [
      _e(1, 'Shopping', 899, today.subtract(const Duration(days: 15))),
      _e(2, 'Shopping', 1249, today.subtract(const Duration(days: 24))),
      _e(3, 'Shopping', 5200, today.subtract(const Duration(days: 3))),
      _e(4, 'Food', 300, today),
      _e(5, 'Food', 320, today.subtract(const Duration(days: 2))),
      _e(6, 'Food', 280, today.subtract(const Duration(days: 4))),
    ];
    final a = AnomalyDetectionEngine.detect(list);
    expect(a.map((x) => x.expense.id), [3]);
    expect(a.single.ratio, closeTo(5200 / 1074, 0.01));
  });

  test('anomaly engine needs 2 history points and a 30-day window', () {
    final list = [
      _e(1, 'Bills', 100, today.subtract(const Duration(days: 40))),
      _e(2, 'Bills', 100, today.subtract(const Duration(days: 35))),
      _e(3, 'Bills', 9000, today),
    ];
    expect(AnomalyDetectionEngine.detect(list), isEmpty);
  });

  test('duplicate score', () {
    final a = _e(1, 'Food', 435.75, today, merchant: 'Zomato');
    expect(duplicateScore(a, _e(2, 'Food', 435.75, today, merchant: 'ZOMATO.')), greaterThanOrEqualTo(0.95));
    expect(duplicateScore(a, _e(3, 'Food', 300, today, merchant: 'Swiggy')), lessThan(0.95));
  });

  test('receipt parser is defensive', () {
    final e = ReceiptParser.fromGemini({
      'merchant': 'Apollo Pharmacy',
      'date': '2099-01-01',
      'items': [
        {'name': 'Dolo 650', 'price': '32', 'quantity': 2},
        {'name': '', 'price': 5},
      ],
      'total': null,
      'category': 'health',
      'payment_method': 'Paid by GPay',
      'confidence': 3,
    }, rawOcr: 'x', now: today);
    expect(e.date, today);
    expect(e.items.length, 1);
    expect(e.total, 64);
    expect(e.category, 'Health');
    expect(e.paymentMethod, 'UPI');
    expect(e.confidence, 1);
  });

  test('offline OCR fallback', () {
    final e = ReceiptParser.fromOcrFallback('BIG BAZAAR\nDate: 12/09/2026\nRice 520.00\nSub Total 520.00\nGrand Total 1,234.50\nCash', now: today);
    expect(e.merchant, 'BIG BAZAAR');
    expect(e.total, 1234.5);
    expect(e.date, DateTime(2026, 9, 12));
    expect(e.paymentMethod, 'Cash');
  });

  test('offline fallback when ML Kit splits "GRAND TOTAL" from its amount', () {
    // Block order ML Kit typically returns for assets/test_receipt.jpg.
    const ocr = 'FRESHMART SUPERMARKET\n12, MG Road, Bengaluru 560001\nBill No: FM-20931\n'
        'Date: 21/09/2026\nAashirvaad Atta 5kg\nSub Total\nGST 5%\nGRAND TOTAL\n'
        'Paid by UPI\n265.00\n1212.00\n60.60\nRs 1,272.60\n1272.60';
    final e = ReceiptParser.fromOcrFallback(ocr, now: today);
    expect(e.merchant, 'FRESHMART SUPERMARKET');
    expect(e.total, 1272.6); // not the bill number 20931
    expect(e.paymentMethod, 'UPI');
    expect(e.date, DateTime(2026, 9, 21));
  });

  test('loose JSON decode handles fences', () {
    expect(GeminiService.decodeJsonLoose('```json\n{"a":1}\n```'), {'a': 1});
    expect(GeminiService.decodeJsonLoose('Sure! [1,2] hope that helps'), [1, 2]);
    expect(GeminiService.decodeJsonLoose('nope'), isNull);
  });
}
