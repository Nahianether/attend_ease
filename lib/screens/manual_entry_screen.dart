import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:intl/intl.dart';

import '../models/time_entry.dart';
import '../providers/app_providers.dart';
import '../widgets/error_handling.dart';
import '../widgets/project_task_picker.dart';

// Form state for the date/time fields (null = use the seeded initial value).
final _manualDateProvider = StateProvider.autoDispose<DateTime?>((_) => null);
final _manualStartProvider = StateProvider.autoDispose<TimeOfDay?>((_) => null);
final _manualEndProvider = StateProvider.autoDispose<TimeOfDay?>((_) => null);

/// Add a new time entry or edit an existing one. Pops `true` when something was
/// saved or deleted so the caller can refresh.
class ManualEntryScreen extends ConsumerStatefulWidget {
  final TimeEntry? existing;
  const ManualEntryScreen({super.key, this.existing});

  @override
  ConsumerState<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends ConsumerState<ManualEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _person = TextEditingController();
  final _task = TextEditingController();
  final _description = TextEditingController();

  late final DateTime _initialDate;
  late final TimeOfDay _initialStart;
  late final TimeOfDay _initialEnd;
  late final int? _initialProjectId;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _person.text = e.person;
      _task.text = e.taskName;
      _description.text = e.description;
      _initialProjectId = e.projectId;
      _initialDate = DateTime(e.start.year, e.start.month, e.start.day);
      _initialStart = TimeOfDay.fromDateTime(e.start);
      _initialEnd = TimeOfDay.fromDateTime(
          e.end ?? e.start.add(const Duration(hours: 1)));
    } else {
      _initialProjectId = null;
      final now = DateTime.now();
      _initialDate = DateTime(now.year, now.month, now.day);
      _initialEnd = TimeOfDay.fromDateTime(now);
      _initialStart =
          TimeOfDay.fromDateTime(now.subtract(const Duration(hours: 1)));
      // Seed the person field from settings for a new entry.
      final name = ref.read(settingsProvider).asData?.value.defaultUserName;
      if (name != null) _person.text = name;
    }
  }

  @override
  void dispose() {
    _person.dispose();
    _task.dispose();
    _description.dispose();
    super.dispose();
  }

  DateTime _combine(DateTime date, TimeOfDay t) =>
      DateTime(date.year, date.month, date.day, t.hour, t.minute);

  Future<void> _save(DateTime date, TimeOfDay startT, TimeOfDay endT) async {
    if (!_formKey.currentState!.validate()) return;
    final start = _combine(date, startT);
    final end = _combine(date, endT);
    if (!end.isAfter(start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time.')),
      );
      return;
    }

    final projectId = ref.read(manualProjectProvider(_initialProjectId));
    final db = ref.read(databaseProvider);
    final existing = widget.existing;
    try {
      if (existing == null) {
        await db.insertEntry(TimeEntry(
          person: _person.text.trim(),
          projectId: projectId,
          taskName: _task.text.trim(),
          description: _description.text.trim(),
          start: start,
          end: end,
          source: 'manual',
          createdAt: DateTime.now(),
        ));
      } else {
        await db.updateEntry(existing.copyWith(
          person: _person.text.trim(),
          projectId: () => projectId,
          taskName: _task.text.trim(),
          description: _description.text.trim(),
          start: start,
          end: () => end,
        ));
      }
      refreshEntryData(ref);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        await showAppError(context, title: 'Could not save entry', error: e);
      }
    }
  }

  Future<void> _delete() async {
    final e = widget.existing;
    if (e?.id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entry?'),
        content: const Text('This time entry will be permanently removed.'),
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
    if (ok == true) {
      try {
        await ref.read(databaseProvider).deleteEntry(e!.id!);
        refreshEntryData(ref);
        if (mounted) Navigator.pop(context, true);
      } catch (err) {
        if (mounted) {
          await showAppError(context,
              title: 'Could not delete entry', error: err);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = ref.watch(_manualDateProvider) ?? _initialDate;
    final startT = ref.watch(_manualStartProvider) ?? _initialStart;
    final endT = ref.watch(_manualEndProvider) ?? _initialEnd;

    final dateFmt = DateFormat('EEE, dd MMM yyyy');
    final span = _combine(date, endT).difference(_combine(date, startT));
    final validSpan = span.inMinutes > 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit entry' : 'Add entry'),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _person,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Person',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            ProjectField(
              projectId: ref.watch(manualProjectProvider(_initialProjectId)),
              onChanged: (v) => ref
                  .read(manualProjectProvider(_initialProjectId).notifier)
                  .state = v,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _task,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Task (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            _boxTile(
              icon: Icons.calendar_today,
              title: 'Date',
              subtitle: dateFmt.format(date),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                );
                if (picked != null) {
                  ref.read(_manualDateProvider.notifier).state = picked;
                }
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _boxTile(
                    icon: Icons.login,
                    title: 'Start',
                    subtitle: startT.format(context),
                    onTap: () async {
                      final picked = await showTimePicker(
                          context: context, initialTime: startT);
                      if (picked != null) {
                        ref.read(_manualStartProvider.notifier).state = picked;
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _boxTile(
                    icon: Icons.logout,
                    title: 'End',
                    subtitle: endT.format(context),
                    onTap: () async {
                      final picked = await showTimePicker(
                          context: context, initialTime: endT);
                      if (picked != null) {
                        ref.read(_manualEndProvider.notifier).state = picked;
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              validSpan ? 'Duration: ${_fmt(span)}' : 'End must be after start',
              style: TextStyle(
                color: validSpan
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _description,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _save(date, startT, endT),
              icon: const Icon(Icons.save),
              label: const Text('Save entry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _boxTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }
}
