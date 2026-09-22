import 'package:flutter/material.dart';

class CategoryInfo {
  const CategoryInfo(this.name, this.color, this.icon, this.emoji);
  final String name;
  final Color color;
  final IconData icon;
  final String emoji;
}

/// Single source of truth for categories — chips, charts and list items all
/// read their colour/icon from here so they stay consistent.
const kCategories = <CategoryInfo>[
  CategoryInfo('Food', Color(0xFFF59E0B), Icons.restaurant_rounded, '🍔'),
  CategoryInfo('Fuel', Color(0xFFEF4444), Icons.local_gas_station_rounded, '⛽'),
  CategoryInfo('Grocery', Color(0xFF22C55E), Icons.shopping_basket_rounded, '🛒'),
  CategoryInfo('Health', Color(0xFFEC4899), Icons.medical_services_rounded, '💊'),
  CategoryInfo('Shopping', Color(0xFF8B5CF6), Icons.shopping_bag_rounded, '🛍️'),
  CategoryInfo('Bills', Color(0xFF3B82F6), Icons.receipt_long_rounded, '🧾'),
  CategoryInfo('Travel', Color(0xFF06B6D4), Icons.directions_car_rounded, '🚕'),
  CategoryInfo('Entertainment', Color(0xFFF97316), Icons.movie_rounded, '🎬'),
  CategoryInfo('Other', Color(0xFF6B7280), Icons.category_rounded, '📦'),
];

final Map<String, CategoryInfo> _byName = {
  for (final c in kCategories) c.name.toLowerCase(): c,
};

/// Unknown names fall back to "Other".
CategoryInfo categoryInfo(String name) =>
    _byName[name.trim().toLowerCase()] ?? kCategories.last;

const kPaymentMethods = ['Cash', 'UPI', 'Card', 'Unknown'];
