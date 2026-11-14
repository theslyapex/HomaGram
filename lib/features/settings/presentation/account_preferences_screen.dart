import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/presentation/homagram_branding.dart';

class AccountPreferencesScreen extends StatefulWidget {
  const AccountPreferencesScreen({super.key});

  @override
  State<AccountPreferencesScreen> createState() => _AccountPreferencesScreenState();
}

class _AccountPreferencesScreenState extends State<AccountPreferencesScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _private = false;
  bool _showFollowers = true;
  bool _showFollowing = true;
  bool _showVisitors = true;
  String _theme = 'system';
  List<Map<String, dynamic>> _blocked = [];
  String? _error;

  SupabaseClient get _client => Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        _client.from('account_settings')
          .select('theme,is_private,show_followers,show_following,show_profile_visitors')
          .eq('user_id', _userId).maybeSingle(),
        _client.from('user_blocks')
          .select('blocked_id')
          .eq('blocker_id', _userId),
      ]);
      final settings = results[0] as Map<String, dynamic>?;
      final blockRows = results[1] as List;
      final blockedIds = blockRows.map((row) => row['blocked_id'] as String).toList();
      final profiles = blockedIds.isEmpty
          ? <dynamic>[]
          : await _client.from('profiles')
              .select('id,username,display_name')
              .inFilter('id', blockedIds);
      final byId = {for (final profile in profiles) profile['id'] as String: profile};
      final blocked = blockedIds.map((id) => byId[id])
          .whereType<Map<String, dynamic>>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final theme = settings?['theme'] as String? ?? 'system';
      if (!mounted) return;
      setState(() {
        _theme = theme;
        _private = settings?['is_private'] as bool? ?? false;
        _showFollowers = settings?['show_followers'] as bool? ?? true;
        _showFollowing = settings?['show_following'] as bool? ?? true;
        _showVisitors = settings?['show_profile_visitors'] as bool? ?? true;
        _blocked = blocked;
        _loading = false;
      });
      HomaGramTheme.mode.value = _toThemeMode(theme);
    } catch (_) {
      if (mounted) setState(() {
        _loading = false;
        _error = 'تنظیمات حساب دریافت نشد. اتصال را بررسی کنید.';
      });
    }
  }

  ThemeMode _toThemeMode(String value) => switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  Future<void> _save(Map<String, dynamic> values) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _client.from('account_settings').upsert({
        'user_id': _userId,
        ...values,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ذخیره تنظیمات انجام نشد. دوباره تلاش کنید.')),
      );
      await _load();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setTheme(String value) async {
    setState(() => _theme = value);
    HomaGramTheme.mode.value = _toThemeMode(value);
    await _save({'theme': value});
  }

  Future<void> _setPrivacy(String key, bool value) async {
    setState(() {
      switch (key) {
        case 'is_private': _private = value; break;
        case 'show_followers': _showFollowers = value; break;
        case 'show_following': _showFollowing = value; break;
        case 'show_profile_visitors': _showVisitors = value; break;
      }
    });
    await _save({key: value});
  }

  Future<void> _unblock(Map<String, dynamic> profile) async {
    final id = profile['id'] as String?;
    if (id == null) return;
    try {
      await _client.from('user_blocks')
          .delete().eq('blocker_id', _userId).eq('blocked_id', id);
      if (mounted) setState(() => _blocked.removeWhere((row) => row['id'] == id));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('رفع مسدودسازی انجام نشد.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('حریم خصوصی و نمایش حساب')),
    body: HomaGramEntrance(child: _loading
      ? const Center(child: CircularProgressIndicator())
      : _error != null
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!),
            TextButton(onPressed: _load, child: const Text('تلاش دوباره')),
          ]))
        : ListView(padding: const EdgeInsets.all(16), children: [
            const Text('نمایش و ظاهر', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 8),
            Card(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
              child: DropdownButtonFormField<String>(
                initialValue: _theme,
                decoration: const InputDecoration(labelText: 'پوسته برنامه', border: InputBorder.none),
                items: const [
                  DropdownMenuItem(value: 'system', child: Text('مطابق تنظیم دستگاه')),
                  DropdownMenuItem(value: 'light', child: Text('روشن')),
                  DropdownMenuItem(value: 'dark', child: Text('تیره')),
                ],
                onChanged: _saving ? null : (value) { if (value != null) _setTheme(value); },
              ),
            )),
            const SizedBox(height: 18),
            const Text('حریم خصوصی حساب', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 8),
            Card(child: Column(children: [
              SwitchListTile.adaptive(
                value: _private,
                onChanged: _saving ? null : (value) => _setPrivacy('is_private', value),
                title: const Text('حساب خصوصی'),
                subtitle: const Text('برای دنبال‌کردن شما، درخواست دنبال‌کردن لازم است.', style: TextStyle(fontSize: 11)),
                secondary: const Icon(Icons.lock_outline_rounded),
              ),
              const Divider(height: 1),
              SwitchListTile.adaptive(
                value: _showFollowers,
                onChanged: _saving ? null : (value) => _setPrivacy('show_followers', value),
                title: const Text('نمایش دنبال‌کنندگان'),
                secondary: const Icon(Icons.people_outline_rounded),
              ),
              const Divider(height: 1),
              SwitchListTile.adaptive(
                value: _showFollowing,
                onChanged: _saving ? null : (value) => _setPrivacy('show_following', value),
                title: const Text('نمایش دنبال‌شوندگان'),
                secondary: const Icon(Icons.person_add_alt_rounded),
              ),
              const Divider(height: 1),
              SwitchListTile.adaptive(
                value: _showVisitors,
                onChanged: _saving ? null : (value) => _setPrivacy('show_profile_visitors', value),
                title: const Text('ثبت بازدیدکنندگان پروفایل'),
                subtitle: const Text('با خاموش‌کردن این گزینه، فهرست بازدیدها برای پروفایل شما ثبت نمی‌شود.', style: TextStyle(fontSize: 11)),
                secondary: const Icon(Icons.visibility_outlined),
              ),
            ])),
            const SizedBox(height: 18),
            Row(children: [
              const Expanded(child: Text('حساب‌های مسدودشده', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
              Text('${_blocked.length}', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 8),
            Card(child: _blocked.isEmpty
              ? const Padding(padding: EdgeInsets.all(16), child: Text('در حال حاضر حسابی را مسدود نکرده‌اید.',
                  style: TextStyle(fontSize: 12)))
              : Column(children: [
                  for (final profile in _blocked)
                    ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person_outline_rounded)),
                      title: Row(children: [
                        Flexible(child: Text(profile['display_name'] as String? ?? 'کاربر هماگرام',
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 4),
                        HomaGramVerifiedBadge(userId: profile['id'] as String?),
                      ]),
                      subtitle: Text('@${profile['username'] ?? 'user'}'),
                      trailing: TextButton(
                        onPressed: () => _unblock(profile),
                        child: const Text('رفع مسدودی'),
                      ),
                    ),
                ])),
            if (_saving) const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          ]),
    ),
  );
}
