import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/time_entry.dart';
import '../providers/app_providers.dart';
import '../services/attendance_stats.dart';
import '../services/pdf_report_service.dart';
import '../services/report_service.dart';
import '../widgets/error_handling.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  Future<void> _selectPreset(
      BuildContext context, WidgetRef ref, DateRangePreset preset) async {
    if (preset == DateRangePreset.custom) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final current = ref.read(reportRangeProvider);
      // Stored range end is exclusive; the inclusive end is one day earlier.
      // Clamp inside [firstDate, today] so the picker's assertions hold.
      var initEnd = current.end.subtract(const Duration(days: 1));
      if (initEnd.isAfter(today)) initEnd = today;
      var initStart = current.start;
      if (initStart.isAfter(initEnd)) initStart = initEnd;
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: today,
        initialDateRange: DateTimeRange(start: initStart, end: initEnd),
      );
      if (picked == null) return;
      final start =
          DateTime(picked.start.year, picked.start.month, picked.start.day);
      final end = DateTime(picked.end.year, picked.end.month, picked.end.day)
          .add(const Duration(days: 1));
      ref.read(reportPresetProvider.notifier).state = preset;
      ref.read(reportRangeProvider.notifier).state = DateRange(start, end);
    } else {
      ref.read(reportPresetProvider.notifier).state = preset;
      ref.read(reportRangeProvider.notifier).state = resolveRange(preset);
    }
  }

  Future<void> _export(
      BuildContext context, WidgetRef ref, List<TimeEntryView> rows) async {
    final now = DateTime.now();
    final pdf = PdfReportService();
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share / Save PDF'),
              onTap: () => Navigator.pop(ctx, 'share'),
            ),
            ListTile(
              leading: const Icon(Icons.print),
              title: const Text('Print preview'),
              onTap: () => Navigator.pop(ctx, 'print'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    await guard(context, () async {
      final range = ref.read(reportRangeProvider);
      final doc = await pdf.build(
        title: 'Time Report',
        range: range,
        nodes: summaryByProjectTask(rows, now),
        daily: timeBuckets(rows, range, now),
        total: grandTotal(rows, now),
      );
      if (choice == 'share') {
        await pdf.share(doc);
      } else {
        await pdf.printPreview(doc);
      }
    }, title: 'Could not export PDF');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preset = ref.watch(reportPresetProvider);
    final range = ref.watch(reportRangeProvider);
    final entriesAsync = ref.watch(reportEntriesProvider);
    final now = DateTime.now();

    final dateFmt = DateFormat('dd MMM');
    final rangeText =
        '${dateFmt.format(range.start)} – ${dateFmt.format(range.end.subtract(const Duration(days: 1)))}';

    final rows = entriesAsync.asData?.value ?? const <TimeEntryView>[];
    final nodes = summaryByProjectTask(rows, now);
    final total = grandTotal(rows, now);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          IconButton(
            tooltip: 'Export PDF',
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: rows.isEmpty ? null : () => _export(context, ref, rows),
          ),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: DateRangePreset.values.map((p) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(p.label),
                    selected: preset == p,
                    onSelected: (_) => _selectPreset(context, ref, p),
                  ),
                );
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child:
                  Text(rangeText, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total tracked',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text(formatHm(total),
                    style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ),
          Expanded(
            child: entriesAsync.hasError
                ? ErrorView(
                    error: entriesAsync.error!,
                    onRetry: () => ref.invalidate(reportEntriesProvider))
                : entriesAsync.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : nodes.isEmpty
                        ? const Center(
                            child: Text('No time tracked in this range.'))
                        : ListView(
                            padding: const EdgeInsets.only(bottom: 24),
                            children:
                                nodes.map((n) => _GroupTile(node: n)).toList(),
                          ),
          ),
        ],
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  final ReportNode node;
  const _GroupTile({required this.node});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ExpansionTile(
        leading: CircleAvatar(
          radius: 10,
          backgroundColor: node.color != null
              ? Color(node.color!)
              : Theme.of(context).colorScheme.secondaryContainer,
        ),
        title: Text(node.label,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        trailing: Text(formatHm(node.total),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        childrenPadding: const EdgeInsets.only(left: 24, right: 16, bottom: 8),
        children: node.children
            .map((c) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(child: Text(c.label)),
                      Text(formatHm(c.total)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}
