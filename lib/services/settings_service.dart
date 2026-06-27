import 'package:shared_preferences/shared_preferences.dart';

/// Stores the worker's name, the manager's WhatsApp number, and the preferred
/// theme. Persisted locally with shared_preferences. (Email/SMTP was removed —
/// WhatsApp is the only notification channel.)
class AppSettings {
  final String managerWhatsApp; // full international number, digits only e.g. 8801712345678
  final String defaultUserName; // the worker's name, asked once on first launch
  final String themeMode; // 'system' | 'light' | 'dark'

  const AppSettings({
    this.managerWhatsApp = '',
    this.defaultUserName = '',
    this.themeMode = 'system',
  });

  bool get whatsAppConfigured => managerWhatsApp.isNotEmpty;

  /// Whether the one-time onboarding (asking the worker's name) is still needed.
  bool get needsOnboarding => defaultUserName.trim().isEmpty;

  AppSettings copyWith({
    String? managerWhatsApp,
    String? defaultUserName,
    String? themeMode,
  }) =>
      AppSettings(
        managerWhatsApp: managerWhatsApp ?? this.managerWhatsApp,
        defaultUserName: defaultUserName ?? this.defaultUserName,
        themeMode: themeMode ?? this.themeMode,
      );
}

class SettingsService {
  static const _kManagerWhatsApp = 'manager_whatsapp';
  static const _kDefaultName = 'default_user_name';
  static const _kThemeMode = 'theme_mode';

  Future<AppSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return AppSettings(
      managerWhatsApp: p.getString(_kManagerWhatsApp) ?? '',
      defaultUserName: p.getString(_kDefaultName) ?? '',
      themeMode: p.getString(_kThemeMode) ?? 'system',
    );
  }

  Future<void> save(AppSettings s) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kManagerWhatsApp, s.managerWhatsApp);
    await p.setString(_kDefaultName, s.defaultUserName);
    await p.setString(_kThemeMode, s.themeMode);
  }
}
