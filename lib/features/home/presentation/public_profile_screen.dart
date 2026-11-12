import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../auth/data/auth_service.dart';
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
  int _followers = 0;
  int _followingCount = 0;
  int _reposts = 0;

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
      final myFollow = await client.from('user_follows').select('following_id')
          .eq('follower_id', _myId).eq('following_id', widget.userId).maybeSingle();
      String? avatar;
      final avatarPath = profile['avatar_path'] as String?;
      if (avatarPath != null) {
        try { avatar = await client.storage.from('avatars').createSignedUrl(avatarPath, 3600); } catch (_) {}
      }
      final posts = <Map<String, dynamic>>[];
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
      if (!mounted) return;
      setState(() {
        _profile = Map<String, dynamic>.from(profile);
        _avatarUrl = avatar;
        _followers = followers.length;
        _followingCount = following.length;
        _reposts = reposts.length;
        _posts = posts;
        _following = myFollow != null;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'پروفایل دریافت نشد یا دسترسی به آن ممکن نیست.'; });
    }
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
      appBar: AppBar(title: const Text('پروفایل کاربر')),
      body: _loading ? const Center(child: CircularProgressIndicator())
          : _error != null ? Center(child: Text(_error!, textAlign: TextAlign.center))
          : RefreshIndicator(onRefresh: _load, child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              children: [
                _header(),
                const SizedBox(height: 18),
                Row(children: [
                  _stat('پست‌ها', _posts.length),
                  _stat('دنبال‌کننده', _followers),
                  _stat('دنبال‌شونده', _followingCount),
                  _stat('بازنشر', _reposts),
                ]),
                const SizedBox(height: 20),
                const Row(children: [
                  Icon(Icons.grid_on_rounded, size: 19, color: HomaGramTheme.turquoise),
                  SizedBox(width: 8),
                  Text('پست‌ها', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                ]),
                const SizedBox(height: 12),
                if (_posts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('هنوز پستی منتشر نشده است.', textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF8490A4))),
                  )
                else
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
                                  Image.network(url, fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
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

  Widget _stat(String label, int value) => Expanded(child: Column(children: [
    Text('$value', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
    const SizedBox(height: 4),
    Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF8490A4))),
  ]));

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
                child: Image.network(post['media_url'] as String, fit: BoxFit.contain)),
            ],
          ],
        ),
      ),
    );
  }
}
