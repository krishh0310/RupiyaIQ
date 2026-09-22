import '../core/utils.dart';

class ExpenseItem {
  const ExpenseItem({this.id, required this.name, required this.price, this.quantity = 1});

  final int? id;
  final String name;

  /// Unit price; line total = price × quantity.
  final double price;
  final double quantity;

  double get lineTotal => price * quantity;

  Map<String, Object?> toMap(int expenseId) => {
        'expense_id': expenseId,
        'name': name,
        'price': price,
        'quantity': quantity,
      };

  factory ExpenseItem.fromMap(Map<String, Object?> m) => ExpenseItem(
        id: m['id'] as int?,
        name: (m['name'] as String?) ?? '',
        price: (m['price'] as num?)?.toDouble() ?? 0,
        quantity: (m['quantity'] as num?)?.toDouble() ?? 1,
      );
}

class Expense {
  const Expense({
    this.id,
    required this.merchant,
    required this.date,
    required this.category,
    this.subtotal = 0,
    this.tax = 0,
    required this.total,
    this.paymentMethod = 'Unknown',
    this.imagePath,
    this.rawOcr,
    this.confidence = 0,
    required this.createdAt,
    this.isAnomaly = false,
    this.items = const [],
  });

  final int? id;
  final String merchant;
  final DateTime date;
  final String category;
  final double subtotal;
  final double tax;
  final double total;
  final String paymentMethod;
  final String? imagePath;
  final String? rawOcr;
  final double confidence;
  final DateTime createdAt;
  final bool isAnomaly;
  final List<ExpenseItem> items;

  bool get hasImage => imagePath != null && imagePath!.isNotEmpty;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'merchant': merchant,
        'date': isoDate(date),
        'category': category,
        'subtotal': subtotal,
        'tax': tax,
        'total': total,
        'payment_method': paymentMethod,
        'image_path': imagePath,
        'raw_ocr': rawOcr,
        'confidence': confidence,
        'created_at': createdAt.toIso8601String(),
        'is_anomaly': isAnomaly ? 1 : 0,
      };

  factory Expense.fromMap(Map<String, Object?> m, List<ExpenseItem> items) => Expense(
        id: m['id'] as int?,
        merchant: (m['merchant'] as String?) ?? '',
        date: DateTime.tryParse((m['date'] as String?) ?? '') ?? DateTime.now(),
        category: (m['category'] as String?) ?? 'Other',
        subtotal: (m['subtotal'] as num?)?.toDouble() ?? 0,
        tax: (m['tax'] as num?)?.toDouble() ?? 0,
        total: (m['total'] as num?)?.toDouble() ?? 0,
        paymentMethod: (m['payment_method'] as String?) ?? 'Unknown',
        imagePath: m['image_path'] as String?,
        rawOcr: m['raw_ocr'] as String?,
        confidence: (m['confidence'] as num?)?.toDouble() ?? 0,
        createdAt: DateTime.tryParse((m['created_at'] as String?) ?? '') ?? DateTime.now(),
        isAnomaly: (m['is_anomaly'] as int? ?? 0) == 1,
        items: items,
      );

  Expense copyWith({
    int? id,
    String? merchant,
    DateTime? date,
    String? category,
    double? subtotal,
    double? tax,
    double? total,
    String? paymentMethod,
    String? imagePath,
    String? rawOcr,
    double? confidence,
    DateTime? createdAt,
    bool? isAnomaly,
    List<ExpenseItem>? items,
  }) =>
      Expense(
        id: id ?? this.id,
        merchant: merchant ?? this.merchant,
        date: date ?? this.date,
        category: category ?? this.category,
        subtotal: subtotal ?? this.subtotal,
        tax: tax ?? this.tax,
        total: total ?? this.total,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        imagePath: imagePath ?? this.imagePath,
        rawOcr: rawOcr ?? this.rawOcr,
        confidence: confidence ?? this.confidence,
        createdAt: createdAt ?? this.createdAt,
        isAnomaly: isAnomaly ?? this.isAnomaly,
        items: items ?? this.items,
      );
}

/// Category → total, sorted biggest first.
Map<String, double> totalsByCategory(Iterable<Expense> expenses) {
  final totals = <String, double>{};
  for (final e in expenses) {
    totals[e.category] = (totals[e.category] ?? 0) + e.total;
  }
  final sorted = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return Map.fromEntries(sorted);
}

double sumTotals(Iterable<Expense> expenses) => expenses.fold(0.0, (s, e) => s + e.total);
