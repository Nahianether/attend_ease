// Throwaway harness used to capture README screenshots. It seeds an in-memory
// database with realistic sample data and shows ONE screen (chosen by the SHOT
// dart-define), styled exactly like the real app.
//
// Usage (run, then capture the window):
//   flutter run -d windows -t tool/screenshot_app.dart --dart-define=SHOT=home
//   ... SHOT=reports | history | projects
import 'dart:io' show Platform;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

import 'package:attend_ease/main.dart' show buildAppTheme;
import 'package:attend_ease/providers/app_providers.dart';
import 'package:attend_ease/services/database_service.dart';
import 'package:attend_ease/screens/history_screen.dart';
import 'package:attend_ease/screens/home_screen.dart';
import 'package:attend_ease/screens/projects_screen.dart';
import 'package:attend_ease/screens/reports_screen.dart';
import 'package:attend_ease/services/settings_service.dart';

const _shot = String.fromEnvironment('SHOT', defaultValue: 'home');

class _FakeSettings extends SettingsService {
  @override
  Future<AppSettings> load() async => const AppSettings(
        defaultUserName: 'Intishar-Ul Islam',
        managerWhatsApp: '8801712345678',
      );
  @override
  Future<void> save(AppSettings s) async {}
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(400, 760),
      center: true,
      title: 'AttendEase',
      titleBarStyle: TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // Seed an in-memory DB with sample data.
  DatabaseService.instance.testOpener = () async {
    sqfliteFfiInit();
    final db = await DatabaseService.openLatest(
        databaseFactoryFfi, inMemoryDatabasePath);

    final now = DateTime.now();
    DateTime at(int dayAgo, int h, int m) =>
        DateTime(now.year, now.month, now.day, h, m)
            .subtract(Duration(days: dayAgo));

    Future<int> project(String name, int color) =>
        db.insert('projects', {
          'name': name,
          'color': color,
          'archived': 0,
          'created_at': now.millisecondsSinceEpoch,
        });

    final website = await project('Website Redesign', 0xFF2E6BE6);
    final mobile = await project('Mobile App', 0xFF22A565);
    final meetings = await project('Client Meetings', 0xFFE6A817);

    Future<void> entry(int? projectId, String task, String desc, DateTime s,
            DateTime e) =>
        db.insert('time_entries', {
          'person': 'Intishar-Ul Islam',
          'project_id': projectId,
          'task_name': task,
          'description': desc,
          'start_ms': s.millisecondsSinceEpoch,
          'end_ms': e.millisecondsSinceEpoch,
          'paused_seconds': 0,
          'source': 'timer',
          'created_at': now.millisecondsSinceEpoch,
        });

    await entry(website, 'Landing page', 'Hero + pricing section',
        at(0, 9, 0), at(0, 11, 30));
    await entry(mobile, 'Bug fixes', 'Login crash on Android',
        at(0, 12, 0), at(0, 14, 15));
    await entry(website, 'Code review', '', at(1, 10, 0), at(1, 12, 0));
    await entry(mobile, 'Release build', '', at(1, 14, 0), at(1, 16, 30));
    await entry(meetings, 'Standup', '', at(2, 9, 30), at(2, 10, 0));
    await entry(website, 'Bug fixes', '', at(3, 13, 0), at(3, 17, 0));
    await entry(null, 'Email & admin', '', at(4, 9, 0), at(4, 10, 0));
    return db;
  };

  runApp(
    ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWithValue(_FakeSettings()),
      ],
      child: const _ShotApp(),
    ),
  );
}

class _ShotApp extends StatelessWidget {
  const _ShotApp();

  @override
  Widget build(BuildContext context) {
    final Widget home = switch (_shot) {
      'reports' => const ReportsScreen(),
      'history' => const HistoryScreen(),
      'projects' => const ProjectsScreen(),
      _ => const HomeScreen(),
    };
    return MaterialApp(
      title: 'AttendEase',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
        },
      ),
      theme: buildAppTheme(Brightness.light),
      home: home,
    );
  }
}
