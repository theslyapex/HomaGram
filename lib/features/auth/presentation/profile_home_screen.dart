import 'package:homagram/app/presentation/homagram_branding.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../core/utils/persian_date.dart';
import '../data/auth_service.dart';
import '../domain/auth_constants.dart';
import '../../home/data/story_service.dart';
import '../../verification/presentation/verification_request_screen.dart';

class ProfileHomeScreen extends StatefulWidget {
  const ProfileHomeScreen({this.onCompleted, super.key});

  final VoidCallback? onCompleted;

  @override
  State<ProfileHomeScreen> createState() => _ProfileHomeScreenState();
}

class _ProfileHomeScreenState extends State<ProfileHomeScreen> {
  AppLocalizations get _t => AppLocalizations.of(context)!;
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _bio = TextEditingController();
  final _birthDate = TextEditingController();
  final _picker = ImagePicker();

  bool _loading = true;
  bool _saving = false;
  bool _uploadingAvatar = false;
  bool _private = false;
  bool _showFollowers = true;
  bool _showFollowing = true;
  bool _showProfileVisitors = true;
  bool _showBirthDate = false;
  bool _onboarding = false;
  String? _avatarPath;
  String? _avatarUrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _bio.dispose();
    _birthDate.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final id = AuthService.client.auth.currentUser!.id;
      final rows = await Future.wait([
        AuthService.client
            .from('profiles')
            .select('username,display_name,bio,avatar_path,profile_completed_at')
            .eq('id', id)
            .single(),
        AuthService.client
            .from('account_settings')
            .select('is_private,show_followers,show_following,show_profile_visitors')
            .eq('user_id', id)
            .single(),
      ]);
      final birthday = await AuthService.client
          .from('profile_birthdays')
          .select('birth_date,is_public')
          .eq('user_id', id)
          .maybeSingle();
      final profile = rows[0];
      final settings = rows[1];
      _username.text = (profile['username'] ?? '') as String;
      _name.text = (profile['display_name'] ?? '') as String;
      _bio.text = (profile['bio'] ?? '') as String;
      _avatarPath = profile['avatar_path'] as String?;
      _onboarding = profile['profile_completed_at'] == null;
      _private = settings['is_private'] as bool? ?? false;
      _showFollowers = settings['show_followers'] as bool? ?? true;
      _showFollowing = settings['show_following'] as bool? ?? true;
      _showProfileVisitors = settings['show_profile_visitors'] as bool? ?? true;
      final savedBirthDate = birthday?['birth_date'] as String?;
      _birthDate.text = savedBirthDate == null
          ? ''
          : persianDate(DateTime.parse(savedBirthDate));
      _showBirthDate = birthday?['is_public'] as bool? ?? false;
      // Avatar delivery is optional: a temporary Storage signing failure
      // must not prevent the user's account details from loading.
      _avatarUrl = null;
      if (_avatarPath != null) {
        try {
          _avatarUrl = await AuthService.client.storage
              .from('avatars')
              .createSignedUrl(_avatarPath!, 3600);
        } catch (_) {
          _avatarUrl = null;
        }
      }
    } catch (_) {
      _error = _t.profileLoadFailed;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text, textAlign: TextAlign.center),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
  }

  Future<void> _pickAvatar() async {
    if (_uploadingAvatar || _saving) return;
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        _message(_t.avatarTooLarge, error: true);
        return;
      }
      final mime = file.mimeType ?? _mimeFromName(file.name);
      if (!const ['image/jpeg', 'image/png', 'image/webp'].contains(mime)) {
        _message(_t.avatarInvalidFormat, error: true);
        return;
      }

      setState(() => _uploadingAvatar = true);
      final id = AuthService.client.auth.currentUser!.id;
      final extension = mime == 'image/png'
          ? 'png'
          : mime == 'image/webp'
              ? 'webp'
              : 'jpg';
      final path = '$id/avatar_${DateTime.now().microsecondsSinceEpoch}.$extension';

      await AuthService.client.storage.from('avatars').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: false),
          );
      await AuthService.client
          .from('profiles')
          .update({'avatar_path': path})
          .eq('id', id);

      final previous = _avatarPath;
      final signed = await AuthService.client.storage
          .from('avatars')
          .createSignedUrl(path, 3600);
      if (!mounted) return;
      setState(() {
        _avatarPath = path;
        _avatarUrl = signed;
      });
      if (previous != null && previous != path) {
        try {
          await AuthService.client.storage.from('avatars').remove([previous]);
        } catch (_) {
          // The new avatar is already saved; an old file can be cleaned up later.
        }
      }
      _message(_t.avatarUpdated);
    } on StorageException catch (e) {
      _message(_t.avatarUploadStorageError(e.message), error: true);
    } catch (_) {
      _message(_t.avatarUploadFailed, error: true);
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  String _mimeFromName(String name) {
    final ext = name.split('.').last.toLowerCase();
    if (ext == 'png') return 'image/png';
    if (ext == 'webp') return 'image/webp';
    if (ext == 'jpg' || ext == 'jpeg') return 'image/jpeg';
    return 'application/octet-stream';
  }

  Future<void> _saveProfile() async {
    final name = _name.text.trim();
    final username = _username.text.trim().toLowerCase();
    final bio = _bio.text.trim();
    if (name.isEmpty || name.length > 50 || bio.length > 160) {
      _message(_t.profileNameBioValidation, error: true);
      return;
    }
    if (validateHomagramUsername(username, accountEmail: AuthService.client.auth.currentUser?.email) != null) {
      _message(_t.profileUsernameValidation, error: true);
      return;
    }
    final birthdayText = _birthDate.text.trim();
    final birthday = birthdayText.isEmpty ? null : parsePersianDate(birthdayText);
    if (birthdayText.isNotEmpty && birthday == null) {
      _message(_t.invalidPersianBirthDate, error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final id = AuthService.client.auth.currentUser!.id;
      final updates = <String, dynamic>{
        'username': username,
        'display_name': name,
        'bio': bio,
      };
      if (_onboarding) {
        updates['profile_completed_at'] = DateTime.now().toUtc().toIso8601String();
      }
      await AuthService.client.from('profiles').update(updates).eq('id', id);
      if (birthday == null) {
        await AuthService.client.from('profile_birthdays').delete().eq('user_id', id);
      } else {
        await AuthService.client.from('profile_birthdays').upsert({
          'user_id': id,
          'birth_date': birthday.toIso8601String().substring(0, 10),
          'is_public': _showBirthDate,
        }, onConflict: 'user_id');
      }
      if (!mounted) return;
      setState(() => _onboarding = false);
      _message(_t.profileSaved);
      widget.onCompleted?.call();
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        _message(_t.profileUsernameTaken, error: true);
      } else {
        _message(_t.profileSaveFailedRetry, error: true);
      }
    } catch (_) {
      _message(_t.profileSaveFailed, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setPrivacy(bool value) async {
    setState(() => _private = value);
    try {
      final id = AuthService.client.auth.currentUser!.id;
      await AuthService.client
          .from('account_settings')
          .update({'is_private': value})
          .eq('user_id', id);
      _message(value ? _t.privateAccountSaved : _t.publicAccountSaved);
    } catch (_) {
      if (mounted) setState(() => _private = !value);
      _message(_t.privacySaveFailed, error: true);
    }
  }

  Future<void> _setVisibility(String column, bool value) async {
    final previous = switch (column) {
      'show_followers' => _showFollowers,
      'show_following' => _showFollowing,
      'show_profile_visitors' => _showProfileVisitors,
      _ => false,
    };
    setState(() {
      if (column == 'show_followers') _showFollowers = value;
      if (column == 'show_following') _showFollowing = value;
      if (column == 'show_profile_visitors') _showProfileVisitors = value;
    });
    try {
      final id = AuthService.client.auth.currentUser!.id;
      await AuthService.client.from('account_settings')
          .update({column: value}).eq('user_id', id);
      _message(_t.privacySettingsSaved);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (column == 'show_followers') _showFollowers = previous;
        if (column == 'show_following') _showFollowing = previous;
        if (column == 'show_profile_visitors') _showProfileVisitors = previous;
      });
      _message(_t.privacySaveFailed, error: true);
    }
  }

  Future<void> _signOut({bool otherDevices = false}) async {
    try {
      if (otherDevices) {
        await AuthService.signOutOtherDevices();
        _message(_t.otherSessionsSignedOut);
      } else {
        await AuthService.signOutThisDevice();
      }
    } catch (_) {
      _message(_t.sessionSignOutFailed, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = AuthService.client.auth.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(_onboarding ? _t.profileSetup : _t.homagramAccount),
        actions: [
          HomaGramSpringPress(child: IconButton(
            tooltip: _t.signOutThisDevice,
            onPressed: _signOut,
            icon: const Icon(Icons.logout_rounded),
          )),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorView()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                    children: [
                      if (_onboarding) _onboardingNotice(),
                      _identity(email),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(_t.profileInformation,
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 18),
                              Center(child: _avatarPicker()),
                              const SizedBox(height: 20),
                              TextField(
                                controller: _name,
                                maxLength: 50,
                                decoration: InputDecoration(
                                  labelText: _t.displayName,
                                  prefixIcon: Icon(Icons.person_outline),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _username,
                                maxLength: 24,
                                textDirection: TextDirection.ltr,
                                decoration: InputDecoration(
                                  labelText: _t.username,
                                  prefixText: '@ ',
                                  prefixIcon: Icon(Icons.alternate_email),
                                  helperText: _t.usernameRules,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _birthDate,
                                onChanged: (_) => setState(() {}),
                                keyboardType: TextInputType.datetime,
                                textDirection: TextDirection.ltr,
                                decoration: InputDecoration(
                                  labelText: _t.persianBirthDate,
                                  hintText: _t.birthDateExample,
                                  prefixIcon: Icon(Icons.cake_outlined),
                                  helperText: _t.birthDateOptionalHint,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SwitchListTile.adaptive(
                                contentPadding: EdgeInsets.zero,
                                value: _showBirthDate,
                                onChanged: _birthDate.text.trim().isEmpty
                                    ? null
                                    : (value) => setState(() => _showBirthDate = value),
                                title: Text(_t.showBirthDate),
                                subtitle: Text(_t.birthDatePrivateHint),
                                secondary: const Icon(Icons.visibility_outlined),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _bio,
                                maxLength: 160,
                                maxLines: 3,
                                decoration: InputDecoration(
                                  labelText: _t.biography,
                                  prefixIcon: Icon(Icons.notes_rounded),
                                  alignLabelWithHint: true,
                                ),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: _saving ? null : () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(builder: (_) => const VerificationRequestScreen()),
                                ),
                                icon: const Icon(Icons.verified_user_outlined),
                                label: Text(_t.requestVerificationBadge),
                              ),
                              const SizedBox(height: 8),
                              HomaGramSpringPress(child: FilledButton(
                                onPressed: _saving ? null : _saveProfile,
                                child: Text(_saving
                                    ? _t.saving
                                    : _onboarding
                                        ? _t.completeAndSaveProfile
                                        : _t.saveChanges),
                              )),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: SwitchListTile(
                          value: _private,
                          onChanged: _setPrivacy,
                          title: Text(_t.privateAccount),
                          subtitle: Text(_t.privateAccountFeatureNotice,
                          ),
                          secondary: const Icon(Icons.lock_outline),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.people_alt_outlined),
                          title: Text(_t.closeFriends,
                              style: TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: Text(_t.closeFriendsPrivateDescription),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            useSafeArea: true,
                            builder: (_) => const CloseFriendsManagerSheet(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            children: [
                              ListTile(
                                leading: Icon(Icons.visibility_off_outlined),
                                title: Text(_t.listPrivacy,
                                    style: TextStyle(fontWeight: FontWeight.w800)),
                                subtitle: Text(_t.listPrivacyDescription),
                              ),
                              SwitchListTile(
                                value: _showFollowers,
                                onChanged: (value) => _setVisibility('show_followers', value),
                                title: Text(_t.showFollowers),
                                subtitle: Text(_t.hideFollowersHint),
                              ),
                              SwitchListTile(
                                value: _showFollowing,
                                onChanged: (value) => _setVisibility('show_following', value),
                                title: Text(_t.showFollowing),
                                subtitle: Text(_t.hideFollowingHint),
                              ),
                              const Divider(height: 1),
                              SwitchListTile(
                                value: _showProfileVisitors,
                                onChanged: (value) => _setVisibility('show_profile_visitors', value),
                                title: Text(_t.showProfileVisitors),
                                subtitle: Text(_t.profileVisitorsHint),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(_t.sessionManagement,
                                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                              const SizedBox(height: 6),
                              Text(_t.sessionManagementDescription,
                                style: TextStyle(height: 1.7, color: Color(0xFF64718A)),
                              ),
                              const SizedBox(height: 12),
                              HomaGramSpringPress(child: OutlinedButton.icon(
                                onPressed: () => _signOut(otherDevices: true),
                                icon: const Icon(Icons.devices_rounded),
                                label: Text(_t.signOutOtherDevices),
                              )),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Center(
                        child: Text(_t.homagramAccountFooter,
                            style: TextStyle(color: Color(0xFF7A879B), fontSize: 11)),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _onboardingNotice() => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: HomaGramTheme.turquoise.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: HomaGramTheme.turquoise.withValues(alpha: .28)),
        ),
        child: Row(
          children: [
            Icon(Icons.auto_awesome_rounded, color: HomaGramTheme.turquoise),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                _t.profileOnboardingNotice,
                style: TextStyle(height: 1.7, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );

  Widget _avatarPicker() => Column(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 54,
                backgroundColor: HomaGramTheme.turquoise.withValues(alpha: .14),
                backgroundImage: _avatarUrl == null ? null : NetworkImage(_avatarUrl!),
                child: _avatarUrl == null
                    ? const Icon(Icons.person_outline_rounded,
                        size: 52, color: HomaGramTheme.turquoise)
                    : null,
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  decoration: const BoxDecoration(
                    color: HomaGramTheme.royalPurple,
                    shape: BoxShape.circle,
                  ),
                  child: HomaGramSpringPress(child: IconButton(
                    onPressed: _uploadingAvatar ? null : _pickAvatar,
                    icon: _uploadingAvatar
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 19),
                  )),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          HomaGramSpringPress(child: TextButton.icon(
            onPressed: _uploadingAvatar ? null : _pickAvatar,
            icon: const Icon(Icons.add_a_photo_outlined, size: 18),
            label: Text(_uploadingAvatar ? _t.uploadingAvatar : _t.chooseProfilePhoto),
          )),
          Text(_t.avatarFormatLimit,
              style: TextStyle(fontSize: 11, color: Color(0xFF7A879B))),
        ],
      );

  Widget _identity(String email) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFF101B35), Color(0xFF263A62)],
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified_user_outlined, color: HomaGramTheme.turquoise, size: 32),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_t.accountActive,
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
                  const SizedBox(height: 5),
                  Text(email,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(color: Color(0xFFD6E8F0), fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 42, color: HomaGramTheme.royalPurple),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              HomaGramSpringPress(child: FilledButton(onPressed: _load, child: Text(_t.tryAgain))),
              HomaGramSpringPress(child: TextButton(onPressed: _signOut, child: Text(_t.signOut))),
            ],
          ),
        ),
      );
}


class CloseFriendsManagerSheet extends StatefulWidget {
  const CloseFriendsManagerSheet({super.key});

  @override
  State<CloseFriendsManagerSheet> createState() => _CloseFriendsManagerSheetState();
}

class _CloseFriendsManagerSheetState extends State<CloseFriendsManagerSheet> {
  AppLocalizations get _t => AppLocalizations.of(context)!;
  final _search = TextEditingController();
  List<Map<String, dynamic>> _candidates = [];
  Set<String> _selected = {};
  bool _loading = true;
  String? _savingId;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(() {
      if (mounted) setState(() => _query = _search.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait([
        StoryService.loadCloseFriendCandidates(),
        StoryService.loadCloseFriends(),
      ]);
      if (!mounted) return;
      setState(() {
        _candidates = values[0];
        _selected = values[1].map((row) => row['id'] as String).toSet();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(Map<String, dynamic> person) async {
    final id = person['id'] as String;
    if (_savingId != null) return;
    final adding = !_selected.contains(id);
    setState(() => _savingId = id);
    try {
      if (adding) {
        await StoryService.addCloseFriend(id);
      } else {
        await StoryService.removeCloseFriend(id);
      }
      if (!mounted) return;
      setState(() {
        if (adding) {
          _selected.add(id);
        } else {
          _selected.remove(id);
        }
        _savingId = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _savingId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t.closeFriendsUpdateFailed)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _candidates.where((person) {
      final username = (person['username'] ?? '').toString().toLowerCase();
      final name = (person['display_name'] ?? '').toString().toLowerCase();
      return _query.isEmpty || username.contains(_query) || name.contains(_query);
    }).toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * .72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(child: Text(_t.manageCloseFriends,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
              Text(_t.selectedPeople(_selected.length),
                style: const TextStyle(color: Color(0xFF20B8B0), fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 6),
            Text(_t.closeFriendsStoryDescription,
              style: TextStyle(height: 1.6, color: Color(0xFF7A879B), fontSize: 12)),
            const SizedBox(height: 14),
            TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: _t.searchFollowers,
                prefixIcon: Icon(Icons.search_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _candidates.isEmpty
                  ? Center(child: Text(_t.noFollowersToAdd))
                  : visible.isEmpty
                    ? Center(child: Text(_t.noSearchResults))
                    : ListView.separated(
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final person = visible[index];
                          final id = person['id'] as String;
                          final selected = _selected.contains(id);
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const CircleAvatar(child: Icon(Icons.person_outline_rounded)),
                            title: Row(mainAxisSize: MainAxisSize.min, children: [
                              Flexible(child: Text(person['display_name']?.toString() ?? _t.userLabel,
                                maxLines: 1, overflow: TextOverflow.ellipsis)),
                              const SizedBox(width: 4),
                              HomaGramVerifiedBadge(userId: id, size: 13),
                            ]),
                            subtitle: Text('@${person['username'] ?? _t.feedUserFallback}'),
                            trailing: _savingId == id
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                              : Switch(
                                  value: selected,
                                  onChanged: (_) => _toggle(person),
                                ),
                            onTap: _savingId == null ? () => _toggle(person) : null,
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }
}
