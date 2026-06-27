import 'package:flutter_test/flutter_test.dart';

import 'package:attend_ease/models/time_entry.dart';
import 'package:attend_ease/services/report_service.dart';

void main() {
  final now = DateTime(2026, 6, 27, 18);

  TimeEntryView view({
    required String person,
    String? project,
    int? projectColor,
    String task = '',
    required int startHour,
    required int endHour,
  }) {
    return TimeEntryView(
      entry: TimeEntry(
        person: person,
        taskName: task,
        start: DateTime(2026, 6, 27, startHour),
        end: DateTime(2026, 6, 27, endHour),
        createdAt: DateTime(2026, 6, 27),
      ),
      projectName: project,
      projectColor: projectColor,
    );
  }

  final rows = [
    view(person: 'Rahim', project: 'Site A', task: 'Wiring', startHour: 8, endHour: 12), // 4h
    view(person: 'Rahim', project: 'Site A', task: 'Wiring', startHour: 13, endHour: 15), // 2h
    view(person: 'Rahim', project: 'Site A', task: 'Plumbing', startHour: 15, endHour: 16), // 1h
    view(person: 'Karim', project: 'Site B', task: 'Painting', startHour: 9, endHour: 14), // 5h
    view(person: 'Karim', startHour: 14, endHour: 15), // 1h untagged
  ];

  test('grand total sums all worked time', () {
    expect(grandTotal(rows, now), const Duration(hours: 13));
  });

  test('summaryByProjectTask groups and subtotals, sorted desc', () {
    final nodes = summaryByProjectTask(rows, now);
    // Site A (7h) > Site B (5h) > No project (1h)
    expect(nodes.map((n) => n.label).toList(),
        ['Site A', 'Site B', 'No project']);
    expect(nodes[0].total, const Duration(hours: 7));

    final siteA = nodes[0];
    // Wiring 6h > Plumbing 1h
    expect(siteA.children.map((c) => c.label).toList(), ['Wiring', 'Plumbing']);
    expect(siteA.children[0].total, const Duration(hours: 6));

    expect(nodes[2].label, 'No project');
    expect(nodes[2].children.single.label, 'No task');
  });

  group('resolveRange', () {
    test('today is the calendar day', () {
      final r = resolveRange(DateRangePreset.today, now: now);
      expect(r.start, DateTime(2026, 6, 27));
      expect(r.end, DateTime(2026, 6, 28));
    });

    test('week starts Monday', () {
      // 2026-06-27 is a Saturday; Monday is 2026-06-22.
      final r = resolveRange(DateRangePreset.thisWeek, now: now);
      expect(r.start, DateTime(2026, 6, 22));
      expect(r.end, DateTime(2026, 6, 29));
    });

    test('month spans the calendar month', () {
      final r = resolveRange(DateRangePreset.thisMonth, now: now);
      expect(r.start, DateTime(2026, 6, 1));
      expect(r.end, DateTime(2026, 7, 1));
    });

    test('last month spans the previous calendar month', () {
      final r = resolveRange(DateRangePreset.lastMonth, now: now);
      expect(r.start, DateTime(2026, 5, 1));
      expect(r.end, DateTime(2026, 6, 1));
    });

    test('this year spans the calendar year', () {
      final r = resolveRange(DateRangePreset.thisYear, now: now);
      expect(r.start, DateTime(2026, 1, 1));
      expect(r.end, DateTime(2027, 1, 1));
    });

    test('last year spans the previous calendar year', () {
      final r = resolveRange(DateRangePreset.lastYear, now: now);
      expect(r.start, DateTime(2025, 1, 1));
      expect(r.end, DateTime(2026, 1, 1));
    });
  });
}
