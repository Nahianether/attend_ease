# AttendEase — Project Guide for Claude

Attendance-tracking Flutter app. A worker taps **START**, enters their name, and
the app logs a check-in, notifies the project manager (auto-email + WhatsApp),
and runs a live timer until they tap **STOP** (check-out).

- **Location:** `F:\Projects\attend_ease`
- **Org / app id:** `com.attendease`  •  **Package name:** `attend_ease`
- **Platforms:** Android + Windows (created with `--platforms android,windows`)
- **Flutter:** 3.41.9 / Dart 3.11.5 (stable)
- **Storage:** on-device only (SQLite) — no backend, no cloud.

## Key product decisions (locked with the user)
- Notifications go to the manager via **BOTH**: automatic **email (SMTP)** and
  **WhatsApp** opened pre-filled (user taps Send).
- **Full WhatsApp auto-send is intentionally NOT implemented** — it needs the
  paid WhatsApp Business API + a backend, and accessibility-clicker hacks risk a
  number ban. Email is the fully-automatic channel. Don't re-litigate this.
- Storage stays **on-device** (SQLite). No Firebase.
- On **desktop**, the window is forced to a **phone size** (see `main.dart`).

## Architecture / file map
```
lib/
  main.dart                       App root + desktop window sizing (window_manager)
  models/
    attendance_record.dart        AttendanceRecord (id,name,type 'in'/'out',timestamp,note)
  services/
    database_service.dart         SQLite (singleton). insert/getAll/lastForName/
                                  recordsForDay/delete. FFI init for desktop.
    settings_service.dart         AppSettings + load/save via shared_preferences
    notification_service.dart     buildMessage + notify(): SMTP email + _openWhatsApp()
    attendance_stats.dart         completedTotals() + formatHm() (pure helpers)
  screens/
    home_screen.dart              START/STOP button, live timer, pause/resume, Today panel
    history_screen.dart           List of all records, delete
    settings_screen.dart          Manager email/WhatsApp + SMTP creds form
```

## Important behaviors (so you don't break them)
- **Check-in vs check-out** is decided by toggling from the person's last DB
  record (`lastForName`). A check-in with no later check-out = "open session".
- **Timer uses an accumulation model** in `home_screen.dart`:
  `_accumulated` (banked completed segments) + current segment since
  `_segmentStart`. **Pause** banks the segment and nulls `_segmentStart`;
  **Resume** starts a new segment. Worked time on check-out excludes paused time.
- **Resume on launch:** if the saved user's last record is an open check-in,
  `_init()` resumes the running timer from that timestamp (pauses are NOT
  persisted — only check-in/out times are in the DB).
- **"Today's hours" panel:** `completedTotals()` sums closed in/out pairs for the
  day; the live session's `_elapsed` is added on top in the UI for the active
  person (green dot). Per calendar day — shifts crossing midnight split.
- **WhatsApp open is cross-platform** (`_openWhatsApp`): tries `whatsapp://send`
  (native app on mobile / WhatsApp Desktop on Windows via registered protocol),
  falls back to `https://wa.me/...` in the browser. Android manifest has the
  matching `<queries>` (https, mailto, whatsapp scheme, com.whatsapp packages)
  plus `INTERNET` permission.

## Settings the user must fill in for notifications to work
In-app Settings screen → `shared_preferences`:
- Manager **email** + manager **WhatsApp** (intl number, digits only e.g. `8801712345678`)
- **Sending** email account + **app password** (Gmail: 2-Step Verification → App
  password; NOT the normal password). SMTP host/port default to Gmail 587.
- SMTP password is stored **plaintext** in shared_prefs — fine for MVP; flag if
  hardening is requested.

## Commands
```powershell
# from F:\Projects\attend_ease
flutter pub get
flutter analyze                       # keep this at "No issues found!"
flutter test
flutter run -d windows                # or -d <android device>
flutter build windows --release       # desktop release
dart run flutter_launcher_icons       # regenerate app icons after changing source
```
Before any Windows build/run, kill a stale instance or the linker fails (LNK1168):
`Get-Process attend_ease -ErrorAction SilentlyContinue | Stop-Process -Force`

## App icon
- Source: `assets/AttendEasy_B_1024.png` (teal→blue gradient checklist, full-bleed,
  transparent corners).
- Adaptive foreground `assets/AttendEasy_B_foreground.png` = source @96% scale;
  adaptive background `#34C3CC` (teal — avoids the white border problem).
- Config lives in `pubspec.yaml` under `flutter_launcher_icons:` (Windows key is
  `generate:` not `generated:`). Regenerate with `dart run flutter_launcher_icons`.
- Older `assets/attendease_logo.png` / `attendease_icon*.png` are superseded.

## Desktop packaging
`flutter build windows --release` → bundle at
`build\windows\x64\runner\Release\`. A distributable copy + zip live in `dist\`
(`dist\AttendEase\attend_ease.exe`, `dist\AttendEase-Windows.zip`). The exe needs
its sibling DLLs + `data\` folder — always ship the whole folder.

## Current status (2026-06)
Working & verified: analyzer clean, widget test passes, Windows release builds &
runs. Features done: START/STOP + live timer, pause/resume, per-person "Today's
hours", auto-email + cross-platform WhatsApp, on-device SQLite, history with
delete, settings, phone-sized desktop window (400×720), custom app icon, packaged
desktop build.

Not yet done / possible next steps: tested on a real Android device & with live
SMTP creds (not done); CSV/Excel export; weekly/monthly per-person summaries;
splash screen; Windows installer (MSIX); secure the stored SMTP password;
persist pauses across restart.
