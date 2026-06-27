import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:intl/intl.dart';

import '../models/time_entry.dart';
import '../providers/app_providers.dart';
import '../services/attendance_stats.dart';
import '../widgets/error_handling.dart';
import 'manual_entry_screen.dart';

/// Ids of entries currently selected for multi-delete (empty = normal mode).
final _selectionProvider = StateProvider.autoDispose<Set<int>>((_) => <int>{});

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  void _openEditor(BuildContext context, [TimeEntry? entry]) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ManualEntryScreen(existing: entry)),
    );
  }

  void _toggle(WidgetRef ref, int id) {
    final next = {...ref.read(_selectionProvider)};
    if (!next.remove(id)) next.add(id);
    ref.read(_selectionProvider.notifier).state = next;
  }

  void _clear(WidgetRef ref) =>
      ref.read(_selectionProvider.notifier).state = <int>{};

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Set<int> ids) async {
    if (ids.isEmpty) return;
    final n = ids.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(n == 1 ? 'Delete entry?' : 'Delete $n entries?'),
        content: Text(
          'This will permanently remove '
          '${n == 1 ? 'this time entry' : '$n time entries'}. '
          'This can\'t be undone.',
        ),
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
    if (ok != true || !context.mounted) return;
    await guard(context, () async {
      final db = ref.read(databaseProvider);
      for (final id in ids) {
        await db.deleteEntry(id);
      }
      refreshEntryData(ref);
      _clear(ref);
    }, title: 'Could not delete');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(historyProvider);
    final selection = ref.watch(_selectionProvider);
    final selecting = selection.isNotEmpty;

    final allIds = entriesAsync.asData?.value
            .map((v) => v.entry.id)
            .whereType<int>()
            .toSet() ??
        <int>{};

    return Scaffold(
      appBar: selecting
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Cancel',
                onPressed: () => _clear(ref),
              ),
              title: Text('${selection.length} selected'),
              actions: [
                IconButton(
                  tooltip: 'Select all',
                  icon: const Icon(Icons.select_all),
                  onPressed: () =>
                      ref.read(_selectionProvider.notifier).state = allIds,
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDelete(context, ref, selection),
                ),
              ],
            )
          : AppBar(
              title: const Text('History'),
              actions: [
                IconButton(
                  tooltip: 'Add entry',
                  icon: const Icon(Icons.add),
                  onPressed: () => _openEditor(context),
                ),
              ],
            ),
      floatingActionButton: selecting
          ? null
          : FloatingActionButton(
              onPressed: () => _openEditor(context),
              tooltip: 'Add entry',
              child: const Icon(Icons.add),
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
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: views.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final v = views[i];
              final e = v.entry;
              final id = e.id;
              final selected = id != null && selection.contains(id);
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
                selected: selected,
                selectedTileColor:
                    Theme.of(context).colorScheme.primaryContainer.withValues(
                          alpha: 0.4,
                        ),
                leading: selecting
                    ? Checkbox(
                        value: selected,
                        onChanged:
                            id == null ? null : (_) => _toggle(ref, id),
                      )
                    : CircleAvatar(
                        backgroundColor: color,
                        child: Text(
                          e.person.isNotEmpty
                              ? e.person[0].toUpperCase()
                              : '?',
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
                trailing: selecting
                    ? null
                    : PopupMenuButton<String>(
                        onSelected: (val) {
                          if (val == 'edit') {
                            _openEditor(context, e);
                          } else if (val == 'delete' && id != null) {
                            _confirmDelete(context, ref, {id});
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                onTap: () {
                  if (selecting) {
                    if (id != null) _toggle(ref, id);
                  } else {
                    _openEditor(context, e);
                  }
                },
                onLongPress:
                    id == null ? null : () => _toggle(ref, id),
              );
            },
          );
        },
      ),
    );
  }
}
