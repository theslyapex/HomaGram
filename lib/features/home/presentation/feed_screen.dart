import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme/app_theme.dart';
import '../../auth/data/auth_service.dart';
import 'create_post_screen.dart';
import 'public_profile_screen.dart';
import '../../../core/utils/persian_date.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  late Future<List<Map<String, dynamic>>> _posts;

  @override
  void initState() {
    super.initState();
    _posts = _loadPosts();
  }

  Future<List<Map<String, dynamic>>> _loadPosts() async {
    final rows = await AuthService.client
        .from('posts')
        .select('id,author_id,author_username,author_display_name,caption,media_path,media_type,created_at')
        .order('created_at', ascending: false)
        .limit(50);
    final authorIds = rows.map((row) => row['author_id'] as String).toSet().toList();
    final profiles = authorIds.isEmpty
        ? <dynamic>[]
        : await AuthService.client.from('profiles')
            .select('id,avatar_path')
            .inFilter('id', authorIds);
    final profileById = <String, Map<String, dynamic>>{
      for (final profile in profiles)
        profile['id'] as String: Map<String, dynamic>.from(profile),
    };
    final result = <Map<String, dynamic>>[];
    for (final item in rows) {
      final post = Map<String, dynamic>.from(item);
      final author = profileById[post['author_id'] as String];
      final avatarPath = author?['avatar_path'] as String?;
      if (avatarPath != null) {
        try {
          post['author_avatar_url'] = await AuthService.client.storage
              .from('avatars').createSignedUrl(avatarPath, 3600);
        } catch (_) {}
      }
      final path = post['media_path'] as String?;
      if (path != null) {
        try {
          post['media_url'] = await AuthService.client.storage
              .from('post-media')
              .createSignedUrl(path, 3600);
        } catch (_) {
          post['media_unavailable'] = true;
        }
      }
      result.add(post);
    }
    return result;
  }

  Future<void> _refresh() async {
    final next = _loadPosts();
    setState(() => _posts = next);
    await next;
  }

  Future<void> _createPost() async {
    final published = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const CreatePostScreen()),
    );
    if (published == true && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
        child: InkWell(
          onTap: _createPost,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: .2)),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 20,
                  backgroundColor: Color(0x223FD6D0),
                  child: Icon(Icons.person_outline, color: HomaGramTheme.turquoise),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('چیزی برای گفتن دارید؟', style: TextStyle(color: Color(0xFF8490A4))),
                ),
                IconButton(
                  tooltip: 'ایجاد پست',
                  onPressed: _createPost,
                  icon: const Icon(Icons.add_circle_rounded, color: HomaGramTheme.turquoise, size: 29),
                ),
              ],
            ),
          ),
        ),
      ),
      Expanded(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _posts,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _stateMessage(
                icon: Icons.cloud_off_outlined,
                title: 'فید بارگذاری نشد',
                message: 'اتصال را بررسی کنید و دوباره تلاش کنید.',
                action: TextButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('تلاش دوباره')),
              );
            }
            final posts = snapshot.data ?? [];
            if (posts.isEmpty) {
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(28, 60, 28, 30),
                  children: [
                    const Icon(Icons.dynamic_feed_outlined, size: 62, color: HomaGramTheme.turquoise),
                    const SizedBox(height: 18),
                    const Text('هنوز پستی منتشر نشده', textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    const Text('اولین پست HomaGram را منتشر کنید و فید را شکل دهید.',
                        textAlign: TextAlign.center, style: TextStyle(height: 1.8, color: Color(0xFF7A879B))),
                    const SizedBox(height: 14),
                    Center(child: FilledButton.icon(onPressed: _createPost,
                        icon: const Icon(Icons.add), label: const Text('ایجاد اولین پست'))),
                  ],
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
                itemCount: posts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) => _PostCard(post: posts[index], onDeleted: () => _refresh()),
              ),
            );
          },
        ),
      ),
    ],
  );

  Widget _stateMessage({required IconData icon, required String title, required String message, Widget? action}) =>
      Center(child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: HomaGramTheme.turquoise),
          const SizedBox(height: 14),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(height: 1.8, color: Color(0xFF7A879B))),
          if (action != null) action,
        ]),
      ));
}

class _PostCard extends StatefulWidget {
  const _PostCard({required this.post, this.onDeleted});
  final Map<String, dynamic> post;
  final VoidCallback? onDeleted;
  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard> {
  bool _liked = false, _saved = false, _reposted = false, _busy = false;
  int _likes = 0, _comments = 0;
  String get _userId => AuthService.client.auth.currentUser!.id;
  String get _postId => widget.post['id'] as String;

  @override
  void initState() { super.initState(); _loadInteractionState(); }

  Future<void> _loadInteractionState() async {
    try {
      final c = AuthService.client;
      final results = await Future.wait([
        c.from('post_likes').select('user_id').eq('post_id', _postId),
        c.from('post_comments').select('id').eq('post_id', _postId),
        c.from('post_likes').select('post_id').eq('post_id', _postId).eq('user_id', _userId).maybeSingle(),
        c.from('saved_posts').select('post_id').eq('post_id', _postId).eq('user_id', _userId).maybeSingle(),
        c.from('post_reposts').select('post_id').eq('post_id', _postId).eq('user_id', _userId).maybeSingle(),
      ]);
      if (!mounted) return;
      setState(() {
        _likes = (results[0] as List).length;
        _comments = (results[1] as List).length;
        _liked = results[2] != null; _saved = results[3] != null; _reposted = results[4] != null;
      });
    } catch (_) {}
  }

  Future<void> _toggle(String table, bool current, void Function(bool) update) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final q = AuthService.client.from(table);
      if (current) {
        await q.delete().eq('post_id', _postId).eq('user_id', _userId);
      } else {
        await q.insert({'post_id': _postId, 'user_id': _userId});
      }
      if (mounted) update(!current);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('عملیات انجام نشد؛ دوباره تلاش کنید.')));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _like() => _toggle('post_likes', _liked, (v) {
    setState(() { _liked = v; _likes += v ? 1 : -1; });
  });

  Future<void> _commentsPage() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PostCommentsScreen(postId: _postId),
    ));
    _loadInteractionState();
  }

  Future<void> _share() async {
    final link = Uri(scheme: 'homagram', host: 'post', path: '/$_postId');
    try {
      await SharePlus.instance.share(ShareParams(
        text: 'این پست را در HomaGram ببین:\n$link',
        subject: 'پست در HomaGram',
      ));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اشتراک‌گذاری در این دستگاه در دسترس نیست.')));
    }
  }

  Future<void> _editCaption() async {
    final controller = TextEditingController(text: widget.post['caption'] as String? ?? '');
    final value = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('ویرایش متن پست'),
      content: TextField(controller: controller, autofocus: true, maxLength: 2200,
        minLines: 2, maxLines: 7, decoration: const InputDecoration(hintText: 'متن پست')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: const Text('ذخیره تغییرات')),
      ],
    ));
    controller.dispose();
    if (value == null || value.length > 2200) return;
    try {
      await AuthService.client.from('posts').update({'caption': value}).eq('id', _postId).eq('author_id', _userId);
      if (mounted) {
        setState(() => widget.post['caption'] = value);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('متن پست ویرایش شد.')));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ویرایش پست انجام نشد.')));
    }
  }

  Future<void> _deletePost() async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('حذف پست'),
      content: const Text('این پست برای همیشه حذف شود؟'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('حذف')),
      ],
    ));
    if (confirmed != true) return;
    try {
      final path = widget.post['media_path'] as String?;
      await AuthService.client.from('posts').delete().eq('id', _postId).eq('author_id', _userId);
      if (path != null) {
        try { await AuthService.client.storage.from('post-media').remove([path]); } catch (_) {}
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('پست حذف شد.')));
      onDeleted?.call();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حذف پست انجام نشد.')));
    }
  }

  Future<void> _reportPost() async {
    const reasons = <String, String>{
      'spam': 'هرزنامه یا تبلیغات',
      'harassment': 'آزار و اذیت',
      'misinformation': 'اطلاعات نادرست',
      'inappropriate': 'محتوای نامناسب',
      'other': 'سایر موارد',
    };
    final reason = await showModalBottomSheet<String>(context: context, showDragHandle: true,
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const ListTile(title: Text('دلیل گزارش این پست را انتخاب کنید')),
        ...reasons.entries.map((e) => ListTile(title: Text(e.value),
          onTap: () => Navigator.pop(ctx, e.key))),
      ])));
    if (reason == null) return;
    try {
      await AuthService.client.from('post_reports').insert({
        'post_id': _postId, 'reporter_id': _userId, 'reason': reason,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('گزارش شما ثبت شد.')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('این پست قبلاً گزارش شده یا ثبت گزارش ممکن نیست.')));
    }
  }

  Future<void> _menu() async {
    final choice = await showModalBottomSheet<String>(context: context, showDragHandle: true,
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: Icon(_saved ? Icons.bookmark_remove_outlined : Icons.bookmark_add_outlined),
          title: Text(_saved ? 'حذف از ذخیره‌شده‌ها' : 'ذخیره پست'),
          onTap: () => Navigator.pop(ctx, 'save')),
        ListTile(leading: Icon(_reposted ? Icons.repeat_on : Icons.repeat),
          title: Text(_reposted ? 'لغو بازنشر' : 'بازنشر در صفحه من'),
          onTap: () => Navigator.pop(ctx, 'repost')),
        ListTile(leading: const Icon(Icons.ios_share_outlined), title: const Text('ارسال پست'),
          onTap: () => Navigator.pop(ctx, 'share')),
        if (widget.post['author_id'] == _userId) ...[
          const Divider(height: 1),
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('ویرایش متن پست'),
            onTap: () => Navigator.pop(ctx, 'edit')),
          ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('حذف پست', style: TextStyle(color: Colors.red)),
            onTap: () => Navigator.pop(ctx, 'delete')),
        ] else
          ListTile(leading: const Icon(Icons.flag_outlined), title: const Text('گزارش پست'),
            onTap: () => Navigator.pop(ctx, 'report')),
      ])));
    if (choice == 'save') await _toggle('saved_posts', _saved, (v) => setState(() => _saved = v));
    if (choice == 'repost') await _toggle('post_reposts', _reposted, (v) => setState(() => _reposted = v));
    if (choice == 'share') await _share();
    if (choice == 'edit') await _editCaption();
    if (choice == 'delete') await _deletePost();
    if (choice == 'report') await _reportPost();
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final caption = (post['caption'] as String? ?? '').trim();
    final mediaUrl = post['media_url'] as String?;
    final mediaType = post['media_type'] as String?;
    final date = DateTime.tryParse(post['created_at'] as String? ?? '')?.toLocal();
    final dateText = date == null ? '' : persianDate(date);
    return Container(
      decoration: BoxDecoration(color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: .16))),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(15, 14, 8, 12), child: Row(children: [
          InkWell(borderRadius: BorderRadius.circular(30),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => PublicProfileScreen(userId: post['author_id'] as String))),
            child: CircleAvatar(radius: 21, backgroundColor: const Color(0x223FD6D0),
              backgroundImage: post['author_avatar_url'] == null ? null : NetworkImage(post['author_avatar_url'] as String),
              child: post['author_avatar_url'] == null
                ? const Icon(Icons.person_outline_rounded, color: HomaGramTheme.turquoise) : null)),
          const SizedBox(width: 11),
          Expanded(child: InkWell(onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => PublicProfileScreen(userId: post['author_id'] as String))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(post['author_display_name'] as String? ?? 'کاربر HomaGram',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              Text('@${post['author_username'] ?? 'user'} • $dateText', textDirection: TextDirection.ltr,
                style: const TextStyle(fontSize: 10, color: Color(0xFF8490A4))),
            ]))),
          IconButton(onPressed: _menu, icon: const Icon(Icons.more_horiz_rounded, color: Color(0xFF8490A4))),
        ])),
        if (caption.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Text(caption, style: const TextStyle(height: 1.85, fontSize: 13))),
        if (mediaUrl != null) mediaType == 'video' ? _FeedVideo(url: mediaUrl)
          : Image.network(mediaUrl, fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) => progress == null ? child
              : const AspectRatio(aspectRatio: 1, child: Center(child: CircularProgressIndicator())),
            errorBuilder: (_, __, ___) => const _MediaError()),
        if (post['media_unavailable'] == true) const _MediaError(),
        Padding(padding: const EdgeInsets.fromLTRB(8, 4, 8, 8), child: Row(children: [
          TextButton.icon(onPressed: _busy ? null : _like,
            icon: Icon(_liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: _liked ? Colors.redAccent : const Color(0xFF8792A5), size: 20),
            label: Text('پسندیدن $_likes')),
          TextButton.icon(onPressed: _commentsPage,
            icon: const Icon(Icons.mode_comment_outlined, size: 19),
            label: Text('دیدگاه $_comments')),
          const Spacer(),
          IconButton(tooltip: 'ارسال', onPressed: _share, icon: const Icon(Icons.send_outlined)),
          IconButton(tooltip: 'گزینه‌ها', onPressed: _menu, icon: const Icon(Icons.more_vert)),
        ])),
      ]),
    );
  }
}

class PostCommentsScreen extends StatefulWidget {
  const PostCommentsScreen({required this.postId, super.key});
  final String postId;
  @override
  State<PostCommentsScreen> createState() => _PostCommentsScreenState();
}

class _PostCommentsScreenState extends State<PostCommentsScreen> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _comments = [];
  bool _loading = true, _sending = false;
  String? _replyTo;
  String? _replyName;
  String get _uid => AuthService.client.auth.currentUser!.id;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final rows = await AuthService.client.from('post_comments')
        .select('id,user_id,parent_id,body,created_at')
        .eq('post_id', widget.postId).order('created_at');
      final ids = rows.map((e) => e['user_id'] as String).toSet().toList();
      final profiles = ids.isEmpty ? <dynamic>[] : await AuthService.client.from('profiles')
        .select('id,username,display_name,avatar_path').inFilter('id', ids);
      final map = {for (final p in profiles) p['id'] as String: Map<String,dynamic>.from(p)};
      if (!mounted) return;
      setState(() { _comments = rows.map((r) {
        final m = Map<String,dynamic>.from(r); m['profile'] = map[m['user_id']]; return m;
      }).toList(); _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _send() async {
    final body = _controller.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await AuthService.client.from('post_comments').insert({
        'post_id': widget.postId, 'user_id': _uid, 'parent_id': _replyTo, 'body': body,
      });
      _controller.clear(); _replyTo = null; _replyName = null; await _load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ثبت دیدگاه انجام نشد.')));
    } finally { if (mounted) setState(() => _sending = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('دیدگاه‌ها')),
    body: Column(children: [
      Expanded(child: _loading ? const Center(child: CircularProgressIndicator())
        : _comments.isEmpty ? const Center(child: Text('هنوز دیدگاهی ثبت نشده است.'))
        : ListView.builder(padding: const EdgeInsets.all(14), itemCount: _comments.length,
          itemBuilder: (context, i) {
            final c = _comments[i], p = c['profile'] as Map<String,dynamic>?;
            final isReply = c['parent_id'] != null;
            return Padding(padding: EdgeInsets.only(bottom: 12, right: isReply ? 28 : 0),
              child: ListTile(dense: true, tileColor: Theme.of(context).cardTheme.color,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                leading: CircleAvatar(child: Text(((p?['display_name'] as String?) ?? 'ک').characters.first)),
                title: Text(p?['display_name'] as String? ?? 'کاربر',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                subtitle: Text(c['body'] as String),
                trailing: TextButton(onPressed: () => setState(() {
                  _replyTo = c['parent_id'] == null ? c['id'] as String : c['parent_id'] as String;
                  _replyName = p?['display_name'] as String? ?? 'کاربر';
                }), child: const Text('پاسخ'))));
          })),
      SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_replyTo != null) Row(children: [
            Expanded(child: Text('پاسخ به $_replyName', style: const TextStyle(fontSize: 12))),
            IconButton(onPressed: () => setState(() { _replyTo = null; _replyName = null; }),
              icon: const Icon(Icons.close, size: 18)),
          ]),
          Row(children: [
            Expanded(child: TextField(controller: _controller, minLines: 1, maxLines: 4,
              maxLength: 2000, decoration: const InputDecoration(hintText: 'دیدگاه خود را بنویسید…'))),
            IconButton(onPressed: _sending ? null : _send,
              icon: _sending ? const SizedBox(width: 18,height:18,child:CircularProgressIndicator(strokeWidth:2))
                : const Icon(Icons.send_rounded, color: HomaGramTheme.turquoise)),
          ]),
        ]))),
    ]),
  );
}

class _FeedVideo extends StatefulWidget {
  const _FeedVideo({required this.url});
  final String url;

  @override
  State<_FeedVideo> createState() => _FeedVideoState();
}

class _FeedVideoState extends State<_FeedVideo> {
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
      if (snapshot.hasError) return const _MediaError();
      if (snapshot.connectionState != ConnectionState.done) {
        return const AspectRatio(aspectRatio: 16 / 9, child: Center(child: CircularProgressIndicator()));
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
              Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(color: Color(0x88000000), shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded, size: 38, color: Colors.white),
              ),
            Positioned(
              left: 8, right: 8, bottom: 8,
              child: VideoProgressIndicator(_controller, allowScrubbing: true,
                  colors: const VideoProgressColors(playedColor: HomaGramTheme.turquoise)),
            ),
          ]),
        ),
      );
    },
  );
}

class _MediaError extends StatelessWidget {
  const _MediaError();
  @override
  Widget build(BuildContext context) => Container(
    height: 180,
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: const Center(child: Icon(Icons.broken_image_outlined, size: 38, color: Color(0xFF8490A4))),
  );
}
