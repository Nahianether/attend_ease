import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/time_entry.dart';
import '../providers/app_providers.dart';
import '../services/attendance_stats.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import '../widgets/error_handling.dart';
import '../widgets/project_task_picker.dart';
import 'history_screen.dart';
import 'projects_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _bootstrapped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;
    final s = await ref.read(settingsProvider.future);
    if (!mounted) return;
    if (s.needsOnboarding) {
      await _onboard();
    } else {
      await ref.read(sessionProvider.notifier).resumeIfAny(s.defaultUserName);
    }
  }

  Future<void> _onboard() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Welcome to AttendEase'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('What is your full name?'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Your name',
                hintText: 'e.g. Rahim Uddin',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) {
      if (mounted) await _onboard(); // re-ask until we have a name
      return;
    }
    await ref.read(settingsProvider.notifier).setName(name.trim());
  }

  Future<void> _onMainButton(AppSettings settings, bool running) async {
    if (ref.read(homeBusyProvider)) return;
    if (settings.needsOnboarding) {
      await _onboard();
      return;
    }
    if (running) {
      await _checkOut();
    } else {
      await _checkIn(settings.defaultUserName);
    }
  }

  Future<void> _checkIn(String name) async {
    final sel = await showStartSheet(context, ref);
    if (sel == null) return;

    ref.read(homeBusyProvider.notifier).state = true;
    try {
      final entry = await ref.read(sessionProvider.notifier).start(
            person: name,
            projectId: sel.projectId,
            taskName: sel.taskName,
            description: sel.description,
          );
      ref.invalidate(todayTotalsProvider);
      final settings =
          ref.read(settingsProvider).asData?.value ?? const AppSettings();
      var result = const NotifyResult();
      if (settings.notifyWhatsApp) {
        result = await ref.read(notificationServiceProvider).notify(
              settings: settings,
              person: name,
              isCheckIn: true,
              when: entry.start,
              projectName: await _projectName(entry.projectId),
              taskName: entry.taskName,
              description: sel.description,
            );
      }
      if (mounted) {
        _showOutcome(
            name: name,
            isCheckIn: true,
            res: result,
            notifyEnabled: settings.notifyWhatsApp);
      }
    } catch (e) {
      if (mounted) {
        await showAppError(context, title: 'Could not check in', error: e);
      }
    } finally {
      if (mounted) ref.read(homeBusyProvider.notifier).state = false;
    }
  }

  Future<void> _checkOut() async {
    ref.read(homeBusyProvider.notifier).state = true;
    try {
      final result = await ref.read(sessionProvider.notifier).stop();
      if (result == null) return;
      ref.invalidate(todayTotalsProvider);
      ref.invalidate(historyProvider);
      ref.invalidate(reportEntriesProvider);
      final entry = result.entry;
      final settings =
          ref.read(settingsProvider).asData?.value ?? const AppSettings();
      var notif = const NotifyResult();
      if (settings.notifyWhatsApp) {
        notif = await ref.read(notificationServiceProvider).notify(
              settings: settings,
              person: entry.person,
              isCheckIn: false,
              when: entry.end!,
              projectName: await _projectName(entry.projectId),
              taskName: entry.taskName,
              description: entry.description,
            );
      }
      if (mounted) {
        _showOutcome(
            name: entry.person,
            isCheckIn: false,
            res: notif,
            worked: result.worked,
            notifyEnabled: settings.notifyWhatsApp);
      }
    } catch (e) {
      if (mounted) {
        await showAppError(context, title: 'Could not check out', error: e);
      }
    } finally {
      if (mounted) ref.read(homeBusyProvider.notifier).state = false;
    }
  }

  Future<String?> _projectName(int? projectId) async {
    if (projectId == null) return null;
    return (await ref.read(databaseProvider).getProject(projectId))?.name;
  }

  void _showOutcome(
      {required String name,
      required bool isCheckIn,
      required NotifyResult res,
      required bool notifyEnabled,
      Duration? worked}) {
    final action = isCheckIn ? 'Checked in' : 'Checked out';
    final lines = <String>['$action: $name'];
    if (worked != null) lines.add('Worked: ${formatHms(worked)}');
    if (!notifyEnabled) {
      lines.add('• WhatsApp notification is off');
    } else if (res.whatsAppConfigured) {
      lines.add(res.whatsAppOpened
          ? '✓ WhatsApp opened — tap Send'
          : '✗ Could not open WhatsApp');
    } else {
      lines.add('• Manager WhatsApp not set (Settings)');
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(action),
        content: Text(lines.join('\n')),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _openScreen(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final settings =
        ref.watch(settingsProvider).asData?.value ?? const AppSettings();
    final session = ref.watch(sessionProvider);
    final busy = ref.watch(homeBusyProvider);
    final todayTotals =
        ref.watch(todayTotalsProvider).asData?.value ?? const {};
    final name = settings.defaultUserName;
    final now = DateFormat('EEEE, dd MMMM yyyy').format(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('AttendEase'),
        actions: [
          IconButton(
            tooltip: 'Reports',
            icon: const Icon(Icons.bar_chart),
            onPressed: () => _openScreen(const ReportsScreen()),
          ),
        ],
      ),
      drawer: _NavDrawer(
        name: name,
        onHistory: () => _openScreen(const HistoryScreen()),
        onProjects: () => _openScreen(const ProjectsScreen()),
        onReports: () => _openScreen(const ReportsScreen()),
        onSettings: () => _openScreen(const SettingsScreen()),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(now, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              if (session.running) ...[
                Text(
                  session.paused ? 'Paused — $name' : 'Working — $name',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                _EntryTagLine(entry: session.entry),
                const SizedBox(height: 8),
                Text(
                  formatHms(session.elapsed),
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: session.paused
                            ? Colors.orange
                            : Theme.of(context).colorScheme.primary,
                      ),
                ),
                const SizedBox(height: 24),
              ] else
                const SizedBox(height: 32),
              _MainButton(
                running: session.running,
                busy: busy,
                onTap: () => _onMainButton(settings, session.running),
              ),
              if (session.running) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => ref.read(sessionProvider.notifier).togglePause(),
                  icon: Icon(session.paused ? Icons.play_arrow : Icons.pause),
                  label: Text(session.paused ? 'Resume' : 'Pause'),
                ),
              ],
              const SizedBox(height: 24),
              _TodayPanel(
                totals: todayTotals,
                liveName: session.running ? name : null,
                liveDuration: session.elapsed,
              ),
              const SizedBox(height: 16),
              if (!session.running && !settings.whatsAppConfigured)
                _ConfigHint(
                    onOpenSettings: () => _openScreen(const SettingsScreen())),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryTagLine extends StatelessWidget {
  final TimeEntry? entry;
  const _EntryTagLine({required this.entry});

  @override
  Widget build(BuildContext context) {
    final e = entry;
    if (e == null) return const SizedBox.shrink();
    final parts = [
      if (e.taskName.isNotEmpty) e.taskName,
      if (e.description.isNotEmpty) e.description,
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        parts.join(' · '),
        style: Theme.of(context).textTheme.bodySmall,
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _NavDrawer extends StatelessWidget {
  final String name;
  final VoidCallback onHistory;
  final VoidCallback onProjects;
  final VoidCallback onReports;
  final VoidCallback onSettings;

  const _NavDrawer({
    required this.name,
    required this.onHistory,
    required this.onProjects,
    required this.onReports,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Icon(Icons.access_time_filled, size: 36),
                const SizedBox(height: 8),
                Text('AttendEase',
                    style: Theme.of(context).textTheme.titleLarge),
                if (name.isNotEmpty)
                  Text(name, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Projects'),
            onTap: () {
              Navigator.pop(context);
              onProjects();
            },
          ),
          ListTile(
            leading: const Icon(Icons.bar_chart),
            title: const Text('Reports'),
            onTap: () {
              Navigator.pop(context);
              onReports();
            },
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('History'),
            onTap: () {
              Navigator.pop(context);
              onHistory();
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Settings'),
            onTap: () {
              Navigator.pop(context);
              onSettings();
            },
          ),
        ],
      ),
    );
  }
}

class _MainButton extends StatelessWidget {
  final bool running;
  final bool busy;
  final VoidCallback onTap;
  const _MainButton(
      {required this.running, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = running
        ? [Colors.red.shade400, Colors.red.shade700]
        : [scheme.primary, scheme.tertiary];
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        width: 200,
        height: 200,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: colors.first.withValues(alpha: 0.4),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Center(
          child: busy
              ? const CircularProgressIndicator(color: Colors.white)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(running ? Icons.stop : Icons.touch_app,
                        size: 56, color: Colors.white),
                    const SizedBox(height: 8),
                    Text(
                      running ? 'STOP' : 'START',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _TodayPanel extends StatelessWidget {
  final Map<String, Duration> totals;
  final String? liveName;
  final Duration liveDuration;

  const _TodayPanel({
    required this.totals,
    required this.liveName,
    required this.liveDuration,
  });

  @override
  Widget build(BuildContext context) {
    final merged = Map<String, Duration>.from(totals);
    if (liveName != null && liveName!.isNotEmpty) {
      merged[liveName!] = (merged[liveName!] ?? Duration.zero) + liveDuration;
    }

    if (merged.isEmpty) return const SizedBox.shrink();

    final entries = merged.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.today, size: 18),
                const SizedBox(width: 6),
                Text("Today's hours",
                    style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const Divider(),
            ...entries.map((e) {
              final isLive = e.key == liveName;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(e.key),
                        if (isLive) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.fiber_manual_record,
                              size: 10, color: Colors.green),
                        ],
                      ],
                    ),
                    Text(
                      formatHm(e.value),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _ConfigHint extends StatelessWidget {
  final VoidCallback onOpenSettings;
  const _ConfigHint({required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              "No manager WhatsApp set yet.\nAdd it so check-ins get sent.",
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings),
              label: const Text('Open Settings'),
            ),
          ],
        ),
      ),
    );
  }
}
