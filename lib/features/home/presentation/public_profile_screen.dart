import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../app/theme/app_theme.dart';
import '../../auth/data/auth_service.dart';
import '../../auth/presentation/profile_home_screen.dart';
import '../../../core/utils/persian_date.dart';

class PublicProfileScreen extends StatefulWidget {
  const PublicProfileScreen({required this.userId, super.key});
  final String userId;

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  bool _loading = true;
  bool _following = false;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _profile;
  String? _avatarUrl;
  List<Map<String, dynamic>> _posts = [];
  List<Map<String, dynamic>> _repostPosts = [];
  int _followers = 0;
  int _followingCount = 0;
  int _reposts = 0;
  int _section = 0;
  int _visitorCount = 0;
  bool _visitorsEnabled = true;
  List<Map<String, dynamic>> _visitors = [];

  String get _myId => AuthService.client.auth.currentUser!.id;
  bool get _isMe => _myId == widget.userId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final client = AuthService.client;
      final profile = await client.from('profiles')
          .select('id,username,display_name,bio,avatar_path,created_at')
          .eq('id', widget.userId).single();
      if (!_isMe) {
        await client.from('profile_views').upsert({
          'profile_id': widget.userId,
          'viewer_id': _myId,
          'viewed_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'profile_id,viewer_id');
      }
      final results = await Future.wait([
        client.from('user_follows').select('follower_id')
            .eq('following_id', widget.userId),
        client.from('user_follows').select('following_id')
            .eq('follower_id', widget.userId),
        client.from('post_reposts').select('post_id')
            .eq('user_id', widget.userId),
        client.from('posts')
            .select('id,author_id,author_username,author_display_name,caption,media_path,media_type,created_at')
            .eq('author_id', widget.userId)
            .order('created_at', ascending: false).limit(60),
      ]);
      final followers = results[0] as List;
      final following = results[1] as List;
      final reposts = results[2] as List;
      final postRows = results[3] as List;
      final repostIds = reposts.map((r) => r['post_id'] as String).toList();
      final repostRows = repostIds.isEmpty ? <dynamic>[] : await client.from('posts')
          .select('id,author_id,author_username,author_display_name,caption,media_path,media_type,created_at')
          .inFilter('id', repostIds).order('created_at', ascending: false);
      final myFollow = await client.from('user_follows').select('following_id')
          .eq('follower_id', _myId).eq('following_id', widget.userId).maybeSingle();

      var visitorsEnabled = true;
      var visitorProfiles = <Map<String, dynamic>>[];
      if (_isMe) {
        final settings = await client.from('account_settings')
            .select('show_profile_visitors')
            .eq('user_id', _myId).maybeSingle();
        visitorsEnabled = settings?['show_profile_visitors'] as bool? ?? true;
        if (visitorsEnabled) {
          final visitRows = await client.from('profile_views')
              .select('viewer_id,viewed_at')
              .eq('profile_id', _myId)
              .order('viewed_at', ascending: false)
              .limit(100);
          final visitorIds = visitRows.map<String>((r) => r['viewer_id'] as String).toList();
          final visitorRows = visitorIds.isEmpty
              ? <dynamic>[]
              : await client.from('profiles')
                  .select('id,username,display_name')
                  .inFilter('id', visitorIds);
          final byId = {for (final p in visitorRows) p['id'] as String: p};
          visitorProfiles = visitRows.map((r) {
            final p = byId[r['viewer_id'] as String];
            if (p == null) return null;
            return <String, dynamic>{
              ...Map<String, dynamic>.from(p),
              'viewed_at': r['viewed_at'],
            };
          }).whereType<Map<String, dynamic>>().toList();
        }
      }
      String? avatar;
      final avatarPath = profile['avatar_path'] as String?;
      if (avatarPath != null) {
        try { avatar = await client.storage.from('avatars').createSignedUrl(avatarPath, 3600); } catch (_) {}
      }
      final posts = <Map<String, dynamic>>[];
      final repostPostList = <Map<String, dynamic>>[];
      for (final row in postRows) {
        final post = Map<String, dynamic>.from(row);
        final path = post['media_path'] as String?;
        if (path != null) {
          try {
            post['media_url'] = await client.storage.from('post-media').createSignedUrl(path, 3600);
          } catch (_) {}
        }
        posts.add(post);
      }
      for (final row in repostRows) {
        final post = Map<String, dynamic>.from(row);
        final path = post['media_path'] as String?;
        if (path != null) {
          try { post['media_url'] = await client.storage.from('post-media').createSignedUrl(path, 3600); } catch (_) {}
        }
        repostPostList.add(post);
      }
      if (!mounted) return;
      setState(() {
        _profile = Map<String, dynamic>.from(profile);
        _avatarUrl = avatar;
        _followers = followers.length;
        _followingCount = following.length;
        _reposts = reposts.length;
        _visitorsEnabled = visitorsEnabled;
        _visitors = visitorProfiles;
        _visitorCount = visitorProfiles.length;
        _posts = posts;
        _repostPosts = repostPostList;
        _following = myFollow != null;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'پروفایل دریافت نشد یا دسترسی به آن ممکن نیست.'; });
    }
  }

  Future<void> _editProfile() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const ProfileHomeScreen(),
    ));
    if (mounted) await _load();
  }

  Future<void> _toggleFollow() async {
    if (_busy || _isMe) return;
    setState(() => _busy = true);
    try {
      final client = AuthService.client;
      if (_following) {
        await client.from('user_follows').delete()
            .eq('follower_id', _myId).eq('following_id', widget.userId);
        setState(() { _following = false; if (_followers > 0) _followers--; });
      } else {
        await client.from('user_follows').insert({
          'follower_id': _myId, 'following_id': widget.userId,
        });
        setState(() { _following = true; _followers++; });
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('عملیات دنبال‌کردن انجام نشد. دوباره تلاش کنید.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isMe ? 'پروفایل من' : 'پروفایل کاربر'),
        actions: [
          if (_isMe) IconButton(
            tooltip: 'ویرایش پروفایل و تنظیمات حساب',
            onPressed: _editProfile,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: _loading ? const Center(child: CircularProgressIndicator())
          : _error != null ? Center(child: Text(_error!, textAlign: TextAlign.center))
          : RefreshIndicator(onRefresh: _load, child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              children: [
                _header(),
                const SizedBox(height: 18),
                Row(children: [
                  _stat('پست‌ها', _posts.length),
                  _stat('دنبال‌کننده', _followers, onTap: () => _showConnections(true)),
                  _stat('دنبال‌شونده', _followingCount, onTap: () => _showConnections(false)),
                  _stat('بازنشر', _reposts),
                  if (_isMe) _stat('بازدیدکننده', _visitorsEnabled ? _visitorCount : 0,
                      onTap: _visitorsEnabled ? _showVisitors : null),
                ]),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(child: _sectionButton(0, Icons.grid_on_rounded, 'پست‌ها')),
                  Expanded(child: _sectionButton(1, Icons.repeat_rounded, 'بازنشرها')),
                ]),
                const SizedBox(height: 14),
                if (_section == 1 && _repostPosts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('هنوز بازنشری ثبت نشده است.', textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF8490A4))),
                  )
                else if (_section == 1)
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _repostPosts.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3, crossAxisSpacing: 4, mainAxisSpacing: 4,
                    ),
                    itemBuilder: (context, index) {
                      final post = _repostPosts[index];
                      final url = post['media_url'] as String?;
                      return GestureDetector(
                        onTap: () => _showPost(post),
                        child: Container(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          child: url == null
                            ? Center(child: Padding(padding: const EdgeInsets.all(8),
                                child: Text((post['caption'] as String? ?? '').isEmpty ? 'پست متنی' : post['caption'] as String,
                                  maxLines: 5, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 11))))
                            : Stack(fit: StackFit.expand, children: [
                                (post['media_type'] == 'video'
                                      ? Container(color: const Color(0xFF171C2B),
                                          child: const Center(child: Icon(Icons.play_circle_fill_rounded,
                                            size: 38, color: Colors.white)))
                                      : Image.network(url, fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined))),
                                if (post['media_type'] == 'video')
                                  const Positioned(right: 6, top: 6,
                                    child: Icon(Icons.play_arrow_rounded, color: Colors.white)),
                              ]),
                        ),
                      );
                    },
                  ),
                if (_section == 0 && _posts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('هنوز پستی منتشر نشده است.', textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF8490A4))),
                  )
                else if (_section == 0)
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _posts.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3, crossAxisSpacing: 4, mainAxisSpacing: 4,
                    ),
                    itemBuilder: (context, index) {
                      final post = _posts[index];
                      final url = post['media_url'] as String?;
                      return GestureDetector(
                        onTap: () => _showPost(post),
                        child: Container(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          child: url == null
                              ? Center(child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text((post['caption'] as String? ?? '').isEmpty ? 'پست متنی' : post['caption'] as String,
                                      maxLines: 5, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 11)),
                                ))
                              : Stack(fit: StackFit.expand, children: [
                                  (post['media_type'] == 'video'
                                      ? Container(color: const Color(0xFF171C2B),
                                          child: const Center(child: Icon(Icons.play_circle_fill_rounded,
                                            size: 38, color: Colors.white)))
                                      : Image.network(url, fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined))),
                                  if (post['media_type'] == 'video')
                                    const Positioned(right: 6, top: 6,
                                      child: Icon(Icons.play_arrow_rounded, color: Colors.white)),
                                ]),
                        ),
                      );
                    },
                  ),
              ],
            )),
    );
  }

  Widget _header() {
    final p = _profile!;
    return Column(children: [
      CircleAvatar(
        radius: 48,
        backgroundColor: HomaGramTheme.turquoise.withValues(alpha: .14),
        backgroundImage: _avatarUrl == null ? null : NetworkImage(_avatarUrl!),
        child: _avatarUrl == null
            ? const Icon(Icons.person_outline_rounded, size: 48, color: HomaGramTheme.turquoise)
            : null,
      ),
      const SizedBox(height: 12),
      Text(p['display_name'] as String? ?? 'کاربر HomaGram',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
      const SizedBox(height: 4),
      Text('@${p['username'] ?? 'user'}', textDirection: TextDirection.ltr,
          style: const TextStyle(color: Color(0xFF8490A4))),
      if ((p['bio'] as String? ?? '').trim().isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(p['bio'] as String, textAlign: TextAlign.center,
            style: const TextStyle(height: 1.8)),
      ],
      if (!_isMe) ...[
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: FilledButton(
          onPressed: _busy ? null : _toggleFollow,
          child: _busy ? const SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_following ? 'دنبال می‌کنید' : 'دنبال کردن'),
        )),
      ],
    ]);
  }



  Widget _sectionButton(int index, IconData icon, String label) {
    final selected = _section == index;
    return InkWell(
      onTap: () => setState(() => _section = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(
          color: selected ? HomaGramTheme.turquoise : Colors.transparent, width: 2.5,
        ))),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 19, color: selected ? HomaGramTheme.turquoise : const Color(0xFF8490A4)),
          const SizedBox(width: 7),
          Text(label, style: TextStyle(fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _stat(String label, int value, {VoidCallback? onTap}) => Expanded(
    child: InkWell(onTap: onTap, child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(children: [
        Text('$value', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF8490A4))),
      ]),
    )),
  );

  Future<void> _showConnections(bool followers) async {
    try {
      final client = AuthService.client;
      final rows = followers
          ? await client.from('user_follows').select('follower_id').eq('following_id', widget.userId)
          : await client.from('user_follows').select('following_id').eq('follower_id', widget.userId);
      final ids = rows.map<String>((row) => (followers ? row['follower_id'] : row['following_id']) as String).toList();
      final profiles = ids.isEmpty ? <dynamic>[] : await client.from('profiles')
          .select('id,username,display_name').inFilter('id', ids);
      final byId = {for (final p in profiles) p['id'] as String: p};
      final ordered = ids.map((id) => byId[id]).whereType<Map<String, dynamic>>().toList();
      if (!mounted) return;
      await showModalBottomSheet<void>(context: context, showDragHandle: true, isScrollControlled: true,
        builder: (sheetContext) => SafeArea(child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * .72,
          child: Column(children: [
            Padding(padding: const EdgeInsets.all(16), child: Text(
              followers ? 'دنبال‌کنندگان' : 'دنبال‌شوندگان',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            Expanded(child: ordered.isEmpty
              ? const Center(child: Text('هنوز کاربری در این فهرست نیست.'))
              : ListView.builder(itemCount: ordered.length, itemBuilder: (context, index) {
                  final p = ordered[index];
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                    title: Text(p['display_name'] as String? ?? 'کاربر HomaGram'),
                    subtitle: Text('@${p['username'] ?? 'user'}'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(this.context).push(MaterialPageRoute<void>(
                        builder: (_) => PublicProfileScreen(userId: p['id'] as String)));
                    },
                  );
                })),
          ]),
        )),
      );
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('دریافت فهرست کاربران انجام نشد.')));
    }
  }

  Future<void> _showVisitors() async {
    if (!_visitorsEnabled) return;
    await showModalBottomSheet<void>(
      context: context, showDragHandle: true, isScrollControlled: true,
      builder: (sheetContext) => SafeArea(child: SizedBox(
        height: MediaQuery.of(sheetContext).size.height * .72,
        child: Column(children: [
          const Padding(padding: EdgeInsets.all(16), child: Text('بازدیدکنندگان پروفایل',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          Expanded(child: _visitors.isEmpty
            ? const Center(child: Text('هنوز بازدیدکننده‌ای ثبت نشده است.'))
            : ListView.builder(itemCount: _visitors.length, itemBuilder: (context, index) {
                final visitor = _visitors[index];
                final date = DateTime.tryParse(visitor['viewed_at'] as String? ?? '')?.toLocal();
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                  title: Text(visitor['display_name'] as String? ?? 'کاربر HomaGram'),
                  subtitle: Text('@' + (visitor['username'] as String? ?? 'user') +
                    (date == null ? '' : ' · ' + persianDate(date))),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(this.context).push(MaterialPageRoute<void>(
                      builder: (_) => PublicProfileScreen(userId: visitor['id'] as String)));
                  },
                );
              })),
        ]),
      )),
    );
  }

  void _showPost(Map<String, dynamic> post) {
    final date = DateTime.tryParse(post['created_at'] as String? ?? '')?.toLocal();
    showModalBottomSheet<void>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(date == null ? '' : persianDate(date),
                style: const TextStyle(color: Color(0xFF8490A4))),
            const SizedBox(height: 10),
            if ((post['caption'] as String? ?? '').isNotEmpty)
              Text(post['caption'] as String, style: const TextStyle(height: 1.8)),
            if (post['media_url'] != null) ...[
              const SizedBox(height: 12),
              ClipRRect(borderRadius: BorderRadius.circular(14),
                child: post['media_type'] == 'video'
                    ? _ProfileVideo(url: post['media_url'] as String)
                    : Image.network(post['media_url'] as String, fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, size: 40))),
            ],
          ],
        ),
      ),
    );
  }
}


class _ProfileVideo extends StatefulWidget {
  const _ProfileVideo({required this.url});
  final String url;

  @override
  State<_ProfileVideo> createState() => _ProfileVideoState();
}

class _ProfileVideoState extends State<_ProfileVideo> {
  late final VideoPlayerController _controller;
  late final Future<void> _initialized;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _initialized = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _initialized,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const SizedBox(height: 220,
          child: Center(child: Icon(Icons.broken_image_outlined, size: 40)));
      }
      if (snapshot.connectionState != ConnectionState.done) {
        return const SizedBox(height: 220,
          child: Center(child: CircularProgressIndicator()));
      }
      return GestureDetector(
        onTap: () => setState(() {
          _controller.value.isPlaying ? _controller.pause() : _controller.play();
        }),
        child: AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: Stack(alignment: Alignment.center, children: [
            VideoPlayer(_controller),
            if (!_controller.value.isPlaying)
              const Icon(Icons.play_circle_fill_rounded, size: 58, color: Colors.white),
          ]),
        ),
      );
    },
  );
}
