import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme/app_theme.dart';
import '../../auth/data/auth_service.dart';
import 'create_post_screen.dart';
import 'public_profile_screen.dart';
import 'stories_screen.dart';
import '../../messaging/data/messaging_service.dart';
import '../../../core/utils/persian_date.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  late Future<List<Map<String, dynamic>>> _posts;
  String? _myAvatarUrl;

  @override
  void initState() {
    super.initState();
    _posts = _loadPosts();
    _loadMyAvatar();
  }

  Future<void> _loadMyAvatar() async {
    try {
      final client = AuthService.client;
      final uid = client.auth.currentUser!.id;
      final profile = await client.from('profiles').select('avatar_path').eq('id', uid).maybeSingle();
      final path = profile?['avatar_path'] as String?;
      if (path == null || path.isEmpty) return;
      final url = await client.storage.from('avatars').createSignedUrl(path, 3600);
      if (mounted) setState(() => _myAvatarUrl = url);
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _loadPosts() async {
    final rows = await AuthService.client
        .from('posts')
        .select('id,author_id,author_username,author_display_name,caption,media_path,media_type,cover_path,created_at')
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
      final coverPath = post['cover_path'] as String?;
      if (coverPath != null) {
        try {
          post['cover_url'] = await AuthService.client.storage
              .from('post-media').createSignedUrl(coverPath, 3600);
        } catch (_) {}
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
      const StoriesStrip(),
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
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0x223FD6D0),
                  backgroundImage: _myAvatarUrl == null ? null : NetworkImage(_myAvatarUrl!),
                  child: _myAvatarUrl == null
                      ? const Icon(Icons.person_outline, color: HomaGramTheme.turquoise)
                      : null,
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
                itemBuilder: (context, index) => PostCard(post: posts[index], onDeleted: () => _refresh()),
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

class PostCard extends StatefulWidget {
  const PostCard({required this.post, this.onDeleted});
  final Map<String, dynamic> post;
  final VoidCallback? onDeleted;
  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _liked = false, _saved = false, _reposted = false, _busy = false, _heartBurst = false;
  Timer? _heartTimer;
  int _likes = 0, _comments = 0;
  String get _userId => AuthService.client.auth.currentUser!.id;
  String get _postId => widget.post['id'] as String;

  @override
  void initState() { super.initState(); _loadInteractionState(); }

  Future<void> _loadInteractionState() async {
    try {
      final c = AuthService.client;
      final likes = await c.from('post_likes').select('user_id').eq('post_id', _postId);
      final comments = await c.from('post_comments').select('id').eq('post_id', _postId);
      final myLike = await c.from('post_likes').select('post_id')
          .eq('post_id', _postId).eq('user_id', _userId).maybeSingle();
      final mySave = await c.from('saved_posts').select('post_id')
          .eq('post_id', _postId).eq('user_id', _userId).maybeSingle();
      final myRepost = await c.from('post_reposts').select('post_id')
          .eq('post_id', _postId).eq('user_id', _userId).maybeSingle();
      if (!mounted) return;
      setState(() {
        _likes = likes.length;
        _comments = comments.length;
        _liked = myLike != null;
        _saved = mySave != null;
        _reposted = myRepost != null;
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

  Future<void> _doubleTapLike() async {
    if (!_liked) await _like();
    if (!mounted) return;
    _heartTimer?.cancel();
    setState(() => _heartBurst = true);
    _heartTimer = Timer(const Duration(milliseconds: 720), () {
      if (mounted) setState(() => _heartBurst = false);
    });
  }

  @override
  void dispose() { _heartTimer?.cancel(); super.dispose(); }

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
    final action = await showModalBottomSheet<String>(
      context: context, showDragHandle: true, useSafeArea: true,
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(padding: EdgeInsets.fromLTRB(20, 8, 20, 14),
          child: Align(alignment: Alignment.centerRight,
            child: Text('همرسانی پست', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)))),
        ListTile(leading: const CircleAvatar(child: Icon(Icons.send_rounded)),
          title: const Text('ارسال برای کاربران HomaGram'),
          subtitle: const Text('انتخاب یک یا چند نفر از گفتگوهای داخلی'),
          onTap: () => Navigator.pop(ctx, 'inside')),
        ListTile(leading: const CircleAvatar(child: Icon(Icons.link_rounded)),
          title: const Text('کپی پیوند پست'),
          subtitle: const Text('برای ارسال در هر پیام‌رسانی'),
          onTap: () => Navigator.pop(ctx, 'copy')),
        ListTile(leading: const CircleAvatar(child: Icon(Icons.ios_share_rounded)),
          title: const Text('اشتراک‌گذاری خارج از HomaGram'),
          subtitle: const Text('ارسال با برنامه‌های دیگر دستگاه'),
          onTap: () => Navigator.pop(ctx, 'external')),
        const SizedBox(height: 10),
      ])),
    );
    if (!mounted || action == null) return;
    final link = Uri(scheme: 'homagram', host: 'post', path: '/$_postId');
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: link.toString()));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('پیوند پست کپی شد.')));
    } else if (action == 'external') {
      try {
        await SharePlus.instance.share(ShareParams(
          text: 'این پست را در HomaGram ببین:\n$link',
          subject: 'پست در HomaGram',
        ));
      } catch (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('اشتراک‌گذاری در این دستگاه در دسترس نیست.')));
      }
    } else if (action == 'inside') {
      final recipients = await showModalBottomSheet<List<Map<String, dynamic>>>(
        context: context, isScrollControlled: true, useSafeArea: true, showDragHandle: true,
        builder: (_) => const _PostShareSheet(),
      );
      if (!mounted || recipients == null || recipients.isEmpty) return;
      var sent = 0;
      for (final recipient in recipients) {
        try {
          final conversationId = await MessagingService.createDirectConversation(recipient['id'] as String);
          await MessagingService.sendTextMessage(
            conversationId, 'HOMAGRAM_POST:$_postId\nاین پست را برای شما فرستادم.',
          );
          sent++;
        } catch (_) {}
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sent == 0 ? 'ارسال پست انجام نشد.' : 'پست برای $sent نفر ارسال شد.')));
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
      widget.onDeleted?.call();
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
        if (caption.isNotEmpty || mediaUrl != null || post['media_unavailable'] == true)
          GestureDetector(
            onDoubleTap: _doubleTapLike,
            child: Stack(alignment: Alignment.center, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (caption.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Text(caption, style: const TextStyle(height: 1.85, fontSize: 13))),
                if (mediaUrl != null) mediaType == 'video' ? _FeedVideo(url: mediaUrl, coverUrl: post['cover_url'] as String?)
                  : Image.network(mediaUrl, fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) => progress == null ? child
                      : const AspectRatio(aspectRatio: 1, child: Center(child: CircularProgressIndicator())),
                    errorBuilder: (_, __, ___) => const _MediaError()),
                if (post['media_unavailable'] == true) const _MediaError(),
              ]),
              IgnorePointer(child: AnimatedOpacity(
                opacity: _heartBurst ? 1 : 0,
                duration: const Duration(milliseconds: 140),
                child: AnimatedScale(
                  scale: _heartBurst ? 1 : .35,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  child: const Icon(Icons.favorite_rounded, size: 92, color: Colors.white,
                    shadows: [Shadow(color: Colors.black45, blurRadius: 18)]),
                ),
              )),
            ]),
          ),
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


class _PostShareSheet extends StatefulWidget {
  const _PostShareSheet();
  @override
  State<_PostShareSheet> createState() => _PostShareSheetState();
}

class _PostShareSheetState extends State<_PostShareSheet> {
  final _controller = TextEditingController();
  final Map<String, Map<String, dynamic>> _selectedUsers = {};
  List<Map<String, dynamic>> _users = [];
  bool _loading = false;
  Timer? _debounce;
  String? _error;

  @override
  void dispose() { _debounce?.cancel(); _controller.dispose(); super.dispose(); }

  void _searchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(value));
  }

  Future<void> _search(String value) async {
    final term = value.trim();
    if (term.length < 2) {
      if (mounted) setState(() { _users = []; _error = null; });
      return;
    }
    setState(() => _loading = true);
    try {
      final client = AuthService.client;
      final uid = client.auth.currentUser!.id;
      final byUsername = await client.from('profiles').select('id,username,display_name')
        .neq('id', uid).ilike('username', '%$term%').limit(20);
      final byName = await client.from('profiles').select('id,username,display_name')
        .neq('id', uid).ilike('display_name', '%$term%').limit(20);
      final merged = <String, Map<String, dynamic>>{};
      for (final row in [...byUsername, ...byName]) {
        merged[row['id'] as String] = Map<String, dynamic>.from(row);
      }
      if (!mounted) return;
      setState(() { _users = merged.values.take(30).toList(); _error = null; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'جست‌وجوی کاربران انجام نشد.'; });
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .72,
      child: Column(children: [
        const Padding(padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Align(alignment: Alignment.centerRight,
            child: Text('انتخاب گیرندگان', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _controller, onChanged: _searchChanged,
            decoration: InputDecoration(
              hintText: 'نام یا نام کاربری را جست‌وجو کنید',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(onPressed: () { _controller.clear(); _search(''); },
                icon: const Icon(Icons.close_rounded)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
        if (_selectedUsers.isNotEmpty)
          Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(alignment: Alignment.centerRight,
              child: Text('${_selectedUsers.length} نفر انتخاب شده‌اند',
                style: const TextStyle(fontWeight: FontWeight.w700)))),
        Expanded(child: _loading ? const Center(child: CircularProgressIndicator())
          : _error != null ? Center(child: Text(_error!))
          : _users.isEmpty ? const Center(child: Text('برای پیدا کردن کاربران، نام یا نام کاربری را جست‌وجو کنید.'))
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _users.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 70),
              itemBuilder: (context, index) {
                final user = _users[index];
                final id = user['id'] as String;
                final selected = _selectedUsers.containsKey(id);
                final name = (user['display_name'] as String?)?.trim();
                final username = (user['username'] as String?)?.trim() ?? '';
                final label = name != null && name.isNotEmpty ? name : username;
                return ListTile(
                  leading: CircleAvatar(child: Text(label.isEmpty ? '?' : label.characters.first.toUpperCase())),
                  title: Text(name != null && name.isNotEmpty ? name : '@$username',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('@$username', textDirection: TextDirection.ltr),
                  trailing: Checkbox(value: selected, onChanged: (_) => setState(() {
                    selected ? _selectedUsers.remove(id) : _selectedUsers[id] = user;
                  })),
                  onTap: () => setState(() {
                    selected ? _selectedUsers.remove(id) : _selectedUsers[id] = user;
                  }),
                );
              },
            )),
        SafeArea(top: false, child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: SizedBox(width: double.infinity,
            child: FilledButton.icon(
              onPressed: _selectedUsers.isEmpty ? null : () {
                Navigator.pop(context, _selectedUsers.values.toList());
              },
              icon: const Icon(Icons.send_rounded),
              label: Text('ارسال برای ${_selectedUsers.length} نفر'),
            ),
          ),
        )),
      ]),
    ),
  );
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
  bool _likeBusy = false;
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
      final commentIds = rows.map((e) => e['id'] as String).toList();
      final likes = commentIds.isEmpty ? <dynamic>[] : await AuthService.client.from('post_comment_likes')
        .select('comment_id,user_id').inFilter('comment_id', commentIds);
      final likeCounts = <String,int>{};
      final myLikes = <String>{};
      for (final like in likes) {
        final id = like['comment_id'] as String;
        likeCounts[id] = (likeCounts[id] ?? 0) + 1;
        if (like['user_id'] == _uid) myLikes.add(id);
      }
      final avatarPaths = profiles.map((p) => p['avatar_path'] as String?).whereType<String>().toSet();
      final avatarUrls = <String,String>{};
      for (final path in avatarPaths) {
        try { avatarUrls[path] = await AuthService.client.storage.from('avatars').createSignedUrl(path, 3600); } catch (_) {}
      }
      if (!mounted) return;
      setState(() { _comments = rows.map((r) {
        final m = Map<String,dynamic>.from(r);
        m['profile'] = map[m['user_id']];
        m['like_count'] = likeCounts[m['id']] ?? 0;
        m['liked_by_me'] = myLikes.contains(m['id']);
        final avatarPath = (m['profile'] as Map<String,dynamic>?)?['avatar_path'] as String?;
        m['avatar_url'] = avatarPath == null ? null : avatarUrls[avatarPath];
        return m;
      }).toList(); _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _toggleCommentLike(Map<String,dynamic> comment) async {
    if (_likeBusy) return;
    setState(() => _likeBusy = true);
    final id = comment['id'] as String;
    final liked = comment['liked_by_me'] == true;
    try {
      final query = AuthService.client.from('post_comment_likes');
      if (liked) {
        await query.delete().eq('comment_id', id).eq('user_id', _uid);
      } else {
        await query.insert({'comment_id': id, 'user_id': _uid});
      }
      if (mounted) setState(() {
        comment['liked_by_me'] = !liked;
        comment['like_count'] = ((comment['like_count'] as int?) ?? 0) + (liked ? -1 : 1);
      });
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ثبت پسند دیدگاه انجام نشد.')),
      );
    } finally { if (mounted) setState(() => _likeBusy = false); }
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
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardTheme.color,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CircleAvatar(
                    radius: 19,
                    backgroundImage: c['avatar_url'] == null ? null : NetworkImage(c['avatar_url'] as String),
                    child: c['avatar_url'] == null
                        ? Text(((p?['display_name'] as String?) ?? 'ک').characters.first)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p?['display_name'] as String? ?? 'کاربر',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                    const SizedBox(height: 5),
                    Text(c['body'] as String, style: const TextStyle(height: 1.55)),
                    const SizedBox(height: 7),
                    Row(children: [
                      Text(persianDate(DateTime.tryParse(c['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now()),
                        style: const TextStyle(fontSize: 10, color: Color(0xFF8490A4))),
                      const Spacer(),
                      InkWell(onTap: () => _toggleCommentLike(c), child: Row(children: [
                        Icon(c['liked_by_me'] == true ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: c['liked_by_me'] == true ? Colors.redAccent : const Color(0xFF8490A4), size: 17),
                        const SizedBox(width: 4),
                        Text('${c['like_count'] ?? 0}', style: const TextStyle(fontSize: 11)),
                      ])),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: () => setState(() {
                          _replyTo = c['parent_id'] == null ? c['id'] as String : c['parent_id'] as String;
                          _replyName = p?['display_name'] as String? ?? 'کاربر';
                        }),
                        child: const Text('پاسخ'),
                      ),
                    ]),
                  ])),
                ]),
              ));
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
  const _FeedVideo({required this.url, this.coverUrl});
  final String url;
  final String? coverUrl;

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
        return AspectRatio(
          aspectRatio: 9 / 16,
          child: Stack(fit: StackFit.expand, children: [
            if (widget.coverUrl != null) Image.network(widget.coverUrl!, fit: BoxFit.cover),
            const Center(child: CircularProgressIndicator()),
          ]),
        );
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
