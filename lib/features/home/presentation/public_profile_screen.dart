import 'package:homagram/app/presentation/homagram_branding.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme/app_theme.dart';
import '../../auth/data/auth_service.dart';
import '../../auth/presentation/profile_home_screen.dart';
import '../../messaging/data/messaging_service.dart';
import '../../messaging/presentation/chat_screen.dart';
import 'story_highlights.dart';
import 'feed_screen.dart' show PostCard;
import 'reels_screen.dart';
import '../../../core/utils/persian_date.dart';
import '../../../l10n/generated/app_localizations.dart';

class PublicProfileScreen extends StatefulWidget {
  const PublicProfileScreen({required this.userId, super.key});
  final String userId;

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  AppLocalizations get _t => AppLocalizations.of(context)!;
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
      final publicBirthday = await client.rpc(
        'get_public_profile_birthday',
        params: {'p_profile_id': widget.userId},
      );
      profile['public_birth_date'] = publicBirthday;
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
            .select('id,author_id,author_username,author_display_name,caption,media_path,media_type,cover_path,created_at,is_reel')
            .eq('author_id', widget.userId)
            .order('created_at', ascending: false).limit(60),
      ]);
      final followers = results[0] as List;
      final following = results[1] as List;
      final reposts = results[2] as List;
      final postRows = results[3] as List;
      final repostIds = reposts.map((r) => r['post_id'] as String).toList();
      final repostRows = repostIds.isEmpty ? <dynamic>[] : await client.from('posts')
          .select('id,author_id,author_username,author_display_name,caption,media_path,media_type,cover_path,created_at')
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
        final coverPath = post['cover_path'] as String?;
        if (coverPath != null) {
          try { post['cover_url'] = await client.storage.from('post-media').createSignedUrl(coverPath, 3600); } catch (_) {}
        }
        posts.add(post);
      }
      for (final row in repostRows) {
        final post = Map<String, dynamic>.from(row);
        final path = post['media_path'] as String?;
        if (path != null) {
          try { post['media_url'] = await client.storage.from('post-media').createSignedUrl(path, 3600); } catch (_) {}
        }
        final coverPath = post['cover_path'] as String?;
        if (coverPath != null) {
          try { post['cover_url'] = await client.storage.from('post-media').createSignedUrl(coverPath, 3600); } catch (_) {}
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
      if (mounted) setState(() { _loading = false; _error = _t.publicProfileLoadFailed; });
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
        SnackBar(content: Text(_t.followActionFailed)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visiblePosts = _section == 0
        ? _posts.where((post) => post['is_reel'] != true).toList()
        : _section == 1
            ? _posts.where((post) => post['is_reel'] == true).toList()
            : _repostPosts;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isMe ? _t.myProfile : _t.userProfile),
        actions: [
          if (_isMe) HomaGramSpringPress(child: IconButton(
            tooltip: _t.editProfileSettings,
            onPressed: _editProfile,
            icon: const Icon(Icons.edit_outlined),
          )),
        ],
      ),
      body: _loading ? const Center(child: CircularProgressIndicator())
          : _error != null ? Center(child: Text(_error!, textAlign: TextAlign.center))
          : HomaGramEntrance(child: RefreshIndicator(onRefresh: _load, child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              children: [
                _header(),
                const SizedBox(height: 18),
                Row(children: [
                  _stat(_t.posts, _posts.where((p) => p['is_reel'] != true).length),
                  _stat(_t.reels, _posts.where((p) => p['is_reel'] == true).length),
                  _stat(_t.follower, _followers, onTap: () => _showConnections(true)),
                  _stat(_t.following, _followingCount, onTap: () => _showConnections(false)),
                ]),
                const SizedBox(height: 14),
                StoryHighlightsStrip(ownerId: widget.userId, isOwner: _isMe),
                if (_isMe) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.visibility_outlined),
                      title: Text(_t.profileVisitors),
                      subtitle: Text(_visitorsEnabled
                          ? _t.profileVisitorCount(_visitorCount)
                          : _t.profileVisitorsDisabled),
                      trailing: const Icon(Icons.chevron_left_rounded),
                      onTap: _visitorsEnabled ? _showVisitors : null,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(child: _sectionButton(0, Icons.grid_on_rounded, _t.posts)),
                  Expanded(child: _sectionButton(1, Icons.play_circle_outline_rounded, _t.reels)),
                  Expanded(child: _sectionButton(2, Icons.repeat_rounded, _t.repostsCount(_reposts))),
                ]),
                const SizedBox(height: 14),
                if (visiblePosts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(30),
                    child: Text(
                      _section == 0 ? _t.noPostsYet
                          : _section == 1 ? _t.noReelsYet
                          : _t.noRepostsYet,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF8490A4)),
                    ),
                  )
                else
                  _profileMediaGrid(visiblePosts),
              ],
            ))),
    );
  }

  Widget _header() {
    final p = _profile!;
    final displayName = (p['display_name'] as String?)?.trim();
    final username = p['username'] as String? ?? 'user';
    final birthDate = p['public_birth_date'] as String?;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF273B70), Color(0xFF174D60), Color(0xFF101B35)],
        ),
        border: Border.all(color: HomaGramTheme.turquoise.withValues(alpha: .24)),
        boxShadow: [BoxShadow(color: HomaGramTheme.turquoise.withValues(alpha: .08),
          blurRadius: 24, offset: const Offset(0, 9))],
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF63D8E7), width: 2),
            boxShadow: [BoxShadow(color: const Color(0xFF63D8E7).withValues(alpha: .22), blurRadius: 18)],
          ),
          child: CircleAvatar(
            radius: 48,
            backgroundColor: const Color(0x223FD6D0),
            backgroundImage: _avatarUrl == null ? null : NetworkImage(_avatarUrl!),
            child: _avatarUrl == null
                ? const Icon(Icons.person_outline_rounded, size: 48, color: Colors.white70)
                : null,
          ),
        ),
        const SizedBox(height: 13),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: Text(
            displayName?.isNotEmpty == true ? displayName! : _t.homagramUser,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
          )),
          const SizedBox(width: 5),
          HomaGramVerifiedBadge(userId: widget.userId, size: 19),
        ]),
        const SizedBox(height: 5),
        Text('@$username', textDirection: TextDirection.ltr,
          style: const TextStyle(color: Color(0xFFD6E8F0), fontSize: 12)),
        if (birthDate != null && birthDate.isNotEmpty) ...[
          const SizedBox(height: 11),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cake_outlined, size: 15, color: Color(0xFFB9DDE8)),
            const SizedBox(width: 6),
            Text(_t.bornOn(persianDate(DateTime.parse(birthDate))),
              style: const TextStyle(color: Color(0xFFD6E8F0), fontSize: 12)),
          ]),
        ],
        if ((p['bio'] as String? ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(p['bio'] as String, textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, height: 1.8, fontSize: 12)),
        ],
        const SizedBox(height: 17),
        if (_isMe)
          SizedBox(width: double.infinity, child: HomaGramSpringPress(child: FilledButton.icon(
            onPressed: _editProfile,
            icon: const Icon(Icons.edit_outlined),
            label: Text(_t.editProfile),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF35BDB6),
              foregroundColor: const Color(0xFF081A2A),
            ),
          )))
        else
          Row(children: [
            Expanded(child: HomaGramSpringPress(child: FilledButton(
              onPressed: _busy ? null : _toggleFollow,
              child: _busy ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_following ? _t.followingAction : _t.follow),
            ))),
            const SizedBox(width: 9),
            Expanded(child: HomaGramSpringPress(child: OutlinedButton.icon(
              onPressed: _openMessage,
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
              label: const Text(_t.message),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
              ),
            ))),
          ]),
        Align(
          alignment: Alignment.center,
          child: TextButton.icon(
            onPressed: _shareProfile,
            icon: const Icon(Icons.ios_share_rounded, color: Colors.white70, size: 16),
            label: const Text(_t.shareProfile, style: TextStyle(color: Colors.white70, fontSize: 11)),
          ),
        ),
      ]),
    );
  }

  Future<void> _openMessage() async {
    try {
      final id = await MessagingService.createDirectConversation(widget.userId);
      if (!mounted) return;
      final name = (_profile?['display_name'] as String?)?.trim();
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          conversationId: id,
          title: name?.isNotEmpty == true ? name! : _t.privateConversation,
        ),
      ));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t.startConversationFailed)),
      );
    }
  }

  Future<void> _shareProfile() async {
    final username = _profile?['username'] as String? ?? 'user';
    final name = _profile?['display_name'] as String? ?? _t.homagramUser;
    await SharePlus.instance.share(ShareParams(text: _t.profileShareText(name, username)));
  }

  Widget _profileMediaGrid(List<Map<String, dynamic>> items) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: items.length,
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3,
      crossAxisSpacing: 4,
      mainAxisSpacing: 4,
    ),
    itemBuilder: (context, index) {
      final post = items[index];
      final url = post['media_url'] as String?;
      final isVideo = post['media_type'] == 'video' || post['is_reel'] == true;
      return GestureDetector(
        onTap: () => _showPost(post),
        child: Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: url == null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    (post['caption'] as String? ?? '').isEmpty ? _t.textPost : post['caption'] as String,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11),
                  ),
                ))
              : Stack(fit: StackFit.expand, children: [
                  isVideo
                      ? (post['cover_url'] != null
                          ? Image.network(post['cover_url'] as String, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(Icons.play_circle_fill_rounded))
                          : Container(
                              color: const Color(0xFF171C2B),
                              child: const Center(child: Icon(Icons.play_circle_fill_rounded,
                                size: 38, color: Colors.white)),
                            ))
                      : Image.network(url, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
                  if (isVideo)
                    const Positioned(right: 6, top: 6,
                      child: Icon(Icons.play_arrow_rounded, color: Colors.white)),
                ]),
        ),
      );
    },
  );

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
              followers ? _t.followers : _t.followingList,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            Expanded(child: ordered.isEmpty
              ? Center(child: Text(_t.emptyConnections))
              : ListView.builder(itemCount: ordered.length, itemBuilder: (context, index) {
                  final p = ordered[index];
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                    title: Row(mainAxisSize: MainAxisSize.min, children: [
                      Flexible(child: Text(p['display_name'] as String? ?? _t.homagramUser,
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 4),
                      HomaGramVerifiedBadge(userId: p['id'] as String?),
                    ]),
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
        const SnackBar(content: Text(_t.loadConnectionsFailed)));
    }
  }

  Future<void> _showVisitors() async {
    if (!_visitorsEnabled) return;
    await showModalBottomSheet<void>(
      context: context, showDragHandle: true, isScrollControlled: true,
      builder: (sheetContext) => SafeArea(child: SizedBox(
        height: MediaQuery.of(sheetContext).size.height * .72,
        child: Column(children: [
          Padding(padding: const EdgeInsets.all(16), child: Text(_t.profileVisitors,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          Expanded(child: _visitors.isEmpty
            ? Center(child: Text(_t.noProfileVisitorsYet))
            : ListView.builder(itemCount: _visitors.length, itemBuilder: (context, index) {
                final visitor = _visitors[index];
                final date = DateTime.tryParse(visitor['viewed_at'] as String? ?? '')?.toLocal();
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                  title: Text(visitor['display_name'] as String? ?? _t.homagramUser),
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
    if (post['media_type'] == 'video' || post['is_reel'] == true) {
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ReelsScreen(initialReelId: post['id'] as String),
      ));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(_t.viewPost)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
          children: [
            PostCard(post: post),
          ],
        ),
      ),
    ));
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
