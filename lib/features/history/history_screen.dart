import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/router.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../dashboard/providers.dart';

/// Deletes with an Undo snackbar. Shared by swipe-to-delete and the detail screen.
void deleteWithUndo(BuildContext context, WidgetRef ref, Expense e) {
  final notifier = ref.read(expensesProvider.notifier);
  final messenger = ScaffoldMessenger.of(context);
  notifier.delete(e).catchError((_) {
    messenger.showSnackBar(const SnackBar(content: Text("Couldn't delete — please try again.")));
  });
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text('Deleted ${e.merchant} (${formatInrExact(e.total)})'),
      duration: const Duration(seconds: 5),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => notifier.restore(e).catchError((_) {
          messenger.showSnackBar(const SnackBar(content: Text("Couldn't restore — please add it again.")));
        }),
      ),
    ));
}

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _search = TextEditingController();
  String _query = '';
  String? _category;
  DateTime? _month; // first day of month, null = all months

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Expense> _filter(List<Expense> all) {
    final q = _query.trim().toLowerCase();
    return all.where((e) {
      if (_category != null && e.category != _category) return false;
      if (_month != null && (e.date.year != _month!.year || e.date.month != _month!.month)) return false;
      if (q.isEmpty) return true;
      return e.merchant.toLowerCase().contains(q) ||
          e.category.toLowerCase().contains(q) ||
          e.items.any((i) => i.name.toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(expensesProvider);
    return SafeArea(
      bottom: false,
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ErrorRetry(
          message: "Couldn't load history",
          onRetry: () => ref.read(expensesProvider.notifier).refresh(),
        ),
        data: (all) => _body(context, all),
      ),
    );
  }

  Widget _body(BuildContext context, List<Expense> all) {
    final t = Theme.of(context).textTheme;
    final filtered = _filter(all);
    final months = <DateTime>{for (final e in all) DateTime(e.date.year, e.date.month)}.toList()
      ..sort((a, b) => b.compareTo(a));

    // Already newest-first, so grouping preserves order.
    final groups = <DateTime, List<Expense>>{};
    for (final e in filtered) {
      groups.putIfAbsent(dayOnly(e.date), () => []).add(e);
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(expensesProvider.notifier).refresh(),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('History', style: t.headlineSmall)),
                  PopupMenuButton<DateTime>(
                    tooltip: 'Filter by month',
                    // DateTime(0) = "All months" (PopupMenuButton ignores null values).
                    onSelected: (m) => setState(() => _month = m.year == 0 ? null : m),
                    itemBuilder: (_) => [
                      PopupMenuItem(value: DateTime(0), child: const Text('All months')),
                      for (final m in months) PopupMenuItem(value: m, child: Text(monthLabel(m))),
                    ],
                    child: Chip(
                      avatar: const Icon(Icons.calendar_month_rounded, size: 18),
                      label: Text(_month == null ? 'All months' : monthLabel(_month!)),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search merchant, category or item',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () => setState(() {
                              _search.clear();
                              _query = '';
                            }),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 40,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: const Text('All'),
                        selected: _category == null,
                        onSelected: (_) => setState(() => _category = null),
                      ),
                    ),
                    for (final c in kCategories)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          avatar: Icon(c.icon, size: 16, color: c.color),
                          label: Text(c.name),
                          selected: _category == c.name,
                          selectedColor: c.color.withValues(alpha: 0.25),
                          onSelected: (s) => setState(() => _category = s ? c.name : null),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 4),
                if (filtered.isNotEmpty)
                  Text('${filtered.length} bills · ${formatInr(sumTotals(filtered))}', style: t.bodySmall),
              ]),
            ),
          ),
          if (all.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(emoji: '🧾', title: 'No expenses yet — snap your first bill! 🧾'),
            )
          else if (filtered.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(emoji: '🔍', title: 'No matching bills', subtitle: 'Try a different search or filter.'),
            )
          else
            for (final g in groups.entries)
              // Each group's header stays pinned only while its own rows scroll by.
              SliverMainAxisGroup(slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _DateHeader(label: relativeDayLabel(g.key), total: sumTotals(g.value)),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList.builder(
                    itemCount: g.value.length,
                    itemBuilder: (context, i) => _SwipeTile(expense: g.value[i], index: i),
                  ),
                ),
              ]),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }
}

class _SwipeTile extends ConsumerWidget {
  const _SwipeTile({required this.expense, required this.index});
  final Expense expense;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Dismissible(
          key: ValueKey('expense-${expense.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(20)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              SizedBox(width: 8),
              Icon(Icons.delete_rounded, color: Colors.white),
            ]),
          ),
          onDismissed: (_) => deleteWithUndo(context, ref, expense),
          child: FadeSlideIn(
            index: index,
            child: ExpenseTile(expense: expense, onTap: () => openExpenseDetail(context, expense.id!)),
          ),
        ),
      );
}

class _DateHeader extends SliverPersistentHeaderDelegate {
  _DateHeader({required this.label, required this.total});
  final String label;
  final double total;

  @override
  double get minExtent => 40;
  @override
  double get maxExtent => 40;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final t = Theme.of(context).textTheme;
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: Alignment.centerLeft,
      child: Row(children: [
        Expanded(child: Text(label, style: t.labelLarge?.copyWith(fontWeight: FontWeight.w700))),
        Text(formatInr(total), style: t.labelMedium),
      ]),
    );
  }

  @override
  bool shouldRebuild(_DateHeader old) => old.label != label || old.total != total;
}
