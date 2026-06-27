import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Navigator key so global error handlers can show a dialog without a local
/// BuildContext. Wired into the root MaterialApp.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

bool _globalErrorVisible = false;

/// Installs a safety net for uncaught **async** errors so they surface as a
/// friendly dialog instead of silently failing. Build-time errors keep the
/// default behaviour (red screen in debug; a friendly box in release).
void installGlobalErrorHandlers() {
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught async error: $error\n$stack');
    _maybeShowGlobalError(error);
    return true; // handled — don't crash the app
  };

  if (!kDebugMode) {
    ErrorWidget.builder = (details) => Material(
          color: Colors.white,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.error_outline, color: Colors.red, size: 40),
                  SizedBox(height: 12),
                  Text(
                    'Something went wrong drawing this screen.\n'
                    'Please go back and try again.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
  }
}

void _maybeShowGlobalError(Object error) {
  if (_globalErrorVisible) return;
  final ctx = appNavigatorKey.currentContext;
  if (ctx == null) return;
  _globalErrorVisible = true;
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await showAppError(ctx, title: 'Unexpected error', error: error);
    _globalErrorVisible = false;
  });
}

/// Turns a raw error into a short, plain-language explanation the user can act
/// on. The raw error is still shown under "Technical details" in the dialog.
String friendlyMessage(Object error) {
  final s = error.toString().toLowerCase();

  if (s.contains('readonly') || s.contains('no such file') ||
      s.contains('disk i/o') || s.contains('disk full') ||
      s.contains('sqlite_full')) {
    return 'Could not save your data. Your device may be out of storage or the '
        'app lacks permission to write. Free up some space and try again.';
  }
  if (s.contains('database') || s.contains('sqlite')) {
    return 'There was a problem reading or saving local data. Please try again; '
        'if it keeps happening, restart the app.';
  }
  if (s.contains('whatsapp') ||
      s.contains('could not launch') ||
      s.contains('activity') ||
      s.contains('no application')) {
    return 'Could not open WhatsApp. Make sure WhatsApp is installed and the '
        'manager number in Settings is correct (digits only, with country code).';
  }
  if (s.contains('printing') ||
      s.contains('print') ||
      s.contains('share') ||
      s.contains('pdf')) {
    return 'Could not open the share / print dialog for the PDF. Please try '
        'again, or pick a different app to share to.';
  }
  if (s.contains('permission')) {
    return 'The app is missing a permission it needs for this action. Please '
        'grant it in your device settings and try again.';
  }
  return 'Something went wrong while completing this action. Please try again.';
}

/// Shows a friendly error dialog with an expandable "Technical details" panel
/// so the user can self-diagnose or report the exact error.
Future<void> showAppError(
  BuildContext context, {
  String title = 'Something went wrong',
  String? message,
  Object? error,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.error_outline, color: Colors.red, size: 36),
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message ?? (error != null ? friendlyMessage(error) : '')),
          if (error != null) ...[
            const SizedBox(height: 12),
            Theme(
              data: Theme.of(ctx).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: const Text('Technical details',
                    style: TextStyle(fontSize: 13)),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SelectableText(
                      error.toString(),
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Runs [action], showing a friendly error dialog if it throws. Returns the
/// action's result, or null on failure.
Future<T?> guard<T>(
  BuildContext context,
  Future<T> Function() action, {
  String title = 'Something went wrong',
  String? message,
}) async {
  try {
    return await action();
  } catch (e) {
    if (context.mounted) {
      await showAppError(context, title: title, message: message, error: e);
    }
    return null;
  }
}

/// A friendly error state for async provider `.when(error: ...)` callbacks,
/// with a Retry button.
class ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const ErrorView({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 40, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              friendlyMessage(error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
            const SizedBox(height: 16),
            ExpansionTile(
              title: const Text('Technical details',
                  style: TextStyle(fontSize: 13)),
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: SelectableText(error.toString(),
                      style: const TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
