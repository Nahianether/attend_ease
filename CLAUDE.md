# AttendEase — Project Guide for Claude

Time-tracking + attendance app (Clockify-style, on-device). A worker taps
**START**, optionally picks a **Project / Task** and types a description, and a
live timer (with pause/resume) runs until **STOP**. Work is stored as **time
entries**, reportable by project/task/person over a date range and exportable to
**PDF**. The manager is notified via **WhatsApp** on check-in/out.

- **Location:** `F:\Projects\attend_ease`
- **Org / app id:** `com.attendease`  •  **Package name:** `attend_ease`
- **Platforms:** Android + Windows
- **Flutter:** 3.41.9 / Dart 3.11.5 (stable)
- **State management:** **Riverpod** (`flutter_riverpod` 3.3.2). App is wrapped in
  `ProviderScope`; screens are `ConsumerWidget`/`ConsumerStatefulWidget`. **Avoid
  `setState` for data** — use providers. Legacy `StateProvider` comes from
  `package:flutter_riverpod/legacy.dart`. `AsyncValue` access uses `.asData?.value`
  (this version has no `valueOrNull`).
- **Storage:** on-device only (SQLite) — no backend, no cloud.

## Key product decisions (locked with the user)
- **Name asked once.** On first launch an onboarding dialog asks the worker's
  full name; it's saved and used for every entry. START never asks again. The
  name is editable in **Settings**. (`AppSettings.needsOnboarding`.)
- **WhatsApp is the ONLY notification channel.** Email/SMTP was fully removed
  (the `mailer` dep is gone). Don't re-add email.
- **Projects & Tasks are optional tags.** START can be skipped to track untagged
  time; entries can still be tagged later via History → edit.
- **Reports export to PDF only** (`pdf` + `printing`). No CSV.
- **Manual entries** (add/edit/delete past sessions) are supported.
- Storage stays **on-device** (SQLite). Pauses are NOT persisted across an app
  restart (documented limitation).
- On **desktop**, the window is forced to a **phone size** (see `main.dart`).

## Data model (SQLite, schema v3)
One row per work **session** (`time_entries`) — replaces the old in/out event
model. See `lib/services/database_service.dart`.
- `projects(id, name, color ARGB int, archived, created_at)` — the only managed
  entity (dropdown). **Task is free text**, not a managed entity.
- `time_entries(id, person, project_id→projects ON DELETE SET NULL,
  **task_name TEXT** (free text, typed per session), description, start_ms,
  end_ms (NULL=running), paused_seconds, source['timer'|'manual'|'migrated'],
  created_at)`
- `tasks(...)` table still exists (legacy v2) but is **unused** — kept only so the
  v2→v3 backfill can read old task names. `task_id` column on `time_entries` is
  likewise legacy/unused.
- **Worked time** = `(end ?? now) - start - paused_seconds`, never negative
  (`TimeEntry.worked()`).
- FK pragma enabled per-connection in `onConfigure` (required for ON DELETE).
- **Migrations** (`onUpgrade`): v1→v2 pairs old `attendance` in/out rows into
  `time_entries` (`source='migrated'`; trailing open check-in → running). v2→v3
  adds `task_name` and backfills it from the old `tasks` table. The `attendance`
  table is **kept** (non-destructive). Tests open at the latest version via
  `DatabaseService.openLatest` (`test/migration_test.dart`).

## Architecture / file map
```
lib/
  main.dart                       ProviderScope + app root + desktop window sizing
                                  + _DragScrollBehavior + _buildTheme (shared M3
                                  theme: rounded cards/inputs/buttons/sheets) +
                                  installGlobalErrorHandlers()
  providers/
    app_providers.dart            ALL Riverpod providers: settings (AsyncNotifier),
                                  session timer (SessionNotifier), projects/tasks
                                  (Future + family), today totals, history, reports
  models/
    project.dart  time_entry.dart   (TimeEntry has free-text taskName; + TimeEntryView)
  services/
    database_service.dart         SQLite v2: projects/tasks/time_entries CRUD +
                                  range queries + migration. openV2() reused by tests.
    attendance_stats.dart         dailyTotalsByPerson(), formatHm(), formatHms()
    report_service.dart           DateRange presets (Today/This week/This month/
                                  Last month/This year/Last year/Custom) +
                                  summaryByProjectTask (pure ReportNode trees) + grandTotal
    pdf_report_service.dart       Colourful Clockify-style PDF (header band, stacked
                                  total bar, per-project colour bars + %, task rows) +
                                  share/print (printing pkg)
    notification_service.dart     WhatsApp-only notify() (buildMessage + _openWhatsApp)
    settings_service.dart         AppSettings{managerWhatsApp, defaultUserName}
  widgets/
    project_task_picker.dart      ProjectField (project dropdown) + showStartSheet()
                                  (the START sheet's Task is a free-text field)
    error_handling.dart           showAppError() friendly dialog + friendlyMessage()
                                  + guard() wrapper + ErrorView + global handlers
                                  (installGlobalErrorHandlers, appNavigatorKey)
  screens/
    home_screen.dart              START/STOP, live timer, pause, onboarding, Today panel, Drawer
    projects_screen.dart          Projects CRUD + color picker (tap a project = edit)
    reports_screen.dart           Date presets + grouping toggle + grand total + Export PDF
    manual_entry_screen.dart      Add/edit/delete a time entry
    history_screen.dart           List sessions (TimeEntryView), tap to edit, FAB to add
    settings_screen.dart          Your name + manager WhatsApp
```

## Error handling & UI conventions
- **All user actions are guarded.** DB writes / check-in/out / save / delete /
  PDF export are wrapped (try/catch or `guard()`); failures show `showAppError`
  (plain-language message + expandable "Technical details"). Provider `.when`
  errors render `ErrorView` (friendly + Retry). Uncaught async errors hit the
  global handler (`installGlobalErrorHandlers`) and surface via `appNavigatorKey`.
  Keep this pattern when adding new actions — don't let exceptions go silent.
- **Forms use modal bottom sheets, not AlertDialogs** (e.g. project create/edit
  `_ProjectSheet`, the START sheet). Confirmations/info stay as dialogs.
- Theme is centralised in `_buildTheme` — don't hardcode per-widget radii/colors.

## Important behaviors (so you don't break them)
- **Timer lives in `SessionNotifier`** (`app_providers.dart`), not the widget. It
  holds a `Timer.periodic` and exposes `SessionState` (running/paused/entry/elapsed).
  Accumulation model: `accumulated` (banked segments) + current segment since
  `segmentStart`. Pause banks + nulls `segmentStart`; resume starts a new segment.
  On STOP, `paused_seconds` = `realElapsed - workedElapsed`, persisted on the entry.
  Home watches `sessionProvider`; `liveEntryIdProvider` keeps `todayTotalsProvider`
  from re-querying every per-second tick (it only depends on the entry id).
- **Resume on launch:** `runningEntryForPerson(name)` finds the `end_ms IS NULL`
  row and resumes from its `start`.
- **"Today's hours" panel:** `entriesForDay` → `dailyTotalsByPerson`; the live
  session is excluded from the totals and overlaid from `_elapsed` for the active
  person (green dot) so it ticks smoothly.
- **Reports aggregate in Dart** over SQL-filtered rows (`entriesInRange`), not
  SQL GROUP BY — needed for live "now" + paused subtraction. Grouping toggles
  between Project→Task and Person→Project.
- **PDF**: `Printing.sharePdf` (Android share / Windows save) and
  `Printing.layoutPdf` (print preview). Built-in Helvetica font is Latin-only —
  bundle a NotoSans TTF if non-Latin (e.g. Bengali) names must render.
- **WhatsApp open** (`_openWhatsApp`): `whatsapp://send` first (app/desktop),
  `wa.me` browser fallback.

## Commands
```powershell
# from F:\Projects\attend_ease
flutter pub get
flutter analyze                       # keep at "No issues found!"
flutter test                          # migration + report + widget tests
flutter run -d windows                # or -d <android device>
flutter build windows --release
dart run flutter_launcher_icons       # regenerate app icons after changing source
```
Before any Windows build/run, kill a stale instance or the linker fails (LNK1168):
`Get-Process attend_ease -ErrorAction SilentlyContinue | Stop-Process -Force`

## App icon
- Source: `assets/AttendEasy_B_1024.png`; adaptive foreground
  `assets/AttendEasy_B_foreground.png` (@96%), background `#34C3CC`. Config in
  `pubspec.yaml` (`flutter_launcher_icons:`, Windows key is `generate:`).

## Current status (2026-06)
Migrated to **Riverpod** (no `setState` for data; fixed a `setState`-returns-Future
crash on the Projects screen) and enabled mouse/trackpad drag-scroll for the Reports
date chips. Clockify-style features complete & verified: analyzer clean, 13 tests pass,
Windows release builds & runs. Done: projects/tasks CRUD, optional tagging at
START, time-entry model + v1→v2 migration, manual add/edit, reports (date presets
+ project/person grouping + grand total), PDF export, WhatsApp-only notify,
first-launch name onboarding, Drawer nav.

Not yet done / possible next steps: tested on a real Android device (PDF share +
WhatsApp); bundle a NotoSans font for non-Latin names in PDF; CSV export; weekly
email/auto summaries; secure storage; persist pauses across restart; repackage
the `dist\` desktop bundle/zip from the new release build.
