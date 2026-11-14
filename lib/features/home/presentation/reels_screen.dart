import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme/app_theme.dart';
import '../../auth/data/auth_service.dart';
import 'create_post_screen.dart';
import 'feed_screen.dart';
import 'public_profile_screen.dart';

class ReelsScreen extends StatefulWidget {
  const ReelsScreen({this.isVisible = true, this.initialReelId, super.key});
  final bool isVisible;
  final String? initialReelId;

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
  late Future<List<Map<String, dynamic>>> _reels;
  int _activeIndex = 0;
  PageController? _pageController;

  @override
  void initState() {
    super.initState();
    _reels = _loadReels();
  }

  Future<List<Map<String, dynamic>>> _loadReels() async {
    final client = AuthService.client;
    final uid = client.auth.currentUser!.id;
    final rows = await client.from('posts')
        .select('id,author_id,author_username,author_display_name,caption,media_path,media_type,cover_path,created_at,is_public')
        .eq('is_reel', true)
        .order('created_at', ascending: false)
        .limit(60);
    final authorIds = rows.map((r) => r['author_id'] as String).toSet().toList();
    final profiles = authorIds.isEmpty ? <dynamic>[] : await client.from('profiles')
        .select('id,avatar_path').inFilter('id', authorIds);
    final avatarById = {for (final p in profiles) p['id'] as String: p['avatar_path'] as String?};
    final output = <Map<String, dynamic>>[];
    for (final row in rows) {
      final item = Map<String, dynamic>.from(row);
      final path = item['media_path'] as String?;
      if (path == null || item['media_type'] != 'video') continue;
      try {
        item['media_url'] = await client.storage.from('post-media').createSignedUrl(path, 3600);
      } catch (_) {
        continue;
      }
      final coverPath = item['cover_path'] as String?;
      if (coverPath != null) {
        try {
          item['cover_url'] = await client.storage.from('post-media').createSignedUrl(coverPath, 3600);
        } catch (_) {}
      }
      final avatarPath = avatarById[item['author_id'] as String];
      if (avatarPath != null) {
        try {
          item['avatar_url'] = await client.storage.from('avatars').createSignedUrl(avatarPath, 3600);
        } catch (_) {}
      }
      item['is_mine'] = item['author_id'] == uid;
      output.add(item);
    }
    if (widget.initialReelId != null) {
      final targetIndex = output.indexWhere((item) => item['id'] == widget.initialReelId);
      if (targetIndex >= 0) _activeIndex = targetIndex;
    }
    return output;
  }

  Future<void> _refresh() async {
    final next = _loadReels();
    setState(() => _reels = next);
    await next;
  }

  Future<void> _createReel() async {
    final published = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const CreatePostScreen(initialReel: true)),
    );
    if (published == true && mounted) await _refresh();
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _reels,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return _emptyState('ویدئوها بارگذاری نشدند.', 'اتصال را بررسی کنید و دوباره تلاش کنید.',
          onPressed: _refresh, icon: Icons.cloud_off_outlined);
      }
      final reels = snapshot.data ?? [];
      if (reels.isEmpty) {
        return _emptyState('هنوز ریلزی منتشر نشده است.',
          'اولین ویدئوی کوتاه را با برش حداکثر دو دقیقه‌ای منتشر کنید.',
          onPressed: _createReel, icon: Icons.video_collection_outlined,
          actionLabel: 'ساخت اولین ریلز');
      }
      _pageController ??= PageController(initialPage: _activeIndex);
      return RefreshIndicator(
        onRefresh: _refresh,
        child: PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          itemCount: reels.length,
          onPageChanged: (index) => setState(() => _activeIndex = index),
          itemBuilder: (context, index) => _ReelCard(
            key: ValueKey(reels[index]['id']),
            reel: reels[index],
            isActive: widget.isVisible && index == _activeIndex,
          ),
        ),
      );
    },
  );

  Widget _emptyState(String title, String subtitle, {
    required VoidCallback onPressed,
    required IconData icon,
    String actionLabel = 'تلاش دوباره',
  }) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 58, color: HomaGramTheme.turquoise),
        const SizedBox(height: 16),
        Text(title, textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text(subtitle, textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF8490A4), height: 1.6)),
        const SizedBox(height: 18),
        FilledButton.icon(onPressed: onPressed,
          icon: const Icon(Icons.add_rounded), label: Text(actionLabel)),
      ]),
    ),
  );
}

class _ReelCard extends StatefulWidget {
  const _ReelCard({required this.reel, required this.isActive, super.key});
  final Map<String, dynamic> reel;
  final bool isActive;

  @override
  State<_ReelCard> createState() => _ReelCardState();
}

class _ReelCardState extends State<_ReelCard> with WidgetsBindingObserver {
  VideoPlayerController? _video;
  bool _loading = true;
  bool _liked = false;
  bool _busy = false;
  int _likes = 0;
  int _comments = 0;
  bool _showPlay = false;

  String get _id => widget.reel['id'] as String;
  String get _uid => AuthService.client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.isActive) _initialize();
    _loadInteractions();
  }

  Future<void> _initialize() async {
    final url = widget.reel['media_url'] as String;
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _video = controller;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(1);
      if (widget.isActive) { await controller.play(); } else { await controller.pause(); }
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void didUpdateWidget(covariant _ReelCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      final controller = _video;
      if (widget.isActive) {
        if (controller == null) { _initialize(); }
        else if (controller.value.isInitialized) { controller.play(); }
      } else if (controller != null && controller.value.isInitialized) {
        controller.pause();
      }
    }
  }

  Future<void> _loadInteractions() async {
    try {
      final client = AuthService.client;
      final likes = await client.from('post_likes').select('user_id').eq('post_id', _id);
      final comments = await client.from('post_comments').select('id').eq('post_id', _id);
      final myLike = await client.from('post_likes').select('post_id')
          .eq('post_id', _id).eq('user_id', _uid).maybeSingle();
      if (!mounted) return;
      setState(() {
        _likes = likes.length;
        _comments = comments.length;
        _liked = myLike != null;
      });
    } catch (_) {}
  }

  Future<void> _toggleLike() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final query = AuthService.client.from('post_likes');
      if (_liked) {
        await query.delete().eq('post_id', _id).eq('user_id', _uid);
      } else {
        await query.insert({'post_id': _id, 'user_id': _uid});
      }
      if (mounted) setState(() {
        _liked = !_liked;
        _likes += _liked ? 1 : -1;
      });
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ثبت پسند انجام نشد. دوباره تلاش کنید.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _togglePlayback() {
    final controller = _video;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      controller.pause();
      setState(() => _showPlay = true);
    } else {
      controller.play();
      setState(() => _showPlay = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _video?.pause();
    } else if (state == AppLifecycleState.resumed && widget.isActive) {
      _video?.play();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _video?.dispose();
    super.dispose();
  }

  Future<void> _openComments() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PostCommentsScreen(postId: _id),
    ));
    _loadInteractions();
  }

  Future<void> _openProfile() {
    return Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PublicProfileScreen(userId: widget.reel['author_id'] as String),
    ));
  }

  Future<void> _share() async {
    await SharePlus.instance.share(ShareParams(text: 'ریلز در HomaGram\n${widget.reel['caption'] ?? ''}'));
  }

  @override
  Widget build(BuildContext context) {
    final controller = _video;
    final author = (widget.reel['author_display_name'] as String?)?.trim();
    final username = widget.reel['author_username'] as String? ?? '';
    final caption = (widget.reel['caption'] as String? ?? '').trim();
    return Stack(fit: StackFit.expand, children: [
      const ColoredBox(color: Colors.black),
      if (controller != null && controller.value.isInitialized)
        Center(
          child: GestureDetector(
            onTap: _togglePlayback,
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
        )
      else if (_loading)
        Stack(fit: StackFit.expand, children: [
          if (widget.reel['cover_url'] != null)
            Image.network(widget.reel['cover_url'] as String, fit: BoxFit.cover),
          const Center(child: CircularProgressIndicator(color: HomaGramTheme.turquoise)),
        ])
      else
        const Center(child: Icon(Icons.video_file_outlined, color: Colors.white54, size: 54)),
      Positioned.fill(child: IgnorePointer(child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: .32), Colors.transparent,
              Colors.black.withValues(alpha: .68)],
            stops: const [0, .38, 1]),
        ),
      ))),
      if (_showPlay)
        const Center(child: Icon(Icons.play_arrow_rounded, size: 76, color: Colors.white)),
      Positioned(
        left: 14, right: 82, bottom: 22,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            onTap: _openProfile,
            child: Row(children: [
              CircleAvatar(
                radius: 17,
                backgroundImage: widget.reel['avatar_url'] == null
                    ? null : NetworkImage(widget.reel['avatar_url'] as String),
                child: widget.reel['avatar_url'] == null
                    ? const Icon(Icons.person_outline, size: 18) : null,
              ),
              const SizedBox(width: 9),
              Expanded(child: Text(
                author == null || author.isEmpty ? '@$username' : author,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
              )),
              if (widget.reel['is_mine'] != true)
                OutlinedButton(
                  onPressed: _openProfile,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('مشاهده پروفایل', style: TextStyle(fontSize: 10)),
                ),
            ]),
          ),
          if (caption.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(caption, maxLines: 4, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, height: 1.5, fontSize: 13)),
          ],
          const SizedBox(height: 8),
          const Text('HomaGram • Reels', style: TextStyle(color: Colors.white70, fontSize: 10)),
        ]),
      ),
      Positioned(
        right: 10, bottom: 28,
        child: Column(children: [
          _action(Icons.favorite_rounded, _likes.toString(),
            color: _liked ? Colors.pinkAccent : Colors.white, onTap: _toggleLike),
          const SizedBox(height: 18),
          _action(Icons.mode_comment_outlined, _comments.toString(), onTap: _openComments),
          const SizedBox(height: 18),
          _action(Icons.share_outlined, 'اشتراک', onTap: _share),
        ]),
      ),
    ]);
  }

  Widget _action(IconData icon, String label, {Color color = Colors.white, required VoidCallback onTap}) =>
    InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        child: Column(children: [
          Icon(icon, color: color, size: 29),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
}
