import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../models/project.dart';
import '../providers/app_providers.dart';
import '../widgets/error_handling.dart';

/// Preset colours offered when creating/editing a project.
const kProjectColors = <Color>[
  Color(0xFF2E6BE6), // blue
  Color(0xFF34C3CC), // teal
  Color(0xFF22A565), // green
  Color(0xFFE6A817), // amber
  Color(0xFFE0552B), // orange
  Color(0xFFD64550), // red
  Color(0xFF8E44AD), // purple
  Color(0xFF5D6D7E), // slate
];

class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref,
      [Project? existing]) async {
    final result = await showModalBottomSheet<Project>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ProjectSheet(existing: existing),
    );
    if (result == null || !context.mounted) return;
    await guard(context, () async {
      final db = ref.read(databaseProvider);
      if (result.id == null) {
        await db.insertProject(result);
      } else {
        await db.updateProject(result);
      }
      ref.invalidate(managedProjectsProvider);
      ref.invalidate(activeProjectsProvider);
    }, title: 'Could not save project');
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, Project p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete project?'),
        content: Text(
          '"${p.name}" and its tasks will be deleted. Existing time entries '
          'are kept but lose their project tag.\n\nTip: Archive instead to hide '
          'it without affecting history.',
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
    if (ok == true && p.id != null && context.mounted) {
      await guard(context, () async {
        await ref.read(databaseProvider).deleteProject(p.id!);
        ref.invalidate(managedProjectsProvider);
        ref.invalidate(activeProjectsProvider);
        refreshEntryData(ref);
      }, title: 'Could not delete project');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showArchived = ref.watch(showArchivedProjectsProvider);
    final projectsAsync = ref.watch(managedProjectsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Projects'),
        actions: [
          IconButton(
            tooltip: showArchived ? 'Hide archived' : 'Show archived',
            icon: Icon(
                showArchived ? Icons.visibility_off : Icons.archive_outlined),
            onPressed: () => ref
                .read(showArchivedProjectsProvider.notifier)
                .state = !showArchived,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Project'),
      ),
      body: projectsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
            error: e, onRetry: () => ref.invalidate(managedProjectsProvider)),
        data: (projects) {
          if (projects.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No projects yet.\nTap “Project” to add one.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: projects.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final pr = projects[i];
              return ListTile(
                leading: CircleAvatar(backgroundColor: pr.colorValue),
                title: Text(pr.name),
                subtitle: pr.archived ? const Text('Archived') : null,
                onTap: () => _edit(context, ref, pr),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    switch (v) {
                      case 'edit':
                        await _edit(context, ref, pr);
                        break;
                      case 'archive':
                        await guard(context, () async {
                          await ref
                              .read(databaseProvider)
                              .setProjectArchived(pr.id!, !pr.archived);
                          ref.invalidate(managedProjectsProvider);
                          ref.invalidate(activeProjectsProvider);
                        }, title: 'Could not update project');
                        break;
                      case 'delete':
                        await _delete(context, ref, pr);
                        break;
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(
                      value: 'archive',
                      child: Text(pr.archived ? 'Unarchive' : 'Archive'),
                    ),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Per-sheet selected colour, seeded with the initial colour (family arg).
final _sheetColorProvider =
    StateProvider.autoDispose.family<int, int>((ref, initial) => initial);

/// Create/edit a project in a bottom-sheet modal (returns a [Project] on save).
class _ProjectSheet extends ConsumerStatefulWidget {
  final Project? existing;
  const _ProjectSheet({this.existing});

  @override
  ConsumerState<_ProjectSheet> createState() => _ProjectSheetState();
}

class _ProjectSheetState extends ConsumerState<_ProjectSheet> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.existing?.name ?? '');

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    final initialColor = existing?.color ?? kProjectColors.first.toARGB32();
    final selected = ref.watch(_sheetColorProvider(initialColor));

    void save() {
      final name = _nameController.text.trim();
      if (name.isEmpty) return;
      Navigator.pop(
        context,
        existing == null
            ? Project(name: name, color: selected, createdAt: DateTime.now())
            : existing.copyWith(name: name, color: selected),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            existing == null ? 'New project' : 'Edit project',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Project name'),
            onSubmitted: (_) => save(),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Colour',
                style: Theme.of(context).textTheme.labelLarge),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: kProjectColors.map((c) {
              final argb = c.toARGB32();
              final isSelected = argb == selected;
              return GestureDetector(
                onTap: () => ref
                    .read(_sheetColorProvider(initialColor).notifier)
                    .state = argb,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: isSelected
                        ? Border.all(
                            color: Theme.of(context).colorScheme.onSurface,
                            width: 3)
                        : null,
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                                color: c.withValues(alpha: 0.5),
                                blurRadius: 8)
                          ]
                        : null,
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, color: Colors.white, size: 20)
                      : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                    onPressed: save, child: const Text('Save')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
