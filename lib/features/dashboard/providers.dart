import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db_helper.dart';
import '../../data/models.dart';
import '../../data/repositories/expense_repository.dart';
import '../insights/anomaly_engine.dart';

final repositoryProvider = Provider<ExpenseRepository>((ref) => ExpenseRepository(DbHelper.instance));

/// All expenses (newest first). Home, History and Insights all derive from
/// this one list, so any add/edit/delete updates every tab at once.
final expensesProvider =
    AsyncNotifierProvider<ExpensesNotifier, List<Expense>>(ExpensesNotifier.new);

class ExpensesNotifier extends AsyncNotifier<List<Expense>> {
  ExpenseRepository get _repo => ref.read(repositoryProvider);

  @override
  Future<List<Expense>> build() => _loadAndFlag();

  /// Loads from DB, re-runs anomaly detection and persists any changed
  /// is_anomaly flags (a new bill can change its neighbours' baselines).
  Future<List<Expense>> _loadAndFlag() async {
    final all = await _repo.getAll();
    final flagged = {for (final a in AnomalyDetectionEngine.detect(all)) a.expense.id};
    final changes = <int, bool>{
      for (final e in all)
        if (e.id != null && e.isAnomaly != flagged.contains(e.id)) e.id!: flagged.contains(e.id),
    };
    await _repo.setAnomalyFlags(changes);
    return [
      for (final e in all) changes.containsKey(e.id) ? e.copyWith(isAnomaly: changes[e.id]) : e,
    ];
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_loadAndFlag);
  }

  Future<int> add(Expense e) async {
    final id = await _repo.insert(e.copyWith(createdAt: DateTime.now()));
    await refresh();
    return id;
  }

  Future<void> updateExpense(Expense e) async {
    await _repo.update(e);
    await refresh();
  }

  /// Optimistic: removes from state synchronously (so a Dismissible can
  /// leave the tree immediately), then deletes in the DB.
  Future<void> delete(Expense e) async {
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData([for (final x in current) if (x.id != e.id) x]);
    }
    await _repo.delete(e.id!);
    await refresh();
  }

  /// Undo for [delete] — re-inserts with the same id and items.
  Future<void> restore(Expense e) async {
    await _repo.insert(e);
    await refresh();
  }
}

final budgetsProvider =
    AsyncNotifierProvider<BudgetsNotifier, Map<String, double>>(BudgetsNotifier.new);

class BudgetsNotifier extends AsyncNotifier<Map<String, double>> {
  @override
  Future<Map<String, double>> build() => ref.read(repositoryProvider).getBudgets();

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => ref.read(repositoryProvider).getBudgets());
  }

  Future<void> setAll(Map<String, double> limits) async {
    final repo = ref.read(repositoryProvider);
    for (final e in limits.entries) {
      await repo.setBudget(e.key, e.value);
    }
    await refresh();
  }
}
