import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/project.dart';
import '../models/time_entry.dart';

/// Local SQLite storage. Works on Android (native sqflite) and Windows/desktop
/// (sqflite_common_ffi).
///
/// Schema v2 introduced Clockify-style `projects`/`tasks`/`time_entries`. v3
/// makes the task a free-text column (`time_entries.task_name`) typed per
/// session instead of a predefined `tasks` row. The old event-based
/// `attendance` table is kept untouched as a non-destructive backup.
class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Database? _db;

  /// Override for tests (e.g. an in-memory factory). When set, [_open] skips
  /// the FFI/path setup and uses this directly.
  Future<Database> Function()? testOpener;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    if (testOpener != null) return testOpener!();

    // On desktop, sqflite needs the FFI factory. Only set it once — on a hot
    // restart the global factory survives, so re-assigning it just triggers
    // sqflite's "changing default factory" warning for no benefit.
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      bool alreadyFfi;
      try {
        alreadyFfi = identical(databaseFactory, databaseFactoryFfi);
      } catch (_) {
        alreadyFfi = false; // not initialised yet
      }
      if (!alreadyFfi) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }
    }

    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'attend_ease.db');

    return openLatest(databaseFactory, path);
  }

  /// Opens the database at the latest version with the migration callbacks.
  /// Exposed so tests can exercise the real schema + upgrade against any
  /// [DatabaseFactory].
  static Future<Database> openLatest(DatabaseFactory factory, String path) {
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onConfigure: _onConfigure,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  static Future<void> _onConfigure(Database db) async {
    // Required for ON DELETE SET NULL / CASCADE to fire (per-connection).
    await db.execute('PRAGMA foreign_keys = ON');
  }

  static Future<void> _onCreate(Database db, int version) async {
    // Legacy event table — retained for backward compatibility / migration
    // fixtures. New installs simply never write to it.
    await db.execute('''
      CREATE TABLE attendance (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        note TEXT
      )
    ''');
    await _createV2Tables(db);
    await _upgradeToV3(db);
  }

  static Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    if (oldV < 2) {
      await _createV2Tables(db);
      await _migrateAttendanceToEntries(db);
    }
    if (oldV < 3) {
      await _upgradeToV3(db);
    }
  }

  /// v3: task becomes free text on the entry. Adds `task_name` and backfills it
  /// from any previously-tagged task rows.
  static Future<void> _upgradeToV3(Database db) async {
    await db.execute(
        "ALTER TABLE time_entries ADD COLUMN task_name TEXT NOT NULL DEFAULT ''");
    await db.execute('''
      UPDATE time_entries
      SET task_name =
          COALESCE((SELECT name FROM tasks WHERE tasks.id = time_entries.task_id), '')
      WHERE task_id IS NOT NULL
    ''');
  }

  static Future<void> _createV2Tables(Database db) async {
    await db.execute('''
      CREATE TABLE projects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        color INTEGER NOT NULL,
        archived INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        archived INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE time_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        person TEXT NOT NULL,
        project_id INTEGER REFERENCES projects(id) ON DELETE SET NULL,
        task_id INTEGER REFERENCES tasks(id) ON DELETE SET NULL,
        description TEXT NOT NULL DEFAULT '',
        start_ms INTEGER NOT NULL,
        end_ms INTEGER,
        paused_seconds INTEGER NOT NULL DEFAULT 0,
        source TEXT NOT NULL DEFAULT 'timer',
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_tasks_project ON tasks(project_id)');
    await db.execute('CREATE INDEX idx_te_start ON time_entries(start_ms)');
    await db.execute('CREATE INDEX idx_te_person ON time_entries(person)');
  }

  /// Pairs old `attendance` in/out events into `time_entries`. Non-destructive:
  /// the `attendance` table is left intact.
  static Future<void> _migrateAttendanceToEntries(Database db) async {
    final rows = await db.query(
      'attendance',
      orderBy: 'name ASC, timestamp ASC',
    );
    if (rows.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final open = <String, Map<String, Object?>>{}; // name -> {start, note}
    final batch = <Map<String, Object?>>[];

    Map<String, Object?> entry({
      required String person,
      required int startMs,
      int? endMs,
      String? description,
    }) =>
        {
          'person': person,
          'project_id': null,
          'task_id': null,
          'description': description ?? '',
          'start_ms': startMs,
          'end_ms': endMs,
          'paused_seconds': 0,
          'source': 'migrated',
          'created_at': now,
        };

    for (final r in rows) {
      final name = r['name'] as String;
      final type = r['type'] as String;
      final ts = r['timestamp'] as int;
      final note = r['note'] as String?;
      if (type == 'in') {
        // Anomaly: a second check-in with no checkout between — the earlier
        // open session had no end, so drop it and keep the newest.
        open[name] = {'start': ts, 'note': note};
      } else {
        final o = open.remove(name);
        if (o != null) {
          batch.add(entry(
            person: name,
            startMs: o['start'] as int,
            endMs: ts,
            description: o['note'] as String?,
          ));
        }
        // Orphan checkout with no open check-in -> ignore.
      }
    }
    // Trailing open check-ins -> running sessions (preserves resume-on-launch).
    open.forEach((name, o) {
      batch.add(entry(
        person: name,
        startMs: o['start'] as int,
        endMs: null,
        description: o['note'] as String?,
      ));
    });

    await db.transaction((txn) async {
      for (final e in batch) {
        await txn.insert('time_entries', e);
      }
    });
  }

  // ---- Projects -----------------------------------------------------------

  Future<Project> insertProject(Project project) async {
    final db = await _database;
    final id = await db.insert('projects', project.toMap()..remove('id'));
    return project.copyWith(id: id);
  }

  Future<int> updateProject(Project project) async {
    final db = await _database;
    return db.update('projects', project.toMap(),
        where: 'id = ?', whereArgs: [project.id]);
  }

  Future<List<Project>> getProjects({bool includeArchived = false}) async {
    final db = await _database;
    final rows = await db.query(
      'projects',
      where: includeArchived ? null : 'archived = 0',
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(Project.fromMap).toList();
  }

  Future<Project?> getProject(int id) async {
    final db = await _database;
    final rows =
        await db.query('projects', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Project.fromMap(rows.first);
  }

  Future<void> setProjectArchived(int id, bool archived) async {
    final db = await _database;
    await db.update('projects', {'archived': archived ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteProject(int id) async {
    final db = await _database;
    await db.delete('projects', where: 'id = ?', whereArgs: [id]);
  }

  // ---- Time entries -------------------------------------------------------

  Future<TimeEntry> insertEntry(TimeEntry e) async {
    final db = await _database;
    final id = await db.insert('time_entries', e.toMap()..remove('id'));
    return e.copyWith(id: id);
  }

  Future<int> updateEntry(TimeEntry e) async {
    final db = await _database;
    return db.update('time_entries', e.toMap(),
        where: 'id = ?', whereArgs: [e.id]);
  }

  Future<void> deleteEntry(int id) async {
    final db = await _database;
    await db.delete('time_entries', where: 'id = ?', whereArgs: [id]);
  }

  /// The most recent still-running entry for [person], or null.
  Future<TimeEntry?> runningEntryForPerson(String person) async {
    final db = await _database;
    final rows = await db.query(
      'time_entries',
      where: 'person = ? AND end_ms IS NULL',
      whereArgs: [person],
      orderBy: 'start_ms DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return TimeEntry.fromMap(rows.first);
  }

  static const _viewSelect = '''
    SELECT te.*, p.name AS project_name, p.color AS project_color
    FROM time_entries te
    LEFT JOIN projects p ON te.project_id = p.id
  ''';

  /// Entries whose start falls on the same calendar day as [day].
  Future<List<TimeEntryView>> entriesForDay(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final db = await _database;
    final rows = await db.rawQuery(
      '$_viewSelect WHERE te.start_ms >= ? AND te.start_ms < ? '
      'ORDER BY te.start_ms DESC',
      [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
    );
    return rows.map(TimeEntryView.fromMap).toList();
  }

  /// Entries that started within [startInclusive, endExclusive), optionally
  /// filtered by [person] and/or [projectId].
  Future<List<TimeEntryView>> entriesInRange(
    DateTime startInclusive,
    DateTime endExclusive, {
    String? person,
    int? projectId,
  }) async {
    final where = <String>['te.start_ms >= ?', 'te.start_ms < ?'];
    final args = <Object?>[
      startInclusive.millisecondsSinceEpoch,
      endExclusive.millisecondsSinceEpoch,
    ];
    if (person != null) {
      where.add('te.person = ?');
      args.add(person);
    }
    if (projectId != null) {
      where.add('te.project_id = ?');
      args.add(projectId);
    }
    final db = await _database;
    final rows = await db.rawQuery(
      '$_viewSelect WHERE ${where.join(' AND ')} ORDER BY te.start_ms DESC',
      args,
    );
    return rows.map(TimeEntryView.fromMap).toList();
  }

  /// All entries, newest first (History screen).
  Future<List<TimeEntryView>> allEntries() async {
    final db = await _database;
    final rows = await db.rawQuery('$_viewSelect ORDER BY te.start_ms DESC');
    return rows.map(TimeEntryView.fromMap).toList();
  }

  /// Distinct worker names seen in entries (for manual-entry person picker).
  Future<List<String>> distinctPersons() async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT person FROM time_entries ORDER BY person COLLATE NOCASE ASC',
    );
    return rows.map((r) => r['person'] as String).toList();
  }
}
