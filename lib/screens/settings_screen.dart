import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../services/settings_service.dart';
import '../widgets/error_handling.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _managerWhatsApp = TextEditingController();
  bool _seeded = false;

  @override
  void dispose() {
    _name.dispose();
    _managerWhatsApp.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    try {
      // Preserve the theme (changed live via its own control).
      final current = ref.read(settingsProvider).asData?.value;
      await ref.read(settingsProvider.notifier).save(AppSettings(
            defaultUserName: _name.text.trim(),
            managerWhatsApp: _managerWhatsApp.text.trim(),
            themeMode: current?.themeMode ?? 'system',
          ));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Settings saved')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        await showAppError(context, title: 'Could not save settings', error: e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            ErrorView(error: e, onRetry: () => ref.invalidate(settingsProvider)),
        data: (s) {
          if (!_seeded) {
            _seeded = true;
            _name.text = s.defaultUserName;
            _managerWhatsApp.text = s.managerWhatsApp;
          }
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _section('You'),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Your full name',
                    hintText: 'e.g. Rahim Uddin',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Please enter your name'
                      : null,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Used to tag every time entry. Asked once on first launch; '
                  'change it here anytime.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 24),
                _section('Manager — who gets notified'),
                TextFormField(
                  controller: _managerWhatsApp,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Manager WhatsApp (with country code)',
                    hintText: 'e.g. 8801712345678',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Digits only, including country code. On check-in/out, '
                  'WhatsApp opens pre-filled — you tap Send.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 24),
                _section('Appearance'),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'system',
                        label: Text('System'),
                        icon: Icon(Icons.brightness_auto)),
                    ButtonSegment(
                        value: 'light',
                        label: Text('Light'),
                        icon: Icon(Icons.light_mode_outlined)),
                    ButtonSegment(
                        value: 'dark',
                        label: Text('Dark'),
                        icon: Icon(Icons.dark_mode_outlined)),
                  ],
                  selected: {s.themeMode},
                  onSelectionChanged: (sel) => ref
                      .read(settingsProvider.notifier)
                      .setThemeMode(sel.first),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Applies instantly. "System" follows your device theme.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save),
                  label: const Text('Save settings'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      );
}
