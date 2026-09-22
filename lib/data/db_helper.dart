import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../config.dart';
import 'seed_data.dart';

class DbHelper {
  DbHelper._();
  static final instance = DbHelper._();

  /// Opened once, lazily; concurrent callers share the same Future.
  late final Future<Database> database = _open();

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'rupiya_iq.db');
    return openDatabase(
      path,
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE expenses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            merchant TEXT,
            date TEXT,
            category TEXT,
            subtotal REAL,
            tax REAL,
            total REAL,
            payment_method TEXT,
            image_path TEXT,
            raw_ocr TEXT,
            confidence REAL,
            created_at TEXT,
            is_anomaly INTEGER DEFAULT 0
          )''');
        await db.execute('''
          CREATE TABLE items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            expense_id INTEGER NOT NULL REFERENCES expenses(id) ON DELETE CASCADE,
            name TEXT,
            price REAL,
            quantity REAL
          )''');
        await db.execute('''
          CREATE TABLE budgets (
            category TEXT PRIMARY KEY,
            monthly_limit REAL
          )''');
        await db.execute('CREATE INDEX idx_expenses_date ON expenses(date)');
        await db.execute('CREATE INDEX idx_expenses_category ON expenses(category)');
        await db.execute('CREATE INDEX idx_items_expense ON items(expense_id)');

        // Seed once: onCreate only runs when the DB file is new, AND the
        // 'seeded' flag must be unset — double guard against duplicate demo data.
        if (kSeedDemoData && !await _alreadySeeded()) {
          await insertSeedData(db);
          await _markSeeded();
        }
      },
    );
  }

  static Future<bool> _alreadySeeded() async {
    try {
      return (await SharedPreferences.getInstance()).getBool('seeded') ?? false;
    } catch (_) {
      return false; // prefs unavailable → onCreate alone still guarantees first-launch-only
    }
  }

  static Future<void> _markSeeded() async {
    try {
      await (await SharedPreferences.getInstance()).setBool('seeded', true);
    } catch (_) {}
  }
}
