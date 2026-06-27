/// One work session: a person's tracked time, optionally tagged to a
/// project/task, with a description. Replaces the old in/out event model.
///
/// `end == null` means the session is still running. Worked time excludes
/// [pausedSeconds] (time the timer was paused).
class TimeEntry {
  final int? id;
  final String person;
  final int? projectId;
  final String taskName; // free text, typed per session
  final String description;
  final DateTime start;
  final DateTime? end;
  final int pausedSeconds;
  final String source; // 'timer' | 'manual' | 'migrated'
  final DateTime createdAt;

  const TimeEntry({
    this.id,
    required this.person,
    this.projectId,
    this.taskName = '',
    this.description = '',
    required this.start,
    this.end,
    this.pausedSeconds = 0,
    this.source = 'timer',
    required this.createdAt,
  });

  bool get isRunning => end == null;

  /// Worked duration, excluding paused time. For a running entry, [now]
  /// (default: DateTime.now()) is used as the end. Never negative.
  Duration worked([DateTime? now]) {
    final endMs = (end ?? now ?? DateTime.now()).millisecondsSinceEpoch;
    final ms = endMs - start.millisecondsSinceEpoch - pausedSeconds * 1000;
    return Duration(milliseconds: ms < 0 ? 0 : ms);
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'person': person,
        'project_id': projectId,
        'task_name': taskName,
        'description': description,
        'start_ms': start.millisecondsSinceEpoch,
        'end_ms': end?.millisecondsSinceEpoch,
        'paused_seconds': pausedSeconds,
        'source': source,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory TimeEntry.fromMap(Map<String, Object?> map) => TimeEntry(
        id: map['id'] as int?,
        person: map['person'] as String,
        projectId: map['project_id'] as int?,
        taskName: (map['task_name'] as String?) ?? '',
        description: (map['description'] as String?) ?? '',
        start: DateTime.fromMillisecondsSinceEpoch(map['start_ms'] as int),
        end: map['end_ms'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(map['end_ms'] as int),
        pausedSeconds: (map['paused_seconds'] as int?) ?? 0,
        source: (map['source'] as String?) ?? 'timer',
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      );

  TimeEntry copyWith({
    int? id,
    String? person,
    int? Function()? projectId,
    String? taskName,
    String? description,
    DateTime? start,
    DateTime? Function()? end,
    int? pausedSeconds,
    String? source,
    DateTime? createdAt,
  }) =>
      TimeEntry(
        id: id ?? this.id,
        person: person ?? this.person,
        projectId: projectId != null ? projectId() : this.projectId,
        taskName: taskName ?? this.taskName,
        description: description ?? this.description,
        start: start ?? this.start,
        end: end != null ? end() : this.end,
        pausedSeconds: pausedSeconds ?? this.pausedSeconds,
        source: source ?? this.source,
        createdAt: createdAt ?? this.createdAt,
      );
}

/// A [TimeEntry] joined with its project name + colour, for display in lists
/// and reports without N+1 lookups. (Task is free text on the entry itself.)
class TimeEntryView {
  final TimeEntry entry;
  final String? projectName;
  final int? projectColor; // ARGB

  const TimeEntryView({
    required this.entry,
    this.projectName,
    this.projectColor,
  });

  /// The task label (entry's free-text task, or null when blank).
  String? get taskName => entry.taskName.isEmpty ? null : entry.taskName;

  factory TimeEntryView.fromMap(Map<String, Object?> map) => TimeEntryView(
        entry: TimeEntry.fromMap(map),
        projectName: map['project_name'] as String?,
        projectColor: map['project_color'] as int?,
      );
}
