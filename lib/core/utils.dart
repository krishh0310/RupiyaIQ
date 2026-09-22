import 'package:intl/intl.dart';

// en_IN gives Indian digit grouping: ₹1,23,456
final _inr0 = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _inr2 = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

/// ₹12,340 — rounded, for summaries.
String formatInr(num v) => _inr0.format(v);

/// ₹435.75 when there are paise, ₹415 when not — for bill details.
String formatInrExact(num v) =>
    v == v.roundToDouble() ? _inr0.format(v) : _inr2.format(v);

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
String shortDate(DateTime d) => DateFormat('d MMM').format(d);
String longDate(DateTime d) => DateFormat('EEE, d MMM yyyy').format(d);
String monthLabel(DateTime d) => DateFormat('MMMM yyyy').format(d);

String relativeDayLabel(DateTime d, {DateTime? now}) {
  final today = dayOnly(now ?? DateTime.now());
  final diff = today.difference(dayOnly(d)).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return DateFormat(d.year == today.year ? 'EEEE, d MMM' : 'd MMM yyyy').format(d);
}

String greeting([DateTime? now]) {
  final h = (now ?? DateTime.now()).hour;
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}

/// Lenient parse: "₹1,234.50" → 1234.5
double? parseAmount(String s) =>
    double.tryParse(s.replaceAll(RegExp(r'[^0-9.\-]'), ''));

double round2(double v) => (v * 100).roundToDouble() / 100;

/// Percentage change, null when there is no baseline.
double? pctChange(double current, double previous) =>
    previous <= 0 ? null : (current - previous) / previous * 100;
