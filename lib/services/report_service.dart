import 'package:intl/intl.dart';

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

/// A labelled time bucket for the report bar chart.
class TimeBucket {
  final String label;
  final Duration total;
  const TimeBucket(this.label, this.total);
}

/// Splits [rows] into ordered buckets across [range] for the bar chart: one bar
/// per day for short ranges (≤ 45 days), otherwise one per month. Empty buckets
/// are included so the timeline stays continuous.
List<TimeBucket> timeBuckets(
    List<TimeEntryView> rows, DateRange range, DateTime now) {
  final spanDays = range.end.difference(range.start).inDays;
  final byMonth = spanDays > 45;
  final keys = <String>[];
  final labels = <String, String>{};
  final totals = <String, Duration>{};

  void add(String key, String label) {
    keys.add(key);
    labels[key] = label;
    totals[key] = Duration.zero;
  }

  if (byMonth) {
    final lastDay = range.end.subtract(const Duration(days: 1));
    var m = DateTime(range.start.year, range.start.month);
    final endM = DateTime(lastDay.year, lastDay.month);
    while (!m.isAfter(endM)) {
      add('${m.year}-${m.month}', DateFormat('MMM').format(m));
      m = DateTime(m.year, m.month + 1);
    }
  } else {
    var d = DateTime(range.start.year, range.start.month, range.start.day);
    while (d.isBefore(range.end)) {
      add('${d.year}-${d.month}-${d.day}', DateFormat('d').format(d));
      d = d.add(const Duration(days: 1));
    }
  }

  for (final v in rows) {
    final s = v.entry.start;
    final key =
        byMonth ? '${s.year}-${s.month}' : '${s.year}-${s.month}-${s.day}';
    final cur = totals[key];
    if (cur != null) totals[key] = cur + v.entry.worked(now);
  }

  return keys.map((k) => TimeBucket(labels[k]!, totals[k]!)).toList();
}

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
