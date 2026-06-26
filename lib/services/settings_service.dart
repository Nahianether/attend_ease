import 'package:shared_preferences/shared_preferences.dart';

/// Stores the manager's contact details and the SMTP account used to send
/// the automatic email. Persisted locally with shared_preferences.
class AppSettings {
  final String managerEmail;
  final String managerWhatsApp; // full international number, digits only e.g. 8801712345678
  final String smtpHost;
  final int smtpPort;
  final String smtpUsername; // the sending email account
  final String smtpPassword; // app password for that account
  final String defaultUserName;

  const AppSettings({
    this.managerEmail = '',
    this.managerWhatsApp = '',
    this.smtpHost = 'smtp.gmail.com',
    this.smtpPort = 587,
    this.smtpUsername = '',
    this.smtpPassword = '',
    this.defaultUserName = '',
  });

  bool get emailConfigured =>
      managerEmail.isNotEmpty &&
      smtpUsername.isNotEmpty &&
      smtpPassword.isNotEmpty;

  bool get whatsAppConfigured => managerWhatsApp.isNotEmpty;

  AppSettings copyWith({
    String? managerEmail,
    String? managerWhatsApp,
    String? smtpHost,
    int? smtpPort,
    String? smtpUsername,
    String? smtpPassword,
    String? defaultUserName,
  }) =>
      AppSettings(
        managerEmail: managerEmail ?? this.managerEmail,
        managerWhatsApp: managerWhatsApp ?? this.managerWhatsApp,
        smtpHost: smtpHost ?? this.smtpHost,
        smtpPort: smtpPort ?? this.smtpPort,
        smtpUsername: smtpUsername ?? this.smtpUsername,
        smtpPassword: smtpPassword ?? this.smtpPassword,
        defaultUserName: defaultUserName ?? this.defaultUserName,
      );
}

class SettingsService {
  static const _kManagerEmail = 'manager_email';
  static const _kManagerWhatsApp = 'manager_whatsapp';
  static const _kSmtpHost = 'smtp_host';
  static const _kSmtpPort = 'smtp_port';
  static const _kSmtpUser = 'smtp_username';
  static const _kSmtpPass = 'smtp_password';
  static const _kDefaultName = 'default_user_name';

  Future<AppSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return AppSettings(
      managerEmail: p.getString(_kManagerEmail) ?? '',
      managerWhatsApp: p.getString(_kManagerWhatsApp) ?? '',
      smtpHost: p.getString(_kSmtpHost) ?? 'smtp.gmail.com',
      smtpPort: p.getInt(_kSmtpPort) ?? 587,
      smtpUsername: p.getString(_kSmtpUser) ?? '',
      smtpPassword: p.getString(_kSmtpPass) ?? '',
      defaultUserName: p.getString(_kDefaultName) ?? '',
    );
  }

  Future<void> save(AppSettings s) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kManagerEmail, s.managerEmail);
    await p.setString(_kManagerWhatsApp, s.managerWhatsApp);
    await p.setString(_kSmtpHost, s.smtpHost);
    await p.setInt(_kSmtpPort, s.smtpPort);
    await p.setString(_kSmtpUser, s.smtpUsername);
    await p.setString(_kSmtpPass, s.smtpPassword);
    await p.setString(_kDefaultName, s.defaultUserName);
  }
}
