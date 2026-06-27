import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/time_entry.dart';
import '../providers/app_providers.dart';
import '../services/attendance_stats.dart';
import '../widgets/error_handling.dart';
import 'manual_entry_screen.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  void _openEditor(BuildContext context, [TimeEntry? entry]) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ManualEntryScreen(existing: entry)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(historyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('Entry'),
      ),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            ErrorView(error: e, onRetry: () => ref.invalidate(historyProvider)),
        data: (views) {
          if (views.isEmpty) {
            return const Center(child: Text('No time entries yet.'));
          }
          return ListView.separated(
            itemCount: views.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final v = views[i];
              final e = v.entry;
              final color = v.projectColor != null
                  ? Color(v.projectColor!)
                  : Theme.of(context).colorScheme.surfaceContainerHighest;
              final tag = [
                if (v.projectName != null) v.projectName!,
                if (v.taskName != null) v.taskName!,
              ].join(' · ');
              final timeRange = e.isRunning
                  ? '${DateFormat('dd MMM, hh:mm a').format(e.start)} → running'
                  : '${DateFormat('dd MMM, hh:mm a').format(e.start)} – '
                      '${DateFormat('hh:mm a').format(e.end!)}';
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: color,
                  child: Text(
                    e.person.isNotEmpty ? e.person[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                title: Row(
                  children: [
                    Expanded(child: Text(e.person)),
                    Text(
                      e.isRunning ? '• live' : formatHm(e.worked()),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: e.isRunning
                            ? Colors.green
                            : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (tag.isNotEmpty) Text(tag),
                    if (e.description.isNotEmpty)
                      Text(e.description,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(timeRange,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
                isThreeLine: tag.isNotEmpty || e.description.isNotEmpty,
                onTap: () => _openEditor(context, e),
              );
            },
          );
        },
      ),
    );
  }
}
