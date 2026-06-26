import '../models/attendance_record.dart';

/// Sums the duration of *completed* check-in → check-out pairs per person for
/// the given records (assumed to be a single day, sorted oldest first).
///
/// A trailing check-in with no matching check-out is treated as an ongoing
/// session and is NOT counted here — the live timer on the home screen adds
/// that person's running time on top.
Map<String, Duration> completedTotals(List<AttendanceRecord> records) {
  final totals = <String, Duration>{};
  final openSince = <String, DateTime>{};

  for (final r in records) {
    if (r.isCheckIn) {
      openSince[r.name] = r.timestamp;
    } else {
      final start = openSince.remove(r.name);
      if (start != null) {
        totals[r.name] = (totals[r.name] ?? Duration.zero) +
            r.timestamp.difference(start);
      }
    }
  }
  return totals;
}

/// Formats a duration as `Hh Mm` (e.g. `2h 05m`).
String formatHm(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  return '${h}h ${m.toString().padLeft(2, '0')}m';
}
