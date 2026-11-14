import 'package:flutter/material.dart';
import '../../../app/bug_report_service.dart';
import '../../../app/presentation/homagram_branding.dart';

class ShakeBugReportSettingsScreen extends StatefulWidget {
  const ShakeBugReportSettingsScreen({super.key});

  @override
  State<ShakeBugReportSettingsScreen> createState() => _ShakeBugReportSettingsScreenState();
}

class _ShakeBugReportSettingsScreenState extends State<ShakeBugReportSettingsScreen> {
  bool _enabled = BugReportPreferences.shakeEnabled.value;
  bool _busy = false;

  Future<void> _toggle(bool value) async {
    setState(() => _busy = true);
    try {
      await BugReportPreferences.setShakeEnabled(value);
      if (mounted) setState(() => _enabled = value);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ذخیره تنظیم انجام نشد. دوباره تلاش کنید.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('گزارش سریع مشکل')),
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
          child: const Row(children: [
            Icon(Icons.vibration_rounded, color: Colors.white, size: 32),
            SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('گزارش با یک حرکت', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
              SizedBox(height: 5),
              Text('گوشی را تکان دهید تا فرم گزارش مشکل با تصویر همین صفحه باز شود.',
                style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.7)),
            ])),
          ]),
        ),
        const SizedBox(height: 14),
        Card(child: SwitchListTile.adaptive(
          value: _enabled,
          onChanged: _busy ? null : _toggle,
          title: const Text('فعال‌سازی گزارش با تکان گوشی', style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: const Text('این قابلیت فقط هنگام ورود به حساب فعال است.', style: TextStyle(fontSize: 11)),
          secondary: const Icon(Icons.bug_report_outlined),
        )),
        const SizedBox(height: 12),
        const _InfoRow(
          icon: Icons.photo_camera_back_outlined,
          title: 'پیش‌نمایش قبل از ارسال',
          body: 'پس از تکان گوشی، تصویر صفحه فقط برای نمایش پیش‌نمایش گرفته می‌شود. هیچ تصویری بدون تأیید شما ارسال نخواهد شد.',
        ),
        const SizedBox(height: 10),
        const _InfoRow(
          icon: Icons.edit_note_rounded,
          title: 'توضیح مشکل',
          body: 'می‌توانید توضیح دهید چه کاری انجام می‌دادید و چه مشکلی رخ داد؛ تصویر و توضیح در یک پیام برای پشتیبانی فرستاده می‌شوند.',
        ),
        const SizedBox(height: 10),
        const _InfoRow(
          icon: Icons.privacy_tip_outlined,
          title: 'حریم خصوصی',
          body: 'پیش از ارسال، تصویر را بررسی کنید و اگر اطلاعات خصوصی یا حساس روی صفحه دیده می‌شود، ارسال را لغو کنید.',
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
