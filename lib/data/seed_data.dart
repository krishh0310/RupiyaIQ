import 'package:sqflite/sqflite.dart';

import '../core/utils.dart';

/// One fake bill: (days ago, merchant, category, payment, tax rate, items).
typedef _Seed = (int, String, String, String, double, List<(String, double, double)>);

/// 25 realistic bills over the last 45 days. Tuned so that:
///  • this week's Food is clearly above last week's (insight material),
///  • the ₹5,200 Amazon order 3 days ago is the single anomaly
///    (≈4.8× the 30-day Shopping average),
///  • Shopping blows its budget (red bar) while Food stays green.
const List<_Seed> _seeds = [
  (0, 'Zomato', 'Food', 'UPI', 0.05, [('Paneer Butter Masala', 280, 1), ('Butter Naan', 45, 3)]),
  (1, 'Big Bazaar', 'Grocery', 'Card', 0, [('Basmati Rice 5kg', 520, 1), ('Toor Dal 1kg', 165, 1), ('Amul Butter 100g', 58, 2), ('Tata Salt 1kg', 28, 1)]),
  (2, 'Indian Oil', 'Fuel', 'UPI', 0, [('Petrol (litre)', 104.6, 11.2)]),
  (3, 'Amazon', 'Shopping', 'Card', 0, [('Noise ColorFit Smartwatch', 3499, 1), ('boAt Airdopes 141', 1701, 1)]),
  (3, 'Zomato', 'Food', 'UPI', 0.05, [('Veg Thali', 249, 1), ('Masala Chaas', 49, 1)]),
  (4, 'Uber', 'Travel', 'UPI', 0, [('Uber Go — Airport', 612, 1)]),
  (5, 'Apollo Pharmacy', 'Health', 'Cash', 0, [('Dolo 650 (strip)', 32, 2), ('Vitamin C tablets', 145, 1), ('Band-Aid pack', 45, 1)]),
  (6, 'Zomato', 'Food', 'Card', 0.05, [('Farmhouse Pizza', 399, 1), ('Garlic Breadsticks', 149, 1)]),
  (9, 'Electricity Board', 'Bills', 'UPI', 0, [('Electricity bill — Aug', 1845, 1)]),
  (10, 'Big Bazaar', 'Grocery', 'UPI', 0, [('Fortune Sunflower Oil 1L', 185, 1), ('Aashirvaad Atta 5kg', 265, 1), ('Milk 1L', 66, 4)]),
  (12, 'Indian Oil', 'Fuel', 'Card', 0, [('Petrol', 1000, 1)]),
  (13, 'PVR Cinemas', 'Entertainment', 'Card', 0.18, [('Movie ticket', 280, 2), ('Popcorn combo', 350, 1)]),
  (15, 'Amazon', 'Shopping', 'UPI', 0, [('Phone cover', 399, 1), ('USB-C cable', 500, 1)]),
  (17, 'Uber', 'Travel', 'Cash', 0, [('Uber Auto', 186, 1)]),
  (18, 'Zomato', 'Food', 'UPI', 0.05, [('Burger combo', 329, 1)]),
  (20, 'Apollo Pharmacy', 'Health', 'UPI', 0, [('Cough syrup', 118, 1), ('Digital thermometer', 299, 1)]),
  (22, 'Big Bazaar', 'Grocery', 'Card', 0, [('Vegetables', 342, 1), ('Fruits', 280, 1), ('Eggs (30)', 210, 1)]),
  (24, 'Amazon', 'Shopping', 'Card', 0, [('Laptop backpack', 1249, 1)]),
  (27, 'Indian Oil', 'Fuel', 'UPI', 0, [('Petrol', 1500, 1)]),
  (30, 'Zomato', 'Food', 'UPI', 0.05, [('Masala Dosa', 180, 1), ('Filter Coffee', 60, 1)]),
  (33, 'Uber', 'Travel', 'UPI', 0, [('Uber Go', 342, 1)]),
  (36, 'Airtel Postpaid', 'Bills', 'UPI', 0, [('Monthly plan', 599, 1)]),
  (40, 'Big Bazaar', 'Grocery', 'Cash', 0, [('Sona Masoori Rice 10kg', 980, 1), ('Sunflower Oil 5L', 820, 1), ('Sugar 2kg', 110, 1), ('Tea 500g', 230, 1)]),
  (43, 'Electricity Board', 'Bills', 'UPI', 0, [('Electricity bill — Jul', 1620, 1)]),
  (44, 'Chai Point', 'Food', 'Cash', 0, [('Masala Chai', 45, 1)]),
];

const _seedBudgets = {
  'Food': 3000.0,
  'Grocery': 4000.0,
  'Fuel': 3000.0,
  'Shopping': 4000.0,
  'Travel': 1500.0,
  'Health': 1000.0,
  'Bills': 2500.0,
  'Entertainment': 1500.0,
};

Future<void> insertSeedData(DatabaseExecutor db, {DateTime? now}) async {
  final today = dayOnly(now ?? DateTime.now());
  for (final (daysAgo, merchant, category, payment, taxRate, items) in _seeds) {
    final subtotal = round2(items.fold(0.0, (s, i) => s + i.$2 * i.$3));
    final tax = round2(subtotal * taxRate);
    final date = today.subtract(Duration(days: daysAgo));
    final id = await db.insert('expenses', {
      'merchant': merchant,
      'date': isoDate(date),
      'category': category,
      'subtotal': subtotal,
      'tax': tax,
      'total': round2(subtotal + tax),
      'payment_method': payment,
      'image_path': null,
      'raw_ocr': null,
      'confidence': 1.0,
      'created_at': date.add(const Duration(hours: 13)).toIso8601String(),
      'is_anomaly': 0, // computed by the anomaly engine on first load
    });
    for (final (name, price, qty) in items) {
      await db.insert('items', {'expense_id': id, 'name': name, 'price': price, 'quantity': qty});
    }
  }
  for (final b in _seedBudgets.entries) {
    await db.insert('budgets', {'category': b.key, 'monthly_limit': b.value});
  }
}
