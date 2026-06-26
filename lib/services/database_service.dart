import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/attendance_record.dart';

/// Local SQLite storage for attendance records. Works on Android (native
/// sqflite) and Windows/desktop (sqflite_common_ffi).
class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    // On desktop, sqflite needs the FFI factory initialised.
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'attend_ease.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE attendance (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            type TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            note TEXT
          )
        ''');
      },
    );
  }

  Future<AttendanceRecord> insert(AttendanceRecord record) async {
    final db = await _database;
    final id = await db.insert('attendance', record.toMap()..remove('id'));
    return record.copyWith(id: id);
  }

  Future<List<AttendanceRecord>> getAll() async {
    final db = await _database;
    final rows = await db.query('attendance', orderBy: 'timestamp DESC');
    return rows.map(AttendanceRecord.fromMap).toList();
  }

  /// All records that fall on the same calendar day as [day], oldest first.
  Future<List<AttendanceRecord>> recordsForDay(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final db = await _database;
    final rows = await db.query(
      'attendance',
      where: 'timestamp >= ? AND timestamp < ?',
      whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
      orderBy: 'timestamp ASC',
    );
    return rows.map(AttendanceRecord.fromMap).toList();
  }

  /// The most recent record for [name], or null if they have none.
  Future<AttendanceRecord?> lastForName(String name) async {
    final db = await _database;
    final rows = await db.query(
      'attendance',
      where: 'name = ?',
      whereArgs: [name],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AttendanceRecord.fromMap(rows.first);
  }

  Future<void> delete(int id) async {
    final db = await _database;
    await db.delete('attendance', where: 'id = ?', whereArgs: [id]);
  }
}
