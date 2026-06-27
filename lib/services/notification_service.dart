import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'settings_service.dart';

/// Outcome of trying to notify the manager, surfaced back to the UI.
class NotifyResult {
  final bool whatsAppConfigured;
  final bool whatsAppOpened;

  const NotifyResult({
    this.whatsAppConfigured = false,
    this.whatsAppOpened = false,
  });
}

class NotificationService {
  /// Builds the human-readable WhatsApp message.
  String buildMessage({
    required String person,
    required bool isCheckIn,
    required DateTime when,
    String? projectName,
    String? taskName,
    String? description,
  }) {
    final action = isCheckIn ? 'CHECKED IN' : 'CHECKED OUT';
    final time = DateFormat('EEE, dd MMM yyyy • hh:mm a').format(when);
    final buf = StringBuffer()
      ..writeln(action)
      ..writeln()
      ..writeln('Name: $person')
      ..writeln('Time: $time');
    if (projectName != null && projectName.isNotEmpty) {
      buf.writeln('Project: $projectName');
    }
    if (taskName != null && taskName.isNotEmpty) {
      buf.writeln('Task: $taskName');
    }
    if (description != null && description.trim().isNotEmpty) {
      buf.writeln('Note: ${description.trim()}');
    }
    buf
      ..writeln()
      ..write('— sent via AttendEase');
    return buf.toString();
  }

  /// Opens WhatsApp pre-filled (if configured). The manager taps Send.
  Future<NotifyResult> notify({
    required AppSettings settings,
    required String person,
    required bool isCheckIn,
    required DateTime when,
    String? projectName,
    String? taskName,
    String? description,
  }) async {
    if (!settings.whatsAppConfigured) {
      return const NotifyResult(whatsAppConfigured: false);
    }
    final message = buildMessage(
      person: person,
      isCheckIn: isCheckIn,
      when: when,
      projectName: projectName,
      taskName: taskName,
      description: description,
    );
    final number = settings.managerWhatsApp.replaceAll(RegExp(r'[^0-9]'), '');
    final opened = await _openWhatsApp(number, message);
    return NotifyResult(whatsAppConfigured: true, whatsAppOpened: opened);
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
