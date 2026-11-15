import 'package:homagram/app/presentation/homagram_branding.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../../app/theme/app_theme.dart';
import '../../auth/data/auth_service.dart';
import 'public_profile_screen.dart';
import 'feed_screen.dart' show PostCommentsScreen;
import '../../messaging/data/messaging_service.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key, this.initialQuery});
  final String? initialQuery;
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _posts = [];
  List<Map<String, dynamic>> _users = [];
  List<String> _hashtags = [];
  bool _loading = true, _searching = false, _popular = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialQuery;
    if (initial != null && initial.isNotEmpty) _search.text = initial;
    _load(term: initial);
  }
  @override
  void dispose() { _debounce?.cancel(); _search.dispose(); super.dispose(); }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _load(term: value));
  }

  Future<void> _load({String? term}) async {
    final query = (term ?? _search.text).trim();
    setState(() { _loading = true; _searching = query.isNotEmpty; _error = null; });
    try {
      final client = AuthService.client;
      var postQuery = client.from('posts').select(
        'id,author_id,author_username,author_display_name,caption,media_path,media_type,cover_path,created_at,is_reel'
      ).eq('is_public', true);
      if (query.isNotEmpty) {
        final hashtag = query.startsWith('#') ? query.substring(1) : query;
        postQuery = postQuery.ilike('caption', query.startsWith('#') ? '%#$hashtag%' : '%$query%');
      }
      final rows = await postQuery.order('created_at', ascending: false).limit(60);
      final ids = rows.map((r) => r['id'] as String).toList();
      final likeRows = ids.isEmpty ? <dynamic>[] : await client.from('post_likes')
        .select('post_id').inFilter('post_id', ids);
      final counts = <String, int>{};
      for (final row in likeRows) {
        final id = row['post_id'] as String;
        counts[id] = (counts[id] ?? 0) + 1;
      }
      final posts = <Map<String, dynamic>>[];
      for (final row in rows) {
        final post = Map<String, dynamic>.from(row);
        post['like_count'] = counts[post['id']] ?? 0;
        final path = post['media_path'] as String?;
        if (path != null) {
          try { post['media_url'] = await client.storage.from('post-media').createSignedUrl(path, 3600); }
          catch (_) {}
        }
        final coverPath = post['cover_path'] as String?;
        if (coverPath != null) {
          try { post['cover_url'] = await client.storage.from('post-media').createSignedUrl(coverPath, 3600); }
          catch (_) {}
        }
        posts.add(post);
      }
      if (_popular) posts.sort((a, b) =>
        (b['like_count'] as int).compareTo(a['like_count'] as int));

      List<Map<String, dynamic>> users = [];
      if (query.isNotEmpty && !query.startsWith('#')) {
        final byUsername = await client.from('profiles').select('id,username,display_name')
          .neq('id', client.auth.currentUser!.id).ilike('username', '%$query%').limit(12);
        final byName = await client.from('profiles').select('id,username,display_name')
          .neq('id', client.auth.currentUser!.id).ilike('display_name', '%$query%').limit(12);
        final merged = <String, Map<String, dynamic>>{};
        for (final user in [...byUsername, ...byName]) {
          merged[user['id'] as String] = Map<String, dynamic>.from(user);
        }
        users = merged.values.take(20).toList();
      }
      final tags = <String>{};
      for (final post in posts) {
        final caption = post['caption'] as String? ?? '';
        for (final match in RegExp(r'#[\p{L}\p{N}_]{2,}', unicode: true).allMatches(caption)) {
          tags.add(match.group(0)!);
        }
      }
      if (!mounted) return;
      setState(() { _posts = posts; _users = users; _hashtags = tags.take(12).toList(); _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'محتوای اکسپلور بارگذاری نشد. اتصال را بررسی و دوباره تلاش کنید.'; });
    }
  }

  void _selectTag(String tag) { _search.text = tag; _load(term: tag); }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('کشف HomaGram', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [HomaGramSpringPress(child: IconButton(onPressed: () => _load(), tooltip: 'تازه‌سازی',
          icon: const Icon(Icons.refresh_rounded))), const SizedBox(width: 4)],
      ),
      body: HomaGramEntrance(child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
          child: TextField(
            controller: _search, onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            onSubmitted: (value) => _load(term: value),
            decoration: InputDecoration(
              hintText: 'جست‌وجوی افراد، پست‌ها و هشتگ‌ها',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.text.isEmpty ? null : HomaGramSpringPress(child: IconButton(
                onPressed: () { _search.clear(); _load(term: ''); },
                icon: const Icon(Icons.close_rounded))),
              filled: true, fillColor: colors.surfaceContainerHighest.withValues(alpha: .55),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: BorderSide.none),
            ),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            children: [
              ChoiceChip(label: const Text('جدیدترین'), selected: !_popular,
                onSelected: (_) { setState(() => _popular = false); _load(); }),
              const SizedBox(width: 8),
              ChoiceChip(label: const Text('محبوب‌ترین'), selected: _popular,
                onSelected: (_) { setState(() => _popular = true); _load(); }),
            ],
          ),
        ),
        if (!_searching && _hashtags.isNotEmpty)
          SizedBox(height: 48, child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            scrollDirection: Axis.horizontal,
            children: _hashtags.map((tag) => Padding(
              padding: const EdgeInsets.only(left: 7),
              child: ActionChip(avatar: const Icon(Icons.tag_rounded, size: 16),
                label: Text(tag), onPressed: () => _selectTag(tag)),
            )).toList(),
          )),
        Expanded(
          child: _loading ? const Center(child: CircularProgressIndicator())
            : _error != null ? Center(child: Padding(
              padding: const EdgeInsets.all(26),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_off_rounded, size: 46), const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center),
                HomaGramSpringPress(child: TextButton.icon(onPressed: () => _load(), icon: const Icon(Icons.refresh), label: const Text('تلاش دوباره'))),
              ]),
            ))
            : RefreshIndicator(
              onRefresh: () => _load(),
              child: CustomScrollView(slivers: [
                if (_users.isNotEmpty) SliverToBoxAdapter(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Text('افراد', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900))),
                    SizedBox(height: 90, child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      scrollDirection: Axis.horizontal, itemCount: _users.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final user = _users[index];
                        final name = (user['display_name'] as String?)?.trim();
                        final username = user['username'] as String? ?? '';
                        final label = name != null && name.isNotEmpty ? name : '@$username';
                        return SizedBox(width: 82, child: InkWell(
                          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => PublicProfileScreen(userId: user['id'] as String))),
                          child: Column(children: [
                            CircleAvatar(radius: 25,
                              backgroundColor: HomaGramTheme.turquoise.withValues(alpha: .15),
                              child: Text(label.characters.first, style: const TextStyle(fontWeight: FontWeight.w900))),
                            const SizedBox(height: 5),
                            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 10))),
                              HomaGramVerifiedBadge(userId: user['id'] as String?, size: 12),
                            ]),
                            Text('@$username', maxLines: 1, overflow: TextOverflow.ellipsis,
                              textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 9, color: Color(0xFF8490A4))),
                          ]),
                        ));
                      },
                    )),
                  ]),
                ),
                SliverToBoxAdapter(child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: Text(_searching ? 'نتایج پست‌ها' : 'پست‌های عمومی',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                )),
                if (_posts.isEmpty)
                  const SliverFillRemaining(hasScrollBody: false,
                    child: Center(child: Text('محتوایی برای نمایش پیدا نشد.')))
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(2, 0, 2, 18),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2, childAspectRatio: .92),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _postTile(_posts[index]), childCount: _posts.length),
                    ),
                  ),
              ]),
            ),
        ),
      ])),
    );
  }

  Widget _postTile(Map<String, dynamic> post) {
    final mediaUrl = post['media_type'] == 'video' ? (post['cover_url'] as String? ?? post['media_url'] as String?) : post['media_url'] as String?;
    final caption = (post['caption'] as String? ?? '').trim();
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => _ExplorePostViewer(posts: _posts, initialIndex: _posts.indexOf(post)))),
      child: Stack(fit: StackFit.expand, children: [
        if (mediaUrl != null)
          Image.network(mediaUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _textTile(caption))
        else _textTile(caption),
        Positioned(left: 5, bottom: 5, child: DecoratedBox(
          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.favorite_rounded, size: 11, color: Colors.white),
              const SizedBox(width: 3),
              Text("${post['like_count'] ?? 0}", style: const TextStyle(color: Colors.white, fontSize: 10)),
            ]),
          ),
        )),
        if (post['media_type'] == 'video')
          Positioned(right: 6, top: 6,
            child: Icon(Icons.video_collection_rounded,
              color: Colors.white, size: 22)),
      ]),
    );
  }

  Widget _textTile(String caption) => Container(
    color: HomaGramTheme.navy, padding: const EdgeInsets.all(9), alignment: Alignment.center,
    child: Text(caption.isEmpty ? 'HomaGram' : caption, maxLines: 7,
      overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
      style: const TextStyle(color: Colors.white, fontSize: 10, height: 1.5)),
  );
}


class _ExplorePostViewer extends StatefulWidget {
  const _ExplorePostViewer({required this.posts, required this.initialIndex});
  final List<Map<String, dynamic>> posts;
  final int initialIndex;

  @override
  State<_ExplorePostViewer> createState() => _ExplorePostViewerState();
}

class _ExplorePostViewerState extends State<_ExplorePostViewer> {
  late final PageController _controller = PageController(initialPage: widget.initialIndex);
  late int _activeIndex = widget.initialIndex;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Stack(children: [
      PageView.builder(
        controller: _controller,
        scrollDirection: Axis.vertical,
        itemCount: widget.posts.length,
        onPageChanged: (index) => setState(() => _activeIndex = index),
        itemBuilder: (context, index) => _ExplorePostPage(
          key: ValueKey(widget.posts[index]['id']),
          post: widget.posts[index],
          isActive: index == _activeIndex,
        ),
      ),
      SafeArea(
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              style: IconButton.styleFrom(backgroundColor: Colors.black45),
            ),
          ),
        ),
      ),
      SafeArea(
        child: Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 18, 16, 0),
            child: Text('کشف', style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800,
              shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
            )),
          ),
        ),
      ),
    ]),
  );
}

class _ExplorePostPage extends StatefulWidget {
  const _ExplorePostPage({super.key, required this.post, required this.isActive});
  final Map<String, dynamic> post;
  final bool isActive;

  @override
  State<_ExplorePostPage> createState() => _ExplorePostPageState();
}

class _ExplorePostPageState extends State<_ExplorePostPage> {
  VideoPlayerController? _video;
  bool _videoReady = false;
  bool _muted = true;
  bool _liked = false, _saved = false, _reposted = false, _busy = false;
  int _likes = 0, _comments = 0;
  String get _postId => widget.post['id'] as String;
  String get _uid => AuthService.client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _likes = (widget.post['like_count'] as int?) ?? 0;
    _loadInteractions();
  }

  Future<void> _loadInteractions() async {
    try {
      final c = AuthService.client;
      final results = await Future.wait([
        c.from('post_likes').select('user_id').eq('post_id', _postId),
        c.from('post_comments').select('id').eq('post_id', _postId),
        c.from('post_likes').select('post_id').eq('post_id', _postId).eq('user_id', _uid).maybeSingle(),
        c.from('saved_posts').select('post_id').eq('post_id', _postId).eq('user_id', _uid).maybeSingle(),
        c.from('post_reposts').select('post_id').eq('post_id', _postId).eq('user_id', _uid).maybeSingle(),
      ]);
      if (!mounted) return;
      setState(() {
        _likes = (results[0] as List).length;
        _comments = (results[1] as List).length;
        _liked = results[2] != null;
        _saved = results[3] != null;
        _reposted = results[4] != null;
        widget.post['like_count'] = _likes;
      });
    } catch (_) {}
  }

  Future<void> _toggleLike() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final q = AuthService.client.from('post_likes');
      if (_liked) {
        await q.delete().eq('post_id', _postId).eq('user_id', _uid);
      } else {
        await q.insert({'post_id': _postId, 'user_id': _uid});
      }
      if (mounted) setState(() {
        _liked = !_liked;
        _likes += _liked ? 1 : -1;
        widget.post['like_count'] = _likes;
      });
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ثبت پسند پست انجام نشد.')));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _openComments() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PostCommentsScreen(postId: _postId),
    ));
    if (mounted) {
      try {
        final rows = await AuthService.client.from('post_comments')
          .select('id').eq('post_id', _postId);
        if (mounted) setState(() => _comments = rows.length);
      } catch (_) {}
    }
  }

  Future<void> _sharePost() async {
    final choice = await showModalBottomSheet<String>(
      context: context, showDragHandle: true, useSafeArea: true,
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(padding: EdgeInsets.all(16), child: Text('همرسانی پست',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900))),
        ListTile(leading: const Icon(Icons.send_rounded),
          title: const Text('ارسال برای کاربران HomaGram'),
          onTap: () => Navigator.pop(ctx, 'internal')),
        ListTile(leading: const Icon(Icons.link_rounded), title: const Text('کپی پیوند پست'),
          onTap: () => Navigator.pop(ctx, 'copy')),
        ListTile(leading: const Icon(Icons.ios_share_rounded), title: const Text('اشتراک‌گذاری خارج از برنامه'),
          onTap: () => Navigator.pop(ctx, 'external')),
      ])),
    );
    if (!mounted || choice == null) return;
    final link = Uri(scheme: 'homagram', host: 'post', path: '/$_postId');
    if (choice == 'copy') {
      await Clipboard.setData(ClipboardData(text: link.toString()));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('پیوند پست کپی شد.')));
    } else if (choice == 'external') {
      await SharePlus.instance.share(ShareParams(
        text: 'این پست را در HomaGram ببین:\n$link', subject: 'پست در HomaGram'));
    } else {
      await _shareToUsers();
    }
  }

  Future<void> _shareToUsers() async {
    final controller = TextEditingController();
    List<Map<String, dynamic>> users = [];
    bool loading = false;
    String? error;
    final selected = <String, Map<String, dynamic>>{};
    await showModalBottomSheet<void>(
      context: context, isScrollControlled: true, useSafeArea: true, showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        Future<void> search(String value) async {
          final term = value.trim();
          if (term.length < 2) { setSheet(() { users = []; error = null; }); return; }
          setSheet(() => loading = true);
          try {
            final c = AuthService.client;
            final byName = await c.from('profiles').select('id,username,display_name')
              .neq('id', _uid).ilike('display_name', '%$term%').limit(15);
            final byUser = await c.from('profiles').select('id,username,display_name')
              .neq('id', _uid).ilike('username', '%$term%').limit(15);
            final merged = <String, Map<String,dynamic>>{};
            for (final u in [...byName, ...byUser]) { merged[u['id'] as String] = Map<String,dynamic>.from(u); }
            setSheet(() { users = merged.values.toList(); loading = false; error = null; });
          } catch (_) { setSheet(() { loading = false; error = 'جست‌وجوی کاربران انجام نشد.'; }); }
        }
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: SizedBox(height: MediaQuery.sizeOf(ctx).height * .68,
            child: Column(children: [
              const Padding(padding: EdgeInsets.all(14), child: Text('انتخاب گیرندگان',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(controller: controller, onChanged: search,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search),
                    hintText: 'نام یا نام کاربری را جست‌وجو کنید'))),
              Expanded(child: loading ? const Center(child: CircularProgressIndicator())
                : error != null ? Center(child: Text(error!))
                : users.isEmpty ? const Center(child: Text('برای یافتن کاربر جست‌وجو کنید.'))
                : ListView.builder(itemCount: users.length, itemBuilder: (_, i) {
                    final u = users[i]; final id = u['id'] as String;
                    final name = (u['display_name'] as String?)?.trim();
                    return CheckboxListTile(value: selected.containsKey(id),
                      title: Text(name?.isNotEmpty == true ? name! : '@${u['username']}'),
                      subtitle: Text('@${u['username']}'),
                      onChanged: (v) => setSheet(() {
                        if (v == true) { selected[id] = u; } else { selected.remove(id); }
                      }));
                  })),
              SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(14),
                child: SizedBox(width: double.infinity, child: FilledButton.icon(
                  onPressed: selected.isEmpty ? null : () => Navigator.pop(ctx),
                  icon: const Icon(Icons.send), label: Text('ارسال برای ${selected.length} نفر'))))),
            ]),
          ),
        );
      }),
    );
    controller.dispose();
    if (selected.isEmpty) return;
    var sent = 0;
    for (final user in selected.values) {
      try {
        final conversation = await MessagingService.createDirectConversation(user['id'] as String);
        await MessagingService.sendTextMessage(conversation,
          'HOMAGRAM_POST:$_postId\\nاین پست را برای شما فرستادم.');
        sent++;
      } catch (_) {}
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(sent == 0 ? 'ارسال پست انجام نشد.' : 'پست برای $sent نفر ارسال شد.')));
  }

  Future<void> _postMenu() async {
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
        if (widget.post['author_id'] == _uid) ...[
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('ویرایش پست'),
            onTap: () => Navigator.pop(ctx, 'edit')),
          ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('حذف پست', style: TextStyle(color: Colors.red)),
            onTap: () => Navigator.pop(ctx, 'delete')),
        ] else
          ListTile(leading: const Icon(Icons.flag_outlined), title: const Text('گزارش پست'),
            onTap: () => Navigator.pop(ctx, 'report')),
      ])));
    if (choice == null || !mounted) return;
    if (choice == 'share') { await _sharePost(); return; }
    if (choice == 'save' || choice == 'repost') {
      final table = choice == 'save' ? 'saved_posts' : 'post_reposts';
      final current = choice == 'save' ? _saved : _reposted;
      try {
        final q = AuthService.client.from(table);
        if (current) { await q.delete().eq('post_id', _postId).eq('user_id', _uid); }
        else { await q.insert({'post_id': _postId, 'user_id': _uid}); }
        if (mounted) setState(() {
          if (choice == 'save') { _saved = !current; } else { _reposted = !current; }
        });
      } catch (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('این عملیات انجام نشد.')));
      }
      return;
    }
    if (choice == 'report') {
      final reason = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('گزارش پست'),
        content: const Text('آیا می‌خواهید این پست را برای بررسی گزارش کنید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'other'), child: const Text('ثبت گزارش')),
        ],
      ));
      if (reason != null) {
        try {
          await AuthService.client.from('post_reports').insert({
            'post_id': _postId, 'reporter_id': _uid, 'reason': reason,
          });
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('گزارش شما ثبت شد.')));
        } catch (_) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ثبت گزارش انجام نشد.')));
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.post['media_type'] == 'video' && widget.post['media_url'] is String) {
      _video = VideoPlayerController.networkUrl(Uri.parse(widget.post['media_url'] as String))
        ..setLooping(true)
        ..setVolume(0)
        ..initialize().then((_) {
          if (!mounted) return;
          setState(() => _videoReady = true);
          if (widget.isActive) _video?.play();
        }).catchError((_) {});
    }
  }

  @override
  void didUpdateWidget(covariant _ExplorePostPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive && _videoReady) {
      if (widget.isActive) {
        _video?.play();
      } else {
        _video?.pause();
      }
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final isVideo = post['media_type'] == 'video';
    final mediaUrl = (post['media_url'] as String?) ?? (post['cover_url'] as String?);
    final author = (post['author_display_name'] as String?)?.trim();
    final username = post['author_username'] as String? ?? '';
    final caption = post['caption'] as String? ?? '';
    return Stack(fit: StackFit.expand, children: [
      const ColoredBox(color: Colors.black),
      if (isVideo && _videoReady && _video != null)
        Center(child: AspectRatio(
          aspectRatio: _video!.value.aspectRatio,
          child: VideoPlayer(_video!),
        ))
      else if (mediaUrl != null)
        Center(child: Image.network(mediaUrl, fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported_outlined,
            color: Colors.white54, size: 54)))
      else
        Center(child: Padding(
          padding: const EdgeInsets.all(30),
          child: Text(caption.isEmpty ? 'HomaGram' : caption,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 22)),
        )),
      if (isVideo)
        Positioned(
          right: 18, bottom: 170,
          child: Column(children: [
            IconButton(
              onPressed: () {
                if (_video == null || !_videoReady) return;
                setState(() {
                  _video!.value.isPlaying ? _video!.pause() : _video!.play();
                });
              },
              icon: Icon((_video?.value.isPlaying ?? false)
                ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                color: Colors.white, size: 38),
            ),
            IconButton(
              onPressed: () {
                setState(() => _muted = !_muted);
                _video?.setVolume(_muted ? 0 : 1);
              },
              icon: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                color: Colors.white),
            ),
          ]),
        ),
      Positioned(
        left: 18, right: 72, bottom: 34,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => PublicProfileScreen(userId: widget.post['author_id'] as String))),
              child: Text(author?.isNotEmpty == true ? author! : '@$username',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)))),
            IconButton(onPressed: _postMenu,
              icon: const Icon(Icons.more_horiz_rounded, color: Colors.white),
              style: IconButton.styleFrom(backgroundColor: Colors.black45)),
          ]),
          if (caption.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(caption, maxLines: 5, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5)),
          ],
        ]),
      ),
      Positioned(
        right: 12, bottom: 34,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _actionButton(
            icon: _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            label: '$_likes', color: _liked ? Colors.redAccent : Colors.white,
            onTap: _busy ? null : _toggleLike),
          const SizedBox(height: 14),
          _actionButton(icon: Icons.mode_comment_outlined, label: '$_comments',
            onTap: _openComments),
          const SizedBox(height: 14),
          _actionButton(icon: Icons.send_outlined, label: 'ارسال',
            onTap: _sharePost),
        ]),
      ),
      if (isVideo && !_videoReady)
        const Center(child: CircularProgressIndicator(color: Colors.white)),
    ]);
  }

  Widget _actionButton({required IconData icon, required String label,
    required VoidCallback? onTap, Color color = Colors.white}) =>
    Column(mainAxisSize: MainAxisSize.min, children: [
      IconButton(onPressed: onTap, icon: Icon(icon, color: color, size: 29),
        style: IconButton.styleFrom(backgroundColor: Colors.black45)),
      Text(label, style: const TextStyle(color: Colors.white, fontSize: 11,
        fontWeight: FontWeight.w700, shadows: [Shadow(color: Colors.black, blurRadius: 5)])),
    ]);
}
