import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import 'spending_summary.dart';

/// Donut of category shares with a tap-to-highlight legend.
class CategoryDonut extends StatefulWidget {
  const CategoryDonut({super.key, required this.totals});
  final Map<String, double> totals;

  @override
  State<CategoryDonut> createState() => _CategoryDonutState();
}

class _CategoryDonutState extends State<CategoryDonut> {
  int _touched = -1;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final entries = widget.totals.entries.toList();
    final total = entries.fold(0.0, (s, e) => s + e.value);
    return Row(children: [
      SizedBox(
        width: 150,
        height: 150,
        child: Stack(alignment: Alignment.center, children: [
          PieChart(
            PieChartData(
              centerSpaceRadius: 44,
              sectionsSpace: 2,
              startDegreeOffset: -90,
              pieTouchData: PieTouchData(touchCallback: (event, response) {
                setState(() {
                  _touched = (!event.isInterestedForInteractions || response?.touchedSection == null)
                      ? -1
                      : response!.touchedSection!.touchedSectionIndex;
                });
              }),
              sections: [
                for (final (i, e) in entries.indexed)
                  PieChartSectionData(
                    value: e.value,
                    color: categoryInfo(e.key).color,
                    radius: i == _touched ? 30 : 24,
                    showTitle: false,
                  ),
              ],
            ),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Total', style: t.labelSmall),
            FittedBox(child: Text(formatInr(total), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
          ]),
        ]),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (i, e) in entries.take(6).indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: categoryInfo(e.key).color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(e.key,
                      style: t.bodySmall?.copyWith(fontWeight: i == _touched ? FontWeight.w700 : null)),
                ),
                Text('${(e.value / total * 100).toStringAsFixed(0)}%', style: t.bodySmall),
              ]),
            ),
        ]),
      ),
    ]);
  }
}

/// Buckets for the bar chart: week → 7 daily bars, month → weekly bars (W1..W5).
List<(String, double)> spendBuckets(List<Expense> expenses, InsightPeriod period, DateTime now) {
  final range = period.current(now);
  if (period == InsightPeriod.week) {
    return [
      for (var i = 0; i < 7; i++)
        () {
          final day = range.start.add(Duration(days: i));
          final sum = sumTotals(expenses.where((e) => dayOnly(e.date) == day));
          return (DateFormat('E').format(day), sum);
        }(),
    ];
  }
  final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
  final weeks = (daysInMonth - 1) ~/ 7 + 1;
  final sums = List<double>.filled(weeks, 0);
  for (final e in expenses.where((e) => range.contains(e.date))) {
    sums[(e.date.day - 1) ~/ 7] += e.total;
  }
  return [for (var i = 0; i < weeks; i++) ('W${i + 1}', sums[i])];
}

class SpendBarChart extends StatelessWidget {
  const SpendBarChart({super.key, required this.buckets});
  final List<(String, double)> buckets;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final maxV = buckets.fold(0.0, (m, b) => b.$2 > m ? b.$2 : m);
    final maxY = maxV <= 0 ? 100.0 : maxV * 1.2;
    return SizedBox(
      height: 190,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          alignment: BarChartAlignment.spaceAround,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: maxY / 4,
            getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.withValues(alpha: 0.15), strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            topTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= buckets.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(buckets[i].$1, style: t.labelSmall),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => AppColors.primary,
              getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                formatInr(rod.toY),
                const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          barGroups: [
            for (final (i, b) in buckets.indexed)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: b.$2,
                  width: buckets.length > 5 ? 18 : 28,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                  gradient: const LinearGradient(
                    colors: [AppColors.accent, AppColors.primary],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                ),
              ]),
          ],
        ),
      ),
    );
  }
}
