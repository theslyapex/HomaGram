import 'package:flutter/material.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/presentation/homagram_branding.dart';

class AccountPreferencesScreen extends StatefulWidget {
  const AccountPreferencesScreen({super.key});

  @override
  State<AccountPreferencesScreen> createState() => _AccountPreferencesScreenState();
}

class _AccountPreferencesScreenState extends State<AccountPreferencesScreen> {
  AppLocalizations get _t => AppLocalizations.of(context)!;
  bool _loading = true;
  bool _saving = false;
  bool _private = false;
  bool _showFollowers = true;
  bool _showFollowing = true;
  bool _showVisitors = true;
  bool _allowMessageForwarding = true;
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
      final settings = await _client.from('account_settings')
          .select('theme,is_private,show_followers,show_following,show_profile_visitors,allow_message_forwarding')
          .eq('user_id', _userId).maybeSingle();
      final blockRows = await _client.from('user_blocks')
          .select('blocked_id')
          .eq('blocker_id', _userId);
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
        _allowMessageForwarding = settings?['allow_message_forwarding'] as bool? ?? true;
        _blocked = blocked;
        _loading = false;
      });
      HomaGramTheme.mode.value = _toThemeMode(theme);
    } catch (_) {
      if (mounted) setState(() {
        _loading = false;
        _error = _t.accountPreferencesLoadFailed;
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
      // The signup trigger creates this row. UPDATE is permitted by the
      // account_settings grants; upsert also requires INSERT permission.
      await _client.from('account_settings')
          .update(values)
          .eq('user_id', _userId);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t.accountPreferencesSaveFailed)),
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
        SnackBar(content: Text(_t.accountPreferencesUnblockFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_t.accountPreferencesTitle)),
    body: HomaGramEntrance(child: _loading
      ? const Center(child: CircularProgressIndicator())
      : _error != null
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!),
            TextButton(onPressed: _load, child: Text(_t.adminRetry)),
          ]))
        : ListView(padding: const EdgeInsets.all(16), children: [
            Text(_t.accountAppearance, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 8),
            Card(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
              child: DropdownButtonFormField<String>(
                initialValue: _theme,
                decoration: InputDecoration(labelText: _t.accountTheme, border: InputBorder.none),
                items: [
                  DropdownMenuItem(value: 'system', child: Text(_t.accountThemeSystem)),
                  DropdownMenuItem(value: 'light', child: Text(_t.accountThemeLight)),
                  DropdownMenuItem(value: 'dark', child: Text(_t.accountThemeDark)),
                ],
                onChanged: _saving ? null : (value) { if (value != null) _setTheme(value); },
              ),
            )),
            const SizedBox(height: 18),
            Text(_t.accountPrivacy, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 8),
            Card(child: Column(children: [
              SwitchListTile.adaptive(
                value: _private,
                onChanged: _saving ? null : (value) => _setPrivacy('is_private', value),
                title: Text(_t.accountPrivate),
                subtitle: Text(_t.accountPrivateDescription, style: TextStyle(fontSize: 11)),
                secondary: const Icon(Icons.lock_outline_rounded),
              ),
              const Divider(height: 1),
              SwitchListTile.adaptive(
                value: _showFollowers,
                onChanged: _saving ? null : (value) => _setPrivacy('show_followers', value),
                title: Text(_t.accountShowFollowers),
                secondary: const Icon(Icons.people_outline_rounded),
              ),
              const Divider(height: 1),
              SwitchListTile.adaptive(
                value: _showFollowing,
                onChanged: _saving ? null : (value) => _setPrivacy('show_following', value),
                title: Text(_t.accountShowFollowing),
                secondary: const Icon(Icons.person_add_alt_rounded),
              ),
              const Divider(height: 1),
              SwitchListTile.adaptive(
                value: _allowMessageForwarding,
                onChanged: _saving ? null : (value) {
                  setState(() => _allowMessageForwarding = value);
                  _save({'allow_message_forwarding': value});
                },
                title: Text(_t.accountAllowForwarding),
                subtitle: Text(_t.accountForwardingDescription, style: TextStyle(fontSize: 11)),
                secondary: const Icon(Icons.forward_to_inbox_outlined),
              ),
              const Divider(height: 1),
              SwitchListTile.adaptive(
                value: _showVisitors,
                onChanged: _saving ? null : (value) => _setPrivacy('show_profile_visitors', value),
                title: Text(_t.accountTrackVisitors),
                subtitle: Text(_t.accountVisitorsDescription, style: TextStyle(fontSize: 11)),
                secondary: const Icon(Icons.visibility_outlined),
              ),
            ])),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(child: Text(_t.accountBlockedUsers, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
              Text('${_blocked.length}', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 8),
            Card(child: _blocked.isEmpty
              ? Padding(padding: EdgeInsets.all(16), child: Text(_t.accountNoBlockedUsers,
                  style: TextStyle(fontSize: 12)))
              : Column(children: [
                  for (final profile in _blocked)
                    ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person_outline_rounded)),
                      title: Row(children: [
                        Flexible(child: Text(profile['display_name'] as String? ?? _t.adminUnknownUser,
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 4),
                        HomaGramVerifiedBadge(userId: profile['id'] as String?),
                      ]),
                      subtitle: Text('@${profile['username'] ?? _t.adminNoUsername}'),
                      trailing: TextButton(
                        onPressed: () => _unblock(profile),
                        child: Text(_t.accountUnblock),
                      ),
                    ),
                ])),
            if (_saving) Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          ]),
    ),
  );
}
