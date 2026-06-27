import 'package:flutter_test/flutter_test.dart';

import 'package:attend_ease/services/pdf_report_service.dart';
import 'package:attend_ease/services/report_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('builds and saves a report PDF without throwing', () async {
    final nodes = [
      const ReportNode(
        label: 'Website Redesign',
        total: Duration(hours: 8, minutes: 30),
        color: 0xFF2E6BE6,
        children: [
          ReportNode(label: 'Landing page', total: Duration(hours: 6)),
          ReportNode(label: 'Code review', total: Duration(hours: 2, minutes: 30)),
        ],
      ),
      const ReportNode(
        label: 'No project',
        total: Duration(hours: 1),
        children: [ReportNode(label: 'No task', total: Duration(hours: 1))],
      ),
    ];
    final doc = await PdfReportService().build(
      title: 'Time Report',
      range: DateRange(DateTime(2026, 6, 22), DateTime(2026, 6, 29)),
      nodes: nodes,
      total: const Duration(hours: 9, minutes: 30),
    );
    final bytes = await doc.save();
    expect(bytes.lengthInBytes, greaterThan(0));
  });
}
