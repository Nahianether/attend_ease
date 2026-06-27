import '../models/time_entry.dart';

enum DateRangePreset {
  today,
  thisWeek,
  thisMonth,
  lastMonth,
  thisYear,
  lastYear,
  custom,
}

extension DateRangePresetLabel on DateRangePreset {
  String get label => switch (this) {
        DateRangePreset.today => 'Today',
        DateRangePreset.thisWeek => 'This week',
        DateRangePreset.thisMonth => 'This month',
        DateRangePreset.lastMonth => 'Last month',
        DateRangePreset.thisYear => 'This year',
        DateRangePreset.lastYear => 'Last year',
        DateRangePreset.custom => 'Custom',
      };
}

/// A half-open date range [start, end).
class DateRange {
  final DateTime start;
  final DateTime end;
  const DateRange(this.start, this.end);
}

/// Resolves a preset to a concrete [DateRange]. Week starts Monday. [now]
/// defaults to DateTime.now() (injectable for tests).
DateRange resolveRange(DateRangePreset preset, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  switch (preset) {
    case DateRangePreset.today:
      return DateRange(today, today.add(const Duration(days: 1)));
    case DateRangePreset.thisWeek:
      final monday = today.subtract(Duration(days: today.weekday - 1));
      return DateRange(monday, monday.add(const Duration(days: 7)));
    case DateRangePreset.thisMonth:
      return DateRange(DateTime(n.year, n.month, 1), DateTime(n.year, n.month + 1, 1));
    case DateRangePreset.lastMonth:
      return DateRange(DateTime(n.year, n.month - 1, 1), DateTime(n.year, n.month, 1));
    case DateRangePreset.thisYear:
      return DateRange(DateTime(n.year, 1, 1), DateTime(n.year + 1, 1, 1));
    case DateRangePreset.lastYear:
      return DateRange(DateTime(n.year - 1, 1, 1), DateTime(n.year, 1, 1));
    case DateRangePreset.custom:
      return DateRange(today, today.add(const Duration(days: 1)));
  }
}

/// A node in a report tree: a label, its total time, and optional children.
class ReportNode {
  final String label;
  final Duration total;
  final List<ReportNode> children;
  final int? color; // ARGB, for the project row

  const ReportNode({
    required this.label,
    required this.total,
    this.children = const [],
    this.color,
  });
}

const _noProject = 'No project';
const _noTask = 'No task';

/// Grand total across all [rows].
Duration grandTotal(List<TimeEntryView> rows, DateTime now) => rows.fold(
      Duration.zero,
      (acc, v) => acc + v.entry.worked(now),
    );

/// Groups entries by Project → Task, each with subtotals, sorted by time desc.
List<ReportNode> summaryByProjectTask(List<TimeEntryView> rows, DateTime now) {
  // project label -> (color, total, {task label -> total})
  final projects = <String, _ProjAgg>{};
  for (final v in rows) {
    final pName = v.projectName ?? _noProject;
    final tName = v.taskName ?? _noTask;
    final worked = v.entry.worked(now);
    final agg = projects.putIfAbsent(pName, () => _ProjAgg(v.projectColor));
    agg.total += worked;
    agg.tasks[tName] = (agg.tasks[tName] ?? Duration.zero) + worked;
  }
  final nodes = projects.entries.map((e) {
    final tasks = e.value.tasks.entries
        .map((t) => ReportNode(label: t.key, total: t.value))
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    return ReportNode(
      label: e.key,
      total: e.value.total,
      color: e.value.color,
      children: tasks,
    );
  }).toList()
    ..sort((a, b) => b.total.compareTo(a.total));
  return nodes;
}

class _ProjAgg {
  final int? color;
  Duration total = Duration.zero;
  final Map<String, Duration> tasks = {};
  _ProjAgg(this.color);
}
