import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../../core/utils.dart';
import '../db_helper.dart';
import '../models.dart';

/// All SQLite access goes through here.
class ExpenseRepository {
  ExpenseRepository(this._dbHelper);
  final DbHelper _dbHelper;

  Future<Database> get _db => _dbHelper.database;

  /// Newest first, with items attached.
  // ponytail: loads everything into memory; paginate if users reach many thousands of bills.
  Future<List<Expense>> getAll() async {
    final db = await _db;
    final rows = await db.query('expenses', orderBy: 'date DESC, created_at DESC');
    final itemRows = await db.query('items', orderBy: 'id');
    final itemsByExpense = <int, List<ExpenseItem>>{};
    for (final r in itemRows) {
      itemsByExpense.putIfAbsent(r['expense_id'] as int, () => []).add(ExpenseItem.fromMap(r));
    }
    return [for (final r in rows) Expense.fromMap(r, itemsByExpense[r['id']] ?? const [])];
  }

  /// Inserts expense + items atomically. Keeps `id` if set (used by undo-delete).
  Future<int> insert(Expense e) async {
    final db = await _db;
    return db.transaction((txn) async {
      final id = await txn.insert('expenses', e.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
      for (final item in e.items) {
        await txn.insert('items', item.toMap(id));
      }
      return id;
    });
  }

  Future<void> update(Expense e) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.update('expenses', e.toMap(), where: 'id = ?', whereArgs: [e.id]);
      await txn.delete('items', where: 'expense_id = ?', whereArgs: [e.id]);
      for (final item in e.items) {
        await txn.insert('items', item.toMap(e.id!));
      }
    });
  }

  /// Items go with it via ON DELETE CASCADE. The receipt image is kept so
  /// "Undo" can restore the expense intact.
  // ponytail: deleted receipts leave orphan image files; sweep on startup if storage matters.
  Future<void> delete(int id) async {
    final db = await _db;
    await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setAnomalyFlags(Map<int, bool> flags) async {
    if (flags.isEmpty) return;
    final db = await _db;
    final batch = db.batch();
    flags.forEach((id, flagged) {
      batch.update('expenses', {'is_anomaly': flagged ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
    });
    await batch.commit(noResult: true);
  }

  /// Returns an existing expense that is ≥95% similar (merchant + total) and
  /// dated within ±1 day of [e], or null.
  Future<Expense?> findDuplicate(Expense e) async {
    final db = await _db;
    final rows = await db.query(
      'expenses',
      where: 'date BETWEEN ? AND ?',
      whereArgs: [
        isoDate(e.date.subtract(const Duration(days: 1))),
        isoDate(e.date.add(const Duration(days: 1))),
      ],
    );
    Expense? best;
    var bestScore = 0.0;
    for (final r in rows) {
      final candidate = Expense.fromMap(r, const []);
      if (candidate.id == e.id) continue;
      final score = duplicateScore(e, candidate);
      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    return bestScore >= 0.95 ? best : null;
  }

  Future<Map<String, double>> getBudgets() async {
    final db = await _db;
    final rows = await db.query('budgets');
    return {
      for (final r in rows) r['category'] as String: (r['monthly_limit'] as num).toDouble(),
    };
  }

  /// limit ≤ 0 removes the budget.
  Future<void> setBudget(String category, double limit) async {
    final db = await _db;
    if (limit <= 0) {
      await db.delete('budgets', where: 'category = ?', whereArgs: [category]);
    } else {
      await db.insert('budgets', {'category': category, 'monthly_limit': limit},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }
}

/// Duplicate similarity in 0..1 — the mean of:
///  • merchant similarity: 1 − (edit distance / longer length), on lowercase
///    letters+digits only, so "BIG BAZAAR." ≈ "Big Bazaar"
///  • total similarity:    1 − |a − b| / max(a, b)
/// The caller already restricts candidates to dates within ±1 day.
double duplicateScore(Expense a, Expense b) {
  String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final m1 = norm(a.merchant), m2 = norm(b.merchant);
  final longer = max(m1.length, m2.length);
  final merchantSim = longer == 0 ? 1.0 : 1 - _levenshtein(m1, m2) / longer;
  final bigger = max(a.total.abs(), b.total.abs());
  final totalSim = bigger == 0 ? 1.0 : 1 - (a.total - b.total).abs() / bigger;
  return (merchantSim + totalSim) / 2;
}

int _levenshtein(String s, String t) {
  if (s == t) return 0;
  if (s.isEmpty) return t.length;
  if (t.isEmpty) return s.length;
  var prev = List<int>.generate(t.length + 1, (i) => i);
  for (var i = 0; i < s.length; i++) {
    final curr = List<int>.filled(t.length + 1, 0)..[0] = i + 1;
    for (var j = 0; j < t.length; j++) {
      final cost = s[i] == t[j] ? 0 : 1;
      curr[j + 1] = min(min(curr[j] + 1, prev[j + 1] + 1), prev[j] + cost);
    }
    prev = curr;
  }
  return prev[t.length];
}
