import '../../core/utils.dart';
import '../../data/models.dart';

class Anomaly {
  const Anomaly({required this.expense, required this.categoryAverage, required this.historyCount});

  final Expense expense;

  /// Average bill size in this category over the 30 days before this expense.
  final double categoryAverage;
  final int historyCount;

  double get ratio => categoryAverage <= 0 ? 0 : expense.total / categoryAverage;

  String get message =>
      'Unusual: ${formatInr(expense.total)} ${expense.category} expense on '
      '${shortDate(expense.date)} — ${ratio.toStringAsFixed(1)}× your 30-day '
      '${expense.category} average (${formatInr(categoryAverage)}).';
}

/// Pure-Dart, fully offline anomaly detection.
///
/// For every expense E:
///   1. Baseline = all OTHER expenses in the same category dated within the
///      30 days up to and including E's date (E itself is excluded, so a big
///      bill can't hide by inflating its own average).
///   2. avg = mean(baseline totals)  — the user's typical bill in that category.
///   3. E is an anomaly if   E.total > 2.5 × avg   OR   E.total − avg > ₹2,000.
///
/// We need at least [minHistory] baseline bills; with 0–1 data points
/// "unusual" is meaningless, so those expenses are never flagged.
class AnomalyDetectionEngine {
  static const windowDays = 30;
  static const ratioThreshold = 2.5;
  static const absoluteThreshold = 2000.0;
  static const minHistory = 2;

  // ponytail: O(n²) per category; fine for thousands of bills, sort + sliding window beyond that.
  static List<Anomaly> detect(List<Expense> expenses) {
    final byCategory = <String, List<Expense>>{};
    for (final e in expenses) {
      byCategory.putIfAbsent(e.category, () => []).add(e);
    }

    final anomalies = <Anomaly>[];
    for (final group in byCategory.values) {
      for (final e in group) {
        final day = dayOnly(e.date);
        final history = group.where((o) {
          if (identical(o, e) || (o.id != null && o.id == e.id)) return false;
          final daysBefore = day.difference(dayOnly(o.date)).inDays;
          return daysBefore >= 0 && daysBefore <= windowDays;
        }).toList();
        if (history.length < minHistory) continue;

        final avg = history.fold(0.0, (s, o) => s + o.total) / history.length;
        final isAnomaly = e.total > avg * ratioThreshold || e.total - avg > absoluteThreshold;
        if (isAnomaly) {
          anomalies.add(Anomaly(expense: e, categoryAverage: avg, historyCount: history.length));
        }
      }
    }
    anomalies.sort((a, b) => b.expense.date.compareTo(a.expense.date));
    return anomalies;
  }
}
