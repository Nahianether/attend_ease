import '../models/time_entry.dart';

/// Sums worked time per person from a list of time entries. Running entries
/// contribute their live time up to [now] (paused time already excluded by
/// [TimeEntry.worked]).
Map<String, Duration> dailyTotalsByPerson(
  List<TimeEntry> entries,
  DateTime now,
) {
  final totals = <String, Duration>{};
  for (final e in entries) {
    totals[e.person] = (totals[e.person] ?? Duration.zero) + e.worked(now);
  }
  return totals;
}

/// Formats a duration as `Hh Mm` (e.g. `2h 05m`).
String formatHm(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  return '${h}h ${m.toString().padLeft(2, '0')}m';
}

/// Formats a duration as `H:MM:SS` (live timer style).
String formatHms(Duration d) {
  final h = d.inHours.toString().padLeft(2, '0');
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}
