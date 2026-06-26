import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/attendance_record.dart';
import '../services/attendance_stats.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _db = DatabaseService.instance;
  final _settingsService = SettingsService();
  final _notifier = NotificationService();

  AppSettings _settings = const AppSettings();
  bool _busy = false;

  // Running session state. Elapsed is accumulated across active segments so
  // that pausing freezes the clock and resuming continues it.
  bool _running = false;
  bool _paused = false;
  String _currentName = '';
  Duration _accumulated = Duration.zero; // time from completed segments
  DateTime? _segmentStart; // start of the current active segment (null = paused)
  Duration _elapsed = Duration.zero; // what the UI shows
  Timer? _ticker;

  // Completed check-in/out totals per person for today (live time added in UI).
  Map<String, Duration> _todayTotals = const {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final s = await _settingsService.load();
    if (!mounted) return;
    setState(() => _settings = s);

    // Resume a session if the last record for the saved user is a check-in
    // that was never checked out (e.g. app was closed mid-session).
    if (s.defaultUserName.isNotEmpty) {
      final last = await _db.lastForName(s.defaultUserName);
      if (mounted && last != null && last.isCheckIn) {
        _beginTicking(last.name, last.timestamp);
      }
    }
    await _refreshTotals();
  }

  Future<void> _refreshTotals() async {
    final records = await _db.recordsForDay(DateTime.now());
    if (mounted) setState(() => _todayTotals = completedTotals(records));
  }

  Future<void> _reloadSettings() async {
    final s = await _settingsService.load();
    if (mounted) setState(() => _settings = s);
  }

  void _beginTicking(String name, DateTime start) {
    _ticker?.cancel();
    setState(() {
      _running = true;
      _paused = false;
      _currentName = name;
      _accumulated = Duration.zero;
      _segmentStart = start;
      _elapsed = DateTime.now().difference(start);
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted || _paused || _segmentStart == null) return;
    setState(() {
      _elapsed = _accumulated + DateTime.now().difference(_segmentStart!);
    });
  }

  void _togglePause() {
    if (!_running) return;
    setState(() {
      if (_paused) {
        // Resume: start a new active segment from now.
        _segmentStart = DateTime.now();
        _paused = false;
      } else {
        // Pause: bank the current segment and freeze the clock.
        if (_segmentStart != null) {
          _accumulated += DateTime.now().difference(_segmentStart!);
        }
        _segmentStart = null;
        _paused = true;
        _elapsed = _accumulated;
      }
    });
  }

  void _stopTicking() {
    _ticker?.cancel();
    _ticker = null;
    setState(() {
      _running = false;
      _paused = false;
      _segmentStart = null;
      _accumulated = Duration.zero;
      _elapsed = Duration.zero;
      _currentName = '';
    });
  }

  Future<void> _onMainButton() async {
    if (_busy) return;
    if (_running) {
      await _checkOut();
    } else {
      await _checkIn();
    }
  }

  Future<void> _checkIn() async {
    final name = await _askName();
    if (name == null || name.trim().isEmpty) return;
    final trimmed = name.trim();

    setState(() => _busy = true);
    try {
      final now = DateTime.now();
      final saved = await _db.insert(AttendanceRecord(
        name: trimmed,
        type: 'in',
        timestamp: now,
      ));

      if (_settings.defaultUserName != trimmed) {
        _settings = _settings.copyWith(defaultUserName: trimmed);
        await _settingsService.save(_settings);
      }

      final result = await _notifier.notify(saved, _settings);
      _beginTicking(trimmed, now);
      await _refreshTotals();
      if (mounted) _showOutcome(saved, result);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkOut() async {
    setState(() => _busy = true);
    try {
      final saved = await _db.insert(AttendanceRecord(
        name: _currentName,
        type: 'out',
        timestamp: DateTime.now(),
      ));
      final worked = _elapsed;
      final result = await _notifier.notify(saved, _settings);
      _stopTicking();
      await _refreshTotals();
      if (mounted) _showOutcome(saved, result, worked: worked);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askName() {
    final controller = TextEditingController(text: _settings.defaultUserName);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Who are you?'),
        content: TextField(
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Start'),
          ),
        ],
      ),
    );
  }

  void _showOutcome(AttendanceRecord r, NotifyResult res, {Duration? worked}) {
    final action = r.isCheckIn ? 'Checked in' : 'Checked out';
    final lines = <String>['$action: ${r.name}'];
    if (worked != null) {
      lines.add('Worked: ${_fmt(worked)}');
    }
    if (res.emailAttempted) {
      lines.add(res.emailSent
          ? '✓ Email sent to manager'
          : '✗ Email failed: ${_short(res.emailError)}');
    } else {
      lines.add('• Email not configured (Settings)');
    }
    lines.add(res.whatsAppOpened
        ? '✓ WhatsApp opened — tap Send'
        : '• WhatsApp not configured (Settings)');

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

  String _fmt(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _short(String? e) {
    if (e == null) return 'unknown error';
    return e.length > 120 ? '${e.substring(0, 120)}…' : e;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateFormat('EEEE, dd MMMM yyyy').format(DateTime.now());
    return Scaffold(
      appBar: AppBar(
        title: const Text('AttendEase'),
        actions: [
          IconButton(
            tooltip: 'History',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              _reloadSettings();
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(now, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 24),
              if (_running) ...[
                Text(
                  _paused ? 'Paused — $_currentName' : 'Working — $_currentName',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  _fmt(_elapsed),
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: _paused
                            ? Colors.orange
                            : Theme.of(context).colorScheme.primary,
                      ),
                ),
                const SizedBox(height: 24),
              ] else
                const SizedBox(height: 40),
              _MainButton(
                running: _running,
                busy: _busy,
                onTap: _onMainButton,
              ),
              if (_running) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _togglePause,
                  icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                  label: Text(_paused ? 'Resume' : 'Pause'),
                ),
              ],
              const SizedBox(height: 24),
              _TodayPanel(
                totals: _todayTotals,
                liveName: _running ? _currentName : null,
                liveDuration: _elapsed,
              ),
              const SizedBox(height: 16),
              if (!_running &&
                  !_settings.emailConfigured &&
                  !_settings.whatsAppConfigured)
                _ConfigHint(
                  onOpenSettings: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const SettingsScreen()),
                    );
                    _reloadSettings();
                  },
                ),
            ],
          ),
        ),
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
  final String? liveName; // person currently checked in (their live time added)
  final Duration liveDuration;

  const _TodayPanel({
    required this.totals,
    required this.liveName,
    required this.liveDuration,
  });

  @override
  Widget build(BuildContext context) {
    // Merge completed totals with the live session of whoever is checked in.
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
                      style:
                          const TextStyle(fontWeight: FontWeight.bold),
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
              'No manager contact set yet.\nAdd email / WhatsApp so check-ins get sent.',
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
