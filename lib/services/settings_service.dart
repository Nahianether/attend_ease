import 'package:shared_preferences/shared_preferences.dart';

/// Stores the worker's name and the manager's WhatsApp number. Persisted
/// locally with shared_preferences. (Email/SMTP was removed — WhatsApp is the
/// only notification channel.)
class AppSettings {
  final String managerWhatsApp; // full international number, digits only e.g. 8801712345678
  final String defaultUserName; // the worker's name, asked once on first launch

  const AppSettings({
    this.managerWhatsApp = '',
    this.defaultUserName = '',
  });

  bool get whatsAppConfigured => managerWhatsApp.isNotEmpty;

  /// Whether the one-time onboarding (asking the worker's name) is still needed.
  bool get needsOnboarding => defaultUserName.trim().isEmpty;

  AppSettings copyWith({
    String? managerWhatsApp,
    String? defaultUserName,
  }) =>
      AppSettings(
        managerWhatsApp: managerWhatsApp ?? this.managerWhatsApp,
        defaultUserName: defaultUserName ?? this.defaultUserName,
      );
}

class SettingsService {
  static const _kManagerWhatsApp = 'manager_whatsapp';
  static const _kDefaultName = 'default_user_name';

  Future<AppSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return AppSettings(
      managerWhatsApp: p.getString(_kManagerWhatsApp) ?? '',
      defaultUserName: p.getString(_kDefaultName) ?? '',
    );
  }

  Future<void> save(AppSettings s) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kManagerWhatsApp, s.managerWhatsApp);
    await p.setString(_kDefaultName, s.defaultUserName);
  }
}
