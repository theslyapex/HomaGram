import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../data/auth_service.dart';
import '../../home/data/story_service.dart';

class ProfileHomeScreen extends StatefulWidget {
  const ProfileHomeScreen({this.onCompleted, super.key});

  final VoidCallback? onCompleted;

  @override
  State<ProfileHomeScreen> createState() => _ProfileHomeScreenState();
}

class _ProfileHomeScreenState extends State<ProfileHomeScreen> {
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _bio = TextEditingController();
  final _picker = ImagePicker();

  bool _loading = true;
  bool _saving = false;
  bool _uploadingAvatar = false;
  bool _private = false;
  bool _showFollowers = true;
  bool _showFollowing = true;
  bool _showProfileVisitors = true;
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
      final profile = rows[0];
      _username.text = (profile['username'] ?? '') as String;
      _name.text = (profile['display_name'] ?? '') as String;
      _bio.text = (profile['bio'] ?? '') as String;
      _avatarPath = profile['avatar_path'] as String?;
      _onboarding = profile['profile_completed_at'] == null;
      _private = rows[1]['is_private'] as bool? ?? false;
      _showFollowers = rows[1]['show_followers'] as bool? ?? true;
      _showFollowing = rows[1]['show_following'] as bool? ?? true;
      _showProfileVisitors = rows[1]['show_profile_visitors'] as bool? ?? true;
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
      _error = 'اطلاعات حساب دریافت نشد. اتصال و دسترسی دیتابیس را بررسی کنید.';
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
        _message('حجم تصویر باید کمتر از ۵ مگابایت باشد.', error: true);
        return;
      }
      final mime = file.mimeType ?? _mimeFromName(file.name);
      if (!const ['image/jpeg', 'image/png', 'image/webp'].contains(mime)) {
        _message('فرمت تصویر باید JPG، PNG یا WEBP باشد.', error: true);
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
      _message('تصویر پروفایل با موفقیت به‌روزرسانی شد.');
    } on StorageException catch (e) {
      _message('بارگذاری تصویر انجام نشد: ${e.message}', error: true);
    } catch (_) {
      _message('بارگذاری تصویر انجام نشد. دوباره تلاش کنید.', error: true);
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
      _message('نام نمایشی باید ۱ تا ۵۰ و بیو حداکثر ۱۶۰ نویسه باشد.', error: true);
      return;
    }
    if (!RegExp(r'^[a-z0-9_]{3,24}$').hasMatch(username)) {
      _message('نام کاربری باید ۳ تا ۲۴ نویسه و فقط شامل حروف انگلیسی کوچک، عدد و زیرخط باشد.', error: true);
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
      if (!mounted) return;
      setState(() => _onboarding = false);
      _message('پروفایل ذخیره شد.');
      widget.onCompleted?.call();
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        _message('این نام کاربری قبلاً انتخاب شده است.', error: true);
      } else {
        _message('ذخیره پروفایل انجام نشد. دوباره تلاش کنید.', error: true);
      }
    } catch (_) {
      _message('ذخیره پروفایل انجام نشد.', error: true);
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
      _message(value ? 'تنظیم حساب خصوصی ذخیره شد.' : 'تنظیم حساب عمومی ذخیره شد.');
    } catch (_) {
      if (mounted) setState(() => _private = !value);
      _message('ذخیره تنظیم حریم خصوصی انجام نشد.', error: true);
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
      _message('تنظیم حریم خصوصی ذخیره شد.');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (column == 'show_followers') _showFollowers = previous;
        if (column == 'show_following') _showFollowing = previous;
        if (column == 'show_profile_visitors') _showProfileVisitors = previous;
      });
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
    } catch (_) {
      _message('خروج از نشست انجام نشد. دوباره تلاش کنید.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = AuthService.client.auth.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(_onboarding ? 'راه‌اندازی حساب' : 'حساب HomaGram'),
        actions: [
          IconButton(
            tooltip: 'خروج از این دستگاه',
            onPressed: _signOut,
            icon: const Icon(Icons.logout_rounded),
          ),
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
                              const Text('اطلاعات پروفایل',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 18),
                              Center(child: _avatarPicker()),
                              const SizedBox(height: 20),
                              TextField(
                                controller: _name,
                                maxLength: 50,
                                decoration: const InputDecoration(
                                  labelText: 'نام نمایشی',
                                  prefixIcon: Icon(Icons.person_outline),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _username,
                                maxLength: 24,
                                textDirection: TextDirection.ltr,
                                decoration: const InputDecoration(
                                  labelText: 'نام کاربری',
                                  prefixText: '@ ',
                                  prefixIcon: Icon(Icons.alternate_email),
                                  helperText: '۳ تا ۲۴ نویسه؛ حروف انگلیسی کوچک، عدد و زیرخط',
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _bio,
                                maxLength: 160,
                                maxLines: 3,
                                decoration: const InputDecoration(
                                  labelText: 'بیوگرافی',
                                  prefixIcon: Icon(Icons.notes_rounded),
                                  alignLabelWithHint: true,
                                ),
                              ),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: _saving ? null : _saveProfile,
                                child: Text(_saving
                                    ? 'در حال ذخیره...'
                                    : _onboarding
                                        ? 'تکمیل و ذخیره پروفایل'
                                        : 'ذخیره تغییرات'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: SwitchListTile(
                          value: _private,
                          onChanged: _setPrivacy,
                          title: const Text('حساب خصوصی'),
                          subtitle: const Text(
                            'حالت خصوصی ذخیره می‌شود؛ محدودیت نمایش محتوا و فید خصوصی در مرحله بعد تکمیل می‌شود.',
                          ),
                          secondary: const Icon(Icons.lock_outline),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.people_alt_outlined),
                          title: const Text('دوستان نزدیک',
                              style: TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: const Text('فهرست خصوصی دوستان نزدیکت را مدیریت کن؛ فقط خودت آن را می‌بینی.'),
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
                              const ListTile(
                                leading: Icon(Icons.visibility_off_outlined),
                                title: Text('حریم خصوصی فهرست‌ها',
                                    style: TextStyle(fontWeight: FontWeight.w800)),
                                subtitle: Text('کنترل کن دیگران کدام فهرست‌های ارتباطی را ببینند.'),
                              ),
                              SwitchListTile(
                                value: _showFollowers,
                                onChanged: (value) => _setVisibility('show_followers', value),
                                title: const Text('نمایش دنبال‌کنندگان'),
                                subtitle: const Text('با خاموش‌کردن، فهرست دنبال‌کنندگان برای دیگران پنهان می‌شود.'),
                              ),
                              SwitchListTile(
                                value: _showFollowing,
                                onChanged: (value) => _setVisibility('show_following', value),
                                title: const Text('نمایش دنبال‌شوندگان'),
                                subtitle: const Text('با خاموش‌کردن، فهرست دنبال‌شوندگان برای دیگران پنهان می‌شود.'),
                              ),
                              const Divider(height: 1),
                              SwitchListTile(
                                value: _showProfileVisitors,
                                onChanged: (value) => _setVisibility('show_profile_visitors', value),
                                title: const Text('اجازه نمایش بازدیدکنندگان پروفایل'),
                                subtitle: const Text('با روشن‌بودن این گزینه، فهرست بازدیدکنندگان در پروفایل خودت قابل مشاهده است.'),
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
                              const Text('مدیریت نشست‌ها',
                                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                              const SizedBox(height: 6),
                              const Text(
                                'می‌توانید نشست‌های دیگر را از حساب خارج کنید.',
                                style: TextStyle(height: 1.7, color: Color(0xFF64718A)),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: () => _signOut(otherDevices: true),
                                icon: const Icon(Icons.devices_rounded),
                                label: const Text('خروج از سایر دستگاه‌ها'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Center(
                        child: Text('HomaGram • حساب کاربری',
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
        child: const Row(
          children: [
            Icon(Icons.auto_awesome_rounded, color: HomaGramTheme.turquoise),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'فقط یک‌بار این اطلاعات را تکمیل کنید. دفعات بعد با حفظ نشست، مستقیم وارد حساب می‌شوید.',
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
                  child: IconButton(
                    onPressed: _uploadingAvatar ? null : _pickAvatar,
                    icon: _uploadingAvatar
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 19),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _uploadingAvatar ? null : _pickAvatar,
            icon: const Icon(Icons.add_a_photo_outlined, size: 18),
            label: Text(_uploadingAvatar ? 'در حال بارگذاری تصویر...' : 'انتخاب تصویر پروفایل'),
          ),
          const Text('JPG، PNG یا WEBP • حداکثر ۵ مگابایت',
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
                  const Text('حساب شما فعال است',
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
              FilledButton(onPressed: _load, child: const Text('تلاش دوباره')),
              TextButton(onPressed: _signOut, child: const Text('خروج از حساب')),
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
          const SnackBar(content: Text('به‌روزرسانی فهرست دوستان نزدیک انجام نشد.')),
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
              const Expanded(child: Text('مدیریت دوستان نزدیک',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
              Text('${_selected.length} نفر',
                style: const TextStyle(color: Color(0xFF20B8B0), fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 6),
            const Text('افرادی را انتخاب کن که بتوانند استوری‌های مخصوص دوستان نزدیک را ببینند.',
              style: TextStyle(height: 1.6, color: Color(0xFF7A879B), fontSize: 12)),
            const SizedBox(height: 14),
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                hintText: 'جست‌وجو میان دنبال‌کنندگان',
                prefixIcon: Icon(Icons.search_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _candidates.isEmpty
                  ? const Center(child: Text('هنوز دنبال‌کننده‌ای برای افزودن وجود ندارد.'))
                  : visible.isEmpty
                    ? const Center(child: Text('نتیجه‌ای پیدا نشد.'))
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
                            title: Text(person['display_name']?.toString() ?? 'کاربر'),
                            subtitle: Text('@${person['username'] ?? 'user'}'),
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
