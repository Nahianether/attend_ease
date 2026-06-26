import 'package:intl/intl.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/attendance_record.dart';
import 'settings_service.dart';

/// Outcome of trying to notify the manager, surfaced back to the UI.
class NotifyResult {
  final bool emailAttempted;
  final bool emailSent;
  final String? emailError;
  final bool whatsAppOpened;

  const NotifyResult({
    this.emailAttempted = false,
    this.emailSent = false,
    this.emailError,
    this.whatsAppOpened = false,
  });
}

class NotificationService {
  /// Builds the human-readable message body shared by email + WhatsApp.
  String buildMessage(AttendanceRecord r) {
    final action = r.isCheckIn ? 'CHECKED IN' : 'CHECKED OUT';
    final when = DateFormat('EEE, dd MMM yyyy • hh:mm a').format(r.timestamp);
    final note = r.note.trim().isEmpty ? '' : '\nNote: ${r.note.trim()}';
    return '$action\n\nName: ${r.name}\nTime: $when$note\n\n— sent via AttendEase';
  }

  /// Sends the automatic email (if configured) and opens WhatsApp pre-filled
  /// (if configured). Each channel fails independently.
  Future<NotifyResult> notify(AttendanceRecord record, AppSettings s) async {
    final message = buildMessage(record);

    bool emailAttempted = false;
    bool emailSent = false;
    String? emailError;

    if (s.emailConfigured) {
      emailAttempted = true;
      try {
        final server = SmtpServer(
          s.smtpHost,
          port: s.smtpPort,
          username: s.smtpUsername,
          password: s.smtpPassword,
          ignoreBadCertificate: false,
        );
        final action = record.isCheckIn ? 'Check-in' : 'Check-out';
        final email = Message()
          ..from = Address(s.smtpUsername, 'AttendEase')
          ..recipients.add(s.managerEmail)
          ..subject = 'Attendance: ${record.name} — $action'
          ..text = message;
        await send(email, server);
        emailSent = true;
      } catch (e) {
        emailError = e.toString();
      }
    }

    bool whatsAppOpened = false;
    if (s.whatsAppConfigured) {
      final number = s.managerWhatsApp.replaceAll(RegExp(r'[^0-9]'), '');
      whatsAppOpened = await _openWhatsApp(number, message);
    }

    return NotifyResult(
      emailAttempted: emailAttempted,
      emailSent: emailSent,
      emailError: emailError,
      whatsAppOpened: whatsAppOpened,
    );
  }

  /// Opens WhatsApp pre-filled, working on both mobile and desktop:
  ///
  /// * If the WhatsApp app (mobile) or WhatsApp Desktop (Windows/macOS) is
  ///   installed, it registers the `whatsapp://` protocol — we open that
  ///   directly so no browser is involved.
  /// * If it isn't installed (protocol not registered), we fall back to the
  ///   `wa.me` web link in the default browser.
  ///
  /// Returns true if either path launched something.
  Future<bool> _openWhatsApp(String number, String message) async {
    final text = Uri.encodeComponent(message);
    final appUri = Uri.parse('whatsapp://send?phone=$number&text=$text');
    final webUri = Uri.parse('https://wa.me/$number?text=$text');

    // 1) Try the installed WhatsApp app / desktop client.
    try {
      if (await canLaunchUrl(appUri)) {
        final ok =
            await launchUrl(appUri, mode: LaunchMode.externalApplication);
        if (ok) return true;
      }
    } catch (_) {
      // protocol not registered / launch refused — fall through to browser
    }

    // 2) Fall back to the browser.
    try {
      return await launchUrl(webUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
