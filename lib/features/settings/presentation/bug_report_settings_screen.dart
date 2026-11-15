import 'package:flutter/material.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../app/bug_report_service.dart';
import '../../../app/presentation/homagram_branding.dart';

class ShakeBugReportSettingsScreen extends StatefulWidget {
  const ShakeBugReportSettingsScreen({super.key});

  @override
  State<ShakeBugReportSettingsScreen> createState() => _ShakeBugReportSettingsScreenState();
}

class _ShakeBugReportSettingsScreenState extends State<ShakeBugReportSettingsScreen> {
  AppLocalizations get _t => AppLocalizations.of(context)!;
  bool _enabled = BugReportPreferences.shakeEnabled.value;
  bool _busy = false;

  Future<void> _toggle(bool value) async {
    setState(() => _busy = true);
    try {
      await BugReportPreferences.setShakeEnabled(value);
      if (mounted) setState(() => _enabled = value);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t.bugReportSettingsSaveFailed)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_t.bugReportSettingsTitle)),
    body: HomaGramEntrance(child: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0xFF293C75), Color(0xFF174D60), Color(0xFF17233E)],
            ),
          ),
          child: Row(children: [
            Icon(Icons.vibration_rounded, color: Colors.white, size: 32),
            SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_t.bugReportShakeTitle, style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
              SizedBox(height: 5),
              Text(_t.bugReportShakeDescription,
                style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.7)),
            ])),
          ]),
        ),
        const SizedBox(height: 14),
        Card(child: SwitchListTile.adaptive(
          value: _enabled,
          onChanged: _busy ? null : _toggle,
          title: Text(_t.bugReportShakeToggle, style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(_t.bugReportSignedInOnly, style: TextStyle(fontSize: 11)),
          secondary: const Icon(Icons.bug_report_outlined),
        )),
        const SizedBox(height: 12),
        _InfoRow(
          icon: Icons.photo_camera_back_outlined,
          title: _t.bugReportPreviewTitle,
          body: _t.bugReportPreviewDescription,
        ),
        const SizedBox(height: 10),
        _InfoRow(
          icon: Icons.edit_note_rounded,
          title: _t.bugReportDetailsTitle,
          body: _t.bugReportDetailsDescription,
        ),
        const SizedBox(height: 10),
        _InfoRow(
          icon: Icons.privacy_tip_outlined,
          title: _t.bugReportPrivacyTitle,
          body: _t.bugReportPrivacyDescription,
        ),
      ],
    )),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(15),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary, size: 23),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text(body, style: const TextStyle(fontSize: 11, height: 1.7)),
        ])),
      ]),
    ),
  );
}
