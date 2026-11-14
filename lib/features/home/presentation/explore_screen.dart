import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/theme/app_theme.dart';
import '../../auth/data/auth_service.dart';
import 'public_profile_screen.dart';
import 'shared_post_screen.dart';

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
  bool _loading = true, _searching = false, _popular = false, _reelsOnly = false;
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
      if (_reelsOnly) postQuery = postQuery.eq('is_reel', true);
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
        actions: [IconButton(onPressed: () => _load(), tooltip: 'تازه‌سازی',
          icon: const Icon(Icons.refresh_rounded)), const SizedBox(width: 4)],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
          child: TextField(
            controller: _search, onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            onSubmitted: (value) => _load(term: value),
            decoration: InputDecoration(
              hintText: 'جست‌وجوی افراد، پست‌ها و هشتگ‌ها',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.text.isEmpty ? null : IconButton(
                onPressed: () { _search.clear(); _load(term: ''); },
                icon: const Icon(Icons.close_rounded)),
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
              const SizedBox(width: 8),
              ChoiceChip(label: const Text('همه محتوا'), selected: !_reelsOnly,
                onSelected: (_) { setState(() => _reelsOnly = false); _load(); }),
              const SizedBox(width: 8),
              ChoiceChip(label: const Text('ریلز'), selected: _reelsOnly,
                onSelected: (_) { setState(() => _reelsOnly = true); _load(); }),
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
                TextButton.icon(onPressed: () => _load(), icon: const Icon(Icons.refresh), label: const Text('تلاش دوباره')),
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
                            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
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
      ]),
    );
  }

  Widget _postTile(Map<String, dynamic> post) {
    final mediaUrl = post['media_type'] == 'video' ? (post['cover_url'] as String? ?? post['media_url'] as String?) : post['media_url'] as String?;
    final caption = (post['caption'] as String? ?? '').trim();
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => SharedPostScreen(postId: post['id'] as String))),
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
