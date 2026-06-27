import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';

import 'package:attend_ease/screens/manual_entry_screen.dart';

void main() {
  final date = DateTime(2026, 6, 28);

  test('same-day entry keeps the end on the same date', () {
    final (start, end) = resolveEntryTimes(
        date, const TimeOfDay(hour: 9, minute: 0),
        const TimeOfDay(hour: 17, minute: 30));
    expect(start, DateTime(2026, 6, 28, 9, 0));
    expect(end, DateTime(2026, 6, 28, 17, 30));
    expect(end.difference(start), const Duration(hours: 8, minutes: 30));
  });

  test('overnight entry rolls the end to the next day', () {
    // 11:48 PM -> 1:24 AM should be a valid 1h 36m session.
    final (start, end) = resolveEntryTimes(
        date, const TimeOfDay(hour: 23, minute: 48),
        const TimeOfDay(hour: 1, minute: 24));
    expect(start, DateTime(2026, 6, 28, 23, 48));
    expect(end, DateTime(2026, 6, 29, 1, 24));
    expect(end.difference(start), const Duration(hours: 1, minutes: 36));
  });
}
