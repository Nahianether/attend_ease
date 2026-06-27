import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../models/project.dart';
import '../providers/app_providers.dart';

// Selected project for the pickers. `startProjectProvider` is for the START
// sheet; `manualProjectProvider` (family keyed by the initial value) seeds the
// manual-entry form. Task is now free text owned by each form's controller.
final startProjectProvider = StateProvider.autoDispose<int?>((_) => null);
final manualProjectProvider =
    StateProvider.autoDispose.family<int?, int?>((ref, initial) => initial);

/// A single Project dropdown (optional). The owner holds the selection and is
/// notified via [onChanged].
class ProjectField extends ConsumerWidget {
  final int? projectId;
  final ValueChanged<int?> onChanged;

  const ProjectField({super.key, required this.projectId, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects =
        ref.watch(activeProjectsProvider).asData?.value ?? const <Project>[];

    final items = <DropdownMenuItem<int?>>[
      const DropdownMenuItem<int?>(value: null, child: Text('No project')),
      ...projects.map((p) => DropdownMenuItem<int?>(
            value: p.id,
            child: Row(
              children: [
                CircleAvatar(radius: 7, backgroundColor: p.colorValue),
                const SizedBox(width: 8),
                Flexible(child: Text(p.name, overflow: TextOverflow.ellipsis)),
              ],
            ),
          )),
    ];
    // Guard: a project archived after tagging won't be in the active list.
    if (projectId != null && !projects.any((p) => p.id == projectId)) {
      items.add(DropdownMenuItem<int?>(
          value: projectId, child: const Text('(archived project)')));
    }

    return DropdownButtonFormField<int?>(
      initialValue: projectId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Project (optional)',
        border: OutlineInputBorder(),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}

/// Result of the START sheet.
class StartSelection {
  final int? projectId;
  final String taskName;
  final String description;
  const StartSelection(
      {this.projectId, this.taskName = '', this.description = ''});
}

/// Shows the optional Project + Task + description sheet when starting a
/// session. Returns a [StartSelection] when the user taps Start, or null if
/// dismissed.
Future<StartSelection?> showStartSheet(BuildContext context, WidgetRef ref) {
  ref.read(startProjectProvider.notifier).state = null;
  return showModalBottomSheet<StartSelection>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _StartSheet(),
  );
}

class _StartSheet extends ConsumerStatefulWidget {
  const _StartSheet();

  @override
  ConsumerState<_StartSheet> createState() => _StartSheetState();
}

class _StartSheetState extends ConsumerState<_StartSheet> {
  final _task = TextEditingController();
  final _desc = TextEditingController();

  @override
  void dispose() {
    _task.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final projectId = ref.watch(startProjectProvider);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('What are you working on?',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          ProjectField(
            projectId: projectId,
            onChanged: (v) =>
                ref.read(startProjectProvider.notifier).state = v,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _task,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Task (optional)',
              hintText: 'What you are doing',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      Navigator.pop(context, const StartSelection()),
                  child: const Text('Skip'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(
                    context,
                    StartSelection(
                      projectId: projectId,
                      taskName: _task.text.trim(),
                      description: _desc.text.trim(),
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
