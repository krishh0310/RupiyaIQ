import 'package:intl/intl.dart';

import '../../core/utils.dart';
import '../../data/models.dart';

enum InsightPeriod { week, month }

class DateRange {
  const DateRange(this.start, this.end);
  final DateTime start; // inclusive
  final DateTime end; // exclusive
  bool contains(DateTime d) => !d.isBefore(start) && d.isBefore(end);
}

extension InsightPeriodX on InsightPeriod {
  String get label => this == InsightPeriod.week ? 'week' : 'month';

  /// Week = last 7 days including today. Month = current calendar month.
  DateRange current(DateTime now) {
    final today = dayOnly(now);
    return this == InsightPeriod.week
        ? DateRange(today.subtract(const Duration(days: 6)), today.add(const Duration(days: 1)))
        : DateRange(DateTime(now.year, now.month), DateTime(now.year, now.month + 1));
  }

  DateRange previous(DateTime now) {
    final cur = current(now);
    return this == InsightPeriod.week
        ? DateRange(cur.start.subtract(const Duration(days: 7)), cur.start)
        : DateRange(DateTime(now.year, now.month - 1), cur.start);
  }
}

/// Aggregates for one period vs the previous one. This is what gets sent to
/// Gemini — a few hundred characters of totals, never the raw bill list — so
/// prompts stay small, fast and private.
class SpendingSummary {
  SpendingSummary(List<Expense> all, this.period, {DateTime? now})
      : now = now ?? DateTime.now() {
    range = period.current(this.now);
    previousRange = period.previous(this.now);
    current = all.where((e) => range.contains(e.date)).toList();
    previous = all.where((e) => previousRange.contains(e.date)).toList();
    byCategory = totalsByCategory(current);
    previousByCategory = totalsByCategory(previous);
    total = sumTotals(current);
    previousTotal = sumTotals(previous);

    final merchants = <String, (double, int)>{};
    for (final e in current) {
      final m = merchants[e.merchant] ?? (0.0, 0);
      merchants[e.merchant] = (m.$1 + e.total, m.$2 + 1);
    }
    topMerchants = merchants.entries.toList()..sort((a, b) => b.value.$1.compareTo(a.value.$1));
    largest = [...current]..sort((a, b) => b.total.compareTo(a.total));
  }

  final InsightPeriod period;
  final DateTime now;
  late final DateRange range;
  late final DateRange previousRange;
  late final List<Expense> current;
  late final List<Expense> previous;
  late final Map<String, double> byCategory;
  late final Map<String, double> previousByCategory;
  late final double total;
  late final double previousTotal;
  late final List<MapEntry<String, (double, int)>> topMerchants;
  late final List<Expense> largest;

  bool get isEmpty => current.isEmpty && previous.isEmpty;

  String _rangeText(DateRange r) {
    final f = DateFormat('d MMM');
    return '${f.format(r.start)}–${f.format(r.end.subtract(const Duration(days: 1)))}';
  }

  /// Compact, line-oriented summary for LLM prompts. Example:
  ///   PERIOD: this week (16 Sep–22 Sep) vs previous week (9 Sep–15 Sep)
  ///   TOTAL: ₹9,387 (previous ₹4,633, change +103%)
  ///   BY CATEGORY (current | previous): Shopping ₹5,200 | ₹0; Food ₹1,324 | ₹0; …
  ///   TOP MERCHANTS: Amazon ₹5,200 (1 bills); Zomato ₹1,324 (3 bills); …
  ///   LARGEST BILLS: 19 Sep Amazon (Shopping) ₹5,200; …
  String toPromptText() {
    final cats = {...byCategory.keys, ...previousByCategory.keys};
    final change = pctChange(total, previousTotal);
    return [
      'PERIOD: this ${period.label} (${_rangeText(range)}) vs previous ${period.label} (${_rangeText(previousRange)})',
      'TOTAL: ${formatInr(total)} (previous ${formatInr(previousTotal)}'
          '${change == null ? '' : ', change ${change >= 0 ? '+' : ''}${change.toStringAsFixed(0)}%'})',
      'BILLS: ${current.length} (previous ${previous.length})',
      'BY CATEGORY (current | previous): ${cats.map((c) => '$c ${formatInr(byCategory[c] ?? 0)} | ${formatInr(previousByCategory[c] ?? 0)}').join('; ')}',
      'TOP MERCHANTS: ${topMerchants.take(5).map((m) => '${m.key} ${formatInr(m.value.$1)} (${m.value.$2} bills)').join('; ')}',
      'LARGEST BILLS: ${largest.take(5).map((e) => '${shortDate(e.date)} ${e.merchant} (${e.category}) ${formatInr(e.total)}').join('; ')}',
    ].join('\n');
  }
}
