import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../models/project.dart';
import '../models/time_entry.dart';
import '../services/attendance_stats.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../services/report_service.dart';
import '../services/settings_service.dart';

// ---- Services ------------------------------------------------------------

final databaseProvider = Provider<DatabaseService>((_) => DatabaseService.instance);
final settingsServiceProvider = Provider<SettingsService>((_) => SettingsService());
final notificationServiceProvider =
    Provider<NotificationService>((_) => NotificationService());

// ---- Settings ------------------------------------------------------------

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() => ref.read(settingsServiceProvider).load();

  Future<void> save(AppSettings s) async {
    await ref.read(settingsServiceProvider).save(s);
    state = AsyncData(s);
  }

  Future<void> setName(String name) async {
    final cur = state.asData?.value ?? const AppSettings();
    await save(cur.copyWith(defaultUserName: name.trim()));
  }

  Future<void> setThemeMode(String mode) async {
    final cur = state.asData?.value ?? const AppSettings();
    await save(cur.copyWith(themeMode: mode));
  }
}

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

/// The active [ThemeMode], derived from saved settings (defaults to system).
final themeModeProvider = Provider<ThemeMode>((ref) {
  final mode = ref.watch(settingsProvider).asData?.value.themeMode ?? 'system';
  return switch (mode) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
});

// ---- Projects & Tasks ----------------------------------------------------

/// Toggle for the Projects management screen (show archived or not).
final showArchivedProjectsProvider = StateProvider<bool>((_) => false);

/// Projects for the management screen (respects the archived toggle).
final managedProjectsProvider = FutureProvider<List<Project>>((ref) {
  final includeArchived = ref.watch(showArchivedProjectsProvider);
  return ref.watch(databaseProvider).getProjects(includeArchived: includeArchived);
});

/// Active projects, for pickers.
final activeProjectsProvider = FutureProvider<List<Project>>(
    (ref) => ref.watch(databaseProvider).getProjects());

// ---- Running session (the timer) -----------------------------------------

class SessionState {
  final bool running;
  final bool paused;
  final TimeEntry? entry;
  final Duration accumulated; // banked worked time from completed segments
  final DateTime? segmentStart; // start of the active segment (null = paused)
  final Duration elapsed; // worked time shown in the UI

  const SessionState({
    this.running = false,
    this.paused = false,
    this.entry,
    this.accumulated = Duration.zero,
    this.segmentStart,
    this.elapsed = Duration.zero,
  });
}

/// Result returned to the UI after closing a session.
class StopResult {
  final TimeEntry entry;
  final Duration worked;
  const StopResult(this.entry, this.worked);
}

class SessionNotifier extends Notifier<SessionState> {
  Timer? _ticker;

  @override
  SessionState build() {
    ref.onDispose(() => _ticker?.cancel());
    return const SessionState();
  }

  DatabaseService get _db => ref.read(databaseProvider);

  /// Resume a still-running session on launch, if one exists for [person].
  Future<void> resumeIfAny(String person) async {
    if (state.running || person.isEmpty) return;
    final running = await _db.runningEntryForPerson(person);
    if (running != null) {
      // Pauses aren't persisted; anchor the continuous clock to the original
      // start so elapsed = now - start.
      _start(running, accumulated: Duration.zero, segmentStart: running.start);
    }
  }

  /// Begins a new session for [person] with the chosen tags. Returns the row.
  Future<TimeEntry> start({
    required String person,
    int? projectId,
    String taskName = '',
    String description = '',
  }) async {
    final now = DateTime.now();
    final entry = await _db.insertEntry(TimeEntry(
      person: person,
      projectId: projectId,
      taskName: taskName,
      description: description,
      start: now,
      source: 'timer',
      createdAt: now,
    ));
    _start(entry, accumulated: Duration.zero, segmentStart: now);
    return entry;
  }

  /// Closes the running session and persists paused time. Returns null if idle.
  Future<StopResult?> stop() async {
    final entry = state.entry;
    if (entry == null) return null;
    final now = DateTime.now();
    final worked = state.elapsed;
    final realSeconds = now.difference(entry.start).inSeconds;
    final paused = (realSeconds - worked.inSeconds).clamp(0, realSeconds);
    final closed = entry.copyWith(end: () => now, pausedSeconds: paused);
    await _db.updateEntry(closed);
    _ticker?.cancel();
    _ticker = null;
    state = const SessionState();
    return StopResult(closed, worked);
  }

  void togglePause() {
    if (!state.running) return;
    if (state.paused) {
      state = SessionState(
        running: true,
        paused: false,
        entry: state.entry,
        accumulated: state.accumulated,
        segmentStart: DateTime.now(),
        elapsed: state.elapsed,
      );
    } else {
      final banked = state.segmentStart == null
          ? state.accumulated
          : state.accumulated + DateTime.now().difference(state.segmentStart!);
      state = SessionState(
        running: true,
        paused: true,
        entry: state.entry,
        accumulated: banked,
        segmentStart: null,
        elapsed: banked,
      );
    }
  }

  void _start(TimeEntry entry,
      {required Duration accumulated, required DateTime segmentStart}) {
    _ticker?.cancel();
    state = SessionState(
      running: true,
      paused: false,
      entry: entry,
      accumulated: accumulated,
      segmentStart: segmentStart,
      elapsed: accumulated + DateTime.now().difference(segmentStart),
    );
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!state.running || state.paused || state.segmentStart == null) return;
    state = SessionState(
      running: true,
      paused: false,
      entry: state.entry,
      accumulated: state.accumulated,
      segmentStart: state.segmentStart,
      elapsed:
          state.accumulated + DateTime.now().difference(state.segmentStart!),
    );
  }
}

final sessionProvider =
    NotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);

/// Whether a check-in/out is in flight (drives the button spinner).
final homeBusyProvider = StateProvider<bool>((_) => false);

/// The id of the live entry (or null). Used to exclude it from day totals
/// without rebuilding on every per-second tick.
final liveEntryIdProvider =
    Provider<int?>((ref) => ref.watch(sessionProvider.select((s) => s.entry?.id)));

/// Completed worked totals per person for today (live session excluded — the
/// UI overlays its live elapsed on top).
final todayTotalsProvider = FutureProvider<Map<String, Duration>>((ref) async {
  final liveId = ref.watch(liveEntryIdProvider);
  final views = await ref.watch(databaseProvider).entriesForDay(DateTime.now());
  final entries =
      views.map((v) => v.entry).where((e) => e.id != liveId).toList();
  return dailyTotalsByPerson(entries, DateTime.now());
});

// ---- History -------------------------------------------------------------

final historyProvider = FutureProvider<List<TimeEntryView>>(
    (ref) => ref.watch(databaseProvider).allEntries());

/// Invalidate everything that reflects the set of time entries.
void refreshEntryData(WidgetRef ref) {
  ref.invalidate(historyProvider);
  ref.invalidate(todayTotalsProvider);
  ref.invalidate(reportEntriesProvider);
}

// ---- Reports -------------------------------------------------------------

final reportPresetProvider =
    StateProvider<DateRangePreset>((_) => DateRangePreset.thisWeek);

final reportRangeProvider =
    StateProvider<DateRange>((_) => resolveRange(DateRangePreset.thisWeek));

final reportEntriesProvider = FutureProvider<List<TimeEntryView>>((ref) {
  final range = ref.watch(reportRangeProvider);
  return ref.watch(databaseProvider).entriesInRange(range.start, range.end);
});
