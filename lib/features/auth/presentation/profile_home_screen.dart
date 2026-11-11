import 'package:flutter/material.dart';
import '../../../app/theme/app_theme.dart';
import '../data/auth_service.dart';

class ProfileHomeScreen extends StatefulWidget {
  const ProfileHomeScreen({super.key});
  @override
  State<ProfileHomeScreen> createState() => _ProfileHomeScreenState();
}

class _ProfileHomeScreenState extends State<ProfileHomeScreen> {
  final _name = TextEditingController();
  final _bio = TextEditingController();
  bool _loading = true, _saving = false, _private = false;
  String? _username, _error;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _name.dispose(); _bio.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final id = AuthService.client.auth.currentUser!.id;
      final rows = await Future.wait([
        AuthService.client.from('profiles').select('username,display_name,bio').eq('id', id).single(),
        AuthService.client.from('account_settings').select('is_private').eq('user_id', id).single(),
      ]);
      if (!mounted) return;
      _username = rows[0]['username'] as String;
      _name.text = rows[0]['display_name'] as String;
      _bio.text = rows[0]['bio'] as String;
      _private = rows[1]['is_private'] as bool;
    } catch (_) {
      _error = 'اطلاعات حساب دریافت نشد. اتصال و دسترسی دیتابیس را بررسی کنید.';
    } finally { if (mounted) setState(() => _loading = false); }
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text, textAlign: TextAlign.center),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
  }

  Future<void> _saveProfile() async {
    final name = _name.text.trim(), bio = _bio.text.trim();
    if (name.isEmpty || name.length > 50 || bio.length > 160) {
      _message('نام نمایشی باید ۱ تا ۵۰ و بیو حداکثر ۱۶۰ نویسه باشد.', error: true); return;
    }
    setState(() => _saving = true);
    try {
      final id = AuthService.client.auth.currentUser!.id;
      await AuthService.client.from('profiles').update({'display_name': name, 'bio': bio}).eq('id', id);
      _message('پروفایل ذخیره شد.');
    } catch (_) { _message('ذخیره پروفایل انجام نشد.', error: true); }
    finally { if (mounted) setState(() => _saving = false); }
  }

  Future<void> _setPrivacy(bool value) async {
    setState(() => _private = value);
    try {
      final id = AuthService.client.auth.currentUser!.id;
      await AuthService.client.from('account_settings').update({'is_private': value}).eq('user_id', id);
      _message(value ? 'تنظیم حساب خصوصی ذخیره شد.' : 'تنظیم حساب عمومی ذخیره شد.');
    } catch (_) {
      if (mounted) setState(() => _private = !value);
      _message('ذخیره تنظیم حریم خصوصی انجام نشد.', error: true);
    }
  }

  Future<void> _signOut({bool otherDevices = false}) async {
    try {
      if (otherDevices) {
        await AuthService.signOutOtherDevices();
        _message('نشست‌های دیگر خاتمه یافتند؛ این دستگاه متصل باقی می‌ماند.');
      } else {
        await AuthService.signOutThisDevice();
      }
    } catch (_) { _message('خروج از نشست انجام نشد. دوباره تلاش کنید.', error: true); }
  }

  @override
  Widget build(BuildContext context) {
    final email = AuthService.client.auth.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('حساب HomaGram'),
        actions: [IconButton(tooltip: 'خروج از این دستگاه', onPressed: _signOut, icon: const Icon(Icons.logout_rounded))]),
      body: _loading ? const Center(child: CircularProgressIndicator())
        : _error != null ? _errorView()
        : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.fromLTRB(18, 12, 18, 28), children: [
          _identity(email),
          const SizedBox(height: 16),
          Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('اطلاعات پروفایل', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('@${_username ?? ''}', textDirection: TextDirection.ltr, textAlign: TextAlign.right,
              style: const TextStyle(color: HomaGramTheme.turquoise, fontWeight: FontWeight.w700)),
            const SizedBox(height: 18),
            TextField(controller: _name, maxLength: 50, decoration: const InputDecoration(labelText: 'نام نمایشی')),
            const SizedBox(height: 12),
            TextField(controller: _bio, maxLength: 160, maxLines: 3, decoration: const InputDecoration(labelText: 'بیوگرافی')),
            const SizedBox(height: 12),
            FilledButton(onPressed: _saving ? null : _saveProfile, child: Text(_saving ? 'در حال ذخیره...' : 'ذخیره تغییرات')),
          ]))),
          const SizedBox(height: 16),
          Card(child: SwitchListTile(
            value: _private, onChanged: _setPrivacy, title: const Text('حساب خصوصی'),
            subtitle: const Text('تنظیم ذخیره می‌شود؛ اعمال کامل آن بر نمایش محتوا در مرحله شبکه اجتماعی تکمیل خواهد شد.'),
            secondary: const Icon(Icons.lock_outline),
          )),
          const SizedBox(height: 16),
          Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('مدیریت نشست‌ها', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 6),
            const Text('می‌توانید نشست‌های دیگر را از حساب خارج کنید.', style: TextStyle(height: 1.7, color: Color(0xFF64718A))),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: () => _signOut(otherDevices: true),
              icon: const Icon(Icons.devices_rounded), label: const Text('خروج از سایر دستگاه‌ها')),
          ]))),
          const SizedBox(height: 20),
          const Center(child: Text('HomaGram • مرحله یک: هسته حساب کاربری', style: TextStyle(color: Color(0xFF7A879B), fontSize: 11))),
        ])),
    );
  }

  Widget _identity(String email) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(24),
      gradient: const LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft,
        colors: [Color(0xFF101B35), Color(0xFF263A62)])),
    child: Row(children: [
      const CircleAvatar(radius: 28, backgroundColor: HomaGramTheme.turquoise,
        child: Icon(Icons.person_outline, color: Colors.white, size: 30)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('حساب شما فعال است', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
        const SizedBox(height: 5),
        Text(email, textDirection: TextDirection.ltr, style: const TextStyle(color: Color(0xFFD6E8F0), fontSize: 12)),
      ])),
    ]),
  );

  Widget _errorView() => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.cloud_off_outlined, size: 42, color: HomaGramTheme.royalPurple),
    const SizedBox(height: 12), Text(_error!, textAlign: TextAlign.center),
    const SizedBox(height: 16), FilledButton(onPressed: _load, child: const Text('تلاش دوباره')),
    TextButton(onPressed: _signOut, child: const Text('خروج از حساب')),
  ])));
}
