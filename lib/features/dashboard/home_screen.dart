import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants.dart';
import '../../core/router.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import 'budget_sheet.dart';
import 'providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      bottom: false,
      child: ref.watch(expensesProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorRetry(
              message: "Couldn't load your expenses",
              onRetry: () => ref.read(expensesProvider.notifier).refresh(),
            ),
            data: (expenses) => _HomeBody(expenses: expenses),
          ),
    );
  }
}

class _HomeBody extends ConsumerWidget {
  const _HomeBody({required this.expenses});
  final List<Expense> expenses;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final month = expenses.where((e) => e.date.year == now.year && e.date.month == now.month).toList();
    final monthTotal = sumTotals(month);
    final byCategory = totalsByCategory(month);
    final budgets = ref.watch(budgetsProvider).valueOrNull ?? const <String, double>{};
    final recent = expenses.take(5).toList();

    return RefreshIndicator(
      onRefresh: () => Future.wait([
        ref.read(expensesProvider.notifier).refresh(),
        ref.read(budgetsProvider.notifier).refresh(),
      ]),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          const _Header(),
          const SizedBox(height: 16),
          _MonthTotalCard(total: monthTotal, bills: month.length, now: now),
          if (byCategory.isNotEmpty) ...[
            const SectionHeader('This month by category'),
            SizedBox(
              height: 112,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: byCategory.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final entry = byCategory.entries.elementAt(i);
                  return FadeSlideIn(
                    index: i,
                    child: _CategoryStat(
                      category: entry.key,
                      amount: entry.value,
                      share: monthTotal == 0 ? 0 : entry.value / monthTotal,
                    ),
                  );
                },
              ),
            ),
          ],
          SectionHeader(
            'Budgets',
            trailing: TextButton.icon(
              onPressed: () => showBudgetSheet(context),
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: Text(budgets.isEmpty ? 'Set' : 'Edit'),
            ),
          ),
          _BudgetsCard(budgets: budgets, spent: byCategory),
          SectionHeader(
            'Recent expenses',
            trailing: expenses.isEmpty
                ? null
                : TextButton(
                    onPressed: () => ref.read(tabProvider.notifier).state = AppTab.history,
                    child: const Text('See all'),
                  ),
          ),
          if (recent.isEmpty)
            EmptyState(
              emoji: '🧾',
              title: 'No expenses yet — snap your first bill! 🧾',
              subtitle: 'Tap the camera button and RupiyaIQ will read, categorise and save it for you.',
              action: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(200, 48)),
                onPressed: () => openScanFlow(context, ref),
                icon: const Icon(Icons.camera_alt_rounded),
                label: const Text('Scan a bill'),
              ),
            )
          else
            for (final (i, e) in recent.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FadeSlideIn(
                  index: i,
                  child: ExpenseTile(expense: e, onTap: () => openExpenseDetail(context, e.id!)),
                ),
              ),
        ],
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final mode = ref.watch(themeModeProvider);
    final (icon, next) = switch (mode) {
      ThemeMode.system => (Icons.brightness_auto_rounded, ThemeMode.light),
      ThemeMode.light => (Icons.light_mode_rounded, ThemeMode.dark),
      ThemeMode.dark => (Icons.dark_mode_rounded, ThemeMode.system),
    };
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${greeting()} 👋', style: t.bodyLarge?.copyWith(color: t.bodySmall?.color)),
          Text('RupiyaIQ', style: t.headlineSmall),
        ]),
      ),
      IconButton.filledTonal(
        tooltip: 'Theme: ${mode.name}',
        onPressed: () => ref.read(themeModeProvider.notifier).state = next,
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (c, a) => RotationTransition(turns: a, child: c),
          child: Icon(icon, key: ValueKey(icon)),
        ),
      ),
    ]);
  }
}

class _MonthTotalCard extends StatelessWidget {
  const _MonthTotalCard({required this.total, required this.bills, required this.now});
  final double total;
  final int bills;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [AppColors.primary, Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Spent in ${DateFormat('MMMM').format(now)}',
            style: t.bodyMedium?.copyWith(color: Colors.white70)),
        const SizedBox(height: 6),
        // Count-up: animates from the previous value to the new total.
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: total),
          duration: const Duration(milliseconds: 1200),
          curve: Curves.easeOutCubic,
          builder: (_, v, _) => FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(formatInr(v), style: t.displaySmall?.copyWith(color: Colors.white)),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          _Pill(icon: Icons.receipt_long_rounded, text: '$bills bills'),
          const SizedBox(width: 8),
          _Pill(icon: Icons.calendar_today_rounded, text: 'Day ${now.day}'),
        ]),
      ]),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
}

class _CategoryStat extends StatelessWidget {
  const _CategoryStat({required this.category, required this.amount, required this.share});
  final String category;
  final double amount;
  final double share;

  @override
  Widget build(BuildContext context) {
    final info = categoryInfo(category);
    final t = Theme.of(context).textTheme;
    return Container(
      width: 124,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: info.color.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CategoryIcon(category, size: 28),
          const Spacer(),
          Text('${(share * 100).toStringAsFixed(0)}%',
              style: t.labelMedium?.copyWith(color: info.color, fontWeight: FontWeight.w700)),
        ]),
        const Spacer(),
        Text(info.name, style: t.bodySmall),
        Text(formatInr(amount), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _BudgetsCard extends StatelessWidget {
  const _BudgetsCard({required this.budgets, required this.spent});
  final Map<String, double> budgets;
  final Map<String, double> spent;

  @override
  Widget build(BuildContext context) {
    if (budgets.isEmpty) {
      return Card(
        child: ListTile(
          leading: const Text('🎯', style: TextStyle(fontSize: 28)),
          title: const Text('Set monthly budgets'),
          subtitle: const Text('Get warned before you overspend in a category.'),
          onTap: () => showBudgetSheet(context),
        ),
      );
    }
    // Most-used budgets first.
    final entries = budgets.entries.toList()
      ..sort((a, b) => ((spent[b.key] ?? 0) / b.value).compareTo((spent[a.key] ?? 0) / a.value));
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Column(children: [
          for (final b in entries) _BudgetBar(category: b.key, spent: spent[b.key] ?? 0, limit: b.value),
        ]),
      ),
    );
  }
}

class _BudgetBar extends StatelessWidget {
  const _BudgetBar({required this.category, required this.spent, required this.limit});
  final String category;
  final double spent;
  final double limit;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final ratio = limit <= 0 ? 0.0 : spent / limit;
    // green < 70%, amber 70–100%, red > 100%
    final color = ratio > 1
        ? AppColors.danger
        : ratio >= 0.7
            ? AppColors.warning
            : AppColors.success;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CategoryIcon(category, size: 26),
          const SizedBox(width: 8),
          Expanded(child: Text(category, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
          Text('${formatInr(spent)} / ${formatInr(limit)}', style: t.bodySmall),
        ]),
        const SizedBox(height: 8),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: ratio.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (_, v, _) => LinearProgressIndicator(
            value: v,
            minHeight: 8,
            color: color,
            backgroundColor: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        if (ratio > 1)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('⚠️ Over budget by ${formatInr(spent - limit)}',
                style: t.bodySmall?.copyWith(color: AppColors.danger, fontWeight: FontWeight.w600)),
          )
        else if (ratio >= 0.7)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Heads up — ${(ratio * 100).toStringAsFixed(0)}% used, ${formatInr(limit - spent)} left',
                style: t.bodySmall?.copyWith(color: AppColors.warning, fontWeight: FontWeight.w600)),
          ),
      ]),
    );
  }
}
