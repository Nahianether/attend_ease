import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/attendance_record.dart';
import '../services/database_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _db = DatabaseService.instance;
  late Future<List<AttendanceRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = _db.getAll();
  }

  void _reload() => setState(() => _future = _db.getAll());

  Future<void> _confirmDelete(AttendanceRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete record?'),
        content: Text('${r.name} — ${r.isCheckIn ? 'in' : 'out'}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true && r.id != null) {
      await _db.delete(r.id!);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance History')),
      body: FutureBuilder<List<AttendanceRecord>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final records = snap.data ?? [];
          if (records.isEmpty) {
            return const Center(
              child: Text('No attendance records yet.'),
            );
          }
          return ListView.separated(
            itemCount: records.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final r = records[i];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: r.isCheckIn
                      ? Colors.green.shade100
                      : Colors.orange.shade100,
                  child: Icon(
                    r.isCheckIn ? Icons.login : Icons.logout,
                    color: r.isCheckIn ? Colors.green : Colors.orange,
                  ),
                ),
                title: Text(r.name),
                subtitle: Text(
                  '${r.isCheckIn ? 'Checked in' : 'Checked out'} • '
                  '${DateFormat('dd MMM yyyy, hh:mm a').format(r.timestamp)}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDelete(r),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
