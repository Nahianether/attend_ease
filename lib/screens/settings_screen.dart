import 'package:flutter/material.dart';

import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _service = SettingsService();
  final _formKey = GlobalKey<FormState>();

  final _managerEmail = TextEditingController();
  final _managerWhatsApp = TextEditingController();
  final _smtpHost = TextEditingController();
  final _smtpPort = TextEditingController();
  final _smtpUser = TextEditingController();
  final _smtpPass = TextEditingController();

  bool _loading = true;
  bool _obscurePass = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await _service.load();
    _managerEmail.text = s.managerEmail;
    _managerWhatsApp.text = s.managerWhatsApp;
    _smtpHost.text = s.smtpHost;
    _smtpPort.text = s.smtpPort.toString();
    _smtpUser.text = s.smtpUsername;
    _smtpPass.text = s.smtpPassword;
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _managerEmail.dispose();
    _managerWhatsApp.dispose();
    _smtpHost.dispose();
    _smtpPort.dispose();
    _smtpUser.dispose();
    _smtpPass.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final s = AppSettings(
      managerEmail: _managerEmail.text.trim(),
      managerWhatsApp: _managerWhatsApp.text.trim(),
      smtpHost: _smtpHost.text.trim().isEmpty
          ? 'smtp.gmail.com'
          : _smtpHost.text.trim(),
      smtpPort: int.tryParse(_smtpPort.text.trim()) ?? 587,
      smtpUsername: _smtpUser.text.trim(),
      smtpPassword: _smtpPass.text,
    );
    await _service.save(s);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Settings saved')));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _section('Project Manager — who gets notified'),
            TextFormField(
              controller: _managerEmail,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Manager email',
                hintText: 'manager@company.com',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _managerWhatsApp,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Manager WhatsApp (with country code)',
                hintText: 'e.g. 8801712345678',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            _section('Sending account — used to send the email automatically'),
            const Text(
              'For Gmail: turn on 2-Step Verification, then create an '
              '"App password" and paste it below (not your normal password).',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _smtpUser,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Sending email address',
                hintText: 'youraccount@gmail.com',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _smtpPass,
              obscureText: _obscurePass,
              decoration: InputDecoration(
                labelText: 'App password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePass
                      ? Icons.visibility
                      : Icons.visibility_off),
                  onPressed: () =>
                      setState(() => _obscurePass = !_obscurePass),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _smtpHost,
                    decoration: const InputDecoration(
                      labelText: 'SMTP host',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _smtpPort,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Save settings'),
            ),
          ],
        ),
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
