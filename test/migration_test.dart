import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attend_ease/models/time_entry.dart';
import 'package:attend_ease/services/database_service.dart';

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  var seq = 0;

  // Builds a v1-shaped DB (attendance table only) seeded with [events], then
  // reopens it at v2 to trigger the migration, returning the resulting entries.
  // Uses a real temp file so data survives the close/reopen (`:memory:` would
  // give a fresh empty DB on the second open).
  Future<List<TimeEntry>> migrate(
      List<Map<String, Object?>> events) async {
    final path = p.join(Directory.systemTemp.path, 'ae_mig_${seq++}.db');
    await factory.deleteDatabase(path);
    // v1 schema + seed
    final v1 = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => db.execute('''
          CREATE TABLE attendance (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            type TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            note TEXT
          )
        '''),
      ),
    );
    for (final e in events) {
      await v1.insert('attendance', e);
    }
    await v1.close();

    // Reopen at the latest version -> onUpgrade runs the pairing migration.
    final db = await DatabaseService.openLatest(factory, path);
    final rows = await db.query('time_entries', orderBy: 'start_ms ASC');
    final entries = rows.map(TimeEntry.fromMap).toList();
    await db.close();
    return entries;
  }

  int t(int h) => DateTime(2026, 1, 1, h).millisecondsSinceEpoch;

  group('attendance -> time_entries migration', () {
    test('pairs a normal in/out into one closed entry', () async {
      final entries = await migrate([
        {'name': 'Rahim', 'type': 'in', 'timestamp': t(9), 'note': 'morning'},
        {'name': 'Rahim', 'type': 'out', 'timestamp': t(17), 'note': null},
      ]);
      expect(entries.length, 1);
      final e = entries.single;
      expect(e.person, 'Rahim');
      expect(e.isRunning, false);
      expect(e.description, 'morning');
      expect(e.source, 'migrated');
      expect(e.worked().inHours, 8);
    });

    test('trailing open check-in becomes a running entry', () async {
      final entries = await migrate([
        {'name': 'Karim', 'type': 'in', 'timestamp': t(10), 'note': null},
      ]);
      expect(entries.single.isRunning, true);
    });

    test('orphan checkout with no open is ignored', () async {
      final entries = await migrate([
        {'name': 'Sara', 'type': 'out', 'timestamp': t(12), 'note': null},
      ]);
      expect(entries, isEmpty);
    });

    test('double check-in keeps the newest open session', () async {
      final entries = await migrate([
        {'name': 'Joy', 'type': 'in', 'timestamp': t(9), 'note': null},
        {'name': 'Joy', 'type': 'in', 'timestamp': t(11), 'note': null},
        {'name': 'Joy', 'type': 'out', 'timestamp': t(15), 'note': null},
      ]);
      expect(entries.length, 1);
      expect(entries.single.start.hour, 11);
      expect(entries.single.worked().inHours, 4);
    });
  });

  group('TimeEntry.worked', () {
    test('excludes paused seconds', () {
      final e = TimeEntry(
        person: 'X',
        start: DateTime(2026, 1, 1, 9),
        end: DateTime(2026, 1, 1, 10),
        pausedSeconds: 600, // 10 min
        createdAt: DateTime(2026, 1, 1),
      );
      expect(e.worked().inMinutes, 50);
    });

    test('running entry measures up to now and never goes negative', () {
      final start = DateTime(2026, 1, 1, 9);
      final now = start.add(const Duration(hours: 2));
      final e = TimeEntry(
        person: 'X',
        start: start,
        pausedSeconds: 3600 * 5, // absurdly large pause
        createdAt: start,
      );
      expect(e.worked(now), Duration.zero);
    });
  });
}
